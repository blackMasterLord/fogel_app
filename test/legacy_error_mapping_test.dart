import 'package:flutter_test/flutter_test.dart';
import 'package:op_wifi_utils/op_wifi_utils.dart';

void main() {
  group('OpWifiUtils error mapping', () {
    test('maps PROBABLE_WRONG_PASSWORD', () {
      expect(OpWifiUtilsError.probableWrongPassword, isNotNull);
      expect(OpWifiUtilsError.probableWrongPassword.index, isNonNegative);
    });

    test('maps NOT_FOUND', () {
      expect(OpWifiUtilsError.notFound, isNotNull);
      expect(OpWifiUtilsError.notFound.index, isNonNegative);
    });

    test('maps ADD_NETWORK_FAILED', () {
      expect(OpWifiUtilsError.addNetworkFailed, isNotNull);
    });

    test('maps WIFI_DISABLED', () {
      expect(OpWifiUtilsError.wifiDisabled, isNotNull);
    });

    test('maps TIMEOUT', () {
      expect(OpWifiUtilsError.timeout, isNotNull);
    });

    test('all error codes exist', () {
      final codes = [
        OpWifiUtilsError.invalidPassword,
        OpWifiUtilsError.probableWrongPassword,
        OpWifiUtilsError.notFound,
        OpWifiUtilsError.addNetworkFailed,
        OpWifiUtilsError.wifiDisabled,
        OpWifiUtilsError.timeout,
        OpWifiUtilsError.unavailable,
        OpWifiUtilsError.permissionRequired,
        OpWifiUtilsError.deviceLocationDisabled,
        OpWifiUtilsError.unknownError,
      ];
      for (final c in codes) {
        expect(c.index, isNonNegative);
      }
    });
  });
}
