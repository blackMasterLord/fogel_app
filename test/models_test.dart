import 'package:flutter_test/flutter_test.dart';
import 'package:fogel_app/models/fogel_settings.dart';

void main() {
  group('BmsData equality', () {
    test('identical values are equal', () {
      const a = BmsData(batteryVoltage: 53.0, soc: 82.0, temperature: 26.4);
      const b = BmsData(batteryVoltage: 53.0, soc: 82.0, temperature: 26.4);
      expect(a, equals(b));
    });

    test('different values are not equal', () {
      const a = BmsData(batteryVoltage: 53.0);
      const b = BmsData(batteryVoltage: 54.0);
      expect(a, isNot(equals(b)));
    });

    test('cellVoltages compared correctly', () {
      const a = BmsData(cellVoltages: [3.30, 3.31, 3.32]);
      const b = BmsData(cellVoltages: [3.30, 3.31, 3.32]);
      const c = BmsData(cellVoltages: [3.30, 3.31, 3.33]);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode consistent with equality', () {
      const a = BmsData(batteryVoltage: 53.0, soc: 82.0);
      const b = BmsData(batteryVoltage: 53.0, soc: 82.0);
      expect(a.hashCode, equals(b.hashCode));
    });

    test('default empty values are equal', () {
      expect(const BmsData(), equals(const BmsData()));
    });
  });

  group('CanMessage', () {
    test('timestamp defaults to now', () {
      final msg = CanMessage(isExtended: false, id: 0x100, dlc: 8, data: [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(msg.timestamp, isNotNull);
      expect(DateTime.now().difference(msg.timestamp).inSeconds, lessThan(1));
    });

    test('explicit timestamp works', () {
      final ts = DateTime(2026, 1, 1);
      final msg = CanMessage(isExtended: false, id: 0x100, dlc: 8, data: [], timestamp: ts);
      expect(msg.timestamp, equals(ts));
    });

    test('isExtended detection', () {
      final standard = CanMessage(isExtended: false, id: 0x100, dlc: 8, data: []);
      final extended = CanMessage(isExtended: true, id: 0x18FEF100, dlc: 8, data: []);
      expect(standard.isExtended, isFalse);
      expect(extended.isExtended, isTrue);
    });
  });

  group('SavedDevice', () {
    test('toJson / fromJson roundtrip', () {
      final device = SavedDevice(address: 'AA:BB:CC:DD:EE:FF', name: 'Fogel Adapter 42', autoConnect: true);
      final json = device.toJson();
      final restored = SavedDevice.fromJson(json);
      expect(restored.address, equals(device.address));
      expect(restored.name, equals(device.name));
      expect(restored.autoConnect, equals(device.autoConnect));
    });
  });

  group('FogelSettings', () {
    test('copyWith preserves unchanged fields', () {
      final s = FogelSettings(connectionStatus: FogelConnectionState.connected, canSpeed: 250);
      final s2 = s.copyWith(connectionStatus: FogelConnectionState.disconnected);
      expect(s2.connectionStatus, equals(FogelConnectionState.disconnected));
      expect(s2.canSpeed, equals(250));
    });

    test('clearSelectedProtocol flag works', () {
      final s = FogelSettings(selectedProtocol: 'HELI');
      final s2 = s.copyWith(clearSelectedProtocol: true);
      expect(s2.selectedProtocol, isNull);
    });

    test('default values', () {
      final s = FogelSettings();
      expect(s.connectionStatus, equals(FogelConnectionState.disconnected));
      expect(s.authAttemptsLeft, equals(5));
      expect(s.themeSetting, equals(AppThemeSetting.system));
    });
  });

  group('CanStats', () {
    test('default values', () {
      const stats = CanStats();
      expect(stats.totalMessages, equals(0));
      expect(stats.uniqueMessages, equals(0));
    });
  });
}
