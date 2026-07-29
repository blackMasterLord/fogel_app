import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:op_wifi_utils/op_wifi_utils.dart';
import '../models/fogel_settings.dart';
import 'connection/connection_state_machine.dart';
import 'device/device_repository.dart';
import 'protocol/fogel_commands.dart';
import 'protocol/fogel_protocol.dart';
import 'transport/tcp_transport.dart';
import 'transport/udp_transport.dart';
import 'wifi_channel.dart';

class FogelAdapterService {
  static final FogelAdapterService _instance = FogelAdapterService._internal();
  factory FogelAdapterService() => _instance;
  FogelAdapterService._internal();

  // --- Modules ---
  final TcpTransport tcp = TcpTransport();
  final UdpTransport udp = UdpTransport();
  late final FogelCommands commands = FogelCommands(tcp);
  late final ConnectionStateMachine state = ConnectionStateMachine(globalSettings);

  // --- State ---
  String _pendingBssid = '';
  String _currentSsid = '';
  String _currentPassword = '';
  bool _isManualDisconnect = false;
  bool isAutoReconnecting = false;
  bool _isReconnecting = false;
  void markReconnecting() => _isReconnecting = true;

  DateTime? _lastTickReceivedAt;
  String? _pendingCommandType;
  bool? _pendingCommandValue;
  String? _pendingSetProtocol;
  bool _isAutoDetecting = false;
  Timer? _commandTimer;
  Timer? _commandStateTimer;
  Timer? _cmdTimeoutTimer;
  Timer? _udpHealthTimer;
  static const Duration _udpStaleThreshold = Duration(seconds: 5);

  // --- Heartbeat (Stage 10) ---
  Timer? _heartbeatTimer;
  int _heartbeatFailCount = 0;
  static const int _maxHeartbeatFails = 3;
  static const Duration _heartbeatInterval = Duration(seconds: 10);
  static const Duration _heartbeatTimeout = Duration(seconds: 5);

  // --- Retry backoff (Stage 12) ---
  int _reconnectAttempts = 0;
  static const List<int> _retryDelaysSec = [1, 2, 5, 10, 30];

  final Map<String, Map<String, dynamic>> _cachedProtocols = {};
  final ValueNotifier<String?> pendingCommand = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingProtocol = ValueNotifier(false);

  static const Duration _commandTimeout = Duration(seconds: 15);
  static const Duration _commandStateTimeout = Duration(seconds: 5);

  bool get isConnected => tcp.isConnected;
  bool get canReconnect => _currentSsid.isNotEmpty && _pendingBssid.isNotEmpty;
  bool get isManualDisconnect => _isManualDisconnect;
  bool get isConnectionStale => _lastTickReceivedAt != null &&
      DateTime.now().difference(_lastTickReceivedAt!) > _udpStaleThreshold;

  static final ValueNotifier<List<CanMessage>> canMessagesNotifier = ValueNotifier([]);
  static const int _maxCanMessages = 500;

  // ===================================================================
  // Connection
  // ===================================================================

  Future<bool> connect(String ssid, String deviceName,
      {String? password, required String bssid, bool skipWifi = false}) async {
    try {
      if (!_isReconnecting) disconnect();
      _isReconnecting = false;
      _isManualDisconnect = false;
      _pendingBssid = bssid;
      _currentSsid = ssid;
      _currentPassword = password ?? '';
      state.toConnecting(bssid, deviceName);

      if (!skipWifi) {
        final wifiResult = await OpWifiUtils.connectToWifi(
          ssid: ssid, password: password, bssid: bssid, timeout: const Duration(seconds: 30));
        if (!wifiResult.isSuccess) { _showError('Не удалось подключиться к WiFi'); return false; }
        await Future.delayed(const Duration(milliseconds: 1500));
        if (_isManualDisconnect) return false;
      }

      // ESP32 AP always uses static IP 192.168.4.1 — no DHCP needed
      const ip = '192.168.4.1';
      await tcp.connect(ip, tcpPort);
      if (_isManualDisconnect) return false;

      // UDP
      await udp.bind(udpPort);
      if (_isManualDisconnect) return false;

      // Register UDP
      commands.sendUdpReg(udpPort);

      _cancelCommandTimer();

      state.toPinging();
      commands.sendPing();
      _startCommandTimer(FogelConnectionState.pinging);

      _setupTcpListener();
      _setupUdpListener();
      return true;
    } catch (_) {}

    _showError('Невозможно подключиться к устройству');
    return false;
  }

  Future<bool> reconnect() async {
    if (!canReconnect) return false;
    return connect(_currentSsid, _currentSsid,
        password: _currentPassword.isNotEmpty ? _currentPassword : null,
        bssid: _pendingBssid, skipWifi: true);
  }

  void disconnect({bool manual = false, bool disconnectWifi = false}) {
    _isManualDisconnect = manual;
    _pendingCommandType = null;
    _pendingCommandValue = null;
    _pendingSetProtocol = null;
    _isAutoDetecting = false;
    _cachedProtocols.clear();
    _stopUdpHealthCheck();
    _stopHeartbeat();
    pendingCommand.value = null;
    isLoadingProtocol.value = false;
    _cancelCommandTimer();
    _cancelCmdTimeout();
    _commandStateTimer?.cancel();
    _commandStateTimer = null;

    udp.disconnect();
    tcp.disconnect();
    _lastTickReceivedAt = null;

    resetCanMessages();

    if (disconnectWifi) _disconnectFromAdapterWifi();

    state.toDisconnected();
  }

  void _disconnectFromAdapterWifi() async {
    try {
      final bssidResult = await OpWifiUtils.getCurrentBssid();
      if (!bssidResult.isSuccess) return;
      if (DeviceRepository.find(bssidResult.data) != null) {
        final ssidResult = await OpWifiUtils.getCurrentSsid();
        if (ssidResult.isSuccess) await OpWifiUtils.disconnectFromWifi(ssidResult.data);
      }
    } catch (_) {}
  }

  // ===================================================================
  // Listeners
  // ===================================================================

  void _setupTcpListener() {
    tcp.onData.listen((data) {
      if (data.isEmpty) return;
      _dispatchTcpMessage(data[0], data.sublist(1));
    });
  }

  void _setupUdpListener() {
    udp.onData.listen((data) {
      if (data.isEmpty) return;
      final type = data[0];
      final payload = data.sublist(1);
      if (type == udpTypeCan) { _handleCanBatch(payload); }
      else if (type == udpTypeTick) { _handleTickUdp(payload); }
    });
  }

  void _dispatchTcpMessage(int type, List<int> payload) {
    switch (type) {
      case msgPong: _onPong(); break;
      case msgOk: break;
      case msgFail: _onTcpFail(); break;
      case msgConfig: _onConfig(payload); break;
      case msgProtocolDtl: _onProtocolDetail(payload); break;
      case msgSpeedResult: _onSpeedResult(payload); break;
      case msgProtoResult: _onProtoResult(payload); break;
      case msgTick: _handleTickUdp(payload); break;
      case msgBusy: _onBusy(); break;
      case msgDeviceInfoResp: _onDeviceInfo(payload); break;
    }
  }

  // ===================================================================
  // Message handlers
  // ===================================================================

  void _onBusy() { _cancelCommandTimer(); _showError('К данному адаптеру подключено другое устройство', disconnectWifi: false); }

  void _onPong() {
    if (state.stage != FogelConnectionState.pinging) return;
    _resetHeartbeat();
    _cancelCommandTimer();
    state.toLoadingConfig();
    _startCommandTimer(FogelConnectionState.loadingConfig);
    commands.requestConfiguration();
  }

  void _onTcpFail() {
    _cancelCommandTimer(); _cancelCmdTimeout();
    if (_isAutoDetecting) {
      _isAutoDetecting = false;
      final d = globalSettings.value.canSpeedDefault;
      globalSettings.value = globalSettings.value.copyWith(isAutoDetecting: false, isAutoSpeed: false, canSpeed: d, clearCurrentScanningSpeed: true, connectionError: 'Не удалось определить скорость CAN-шины.');
    } else if (_pendingCommandType != null) {
      _commandStateTimer?.cancel(); _commandStateTimer = null; _clearPendingCommand();
      globalSettings.value = globalSettings.value.copyWith(connectionError: 'Не удалось выполнить команду.');
    } else if (state.stage == FogelConnectionState.pinging) { _showError('Невозможно подключиться к устройству'); }
    else if (state.stage == FogelConnectionState.loadingConfig) { _showError('Не удалось получить конфигурацию.'); }
  }

  void _onConfig(List<int> payload) {
    if (state.stage != FogelConnectionState.loadingConfig) return;
    _cancelCommandTimer();
    int pos = 0;
    final protoCount = readInt16(payload, pos); pos += 2;
    final protocols = <String>[];
    for (int i = 0; i < protoCount; i++) { final nl = payload[pos++]; protocols.add(utf8.decode(payload.sublist(pos, pos + nl))); pos += nl; }
    final speedCount = readInt16(payload, pos); pos += 2;
    final speeds = <int>[];
    for (int i = 0; i < speedCount; i++) { speeds.add(readUint32(payload, pos)); pos += 4; }
    speeds.sort();
    final defaultSpeed = readUint32(payload, pos); pos += 4;
    final hasAuto = payload[pos] != 0;
    state.toConnected(protocols, speeds, defaultSpeed, hasAuto);
    _startUdpHealthCheck();
    _startHeartbeat();
    _resetReconnectBackoff();
    setSpeed(defaultSpeed);
    // Async identity check — non-blocking legacy fallback
    commands.requestDeviceInfo();
  }

  void _onDeviceInfo(List<int> payload) {
    // ESP32 firmware may not support MSG_DEVICE_INFO yet — ignore parse failures
    try {
      if (payload.length < 2) return;
      // Check model field starts at byte 16 (after 16-byte deviceId)
      final modelBytes = payload.sublist(16, (16 + 16).clamp(0, payload.length));
      final model = utf8.decode(modelBytes).trim();
      if (model.isNotEmpty && model != 'Fogel Adapter') {
        debugPrint('[Identity] Wrong device: $model');
        disconnect(manual: true);
        globalSettings.value = globalSettings.value.copyWith(
          connectionError: 'Подключено неверное устройство',
        );
      }
    } catch (_) { /* legacy ESP32 — ignore */ }
  }

  void _onProtocolDetail(List<int> payload) {
    _cancelCmdTimeout(); int pos = 0;
    final nl = payload[pos++]; final name = utf8.decode(payload.sublist(pos, pos + nl)); pos += nl;
    final speed = readUint32(payload, pos); pos += 4;
    final plen = readInt16(payload, pos); pos += 2; final params = utf8.decode(payload.sublist(pos, pos + plen)); pos += plen;
    final clen = readInt16(payload, pos); pos += 2; final cmds = utf8.decode(payload.sublist(pos, pos + clen));
    _cachedProtocols[name] = {'speed': speed, 'params': params.split(','), 'commands': cmds.split(',')};
    if (_pendingSetProtocol == name) setProtocol(name);
  }

  void _onSpeedResult(List<int> payload) { _cancelCommandTimer(); _cancelCmdTimeout(); _applySetSpeedResult(readUint32(payload, 0)); }
  void _onProtoResult(List<int> payload) { _cancelCommandTimer(); _cancelCmdTimeout(); _applySetProtocolResult(payload[0] > 0 ? utf8.decode(payload.sublist(1, 1 + payload[0])) : null); }

  // TICK
  void _handleTickUdp(List<int> payload) {
    _lastTickReceivedAt = DateTime.now(); _resetUdpWatchdog();
    int pos = 0;
    final voltage = readNullableDouble(payload, pos, 10); pos += 2;
    final soc = readNullableDouble(payload, pos, 1, nullSentinel: 0x8000); pos += 2;
    final temperature = readNullableDouble(payload, pos, 10); pos += 2;
    final chargeCurrent = readNullableDouble(payload, pos, 10); pos += 2;
    final dischargeCurrent = readNullableDouble(payload, pos, 10); pos += 2;
    final flags = payload[pos++];
    final chargeOn = (flags & 0x01) != 0; final dischargeOn = (flags & 0x02) != 0; final prechargeOn = (flags & 0x04) != 0;
    final totalMessages = readUint32(payload, pos); pos += 4;
    final uniqueMessages = readUint32(payload, pos); pos += 4;
    final cellCount = payload[pos++];
    final cellVoltages = <double>[];
    for (int i = 0; i < cellCount; i++) { final raw = readInt16(payload, pos); pos += 2; cellVoltages.add(raw / 100.0); }
    // Pending command confirmation
    if (_pendingCommandType != null && _pendingCommandValue != null) {
      bool matched = false;
      switch (_pendingCommandType!) { case 'CHARGE': matched = chargeOn == _pendingCommandValue; case 'DISCHARGE': matched = dischargeOn == _pendingCommandValue; case 'PRECHARGE': matched = prechargeOn == _pendingCommandValue; }
      if (matched) { _commandStateTimer?.cancel(); _commandStateTimer = null; _clearPendingCommand(); }
    }
    final ns = CanStats(totalMessages: totalMessages, uniqueMessages: uniqueMessages);
    if (canStatsNotifier.value != ns) canStatsNotifier.value = ns;
    final nb = BmsData(batteryVoltage: voltage, soc: soc, temperature: temperature, chargeCurrent: chargeCurrent, dischargeCurrent: dischargeCurrent, cellVoltages: cellVoltages, cellCount: cellCount, chargeOn: chargeOn, dischargeOn: dischargeOn, prechargeOn: prechargeOn, totalMessages: totalMessages, uniqueMessages: uniqueMessages);
    if (bmsNotifier.value != nb) bmsNotifier.value = nb;
  }

  void _handleCanBatch(List<int> data) {
    if (data.isEmpty) return;
    final count = data[0]; if (count == 0) return;
    final msgs = <CanMessage>[]; int pos = 1;
    for (int i = 0; i < count; i++) {
      if (pos + 21 > data.length) break;
      msgs.add(CanMessage(isExtended: (readUint32(data, pos) > 0x7FF), id: readUint32(data, pos), dlc: data[pos + 4], data: data.sublist(pos + 5, pos + 5 + data[pos + 4]), period: readUint32(data, pos + 13), count: readUint32(data, pos + 17)));
      pos += 21;
    }
    canMessagesNotifier.value = msgs.length > _maxCanMessages ? msgs.sublist(msgs.length - _maxCanMessages) : msgs;
  }

  // ===================================================================
  // Commands
  // ===================================================================

  void requestConfiguration() => commands.requestConfiguration();
  void sendClearCan() => commands.sendClearCan();
  void getProtocol(String name) { _startCmdTimeout('Не удалось получить протокол.'); commands.getProtocol(name); }
  void setSpeed(int speed) { _startCmdTimeout('Не удалось установить скорость CAN-шины.'); commands.setSpeed(speed); }
  void setSpeedAuto() { _isAutoDetecting = true; globalSettings.value = globalSettings.value.copyWith(isAutoDetecting: true, isAutoSpeed: true, clearCurrentScanningSpeed: true, clearSelectedProtocol: true, clearProtocolParams: true, clearProtocolCommands: true); _startCmdTimeout('Не удалось определить скорость CAN-шины.'); commands.setSpeedAuto(); }
  void setProtocol(String? name) { if (name == null) { _startCmdTimeout('Не удалось очистить протокол.'); } else { _startCmdTimeout('Не удалось установить протокол.'); } commands.setProtocol(name); }
  void selectProtocol(String name) { _pendingSetProtocol = name; isLoadingProtocol.value = true; if (_cachedProtocols.containsKey(name)) { setProtocol(name); } else { getProtocol(name); } }
  void sendCommand(String type, bool value) {
    _pendingCommandType = type; _pendingCommandValue = value; pendingCommand.value = type;
    _commandStateTimer?.cancel();
    _commandStateTimer = Timer(_commandStateTimeout, () { if (_pendingCommandType == type) { _commandStateTimer = null; _clearPendingCommand(); globalSettings.value = globalSettings.value.copyWith(connectionError: 'Не удалось выполнить команду.'); } });
    commands.sendCommand(type, value);
  }

  // ===================================================================
  // Helpers
  // ===================================================================

  void _applySetSpeedResult(int speed) { if (_isAutoDetecting) { globalSettings.value = globalSettings.value.copyWith(currentScanningSpeed: speed, canSpeed: speed); } else { _finalizeProtocolSelection(speed); } }
  void _applySetProtocolResult(String? name) {
    if (name == null) { _pendingSetProtocol = null; isLoadingProtocol.value = false; globalSettings.value = globalSettings.value.copyWith(clearSelectedProtocol: true, clearProtocolParams: true, clearProtocolCommands: true); bmsNotifier.value = const BmsData(); }
    else { final speed = _cachedProtocols[name]?['speed'] as int?; _finalizeProtocolSelection(speed); }
  }
  void _finalizeProtocolSelection(int? speed) { final p = _pendingSetProtocol; final c = p != null ? _cachedProtocols[p] : null; _pendingSetProtocol = null; isLoadingProtocol.value = false; globalSettings.value = globalSettings.value.copyWith(selectedProtocol: p, canSpeed: speed, protocolParams: c?['params'] ?? [], protocolCommands: c?['commands'] ?? [], canNodes: []); bmsNotifier.value = const BmsData(); }
  void _clearPendingCommand() { _pendingCommandType = null; _pendingCommandValue = null; pendingCommand.value = null; }

  void _startCommandTimer(FogelConnectionState stage) { _cancelCommandTimer(); _commandTimer = Timer(_commandTimeout, () { if (globalSettings.value.connectionStatus == stage) { switch (stage) { case FogelConnectionState.connecting: case FogelConnectionState.pinging: _showError('Невозможно подключиться к устройству'); case FogelConnectionState.loadingConfig: _showError('Не удалось получить конфигурацию.'); default: _showError('Превышено время ожидания ответа.'); } } }); }
  void _cancelCommandTimer() { _commandTimer?.cancel(); _commandTimer = null; }
  void _startCmdTimeout(String msg) { _cmdTimeoutTimer?.cancel(); _cmdTimeoutTimer = Timer(_commandStateTimeout, () { _cmdTimeoutTimer = null; _pendingSetProtocol = null; isLoadingProtocol.value = false; _isAutoDetecting = false; globalSettings.value = globalSettings.value.copyWith(connectionError: msg); }); }
  void _cancelCmdTimeout() { _cmdTimeoutTimer?.cancel(); _cmdTimeoutTimer = null; }

  void _startUdpHealthCheck() => _resetUdpWatchdog();
  void _resetUdpWatchdog() { _udpHealthTimer?.cancel(); _udpHealthTimer = Timer(_udpStaleThreshold, () { if (globalSettings.value.connectionStatus == FogelConnectionState.connected) { debugPrint('[UDP] TICK stale'); globalSettings.value = globalSettings.value.copyWith(connectionStatus: FogelConnectionState.disconnected); } }); }
  void _stopUdpHealthCheck() { _udpHealthTimer?.cancel(); _udpHealthTimer = null; }

  void _showError(String message, {bool disconnectWifi = true}) { if (disconnectWifi) disconnect(disconnectWifi: true); globalSettings.value = FogelSettings(themeSetting: globalSettings.value.themeSetting, savedDevices: DeviceRepository.all, wifiEnabled: globalSettings.value.wifiEnabled, connectionError: message); }

  static void resetCanMessages() { canMessagesNotifier.value = []; }

  // ===================================================================
  // Heartbeat (Stage 10)
  // ===================================================================

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatFailCount = 0;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeatPing());
  }

  void _sendHeartbeatPing() {
    if (!isConnected) return;
    commands.sendPing();
    _heartbeatFailCount++;
    Timer(_heartbeatTimeout, () {
      if (_heartbeatFailCount >= _maxHeartbeatFails) {
        debugPrint('[Heartbeat] $_maxHeartbeatFails consecutive failures, reconnecting');
        _stopHeartbeat();
        _reconnectWithBackoff().then((ok) {
          if (ok) {
            _startHeartbeat();
          } else {
            disconnect(manual: true);
            globalSettings.value = globalSettings.value.copyWith(
              connectionError: 'Связь с адаптером потеряна',
            );
          }
        });
      }
    });
  }

  void _resetHeartbeat() {
    _heartbeatFailCount = 0;
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<bool> _reconnectWithBackoff() async {
    if (!canReconnect || _reconnectAttempts >= _retryDelaysSec.length) return false;
    final delay = _retryDelaysSec[_reconnectAttempts];
    _reconnectAttempts++;
    debugPrint('[Reconnect] Attempt $_reconnectAttempts/${_retryDelaysSec.length} in ${delay}s');
    await Future.delayed(Duration(seconds: delay));
    return await reconnect();
  }

  void _resetReconnectBackoff() { _reconnectAttempts = 0; }

  // --- Delegates ---
  static Future<void> loadSavedDevices() async { await DeviceRepository.load(); globalSettings.value = globalSettings.value.copyWith(savedDevices: DeviceRepository.all); }
  static Future<void> deleteDevice(String bssid) async { await DeviceRepository.delete(bssid); globalSettings.value = globalSettings.value.copyWith(savedDevices: DeviceRepository.all); }
  Future<void> saveDevice(String bssid, String name, String password) async { await DeviceRepository.save(bssid, name, password); globalSettings.value = globalSettings.value.copyWith(savedDevices: DeviceRepository.all); }
  Future<bool> isWifiEnabled() async => await WiFiChannel.isWifiEnabled();
  Future<List<WifiNetworkInfo>> scanNetworks() async => await WiFiChannel.scanNetworks();
}
