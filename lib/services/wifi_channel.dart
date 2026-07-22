import 'dart:async';
import 'package:flutter/services.dart';

class WifiNetworkInfo {
  final String ssid;
  final String bssid;
  final int signalLevel;
  final String capabilities;

  const WifiNetworkInfo({
    required this.ssid,
    required this.bssid,
    required this.signalLevel,
    required this.capabilities,
  });

  factory WifiNetworkInfo.fromMap(Map<dynamic, dynamic> map) {
    final ssid = map['ssid'];
    final bssid = map['bssid'];
    if (ssid == null || bssid == null) {
      throw ArgumentError('WifiNetworkInfo requires ssid and bssid');
    }
    return WifiNetworkInfo(
      ssid: ssid.toString(),
      bssid: bssid.toString(),
      signalLevel: map['signalLevel'] as int? ?? 0,
      capabilities: (map['capabilities'] ?? '').toString(),
    );
  }

  bool get isOpen =>
      !capabilities.contains('WPA') &&
      !capabilities.contains('WEP') &&
      !capabilities.contains('RSN');
}

class WiFiChannel {
  static const _method = MethodChannel('com.fogel.app/wifi');
  static const _event = EventChannel('com.fogel.app/wifi/events');
  static const _dhcpEvent = EventChannel('com.fogel.app/wifi/dhcp');

  static Stream<Map<String, dynamic>>? _eventStream;
  static Stream<bool>? _dhcpStream;

  static Future<void> openWifiSettings() async {
    await _method.invokeMethod('openWifiSettings');
  }

  static Future<String?> getConnectedSSID() async {
    return await _method.invokeMethod<String>('getConnectedSSID');
  }

  static Future<bool> isWifiEnabled() async {
    return await _method.invokeMethod<bool>('isWifiEnabled') ?? false;
  }

  static Future<void> enableWifi() async {
    await _method.invokeMethod('enableWifi');
  }

  static Future<void> showWifiPanel() async {
    await _method.invokeMethod('showWifiPanel');
  }

  static Future<String?> getGatewayIp() async {
    return await _method.invokeMethod<String>('getGatewayIp');
  }

  static Future<List<WifiNetworkInfo>> scanNetworks() async {
    final result = await _method.invokeMethod<List>('scanNetworks');
    if (result == null) return [];
    return result
        .map((e) => WifiNetworkInfo.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  static Stream<Map<String, dynamic>> get onWifiChanged {
    _eventStream ??= _event.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
    return _eventStream!;
  }

  static Stream<bool> get onDhcpReady {
    _dhcpStream ??= _dhcpEvent.receiveBroadcastStream().map((event) => true);
    return _dhcpStream!;
  }
}
