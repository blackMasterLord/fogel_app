import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_master/permission_master.dart';
import 'package:op_wifi_utils/op_wifi_utils.dart';
import '../models/fogel_settings.dart';
import '../services/device_secure_store.dart';
import '../services/fogel_adapter_service.dart';
import '../services/scan_controller.dart';
import '../services/wifi_channel.dart';
import 'password_page.dart';

bool get adapterPageIsScanning => ScanController().scanning;
int get adapterPageFoundCount => ScanController().foundCount;

class AdapterConnectPage extends StatefulWidget {
  const AdapterConnectPage({super.key});

  static ValueNotifier<int> get scanState => ScanController().stateNotifier;

  @override
  State<AdapterConnectPage> createState() => _AdapterConnectPageState();
}

class _AdapterConnectPageState extends State<AdapterConnectPage> with WidgetsBindingObserver {
  static const _wifiEnableTimeout = Duration(seconds: 30);

  final ScanController _scan = ScanController();
  StreamSubscription? _wifiSub;
  final ScrollController _listScrollController = ScrollController();
  bool _prevWifiEnabled = true;
  FogelConnectionState? _prevConnectionStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    globalSettings.addListener(_onSettingsChanged);
    _prevWifiEnabled = globalSettings.value.wifiEnabled;
    _prevConnectionStatus = globalSettings.value.connectionStatus;
    _refreshStatus();
    _wifiSub = WiFiChannel.onWifiChanged.listen((_) => _refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    globalSettings.removeListener(_onSettingsChanged);
    _wifiSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final settings = globalSettings.value;
    final status = settings.connectionStatus;

    if (!settings.wifiEnabled && _prevWifiEnabled) {
      _scan.stop();
      _scan.reset();
    }
    _prevWifiEnabled = settings.wifiEnabled;

    if (_prevConnectionStatus == FogelConnectionState.connected && status == FogelConnectionState.disconnected) {
      if (!_scan.manualDisconnect && !FogelAdapterService().isAutoReconnecting) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Связь с адаптером потеряна'), backgroundColor: Colors.red)); }
        });
      }
      _scan.manualDisconnect = false;
    }
    _prevConnectionStatus = status;
    setState(() {});
  }

  Future<void> _refreshStatus() async {
    final enabled = await FogelAdapterService().isWifiEnabled();
    if (mounted && !_scan.scanning) {
      if (globalSettings.value.wifiEnabled != enabled) {
        globalSettings.value = globalSettings.value.copyWith(wifiEnabled: enabled);
      }
    }
  }

  // === Permissions ===

  static const _requiredPermissions = [
    _PermItem(russianName: 'точное местоположение',       type: PermissionType.fineLocation, rawPermission: 'android.permission.ACCESS_FINE_LOCATION'),
    _PermItem(russianName: 'поиск устройств поблизости', type: PermissionType.nearbyDevices, rawPermission: 'android.permission.NEARBY_WIFI_DEVICES'),
  ];

  Future<bool> _requestPermissions() async {
    final pm = PermissionMaster();

    // 1. Check current statuses
    final missing = <_PermItem>[];
    for (final p in _requiredPermissions) {
      final status = await pm.checkPermissionStatus(p.rawPermission);
      if (status != PermissionStatus.granted) missing.add(p);
    }
    if (missing.isEmpty) return true;

    // 2. Custom rationale dialog BEFORE system dialog
    final accepted = await _showRationale(missing);
    if (!accepted || !mounted) return false;

    // 3. Request each missing permission via permission_master
    final failed = <_PermItem>[];
    for (final p in missing) {
      final status = await pm.requestPermissionWithDialog(
        permission: p.type,
        title: 'Доступ к местоположению',
        message: 'Для поиска и подключения к Fogel Adapter необходим доступ к ${p.russianName}.',
      );
      if (status != PermissionStatus.granted) failed.add(p);
    }

    // 4. Special case: FINE denied + COARSE granted = user chose "Approximate"
    if (!await _checkApproximate(pm)) return false;

    // 5. All granted?
    if (failed.isEmpty) return true;

    // 6. Final dialog: permanently blocked
    await _showBlockedDialog(failed, pm);
    return false;
  }

  // --- Permission helpers ---

  Future<bool> _showRationale(List<_PermItem> missing) async {
    final names = missing.map((p) => '• ${p.russianName}').join('\n');
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      icon: Icon(Icons.wifi_rounded, color: Theme.of(context).colorScheme.primary, size: 48),
      title: const Text('Доступ к местоположению'),
      content: Text('Для поиска адаптеров необходимо предоставить разрешения:\n\n$names'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отменить')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Продолжить')),
      ],
    )) ?? false;
  }

  Future<bool> _checkApproximate(PermissionMaster pm) async {
    // If FINE is granted — not an approximate issue
    final fineStatus = await pm.checkPermissionStatus('android.permission.ACCESS_FINE_LOCATION');
    if (fineStatus == PermissionStatus.granted) return true;

    // Check if COARSE was granted instead (user chose "Approximate")
    final coarseStatus = await pm.checkPermissionStatus('android.permission.ACCESS_COARSE_LOCATION');
    if (coarseStatus != PermissionStatus.granted) return true; // not an approximate issue

    if (!mounted) return false;
    final goSettings = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.location_searching, color: Colors.blue, size: 48),
      title: const Text('Точное местоположение'),
      content: const Text('Для поиска адаптеров нужно точное местоположение.\n\nВ настройках выберите «Точное» вместо «Приблизительно».'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Позже')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Открыть настройки')),
      ],
    ));
    if (goSettings == true) await pm.openAppSettingsDirectly();
    return false;
  }

  Future<void> _showBlockedDialog(List<_PermItem> failed, PermissionMaster pm) async {
    if (!mounted) return;
    final names = failed.map((p) => '• ${p.russianName}').join('\n');
    final goSettings = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.block, color: Colors.red, size: 48),
      title: const Text('Разрешения отклонены'),
      content: Text('Разрешения полностью отклонены. Включите в настройках приложения:\n\n$names'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Закрыть')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Открыть настройки')),
      ],
    ));
    if (goSettings == true) await pm.openAppSettingsDirectly();
  }

  // === Scan ===

  Future<void> _doScan() async {
    debugPrint('[SCAN-DEBUG] _doScan: starting');
    final granted = await _requestPermissions();
    debugPrint('[SCAN-DEBUG] _doScan: permissions=$granted mounted=$mounted');
    if (!mounted) return;
    if (!granted) {
      _scan.scanError = 'Для поиска устройств необходимо разрешить доступ к местоположению';
      _scan.stateNotifier.value++;
      return;
    }
    debugPrint('[SCAN-DEBUG] _doScan: calling _scan.start(), scanning=${_scan.scanning}');
    await _scan.start();
    debugPrint('[SCAN-DEBUG] _doScan: _scan.start() returned, networks=${_scan.networks?.length}');
    if (mounted) setState(() {});
  }

  // === Connect ===

  Future<void> _onNetworkTap(WifiNetworkInfo network) async {
    final settings = globalSettings.value;
    if (settings.connectionStatus == FogelConnectionState.connected && settings.connectedDeviceAddress == network.bssid) return;

    final saved = _findSavedDevice(network.bssid);
    final device = saved ?? SavedDevice(address: network.bssid, name: network.ssid);

    if (!network.isOpen && saved == null) {
      await Navigator.push(context, PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => PasswordPage(
          device: device, connectFn: (d, r, p) => _connectToDevice(d, r, false, p),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
      ));
    } else {
      _connectToDevice(device);
    }
  }

  bool _isConnectingToDevice = false;

  Future<bool> _connectToDevice(SavedDevice device, [bool remember = true, bool showErrors = true, String? password]) async {
    if (!mounted || _isConnectingToDevice) return false;
    _isConnectingToDevice = true;

    // Use provided password or fall back to secure storage (for saved/reconnect)
    final pwd = password ?? await DeviceSecureStore.getPassword(device.address) ?? '';

    try {
      globalSettings.value = globalSettings.value.copyWith(
        connectionStatus: FogelConnectionState.connecting,
        connectedDeviceAddress: device.address, connectedDeviceName: device.name, connectionError: null);
      if (mounted) setState(() {});

      final wifiEnabled = await FogelAdapterService().isWifiEnabled();
      if (!mounted) return false;
      if (!wifiEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Для подключения к адаптеру необходимо включить WiFi'),
            backgroundColor: Theme.of(context).colorScheme.primary));
        await WiFiChannel.showWifiPanel();
        final enabled = await _waitForWifiEnable();
        if (!enabled || !mounted) { _resetConnectionStatus(); return false; }
      }

      // Quick freshness scan
      if (_scan.networks == null || _scan.lastScanTime == null || DateTime.now().difference(_scan.lastScanTime!) > const Duration(seconds: 5)) {
        try {
          final nets = await FogelAdapterService().scanNetworks().timeout(const Duration(seconds: 3));
          _scan.networks = nets.where((n) => n.ssid.startsWith('Fogel Adapter')).toList();
          _scan.lastScanTime = DateTime.now();
        } catch (_) {}
      }

      if (!_scan.isInRange(device.address) && _scan.networks != null) {
        _showConnectionError('Адаптер недоступен');
        _resetConnectionStatus(); return false;
      }

      final wifiResult = await OpWifiUtils.connectToWifi(
        ssid: device.name, password: pwd.isNotEmpty ? pwd : null,
        bssid: device.address, timeout: const Duration(seconds: 20));

      if (!mounted) return false;
      if (!wifiResult.isSuccess) {
        if (pwd.isNotEmpty) {
          if (!_scan.isInRange(device.address) && _scan.networks != null) {
            _scan.reset(); _showConnectionError('Адаптер недоступен');
          } else {
            _showConnectionError('Не удалось подключиться к адаптеру');
          }
        } else {
          _showConnectionError('Адаптер недоступен');
        }
        _resetConnectionStatus(); return false;
      }

      _scan.stop();
      if (remember && pwd.isNotEmpty) FogelAdapterService().saveDevice(device.address, device.name, pwd);
      await _refreshStatus();

      FogelAdapterService().connect(device.name, device.name, bssid: device.address, skipWifi: true)
        .timeout(const Duration(seconds: 20), onTimeout: () => false)
        .then((ok) { if (!ok && mounted) { _showConnectionError('Не удалось установить TCP-соединение'); _resetConnectionStatus(); } });

      return true;
    } catch (e) {
      if (mounted && showErrors) _showConnectionError('Ошибка: $e');
      _resetConnectionStatus(); return false;
    } finally {
      _isConnectingToDevice = false;
    }
  }

  void _showConnectionError(String msg) => globalSettings.value = globalSettings.value.copyWith(connectionError: msg);

  void _resetConnectionStatus() {
    if (!mounted) return;
    final s = globalSettings.value;
    if (s.connectionStatus == FogelConnectionState.connecting || s.connectionStatus == FogelConnectionState.pinging ||
        s.connectionStatus == FogelConnectionState.loadingConfig || s.connectionStatus == FogelConnectionState.reconnecting) {
      globalSettings.value = s.copyWith(connectionStatus: FogelConnectionState.disconnected);
    }
  }

  Future<bool> _waitForWifiEnable() async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < _wifiEnableTimeout) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return false;
      if (await FogelAdapterService().isWifiEnabled()) return true;
    }
    return false;
  }

  SavedDevice? _findSavedDevice(String bssid) {
    for (final d in globalSettings.value.savedDevices) { if (d.address == bssid) return d; }
    return null;
  }

  Color _signalColor(int level) {
    if (level >= 4) return Colors.green;
    if (level >= 3) return Colors.lightGreen;
    if (level >= 2) return Colors.orange;
    return Colors.red;
  }

  // ===================================================================
  // UI — matches original layout exactly
  // ===================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Адаптер')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_scan.stateNotifier, globalSettings]),
        builder: (context, _) {
          final settings = globalSettings.value;
          return Column(children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: settings.wifiEnabled ? const SizedBox.shrink() : Material(
                color: Colors.red.withValues(alpha: 0.1),
                child: InkWell(
                  onTap: () => WiFiChannel.enableWifi(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    child: const Row(children: [
                      Icon(Icons.wifi_off, color: Colors.red), SizedBox(width: 10),
                      Expanded(child: Text('Для подключения к адаптеру необходимо включить WiFi.',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                      Icon(Icons.chevron_right, color: Colors.red, size: 24),
                    ]),
                  ),
                ),
              ),
            ),
            Expanded(child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildStatusSection(settings),
              ),
              const SizedBox(height: 16),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildConnectButton(settings),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: settings.connectionError != null
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            width: double.infinity, padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.red.withAlpha(15), borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 18), const SizedBox(width: 10),
                              Expanded(child: Text(settings.connectionError!, style: const TextStyle(fontSize: 13, color: Colors.red))),
                            ]),
                          ),
                        ),
                      ])
                    : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Expanded(child: Text('Список адаптеров', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                  TextButton.icon(
                    onPressed: (!settings.wifiEnabled || _scan.scanning || settings.isConnecting) ? null : _doScan,
                    icon: _scan.scanning
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400]))
                        : const Icon(Icons.refresh, size: 20),
                    label: const Text('Поиск'),
                    style: TextButton.styleFrom(
                      foregroundColor: (!settings.wifiEnabled || _scan.scanning || settings.isConnecting) ? Colors.grey[400] : Theme.of(context).colorScheme.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildScanBody(settings)),
            ])),
          ]);
          },
        ),
      );
  }

  Widget _buildStatusSection(FogelSettings settings) {
    final isConnected = settings.connectionStatus == FogelConnectionState.connected;
    final isConnecting = settings.isConnecting;

    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('Статус', style: TextStyle(fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(isConnected ? 'Подключен' : isConnecting ? 'Подключение к' : 'Не подключен', style: const TextStyle(fontSize: 13)),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 250), curve: Curves.easeInOut, alignment: Alignment.topCenter,
            child: isConnected || isConnecting
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 4),
                    Row(children: [const Spacer(), Text(settings.connectedDeviceName, style: const TextStyle(fontSize: 13))]),
                  ])
                : const SizedBox.shrink(),
          ),
        ])),
      ]),
    ));
  }

  Widget _buildConnectButton(FogelSettings settings) {
    final isConnected = settings.connectionStatus == FogelConnectionState.connected;
    final isConnecting = settings.isConnecting;

    Widget? child;
    if (isConnected) {
      child = SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: () {
          _scan.manualDisconnect = true;
          FogelAdapterService().disconnect(manual: true, disconnectWifi: true);
        },
        style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: const Icon(Icons.link_off), label: const Text('Отключить'),
      ));
    } else if (isConnecting) {
      child = SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () {
          _scan.manualDisconnect = true;
          FogelAdapterService().disconnect(manual: true, disconnectWifi: true);
        },
        style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange), padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: const Icon(Icons.close), label: const Text('Отмена'),
      ));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250), switchInCurve: Curves.easeOut, switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: child ?? const SizedBox.shrink(),
    );
  }

  Widget _buildScanBody(FogelSettings settings) {
    final wifiOn = settings.wifiEnabled;
    final scanErr = _scan.scanError;
    final nets = _scan.networks;
    final scanning = _scan.scanning;
    debugPrint('[SCAN-DEBUG] _buildScanBody: wifiOn=$wifiOn isConnecting=${settings.isConnecting} scanErr=$scanErr nets=${nets?.length} scanning=$scanning');
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isConnecting = settings.isConnecting;

    if (!settings.wifiEnabled) {
      return Center(child: Padding(
      padding: EdgeInsets.only(bottom: bottomPadding), child: const Text('Включите WiFi для поиска адаптеров')));
    }

    if (isConnecting) {
      return Center(child: Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(height: 16),
        Text('Подключение...', style: TextStyle(color: Colors.grey[600], fontSize: 15)),
      ])));
    }

    if (_scan.scanError != null) {
      return Center(child: Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: Colors.grey[400]), const SizedBox(height: 12),
        Text(_scan.scanError!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
      ])));
    }

    final scannedSsids = <String>{};
    final tiles = <Widget>[];

    if (_scan.networks != null) {
      for (final network in _scan.networks!) {
        scannedSsids.add(network.ssid);
        if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 8));
        tiles.add(_buildNetworkTile(network, settings));
      }
    }

    if (!_scan.scanning && _scan.networks != null && settings.connectionStatus != FogelConnectionState.connected && !isConnecting) {
      for (final d in settings.savedDevices) {
        if (!scannedSsids.contains(d.name) && d.address != settings.connectedDeviceAddress) {
          if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 8));
          tiles.add(_buildOfflineDeviceTile(d));
        }
      }
    }

    Widget content;
    String key;

    if (_scan.scanning && tiles.isEmpty) {
      key = 'scanning';
      content = Center(child: Padding(padding: EdgeInsets.only(bottom: bottomPadding), child: const Text('Поиск адаптеров...')));
    } else if (tiles.isEmpty) {
      key = 'empty';
      content = Center(child: Padding(padding: EdgeInsets.only(bottom: bottomPadding), child: const Text('Адаптеры не найдены')));
    } else {
      key = 'list';
      content = Scrollbar(
        controller: _listScrollController, thumbVisibility: true,
        child: ListView(controller: _listScrollController, padding: EdgeInsets.only(left: 16, right: 16, bottom: 16 + bottomPadding), children: tiles),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250), switchInCurve: Curves.easeOut, switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(key), child: content),
    );
  }

  Widget _buildNetworkTile(WifiNetworkInfo network, FogelSettings settings) {
    final saved = _findSavedDevice(network.bssid);
    final signal = network.signalLevel;
    final isCurrentDevice = settings.connectionStatus == FogelConnectionState.connected && settings.connectedDeviceAddress == network.bssid;

    String? subtitle;
    Color? subtitleColor;
    if (isCurrentDevice) { subtitle = 'Текущее подключение'; subtitleColor = Colors.green; }
    else if (saved != null) { subtitle = 'Сохранен'; subtitleColor = Colors.grey[500]; }
    else { subtitle = 'Доступен для подключения'; subtitleColor = Colors.green; }

    return Card(clipBehavior: Clip.antiAlias, child: ListTile(
      leading: _buildSignalIcon(signal),
      title: Text(network.ssid, style: TextStyle(fontWeight: FontWeight.w500, color: isCurrentDevice ? Colors.grey : null), overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: subtitleColor)),
      trailing: isCurrentDevice ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : saved != null ? const Icon(Icons.link, color: Colors.green, size: 20) : const Icon(Icons.chevron_right),
      onTap: () => _onNetworkTap(network),
      onLongPress: saved != null ? () => _showDeviceContextMenu(saved) : null,
    ));
  }

  Widget _buildOfflineDeviceTile(SavedDevice device) {
    final settings = globalSettings.value;
    final isCurrentDevice = settings.connectionStatus == FogelConnectionState.connected && settings.connectedDeviceAddress == device.address;

    return Card(clipBehavior: Clip.antiAlias, child: ListTile(
      leading: _buildSignalIcon(0),
      title: Text(device.name, style: TextStyle(fontWeight: FontWeight.w500, color: Colors.red[300]), overflow: TextOverflow.ellipsis),
      subtitle: Text('Недоступен', style: TextStyle(fontSize: 12, color: Colors.red[200])),
      trailing: isCurrentDevice ? const Icon(Icons.check_circle, color: Colors.green, size: 20) : null,
      onLongPress: () => _showDeviceContextMenu(device),
    ));
  }

  Widget _buildSignalIcon(int level) {
    final color = _signalColor(level);
    final bars = level.clamp(0, 4);
    return SizedBox(width: 24, height: 24, child: CustomPaint(painter: _SignalBarsPainter(bars: bars, color: color)));
  }

  void _showDeviceContextMenu(SavedDevice device) {
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 12),
      ListTile(
        leading: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('Забыть', style: TextStyle(color: Colors.red)),
        onTap: () async {
          Navigator.pop(ctx);
          _scan.manualDisconnect = true;
          FogelAdapterService().disconnect(manual: true, disconnectWifi: false);
          await FogelAdapterService.deleteDevice(device.address);
          setState(() {});
        },
      ),
      const SizedBox(height: 12),
    ])));
  }
}

// ===================================================================
// Signal Bars Painter — matches original design
// ===================================================================

class _SignalBarsPainter extends CustomPainter {
  final int bars;
  final Color color;
  _SignalBarsPainter({required this.bars, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 3..strokeCap = StrokeCap.round;
    const gap = 2.0;
    final barWidth = (size.width - gap * 3) / 4;
    final maxHeight = size.height;

    for (int i = 0; i < 4; i++) {
      final barHeight = maxHeight * (0.3 + 0.23 * i);
      final x = i * (barWidth + gap);
      final y = maxHeight - barHeight;
      final opacity = i < bars ? 1.0 : 0.2;
      paint.color = color.withValues(alpha: opacity);
      canvas.drawLine(Offset(x + barWidth / 2, y), Offset(x + barWidth / 2, maxHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalBarsPainter old) => old.bars != bars || old.color != color;
}

class _PermItem {
  final String russianName;
  final PermissionType type;
  final String rawPermission;
  const _PermItem({required this.russianName, required this.type, required this.rawPermission});
}
