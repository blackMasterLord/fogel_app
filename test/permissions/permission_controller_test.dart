import 'package:flutter_test/flutter_test.dart';
import 'package:fogel_app/services/permission_controller.dart';

void main() {
  group('PermissionController', () {
    test('PermissionResult enum exists', () {
      expect(PermissionResult.granted, isNotNull);
      expect(PermissionResult.denied, isNotNull);
      expect(PermissionResult.permanentlyDenied, isNotNull);
      expect(PermissionResult.restricted, isNotNull);
    });

    test('ensureLocationEnabled returns true', () async {
      final result = await PermissionController.ensureLocationEnabled();
      expect(result, isTrue);
    });

    test('resolveWifiPermissions returns list', () {
      // In test (non-Android), returns empty. On Android, returns permissions.
      final perms = PermissionController.resolveWifiPermissions();
      expect(perms, isNotNull);
      // On non-Android: empty; on Android: non-empty
      // Both are valid — just verify no exception thrown.
    });
  });
}
