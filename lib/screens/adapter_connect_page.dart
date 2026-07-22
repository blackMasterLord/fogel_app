import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:op_wifi_utils/op_wifi_utils.dart';
import '../models/fogel_settings.dart';
import '../services/fogel_adapter_service.dart';
import '../services/wifi_channel.dart';
import 'password_page.dart';

class AdapterConnectPage extends StatefulWidget {
  const AdapterConnectPage({super.key});

  @override
  State<AdapterConnectPage> createState() => _AdapterConnectPageState();
}

class _AdapterConnectPageState extends State<AdapterConnectPage>
    with WidgetsBindingObserver {
  static const _wifiEnableTimeout = Duration(seconds: 30);

  static List<WifiNetworkInfo>? _fogelNetworks;
  static String? _scanError;
  static bool _scanning = false;
  static bool _suppressWifiRefresh = false;
  static bool _manualDisconnect = false;
  StreamSubscription? _wifiSub;
  final ScrollController _listScrollController = ScrollController();
  bool _prevWifiEnabled = true;
  String? _prevConnectionStatus;
  bool _waitingForSettingsReturn = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[AdapterPage] initState');
    WidgetsBinding.instance.addObserver(this);
    globalSettings.addListener(_onSettingsChanged);
    _scanning = false;
    _prevWifiEnabled = globalSettings.value.wifiEnabled;
    _prevConnectionStatus = globalSettings.value.connectionStatus;
    _refreshStatus();
    _wifiSub = WiFiChannel.onWifiChanged.listen((_) {
      _refreshStatus();
    });
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
    debugPrint('[AdapterPage] lifecycle: $state');
    if (state == AppLifecycleState.resumed) {
      if (_waitingForSettingsReturn) {
        _waitingForSettingsReturn = false;
        _checkPermissionsAfterSettingsReturn();
      } else {
        _refreshStatus();
        // After OS permission dialog, Activity may have been recreated.
        // If permission is now granted and no scan in progress, auto-scan.
        _resumeScanIfPermissionGranted();
      }
    }
  }

  Future<void> _resumeScanIfPermissionGranted() async {
    debugPrint('[AdapterPage] _resumeScanIfPermissionGranted: scanning=$_scanning connecting=$_isConnectingToDevice fogelNetworks=$_fogelNetworks');
    if (_scanning || _isConnectingToDevice) return;
    final s = globalSettings.value;
    if (s.connectionStatus == 'connected') return;

    // Force WiFi state refresh before checking
    final wifiEnabled = await FogelAdapterService().isWifiEnabled();
    debugPrint('[AdapterPage] _resumeScanIfPermissionGranted: wifiEnabled=$wifiEnabled');
    if (mounted && globalSettings.value.wifiEnabled != wifiEnabled) {
      globalSettings.value = globalSettings.value.copyWith(wifiEnabled: wifiEnabled);
    }

    if (!wifiEnabled) return; // WiFi off — scanning impossible

    final locStatus = await Permission.location.status;
    final nearbyStatus = await Permission.nearbyWifiDevices.status;
    if ((locStatus.isGranted || locStatus.isLimited || nearbyStatus.isGranted) && !_scanning && mounted) {
      _doScan();
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;

    final settings = globalSettings.value;
    final status = settings.connectionStatus;

    // WiFi turned off → stop scan, clear list
    if (!settings.wifiEnabled && _prevWifiEnabled) {
      _stopScanning();
      _fogelNetworks = null;
    }
    _prevWifiEnabled = settings.wifiEnabled;

    // Connection lost unexpectedly → show snackbar
    if (_prevConnectionStatus == 'connected' && status == 'disconnected') {
      if (!_manualDisconnect && !FogelAdapterService().isAutoReconnecting) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Связь с адаптером потеряна'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      }
      _manualDisconnect = false;
    }

    _prevConnectionStatus = status;
    setState(() {});
  }

  Future<void> _refreshStatus() async {
    final enabled = await FogelAdapterService().isWifiEnabled();
    debugPrint('[AdapterPage] _refreshStatus: enabled=$enabled scanning=$_scanning suppress=$_suppressWifiRefresh');
    if (mounted && !_scanning && !_suppressWifiRefresh) {
      if (globalSettings.value.wifiEnabled != enabled) {
        globalSettings.value = globalSettings.value.copyWith(wifiEnabled: enabled);
      }
    }
  }

  Future<void> _checkPermissionsAfterSettingsReturn() async {
    final status = await Permission.location.status;
    if (status.isGranted || status.isLimited) {
      // Permission was granted in settings — auto-scan
      _doScan();
    } else {
      // Still not granted — refresh status anyway
      _refreshStatus();
    }
  }

  // --- Permissions ---

  Future<bool> _requestPermissions() async {
    // Android 13+ needs NEARBY_WIFI_DEVICES; older needs ACCESS_FINE_LOCATION.
    final locStatus = await Permission.location.status;
    final nearbyStatus = await Permission.nearbyWifiDevices.status;
    debugPrint('[AdapterPage] _requestPermissions: location=$locStatus nearby=$nearbyStatus');

    // Already have sufficient permission
    if (nearbyStatus.isGranted || locStatus.isGranted || locStatus.isLimited) return true;

    // Restricted
    if (locStatus.isRestricted) {
      if (mounted) {
        await showDialog(context: context, builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.block, color: Colors.red, size: 48),
          title: const Text('Доступ ограничен'),
          content: const Text('Разрешение ограничено. Обратитесь к разработчику.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ок'))],
        ));
      }
      return false;
    }

    // Rationale if previously denied
    if (locStatus.isDenied) {
      if (!mounted) return false;
      final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        icon: Icon(Icons.wifi_rounded, color: Theme.of(context).colorScheme.primary, size: 48),
        title: const Text('Доступ к местоположению'),
        content: const Text('Для поиска и подключения к Fogel Adapter необходим доступ к местоположению и устройствам поблизости.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не сейчас')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Продолжить')),
        ],
      ));
      if (accepted != true || !mounted) return false;
    }

    // Request both — platform picks the right one
    await Permission.location.request();
    await Permission.nearbyWifiDevices.request();

    final newLoc = await Permission.location.status;
    final newNearby = await Permission.nearbyWifiDevices.status;
    if (newNearby.isGranted || newLoc.isGranted || newLoc.isLimited) return true;

    // Still not granted — show settings redirect
    if (mounted) {
      await showDialog(context: context, builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
        title: const Text('Разрешение отклонено'),
        content: const Text('Необходимо предоставить доступ к местоположению или устройствам поблизости в настройках.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ок')),
          FilledButton(onPressed: () { _waitingForSettingsReturn = true; Navigator.pop(context); openAppSettings(); },
            child: const Text('Перейти в настройки')),
        ],
      ));
    }
    return false;
  }

  // --- WiFi enable ---

  Future<bool> _waitForWifiEnable() async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < _wifiEnableTimeout) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return false;
      final enabled = await FogelAdapterService().isWifiEnabled();
      if (enabled) return true;
    }
    return false;
  }

  // --- Scan ---

  void _stopScanning() {
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _doScan() async {
    debugPrint('[AdapterPage] _doScan START');
    final granted = await _requestPermissions();
    debugPrint('[AdapterPage] _doScan: granted=$granted mounted=$mounted');
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _scanError = 'Для поиска устройств необходимо разрешить доступ к местоположению';
      });
      return;
    }

    setState(() {
      _scanning = true;
      _fogelNetworks = [];
      _scanError = null;
    });

    Future<void> scanCycle() async {
      if (!_scanning) return;
      if (!globalSettings.value.wifiEnabled) { _stopScanning(); return; }
      try {
        final networks = await FogelAdapterService().scanNetworks();
        if (!_scanning) return;
        final fogelNetworks = networks
            .where((n) => n.ssid.startsWith('Fogel Adapter'))
            .toList();

        _fogelNetworks = fogelNetworks
          ..sort((a, b) => b.signalLevel.compareTo(a.signalLevel));
        if (mounted) setState(() {});
      } catch (_) {}
    }

    await scanCycle();
    if (!_scanning) return;

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (_scanning && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 4));
      if (!_scanning) return;
      if (!globalSettings.value.wifiEnabled) { _stopScanning(); return; }
      await scanCycle();
    }
    _stopScanning();
  }

  // --- Network selection ---

  Future<void> _onNetworkTap(WifiNetworkInfo network) async {
    final settings = globalSettings.value;
    if (settings.connectionStatus == 'connected' &&
        settings.connectedDeviceAddress == network.bssid) {
      return;
    }

    final saved = _findSavedDevice(network.bssid);

    final device = saved ?? SavedDevice(
      address: network.bssid,
      name: network.ssid,
      password: '',
    );

    if (!network.isOpen && saved == null) {
      await Navigator.push(context, PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => PasswordPage(
          device: device,
          connectFn: (d, r) => _connectToDevice(d, r, false),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ));
    } else {
      _connectToDevice(device);
    }
  }

  // --- Connect ---

  bool _isConnectingToDevice = false;

  Future<bool> _connectToDevice(SavedDevice device, [bool remember = true, bool showErrors = true]) async {
    if (!mounted || _isConnectingToDevice) return false;
    _isConnectingToDevice = true;

    try {
      globalSettings.value = globalSettings.value.copyWith(
        connectionStatus: 'connecting',
        connectedDeviceAddress: device.address,
        connectedDeviceName: device.name,
        connectionError: null,
      );
      if (mounted) setState(() {});

      // Check WiFi
      final wifiEnabled = await FogelAdapterService().isWifiEnabled();
      if (!mounted) return false;

      if (!wifiEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Для подключения к адаптеру необходимо включить WiFi'),
            backgroundColor: Theme.of(context).colorScheme.primary),
        );
        await WiFiChannel.showWifiPanel();
        final enabled = await _waitForWifiEnable();
        if (!enabled || !mounted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Не удалось включить WiFi'), backgroundColor: Colors.red));
          }
          _resetConnectionStatus();
          return false;
        }
      }

      // Check if adapter is still in range using latest scan results
      final inScanResults = _fogelNetworks?.any((n) => n.bssid == device.address) ?? true;

      if (!inScanResults && _fogelNetworks != null) {
        _showConnectionError('Адаптер недоступен — не в зоне действия WiFi');
        _resetConnectionStatus();
        return false;
      }

      // Connect WiFi
      _suppressWifiRefresh = true;
      try {
        final wifiResult = await OpWifiUtils.connectToWifi(
          ssid: device.name,
          password: device.password.isNotEmpty ? device.password : null,
          bssid: device.address,
          timeout: const Duration(seconds: 20),
        );

        if (!mounted) return false;

        if (!wifiResult.isSuccess) {
          debugPrint('[AdapterPage] WiFi connect FAILED: ${wifiResult.error.type}');
          await _refreshStatus();
          if (device.password.isNotEmpty) {
            _showConnectionError('Не удалось подключиться к адаптеру');
          } else {
            _showConnectionError('Адаптер недоступен');
          }
          _resetConnectionStatus();
          return false;
        }

        // WiFi connected
        _stopScanning();
      } finally {
        _suppressWifiRefresh = false;
      }
      if (remember && device.password.isNotEmpty) {
        FogelAdapterService().saveDevice(device.address, device.name, device.password);
      }

      await _refreshStatus();

      // TCP connection with unified timeout
      final connected = await FogelAdapterService().connect(
        device.name, device.name, bssid: device.address, skipWifi: true,
      ).timeout(const Duration(seconds: 20), onTimeout: () => false);

      if (!mounted) return false;

      if (!connected) {
        if (showErrors) {
          _showConnectionError('Адаптер не отвечает — не удалось установить TCP-соединение');
        }
        _resetConnectionStatus();
        return false;
      }

      return true;
    } catch (e) {
      _suppressWifiRefresh = false;
      if (mounted && showErrors) {
        _showConnectionError('Ошибка подключения: $e');
      }
      _resetConnectionStatus();
      return false;
    } finally {
      _isConnectingToDevice = false;
    }
  }

  void _showConnectionError(String message) {
    globalSettings.value = globalSettings.value.copyWith(connectionError: message);
  }

  void _resetConnectionStatus() {
    if (!mounted) return;
    final s = globalSettings.value;
    if (s.connectionStatus == 'connecting' || s.connectionStatus == 'pinging' ||
        s.connectionStatus == 'loading_config' || s.connectionStatus == 'reconnecting') {
      globalSettings.value = s.copyWith(
        connectionStatus: 'disconnected',
        connectionError: null,
      );
    }
  }

  // --- Helpers ---

  SavedDevice? _findSavedDevice(String bssid) {
    for (final d in globalSettings.value.savedDevices) {
      if (d.address == bssid) return d;
    }
    return null;
  }

  Color _signalColor(int level) {
    if (level >= 4) return Colors.green;
    if (level >= 3) return Colors.lightGreen;
    if (level >= 2) return Colors.orange;
    return Colors.red;
  }

  bool _isConnecting(FogelSettings s) => s.isConnecting;

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Адаптер')),
      body: ValueListenableBuilder<FogelSettings>(
        valueListenable: globalSettings,
        builder: (context, settings, _) {
          return Column(
            children: [
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
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_off, color: Colors.red),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Для подключения к адаптеру необходимо включить WiFi.',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Colors.red, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
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
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withAlpha(15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(settings.connectionError!,
                                            style: const TextStyle(fontSize: 13, color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    //const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Список адаптеров',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ),
                          TextButton.icon(
                            onPressed: (!settings.wifiEnabled || _scanning || _isConnecting(settings)) ? null : _doScan,
                            icon: _scanning
                                ? SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400]),
                                  )
                                : const Icon(Icons.refresh, size: 20),
                            label: const Text('Поиск'),
                            style: TextButton.styleFrom(
                              foregroundColor: (!settings.wifiEnabled || _scanning || _isConnecting(settings)) ? Colors.grey[400] : Theme.of(context).colorScheme.primary,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _buildScanBody(settings),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Status section (adapter only, no WiFi) ---

  Widget _buildStatusSection(FogelSettings settings) {
    final isConnected = settings.connectionStatus == 'connected';
    final isConnecting = _isConnecting(settings);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Статус',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Text(
                        isConnected
                            ? 'Подключен'
                            : isConnecting
                                ? 'Подключение к'
                                : 'Не подключен',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: isConnected || isConnecting
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Spacer(),
                                  Text(
                                    settings.connectedDeviceName,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Connect / Disconnect button ---

  Widget _buildConnectButton(FogelSettings settings) {
    final isConnected = settings.connectionStatus == 'connected';
    final isConnecting = _isConnecting(settings);

    Widget? child;
    if (isConnected) {
      child = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () {
            _manualDisconnect = true;
            FogelAdapterService().disconnect(manual: true, disconnectWifi: true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Устройство отключено'),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.link_off),
          label: const Text('Отключить'),
        ),
      );
    } else if (isConnecting) {
      child = SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            _manualDisconnect = true;
            FogelAdapterService().disconnect(manual: true, disconnectWifi: true);
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            side: const BorderSide(color: Colors.orange),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.close),
          label: const Text('Отмена'),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: child ?? const SizedBox.shrink(),
    );
  }

  Widget _buildScanBody(FogelSettings settings) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isConnecting = _isConnecting(settings);

    if (!settings.wifiEnabled) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: const Text('Включите WiFi для поиска адаптеров'),
        ),
      );
    }

    if (isConnecting) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(height: 16),
              Text('Подключение...', style: TextStyle(color: Colors.grey[600], fontSize: 15)),
            ],
          ),
        ),
      );
    }

    if (_scanError != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(_scanError!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    // Build adapter list
    final scannedSsids = <String>{};
    final tiles = <Widget>[];

    // Found adapters
    if (_fogelNetworks != null) {
      for (final network in _fogelNetworks!) {
        scannedSsids.add(network.ssid);
        if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 8));
        tiles.add(_buildNetworkTile(network, settings));
      }
    }

    // Offline saved devices — only after a scan completed and device wasn't found
    if (!_scanning && _fogelNetworks != null &&
        settings.connectionStatus != 'connected' && !_isConnecting(settings)) {
        for (final d in settings.savedDevices) {
          if (!scannedSsids.contains(d.name) && d.address != settings.connectedDeviceAddress) {
            if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 8));
            tiles.add(_buildOfflineDeviceTile(d));
          }
        }
    }

    Widget content;
    String key;

    if (_scanning && tiles.isEmpty) {
      key = 'scanning';
      content = Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: const Text('Поиск адаптеров...'),
        ),
      );
    } else if (tiles.isEmpty) {
      key = 'empty';
      content = Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: const Text('Адаптеры не найдены'),
        ),
      );
    } else {
      key = 'list';
      content = Scrollbar(
        controller: _listScrollController,
        thumbVisibility: true,
        child: ListView(
          controller: _listScrollController,
          padding: EdgeInsets.only(
            left: 16, right: 16,
            bottom: 16 + bottomPadding,
          ),
          children: tiles,
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(key), child: content),
    );
  }

  Widget _buildNetworkTile(WifiNetworkInfo network, FogelSettings settings) {
    final saved = _findSavedDevice(network.bssid);
    final signal = network.signalLevel;
    final isCurrentDevice = settings.connectionStatus == 'connected' &&
        settings.connectedDeviceAddress == network.bssid;

    String? subtitle;
    Color? subtitleColor;
    if (isCurrentDevice) {
      subtitle = 'Текущее подключение';
      subtitleColor = Colors.green;
    } else if (saved != null) {
      subtitle = 'Сохранен';
      subtitleColor = Colors.grey[500];
    } else {
      subtitle = 'Доступен для подключения';
      subtitleColor = Colors.green;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: _buildSignalIcon(signal),
        title: Text(
          network.ssid,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isCurrentDevice ? Colors.grey : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: subtitleColor)),
        trailing: isCurrentDevice
            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
            : saved != null
                ? const Icon(Icons.link, color: Colors.green, size: 20)
                : const Icon(Icons.chevron_right),
        onTap: () => _onNetworkTap(network),
        onLongPress: saved != null ? () => _showDeviceContextMenu(saved) : null,
      ),
    );
  }

  Widget _buildOfflineDeviceTile(SavedDevice device) {
    final settings = globalSettings.value;
    final isCurrentDevice = settings.connectionStatus == 'connected' &&
        settings.connectedDeviceAddress == device.address;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: _buildSignalIcon(0),
        title: Text(
          device.name,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.red[300],
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('Недоступен', style: TextStyle(fontSize: 12, color: Colors.red[200])),
        trailing: isCurrentDevice
            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
            : null,
        onLongPress: () => _showDeviceContextMenu(device),
      ),
    );
  }

  Widget _buildSignalIcon(int level) {
    final color = _signalColor(level);
    final bars = level.clamp(0, 4);

    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _SignalBarsPainter(bars: bars, color: color),
      ),
    );
  }

  // --- Context menu (long press) ---

  void _showDeviceContextMenu(SavedDevice device) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Забыть', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                _suppressWifiRefresh = true;
                try {
                  final ssidResult = await OpWifiUtils.getCurrentSsid();
                  if (ssidResult.isSuccess) {
                    await OpWifiUtils.disconnectFromWifi(ssidResult.data);
                  }
                } catch (_) {}
                _manualDisconnect = true;
                FogelAdapterService().disconnect(manual: true, disconnectWifi: false);
                await FogelAdapterService.deleteDevice(device.address);
                _suppressWifiRefresh = false;
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  final int bars;
  final Color color;

  _SignalBarsPainter({required this.bars, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const gap = 2.0;
    final barWidth = (size.width - gap * 3) / 4;
    final maxHeight = size.height;

    for (int i = 0; i < 4; i++) {
      final barHeight = maxHeight * (0.3 + 0.23 * i);
      final x = i * (barWidth + gap);
      final y = maxHeight - barHeight;
      final opacity = i < bars ? 1.0 : 0.2;
      paint.color = color.withValues(alpha: opacity);
      canvas.drawLine(
        Offset(x + barWidth / 2, y),
        Offset(x + barWidth / 2, maxHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalBarsPainter old) => old.bars != bars || old.color != color;
}
