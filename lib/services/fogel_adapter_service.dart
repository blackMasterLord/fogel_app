import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:op_wifi_utils/op_wifi_utils.dart';
import '../models/fogel_settings.dart';
import 'wifi_channel.dart';

/// Binary protocol constants (mirrors settings.h on ESP32)
const int tcpPort = 8888;
const int udpPort = 8889;

// Client → ESP32 message types
const int msgPing = 0x01;
const int msgTickOk = 0x02;
const int msgGetConfig = 0x03;
const int msgGetProtocol = 0x04;
const int msgSetCanSpeed = 0x05;
const int msgSetProtocol = 0x06;
const int msgCmd = 0x07;
const int msgUdpReg = 0x08;
const int msgCanClear = 0x09;

// ESP32 → Client message types
const int msgPong = 0x81;
const int msgOk = 0x82;
const int msgFail = 0x83;
const int msgConfig = 0x84;
const int msgProtocolDtl = 0x85;
const int msgSpeedResult = 0x86;
const int msgProtoResult = 0x87;
const int msgTick = 0x88;
const int msgBusy = 0x8A;   // ESP32 → client: adapter occupied

// UDP packet type prefixes (mirrors main.cpp)
const int udpTypeCan  = 0x01;
const int udpTypeTick = 0x02;

class FogelAdapterService {
  static final FogelAdapterService _instance = FogelAdapterService._internal();
  factory FogelAdapterService() => _instance;
  FogelAdapterService._internal();

  // --- Transport sockets ---
  Socket? _tcpSocket;
  RawDatagramSocket? _udpSocket;
  final List<int> _tcpBuffer = [];

  static List<SavedDevice> _savedDevicesList = [];

  String _pendingBssid = '';
  String _currentSsid = '';
  String _currentPassword = '';
  String _connectionStage = '';
  bool _isManualDisconnect = false;
  /// Set to true during auto-reconnect on app resume to suppress "connection lost" UI.
  bool isAutoReconnecting = false;
  bool _isReconnecting = false; // skips disconnect() inside connect() when reconnecting

  void markReconnecting() => _isReconnecting = true;
  DateTime? _lastTickReceivedAt;
  String? _pendingCommandType;
  bool? _pendingCommandValue;
  String? _pendingSetProtocol;
  bool _isAutoDetecting = false;
  Timer? _commandTimer;
  Timer? _commandStateTimer;
  Timer? _cmdTimeoutTimer;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  bool _tcpNeedsReconnect = false;
  bool _tcpReconnecting = false;
  Timer? _udpHealthTimer;
  static const Duration _udpStaleThreshold = Duration(seconds: 5);

  final Map<String, Map<String, dynamic>> _cachedProtocols = {};
  final ValueNotifier<String?> pendingCommand = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingProtocol = ValueNotifier(false);

  // --- CAN messages: received as batch from ESP32 ---
  static final ValueNotifier<List<CanMessage>> canMessagesNotifier = ValueNotifier([]);
  static const int _maxCanMessages = 500;
  final List<CanMessage> _canBatchMessages = [];

  static const Duration _commandTimeout = Duration(seconds: 15);
  static const Duration _commandStateTimeout = Duration(seconds: 5);

  bool get isConnected => _tcpSocket != null;
  bool get canReconnect => _currentSsid.isNotEmpty && _pendingBssid.isNotEmpty;
  bool get isManualDisconnect => _isManualDisconnect;
  bool get isConnectionStale => _lastTickReceivedAt != null &&
      DateTime.now().difference(_lastTickReceivedAt!) > _udpStaleThreshold;

  // ===================================================================
  // Binary protocol helpers
  // ===================================================================

  static Uint8List _buildFrame(int type, [List<int>? payload]) {
    final data = payload;
    final dataLen = data?.length ?? 0;
    final len = 1 + dataLen;
    final buf = Uint8List(2 + len); // LEN(2) + TYPE(1) + DATA
    buf[0] = (len >> 8) & 0xFF;
    buf[1] = len & 0xFF;
    buf[2] = type;
    if (data != null && dataLen > 0) {
      buf.setRange(3, 3 + dataLen, data);
    }
    return buf;
  }

  static int _readInt16(List<int> data, int pos) =>
      (data[pos] << 8) | data[pos + 1];

  static int _readUint32(List<int> data, int pos) =>
      ((data[pos] << 24) | (data[pos + 1] << 16) |
          (data[pos + 2] << 8) | data[pos + 3]);

  static double? _readNullableDouble(List<int> data, int pos, int scale,
      {int nullSentinel = 0x7FFF}) {
    final raw = _readInt16(data, pos);
    if (raw == nullSentinel) return null;
    return raw / scale;
  }

  void _sendTcpMessage(int type, [List<int>? payload]) {
    if (_tcpSocket == null) {
      if (_tcpNeedsReconnect) {
        _reconnectTcp(); // fire-and-forget background reconnect
      }
      return;
    }
    try {
      _tcpSocket!.add(_buildFrame(type, payload));
    } catch (e) {
      debugPrint('[TCP] Send error (type=0x${type.toRadixString(16)}): $e');
    }
  }

  Future<void> _reconnectTcp() async {
    if (!canReconnect || _tcpReconnecting || _tcpSocket != null) return;
    _tcpReconnecting = true;
    _tcpNeedsReconnect = false;
    try {
      final gateway = await WiFiChannel.getGatewayIp();
      final adapterIp = (gateway != null && gateway.isNotEmpty) ? gateway : '192.168.4.1';
      _tcpSocket = await Socket.connect(adapterIp, tcpPort);
      _tcpSocket!.listen(
        (data) {
          _tcpBuffer.addAll(data);
          _processTcpBuffer();
        },
        onDone: () {
          debugPrint('[TCP] Socket closed (lazy)');
          _tcpSocket?.close();
          _tcpSocket = null;
          _tcpNeedsReconnect = true;
        },
        onError: (e) {
          debugPrint('[TCP] Socket error (lazy): $e');
          _tcpSocket?.close();
          _tcpSocket = null;
          _tcpNeedsReconnect = true;
        },
      );
      _tcpSocket!.add(_buildFrame(msgUdpReg, [
        (udpPort >> 8) & 0xFF,
        udpPort & 0xFF,
      ]));
      debugPrint('[TCP] Reconnected lazily');
    } catch (e) {
      debugPrint('[TCP] Lazy reconnect failed: $e');
      _tcpNeedsReconnect = true;
    } finally {
      _tcpReconnecting = false;
    }
  }

  // ===================================================================
  // TCP buffer processing
  // ===================================================================

  void _processTcpBuffer() {
    int pos = 0;
    while (pos + 3 <= _tcpBuffer.length) {
      final len = (_tcpBuffer[pos] << 8) | _tcpBuffer[pos + 1];
      final frameEnd = pos + 2 + len;
      if (frameEnd > _tcpBuffer.length) break; // incomplete frame

      final type = _tcpBuffer[pos + 2];
      final payload = _tcpBuffer.sublist(pos + 3, frameEnd);

      _dispatchTcpMessage(type, payload);
      pos = frameEnd;
    }

    if (pos > 0 && pos <= _tcpBuffer.length) {
      _tcpBuffer.removeRange(0, pos);
    }
  }

  void _dispatchTcpMessage(int type, List<int> payload) {
    switch (type) {
      case msgPong:
        _onPong();
        break;
      case msgOk:
        break;
      case msgFail:
        _onTcpFail();
        break;
      case msgConfig:
        _onConfig(payload);
        break;
      case msgProtocolDtl:
        _onProtocolDetail(payload);
        break;
      case msgSpeedResult:
        _onSpeedResult(payload);
        break;
      case msgProtoResult:
        _onProtoResult(payload);
        break;
      case msgTick:
        _onTick(payload);
        break;
      case msgBusy:
        _onBusy();
        break;
      default:
        debugPrint('[TCP] Unknown message type: 0x${type.toRadixString(16)}');
        break;
    }
  }

  // ===================================================================
  // Message handlers
  // ===================================================================

  void _onBusy() {
    _cancelCommandTimer();
    _showError('К данному адаптеру подключено другое устройство', disconnectWifi: false);
  }

  void _onPong() {
    if (_connectionStage == 'pinging') {
      _cancelCommandTimer();
      _connectionStage = 'loading_config';
      _applyGlobalSettings(globalSettings.value.copyWith(
        connectionStatus: 'loading_config',
        connectedDeviceAddress: _pendingBssid,
      ));
      _startCommandTimer('loading_config');
      requestConfiguration();
    }
  }

  void _onTcpFail() {
    _cancelCommandTimer();
    _cancelCmdTimeout();

    if (_isAutoDetecting) {
      _isAutoDetecting = false;
      final defaultSpeed = globalSettings.value.canSpeedDefault;
      _applyGlobalSettings(globalSettings.value.copyWith(
        isAutoDetecting: false,
        isAutoSpeed: false,
        canSpeed: defaultSpeed,
        clearCurrentScanningSpeed: true,
        connectionError: 'Не удалось определить скорость CAN-шины.',
      ));
    } else if (_pendingCommandType != null) {
      _commandStateTimer?.cancel();
      _commandStateTimer = null;
      _clearPendingCommand();
      _applyGlobalSettings(globalSettings.value.copyWith(
        connectionError: 'Не удалось выполнить команду.',
      ));
    } else if (_connectionStage == 'pinging') {
      _showError('Невозможно подключиться к устройству');
    } else if (_connectionStage == 'loading_config') {
      _showError('Не удалось получить конфигурацию.');
    }
  }

  void _onConfig(List<int> payload) {
    if (_connectionStage != 'loading_config') return;
    _cancelCommandTimer();

    int pos = 0;

    // Parse protocols
    final protoCount = _readInt16(payload, pos); pos += 2;
    final protocols = <String>[];
    for (int i = 0; i < protoCount; i++) {
      final nameLen = payload[pos++];
      final name = utf8.decode(payload.sublist(pos, pos + nameLen));
      pos += nameLen;
      protocols.add(name);
    }

    // Parse CAN speeds
    final speedCount = _readInt16(payload, pos); pos += 2;
    final speeds = <int>[];
    for (int i = 0; i < speedCount; i++) {
      speeds.add(_readUint32(payload, pos)); pos += 4;
    }
    speeds.sort();

    // Default speed
    final defaultSpeed = _readUint32(payload, pos); pos += 4;

    // Has auto
    final hasAuto = payload[pos] != 0;

    _connectionStage = 'connected';
    _applyGlobalSettings(globalSettings.value.copyWith(
      connectionStatus: 'connected',
      connectedDeviceAddress: _pendingBssid,
      availableProtocols: protocols,
      availableCanSpeeds: speeds,
      canSpeedDefault: defaultSpeed,
      hasAutoSpeed: hasAuto,
      canSpeed: defaultSpeed,
      clearSelectedProtocol: true,
      clearProtocolParams: true,
      clearProtocolCommands: true,
      connectionError: null,
    ));
    _startUdpHealthCheck();
    setSpeed(defaultSpeed);
  }

  void _onProtocolDetail(List<int> payload) {
    _cancelCmdTimeout();

    int pos = 0;
    final nameLen = payload[pos++];
    final name = utf8.decode(payload.sublist(pos, pos + nameLen));
    pos += nameLen;

    final speed = _readUint32(payload, pos); pos += 4;

    final paramsLen = _readInt16(payload, pos); pos += 2;
    final params = utf8.decode(payload.sublist(pos, pos + paramsLen));
    pos += paramsLen;

    final commandsLen = _readInt16(payload, pos); pos += 2;
    final commands = utf8.decode(payload.sublist(pos, pos + commandsLen));

    _cachedProtocols[name] = {
      'speed': speed,
      'params': params.split(','),
      'commands': commands.split(','),
    };

    if (_pendingSetProtocol == name) {
      setProtocol(name);
    }
  }

  void _onSpeedResult(List<int> payload) {
    _cancelCommandTimer();
    _cancelCmdTimeout();

    final speed = _readUint32(payload, 0);
    _applySetSpeedResult(speed);
  }

  void _onProtoResult(List<int> payload) {
    _cancelCommandTimer();
    _cancelCmdTimeout();

    final nameLen = payload[0];
    final name = (nameLen > 0)
        ? utf8.decode(payload.sublist(1, 1 + nameLen))
        : null;
    _applySetProtocolResult(name);
  }

  void _onTick(List<int> payload) => _handleTickUdp(payload);

  // ===================================================================
  // UDP packet dispatcher (type-prefixed: 0x01=CAN, 0x02=TICK)
  // ===================================================================

  void _dispatchUdpPacket(List<int> data) {
    if (data.isEmpty) return;
    final type = data[0];
    final payload = data.sublist(1);
    switch (type) {
      case udpTypeCan:
        _handleCanBatch(payload);
        break;
      case udpTypeTick:
        _handleTickUdp(payload);
        break;
    }
  }

  // --- TICK handler (UDP, no TCP frame wrapper) ---

  void _handleTickUdp(List<int> payload) {
    _lastTickReceivedAt = DateTime.now();
    _resetUdpWatchdog(); // reset on every TICK — no periodic polling
    int pos = 0;

    final voltage = _readNullableDouble(payload, pos, 10); pos += 2;
    final soc = _readNullableDouble(payload, pos, 1, nullSentinel: 0x8000); pos += 2;
    final temperature = _readNullableDouble(payload, pos, 10); pos += 2;
    final chargeCurrent = _readNullableDouble(payload, pos, 10); pos += 2;
    final dischargeCurrent = _readNullableDouble(payload, pos, 10); pos += 2;

    final flags = payload[pos++];
    final chargeOn = (flags & 0x01) != 0;
    final dischargeOn = (flags & 0x02) != 0;
    final prechargeOn = (flags & 0x04) != 0;

    final totalMessages = _readUint32(payload, pos); pos += 4;
    final uniqueMessages = _readUint32(payload, pos); pos += 4;

    final cellCount = payload[pos++];
    final cellVoltages = <double>[];
    for (int i = 0; i < cellCount; i++) {
      final raw = _readInt16(payload, pos); pos += 2;
      cellVoltages.add(raw / 100.0);
    }

    // Check pending command confirmation
    if (_pendingCommandType != null && _pendingCommandValue != null) {
      bool matched = false;
      switch (_pendingCommandType!) {
        case 'CHARGE':
          matched = chargeOn == _pendingCommandValue;
          break;
        case 'DISCHARGE':
          matched = dischargeOn == _pendingCommandValue;
          break;
        case 'PRECHARGE':
          matched = prechargeOn == _pendingCommandValue;
          break;
      }
      if (matched) {
        _commandStateTimer?.cancel();
        _commandStateTimer = null;
        _clearPendingCommand();
      }
    }

    final newStats = CanStats(
      totalMessages: totalMessages,
      uniqueMessages: uniqueMessages,
    );
    if (canStatsNotifier.value != newStats) {
      canStatsNotifier.value = newStats;
    }

    final newBms = BmsData(
      batteryVoltage: voltage,
      soc: soc,
      temperature: temperature,
      chargeCurrent: chargeCurrent,
      dischargeCurrent: dischargeCurrent,
      cellVoltages: cellVoltages,
      cellCount: cellCount,
      chargeOn: chargeOn,
      dischargeOn: dischargeOn,
      prechargeOn: prechargeOn,
      totalMessages: totalMessages,
      uniqueMessages: uniqueMessages,
    );
    if (bmsNotifier.value != newBms) {
      bmsNotifier.value = newBms;
    }
  }

  // --- UDP watchdog (drives connectionStatus, no polling) ---

  void _startUdpHealthCheck() {
    _resetUdpWatchdog();
  }

  void _resetUdpWatchdog() {
    _udpHealthTimer?.cancel();
    _udpHealthTimer = Timer(_udpStaleThreshold, () {
      final s = globalSettings.value;
      if (s.connectionStatus == 'connected') {
        debugPrint('[UDP] TICK stale, connection lost');
        _applyGlobalSettings(s.copyWith(connectionStatus: 'disconnected'));
      }
    });
  }

  void _stopUdpHealthCheck() {
    _udpHealthTimer?.cancel();
    _udpHealthTimer = null;
  }

  void _handleCanBatch(List<int> data) {
    if (data.isEmpty) return;
    final count = data[0];
    if (count == 0) return;

    _canBatchMessages.clear();
    int pos = 1;
    for (int i = 0; i < count; i++) {
      if (pos + 21 > data.length) break;
      final id = _readUint32(data, pos); pos += 4;
      final dlc = data[pos++];
      final canData = data.sublist(pos, pos + dlc); pos += 8;
      final period = _readUint32(data, pos); pos += 4;
      final msgCount = _readUint32(data, pos); pos += 4;

      _canBatchMessages.add(CanMessage(
        isExtended: id > 0x7FF,
        id: id,
        dlc: dlc,
        data: canData,
        period: period,
        count: msgCount,
      ));
    }

    if (_canBatchMessages.length > _maxCanMessages) {
      _canBatchMessages.removeRange(0, _canBatchMessages.length - _maxCanMessages);
    }
    canMessagesNotifier.value = List.of(_canBatchMessages);
  }

  // ===================================================================
  // State helpers
  // ===================================================================

  void _applySetSpeedResult(int speed) {
    if (_isAutoDetecting) {
      _applyGlobalSettings(globalSettings.value.copyWith(
        currentScanningSpeed: speed,
        canSpeed: speed,
      ));
    } else {
      _finalizeProtocolSelection(speed);
    }
  }

  void _applySetProtocolResult(String? name) {
    if (name == null) {
      _pendingSetProtocol = null;
      isLoadingProtocol.value = false;
      _applyGlobalSettings(globalSettings.value.copyWith(
        clearSelectedProtocol: true,
        clearProtocolParams: true,
        clearProtocolCommands: true,
      ));
      // Reset BMS data through the dedicated notifier, not globalSettings.
      bmsNotifier.value = const BmsData();
    } else {
      final speed = _cachedProtocols[name]?['speed'] as int?;
      _finalizeProtocolSelection(speed);
    }
  }

  void _finalizeProtocolSelection(int? speed) {
    final protoName = _pendingSetProtocol;
    final cached = protoName != null ? _cachedProtocols[protoName] : null;

    _pendingSetProtocol = null;
    isLoadingProtocol.value = false;

    _applyGlobalSettings(globalSettings.value.copyWith(
      selectedProtocol: protoName,
      canSpeed: speed,
      protocolParams: cached?['params'] ?? [],
      protocolCommands: cached?['commands'] ?? [],
      canNodes: [],
    ));
    // Reset BMS data through the dedicated notifier, not globalSettings.
    bmsNotifier.value = const BmsData();
  }

  void _clearPendingCommand() {
    _pendingCommandType = null;
    _pendingCommandValue = null;
    pendingCommand.value = null;
  }

  static void _applyGlobalSettings(FogelSettings settings) {
    globalSettings.value = settings;
  }

  // ===================================================================
  // Connection
  // ===================================================================

  Future<bool> connect(String ssid, String deviceName,
      {String? password, required String bssid, bool skipWifi = false}) async {
    try {
      if (!_isReconnecting) {
        disconnect();
      }
      _isReconnecting = false;
      _isManualDisconnect = false;
      _pendingBssid = bssid;
      _currentSsid = ssid;
      _currentPassword = password ?? '';

      _connectionStage = 'connecting';
      _applyGlobalSettings(globalSettings.value.copyWith(
        connectionStatus: 'connecting',
        connectedDeviceName: deviceName,
        connectionError: null,
      ));

      // Step 1: Connect to WiFi
      if (!skipWifi) {
        final wifiResult = await OpWifiUtils.connectToWifi(
          ssid: ssid,
          password: password,
          bssid: _pendingBssid,
          timeout: const Duration(seconds: 30),
        );
        if (!wifiResult.isSuccess) {
          _showError('Не удалось подключиться к WiFi');
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 1500));
        if (_isManualDisconnect) return false;
      }

      // Step 2: Wait for DHCP (event-driven, max 5s)
      try {
        await WiFiChannel.onDhcpReady.first.timeout(const Duration(seconds: 5));
      } catch (_) {
        // DHCP didn't fire — proceed anyway, TCP connect will fail if no IP
      }
      if (_isManualDisconnect) return false;
      _cancelCommandTimer();

      // Step 3: Connect TCP
      _startCommandTimer('connecting');
      try {
        final gateway = await WiFiChannel.getGatewayIp();
        final adapterIp = (gateway != null && gateway.isNotEmpty) ? gateway : '192.168.4.1';
        _tcpSocket = await Socket.connect(
          adapterIp,
          tcpPort,
        );
        if (_isManualDisconnect) return false;
        _tcpSocket!.listen(
          (data) {
            _tcpBuffer.addAll(data);
            _processTcpBuffer();
          },
          onDone: () {
            debugPrint('[TCP] Socket closed');
            _tcpSocket?.close();
            _tcpSocket = null;
            _tcpNeedsReconnect = true;
          },
          onError: (e) {
            debugPrint('[TCP] Socket error: $e');
            _tcpSocket?.close();
            _tcpSocket = null;
            _tcpNeedsReconnect = true;
          },
        );

        // Step 4: Bind UDP
        _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          udpPort,
        );
        if (_isManualDisconnect) return false;
        _listenUdp(_udpSocket!);

        // Step 5: Register UDP port with ESP32
        _sendTcpMessage(msgUdpReg, [
          (udpPort >> 8) & 0xFF,
          udpPort & 0xFF,
        ]);
      } catch (e) {
        _showError('Не удалось подключиться к адаптеру');
        return false;
      }

      _cancelCommandTimer();

      if (isConnected) {
        _connectionStage = 'pinging';
        _applyGlobalSettings(globalSettings.value.copyWith(
          connectionStatus: 'pinging',
        ));
        _sendTcpMessage(msgPing);
        _startCommandTimer('pinging');
        return true;
      }
    } catch (_) {}

    _showError('Невозможно подключиться к устройству');
    return false;
  }

  Future<bool> reconnect() async {
    if (_currentSsid.isEmpty || _pendingBssid.isEmpty) return false;
    return connect(
      _currentSsid,
      _currentSsid,
      password: _currentPassword.isNotEmpty ? _currentPassword : null,
      bssid: _pendingBssid,
      skipWifi: true,
    );
  }

  void disconnect({bool manual = false, bool disconnectWifi = false}) {
    _isManualDisconnect = manual;
    _pendingCommandType = null;
    _pendingCommandValue = null;
    _pendingSetProtocol = null;
    _tcpNeedsReconnect = false;
    _isAutoDetecting = false;
    _connectionStage = '';
    _tcpBuffer.clear();
    _cachedProtocols.clear();
    _stopUdpHealthCheck();
    pendingCommand.value = null;
    isLoadingProtocol.value = false;
    _cancelCommandTimer();
    _cancelCmdTimeout();
    _commandStateTimer?.cancel();
    _commandStateTimer = null;

    _udpSubscription?.cancel();
    _udpSubscription = null;
    _udpSocket?.close();
    _udpSocket = null;

    _tcpSocket?.close();
    _tcpSocket = null;
    _lastTickReceivedAt = null;

    resetCanMessages();

    if (disconnectWifi) {
      _disconnectFromAdapterWifi();
    }

    _applyGlobalSettings(FogelSettings(
      themeSetting: globalSettings.value.themeSetting,
      savedDevices: _savedDevicesList,
      wifiEnabled: globalSettings.value.wifiEnabled,
    ));
  }

  void _disconnectFromAdapterWifi() async {
    try {
      final bssidResult = await OpWifiUtils.getCurrentBssid();
      if (!bssidResult.isSuccess) return;
      final bssid = bssidResult.data;
      final isOnAdapter = _savedDevicesList.any((d) => d.address == bssid);
      if (isOnAdapter) {
        final ssidResult = await OpWifiUtils.getCurrentSsid();
        if (ssidResult.isSuccess) {
          await OpWifiUtils.disconnectFromWifi(ssidResult.data);
        }
      }
    } catch (_) {}
  }

  // ===================================================================
  // Timer management
  // ===================================================================

  void _startCommandTimer(String stage) {
    _cancelCommandTimer();
    _commandTimer = Timer(_commandTimeout, () {
      final currentStatus = globalSettings.value.connectionStatus;
      if (currentStatus == stage) {
        switch (stage) {
          case 'connecting':
          case 'pinging':
            _showError('Невозможно подключиться к устройству');
            break;
          case 'loading_config':
            _showError('Не удалось получить конфигурацию.');
            break;
          default:
            _showError('Превышено время ожидания ответа.');
        }
      }
    });
  }

  void _cancelCommandTimer() {
    _commandTimer?.cancel();
    _commandTimer = null;
  }

  void _startCmdTimeout(String errorMessage) {
    _cmdTimeoutTimer?.cancel();
    _cmdTimeoutTimer = Timer(_commandStateTimeout, () {
      _cmdTimeoutTimer = null;
      _pendingSetProtocol = null;
      isLoadingProtocol.value = false;
      _isAutoDetecting = false;
      _applyGlobalSettings(globalSettings.value.copyWith(
        connectionError: errorMessage,
      ));
    });
  }

  void _cancelCmdTimeout() {
    _cmdTimeoutTimer?.cancel();
    _cmdTimeoutTimer = null;
  }

  void _listenUdp(RawDatagramSocket socket, {bool isRebind = false}) {
    _udpSubscription = socket.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          try {
            final packet = socket.receive();
            if (packet != null && packet.data.isNotEmpty) {
              _dispatchUdpPacket(packet.data);
            }
          } catch (e) {
            debugPrint('[UDP] Receive error${isRebind ? " after rebind" : ""}: $e');
          }
        }
      },
      onError: (e) {
        debugPrint('[UDP] Socket error: $e');
        if (!isRebind) _tryRebindUdp();
      },
      onDone: () {
        debugPrint('[UDP] Socket closed');
        if (!isRebind) _tryRebindUdp();
      },
    );
  }
  /// Attempt to rebind the UDP socket after an error or unexpected close.
  void _tryRebindUdp() {
    _udpSubscription?.cancel();
    _udpSubscription = null;
    _udpSocket?.close();
    _udpSocket = null;

    try {
      RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort).then((socket) {
        _udpSocket = socket;
        _listenUdp(socket, isRebind: true);
        debugPrint('[UDP] Socket rebound successfully');
      }).catchError((e) {
        debugPrint('[UDP] Failed to rebind socket: $e');
      });
    } catch (e) {
      debugPrint('[UDP] Rebind failed: $e');
    }
  }

  void _showError(String message, {bool disconnectWifi = true}) {
    disconnect(disconnectWifi: disconnectWifi);
    _applyGlobalSettings(FogelSettings(
      themeSetting: globalSettings.value.themeSetting,
      savedDevices: _savedDevicesList,
      connectionError: message,
    ));
  }

  static void resetCanMessages() {
    canMessagesNotifier.value = [];
  }

  // ===================================================================
  // Device management (unchanged)
  // ===================================================================

  static Future<void> loadSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('saved_fogel_devices') ?? [];
    _savedDevicesList = list.map((item) => SavedDevice.fromJson(jsonDecode(item))).toList();
    _applyGlobalSettings(globalSettings.value.copyWith(savedDevices: _savedDevicesList));
  }

  static Future<void> deleteDevice(String bssid) async {
    final prefs = await SharedPreferences.getInstance();
    _savedDevicesList.removeWhere((d) => d.address == bssid);
    final list = _savedDevicesList.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList('saved_fogel_devices', list);
    _applyGlobalSettings(globalSettings.value.copyWith(savedDevices: _savedDevicesList));
  }

  Future<void> saveDevice(String bssid, String name, String password) async {
    final prefs = await SharedPreferences.getInstance();
    _savedDevicesList.removeWhere((d) => d.address == bssid);
    _savedDevicesList.add(SavedDevice(address: bssid, name: name, password: password));
    final list = _savedDevicesList.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList('saved_fogel_devices', list);
    _applyGlobalSettings(globalSettings.value.copyWith(savedDevices: _savedDevicesList));
  }

  Future<bool> isWifiEnabled() async => await WiFiChannel.isWifiEnabled();

  Future<List<WifiNetworkInfo>> scanNetworks() async => await WiFiChannel.scanNetworks();

  // ===================================================================
  // Command methods (build binary frames)
  // ===================================================================

  void requestConfiguration() {
    _sendTcpMessage(msgGetConfig);
  }

  void sendClearCan() {
    _sendTcpMessage(msgCanClear);
  }

  void getProtocol(String name) {
    final nameBytes = utf8.encode(name);
    _startCmdTimeout('Не удалось получить протокол.');
    _sendTcpMessage(msgGetProtocol, [nameBytes.length, ...nameBytes]);
  }

  void setSpeed(int speed) {
    _startCmdTimeout('Не удалось установить скорость CAN-шины.');
    _sendTcpMessage(msgSetCanSpeed, [
      (speed >> 24) & 0xFF,
      (speed >> 16) & 0xFF,
      (speed >> 8) & 0xFF,
      speed & 0xFF,
    ]);
  }

  void setSpeedAuto() {
    _isAutoDetecting = true;
    _applyGlobalSettings(globalSettings.value.copyWith(
      isAutoDetecting: true,
      isAutoSpeed: true,
      clearCurrentScanningSpeed: true,
      clearSelectedProtocol: true,
      clearProtocolParams: true,
      clearProtocolCommands: true,
    ));
    _startCmdTimeout('Не удалось определить скорость CAN-шины.');
    _sendTcpMessage(msgSetCanSpeed, [0xFF, 0xFF, 0xFF, 0xFF]); // AUTO = 0xFFFFFFFF
  }

  void setProtocol(String? name) {
    if (name == null) {
      _startCmdTimeout('Не удалось очистить протокол.');
      _sendTcpMessage(msgSetProtocol, [0]); // name_len = 0 → NULL
    } else {
      final nameBytes = utf8.encode(name);
      _startCmdTimeout('Не удалось установить протокол.');
      _sendTcpMessage(msgSetProtocol, [nameBytes.length, ...nameBytes]);
    }
  }

  void selectProtocol(String name) {
    _pendingSetProtocol = name;
    isLoadingProtocol.value = true;

    if (_cachedProtocols.containsKey(name)) {
      setProtocol(name);
    } else {
      getProtocol(name);
    }
  }

  void sendCommand(String type, bool value) {
    _pendingCommandType = type;
    _pendingCommandValue = value;
    pendingCommand.value = type;

    _commandStateTimer?.cancel();
    _commandStateTimer = Timer(_commandStateTimeout, () {
      if (_pendingCommandType == type) {
        _commandStateTimer = null;
        _pendingCommandType = null;
        _pendingCommandValue = null;
        pendingCommand.value = null;
        _applyGlobalSettings(globalSettings.value.copyWith(
          connectionError: 'Не удалось выполнить команду.',
        ));
      }
    });

    final typeBytes = utf8.encode(type);
    _sendTcpMessage(msgCmd, [
      typeBytes.length,
      ...typeBytes,
      value ? 1 : 0,
    ]);
  }
}