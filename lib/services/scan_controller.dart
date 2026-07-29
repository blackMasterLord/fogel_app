import 'dart:async';
import 'package:flutter/material.dart';
import '../models/fogel_settings.dart';
import '../services/fogel_adapter_service.dart';
import '../services/wifi_channel.dart';

/// Manages WiFi scan lifecycle independently of widget tree.
/// Scan persists across page navigations; state is static.
class ScanController {
  List<WifiNetworkInfo>? networks;
  String? scanError;
  bool scanning = false;
  DateTime? lastScanTime;
  VoidCallback? _wifiOffListener;
  bool manualDisconnect = false;

  final ValueNotifier<int> stateNotifier = ValueNotifier(0);

  static final ScanController _instance = ScanController._();
  factory ScanController() => _instance;
  ScanController._();

  void _notify() => stateNotifier.value++;

  void stop() {
    scanning = false;
    _notify();
    final l = _wifiOffListener;
    if (l != null) {
      globalSettings.removeListener(l);
      _wifiOffListener = null;
    }
  }

  void reset() {
    networks = null;
    scanError = null;
    _notify();
  }

  Future<void> start() async {
    debugPrint('[SCAN-DEBUG] ScanController.start: scanning=$scanning');
    if (scanning) return;

    scanning = true;
    networks = [];
    scanError = null;
    _notify();
    debugPrint('[SCAN-DEBUG] ScanController.start: scanning set to true, calling _scanCycle');

    // WiFi-off listener that outlives widget disposal
    void onWifiChange() {
      if (!globalSettings.value.wifiEnabled && scanning) {
        stop();
        networks = null;
        lastScanTime = null;
        _notify();
      }
    }
    globalSettings.addListener(onWifiChange);
    _wifiOffListener = onWifiChange;

    await _scanCycle();
    if (!scanning) return;

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    var interval = 3;
    var count = 0;
    while (scanning && DateTime.now().isBefore(deadline)) {
      await Future.delayed(Duration(seconds: interval));
      if (!scanning) return;
      if (!globalSettings.value.wifiEnabled) { stop(); return; }
      await _scanCycle();
      count++;
      if (count == 3) interval = 6;
      if (networks != null && networks!.any((n) => n.ssid.startsWith('Fogel Adapter'))) {
        interval = 10;
      }
    }
    stop();
  }

  Future<void> _scanCycle() async {
    debugPrint('[SCAN-DEBUG] _scanCycle: scanning=$scanning wifiEnabled=${globalSettings.value.wifiEnabled}');
    if (!scanning) return;
    if (!globalSettings.value.wifiEnabled) { stop(); return; }
    try {
      final result = await FogelAdapterService().scanNetworks();
      debugPrint('[SCAN-DEBUG] _scanCycle: scanNetworks returned ${result.length} total, ${result.where((n) => n.ssid.startsWith("Fogel Adapter")).length} fogel');
      if (!scanning) return;
      networks = result.where((n) => n.ssid.startsWith('Fogel Adapter')).toList()
        ..sort((a, b) => b.signalLevel.compareTo(a.signalLevel));
      lastScanTime = DateTime.now();
      debugPrint('[SCAN-DEBUG] _scanCycle: networks set to ${networks?.length} items, calling _notify');
      _notify();
    } catch (e) {
      debugPrint('[SCAN-DEBUG] _scanCycle: EXCEPTION $e');
    }
  }

  bool get isScanning => scanning;
  int get foundCount => networks?.length ?? 0;
  bool isInRange(String bssid) => networks?.any((n) => n.bssid == bssid) ?? true;
  WifiNetworkInfo? find(String bssid) {
    try { return networks?.firstWhere((n) => n.bssid == bssid); } catch (_) { return null; }
  }
}
