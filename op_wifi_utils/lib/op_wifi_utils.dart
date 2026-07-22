import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:op_result/op_result.dart';

/// All error types surfaced by the native layer or enforced here.
/// Keep a few extras for cross-platform parity / future use.
enum OpWifiUtilsError {
  invalidPassword,
  invalidSsid,
  ssidMissing,
  alreadyConnected,
  unsupportedPlatform,
  permissionRequired,
  deviceLocationDisabled,
  unavailable,
  readyTimeout,
  neHotspotUnknown,
  osUnknown,
  unknownCurrentSsid,
  unknownCurrentBssid,
  apiUnsupported,
  unknownError,
}

class OpWifiUtils {
  static const MethodChannel _channel = MethodChannel('op_wifi_utils');

  /// Maps platform error codes (from Swift/Android) to enum.
  static OpWifiUtilsError _mapCodeToError(String code) {
    switch (code) {
      case 'INVALID_PASSWORD':
        return OpWifiUtilsError.invalidPassword;
      case 'INVALID_SSID':
        return OpWifiUtilsError.invalidSsid;
      case 'MISSING_SSID':
        return OpWifiUtilsError.ssidMissing;
      // case 'SSID_NOT_FOUND':
      //   return OpWifiUtilsError.ssidNotFound;
      case 'ALREADY_ASSOCIATED': // legacy alias
      case 'ALREADY_CONNECTED':
        return OpWifiUtilsError.alreadyConnected;
      case 'PERMISSION_REQUIRED':
        return OpWifiUtilsError.permissionRequired;
      case 'LOCATION_DISABLED':
        return OpWifiUtilsError.deviceLocationDisabled;
      case 'UNAVAILABLE':
        return OpWifiUtilsError.unavailable;
      case 'READY_TIMEOUT':
        return OpWifiUtilsError.readyTimeout;
      case 'NEHOTSPOT_UNKNOWN':
        return OpWifiUtilsError.neHotspotUnknown;
      case 'OS_UNKNOWN':
        return OpWifiUtilsError.osUnknown;
      case 'UNKNOWN_CURRENT_SSID':
        return OpWifiUtilsError.unknownCurrentSsid;
      case 'UNKNOWN_CURRENT_BSSID':
        return OpWifiUtilsError.unknownCurrentBssid;
      case 'UNSUPPORTED':
      case 'UNSUPPORTED_API':
        return OpWifiUtilsError.apiUnsupported;
      default:
        debugPrint("OpWifiUtilsError received unmapped code: $code");
        return OpWifiUtilsError.unknownError;
    }
  }

  /// Programmatically join a Wi-Fi network.
  ///
  /// iOS: succeeds as soon as NEHotspotConfiguration.apply(...) completes with no error.
  ///      We do NOT fail the call based on an SSID peek (best-effort verification is app-level).
  /// Android: behavior depends on the platform implementation.
  ///
  /// [ssid] required. [password] optional (open networks). [joinOnce] true prevents
  /// iOS from persisting the profile (recommended for device hotspots with no internet).
  /// [timeout] is enforced on the Dart side to avoid hangs regardless of native behavior.
  static Future<OpResult<void>> connectToWifi({
    required String ssid,
    String? password,
    String? bssid,
    bool joinOnce = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    debugPrint(
      '[OpWifiUtils] connectToWifi called with ssid: $ssid, bssid: ${bssid ?? "none"}, password: ${password != null ? '[provided]' : '[none]'}, joinOnce: $joinOnce',
    );

    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        return OpResult.failure(
          OpError(type: OpWifiUtilsError.unsupportedPlatform),
        );
      }

      final invoke = _channel.invokeMethod<bool>('connectToWifi', {
        'ssid': ssid,
        'password': password,
        'bssid': bssid,
        'joinOnce': joinOnce,
      });

      // IMPORTANT:
      // - Android: on timeout we DO NOT throw; we return `false` and map to UNAVAILABLE (retryable).
      // - iOS: on timeout we throw READY_TIMEOUT (as before).
      final bool? ok = await invoke.timeout(
        timeout,
        onTimeout: () {
          if (Platform.isIOS) {
            throw PlatformException(
              code: 'READY_TIMEOUT',
              message: 'Connection attempt timed out',
            );
          } else {
            // Android: treat as transient unavailability
            return false;
          }
        },
      );

      debugPrint('[OpWifiUtils] connectToWifi result: $ok');

      if (ok == true) {
        return OpResult.success(null);
      }

      // Platform never returns false on success; using false here means "our timeout fallback" or an unexpected falsy result. Map to retryable UNAVAILABLE on Android; unknown on iOS.
      return OpResult.failure(
        OpError(
          type: Platform.isAndroid
              ? OpWifiUtilsError.unavailable
              : OpWifiUtilsError.unknownError,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('[OpWifiUtils] connectToWifi platform exception: ${e.code}');
      return OpResult.failure(OpError(type: _mapCodeToError(e.code)));
    } catch (e) {
      debugPrint('[OpWifiUtils] connectToWifi unexpected exception: $e');
      return OpResult.failure(OpError(type: OpWifiUtilsError.unknownError));
    }
  }

  /// Remove the stored configuration for an SSID (does NOT force immediate detach on iOS).
  static Future<OpResult<void>> disconnectFromWifi(String ssid) async {
    try {
      final ok = await _channel.invokeMethod<bool>('disconnectFromWifi', {
        'ssid': ssid,
      });
      return (ok == true)
          ? OpResult.success(null)
          : OpResult.failure(OpError(type: OpWifiUtilsError.unknownError));
    } on PlatformException catch (e) {
      return OpResult.failure(OpError(type: _mapCodeToError(e.code)));
    } catch (e) {
      debugPrint('disconnectFromWifi failed: $e');
      return OpResult.failure(OpError(type: OpWifiUtilsError.unknownError));
    }
  }

  /// Basic availability probe (delegated to platform).
  static Future<OpResult<bool>> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return OpResult.failure(
        OpError(type: OpWifiUtilsError.unsupportedPlatform),
      );
    }
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return OpResult.success(ok ?? false);
    } catch (e, stack) {
      debugPrint('isAvailable failed: $e');
      debugPrintStack(stackTrace: stack);
      return OpResult.failure(OpError(type: OpWifiUtilsError.unknownError));
    }
  }

  /// Best-effort current SSID; may fail on permission/timing (esp. iOS/Android without Location).
  static Future<OpResult<String>> getCurrentSsid() async {
    try {
      final ssid = await _channel.invokeMethod<String>('getCurrentSsid');
      return OpResult.success(ssid ?? '');
    } on PlatformException catch (e) {
      return OpResult.failure(OpError(type: _mapCodeToError(e.code)));
    } catch (_) {
      return OpResult.failure(OpError(type: OpWifiUtilsError.unknownError));
    }
  }

  /// Best-effort current BSSID (MAC address of the connected access point).
  static Future<OpResult<String>> getCurrentBssid() async {
    try {
      final bssid = await _channel.invokeMethod<String>('getCurrentBssid');
      return OpResult.success(bssid ?? '');
    } on PlatformException catch (e) {
      return OpResult.failure(OpError(type: _mapCodeToError(e.code)));
    } catch (_) {
      return OpResult.failure(OpError(type: OpWifiUtilsError.unknownError));
    }
  }
}
