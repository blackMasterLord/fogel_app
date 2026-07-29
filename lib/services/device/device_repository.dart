import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/fogel_settings.dart';
import '../device_secure_store.dart';

class DeviceRepository {
  static const _key = 'saved_fogel_devices';
  static List<SavedDevice> _list = [];

  static List<SavedDevice> get all => _list;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _list = raw.map((item) => SavedDevice.fromJson(jsonDecode(item))).toList();
  }

  static Future<void> save(String bssid, String name, String password) async {
    final prefs = await SharedPreferences.getInstance();
    _list.removeWhere((d) => d.address == bssid);
    _list.add(SavedDevice(address: bssid, name: name, lastConnectedTimestamp: DateTime.now()));
    final raw = _list.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_key, raw);
    await DeviceSecureStore.savePassword(bssid, password);
  }

  static Future<void> delete(String bssid) async {
    final prefs = await SharedPreferences.getInstance();
    _list.removeWhere((d) => d.address == bssid);
    final raw = _list.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_key, raw);
    await DeviceSecureStore.deletePassword(bssid);
  }

  static Future<String?> getPassword(String bssid) => DeviceSecureStore.getPassword(bssid);

  static SavedDevice? find(String bssid) {
    try {
      return _list.firstWhere((d) => d.address == bssid);
    } catch (_) {
      return null;
    }
  }
}
