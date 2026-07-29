import 'package:flutter_test/flutter_test.dart';
import 'package:fogel_app/services/scan_controller.dart';

void main() {
  group('ScanController', () {
    test('singleton', () {
      final a = ScanController();
      final b = ScanController();
      expect(identical(a, b), isTrue);
    });

    test('initial state', () {
      final scan = ScanController();
      expect(scan.scanning, isFalse);
      expect(scan.networks, isNull);
      expect(scan.foundCount, 0);
    });

    test('isInRange returns true when networks is null', () {
      final scan = ScanController();
      scan.networks = null;
      expect(scan.isInRange('AA:BB:CC:DD:EE:FF'), isTrue);
    });

    test('isInRange returns false when bssid not found', () {
      final scan = ScanController();
      scan.networks = [];
      expect(scan.isInRange('AA:BB:CC:DD:EE:FF'), isFalse);
    });

    test('stop sets scanning to false', () {
      final scan = ScanController();
      scan.scanning = true;
      scan.stop();
      expect(scan.scanning, isFalse);
    });

    test('reset clears networks and error', () {
      final scan = ScanController();
      scan.networks = [];
      scan.scanError = 'err';
      scan.reset();
      expect(scan.networks, isNull);
      expect(scan.scanError, isNull);
    });
  });
}
