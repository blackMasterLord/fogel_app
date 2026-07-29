import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores device passwords in platform secure storage (Keychain on iOS,
/// EncryptedSharedPreferences on Android).
///
/// SharedPreferences stores only metadata: address, name, autoConnect, etc.
/// Password is stored separately under key `fogel_device_password_{address}`.
class DeviceSecureStore {
  static const _storage = FlutterSecureStorage();

  static Future<void> savePassword(String address, String password) async {
    await _storage.write(key: _key(address), value: password);
  }

  static Future<String?> getPassword(String address) async {
    return await _storage.read(key: _key(address));
  }

  static Future<void> deletePassword(String address) async {
    await _storage.delete(key: _key(address));
  }

  static Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  static String _key(String address) => 'fogel_device_password_$address';
}
