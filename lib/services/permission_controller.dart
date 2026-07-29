import 'dart:io' show Platform;
import 'package:permission_master/permission_master.dart';

enum PermissionResult { granted, denied, permanentlyDenied, restricted }

class PermissionController {
  static List<PermissionType> resolveWifiPermissions() {
    if (!Platform.isAndroid) return [];
    return [PermissionType.fineLocation, PermissionType.nearbyDevices];
  }

  static Future<PermissionResult> ensureWifiPermissions() async {
    final pm = PermissionMaster();
    final perms = resolveWifiPermissions();
    if (perms.isEmpty) return PermissionResult.granted;

    for (final p in perms) {
      final status = await pm.checkPermissionStatus(p.value);
      if (status == PermissionStatus.granted) return PermissionResult.granted;
    }

    for (final p in perms) {
      final status = await pm.checkPermissionStatus(p.value);
      if (status == PermissionStatus.openSettings) return PermissionResult.permanentlyDenied;
      if (status == PermissionStatus.restricted) return PermissionResult.restricted;
    }

    final status = await pm.requestLocationPermission();
    if (status == PermissionStatus.granted) return PermissionResult.granted;
    if (status == PermissionStatus.openSettings) return PermissionResult.permanentlyDenied;

    return PermissionResult.denied;
  }

  static Future<bool> ensureLocationEnabled() async {
    return true;
  }
}
