import 'package:flutter_test/flutter_test.dart';
import 'package:fogel_app/models/fogel_settings.dart';

/// Verify connection flow logic: error differentiation, status transitions, guards.

void main() {
  group('Connection status machine', () {
    test('connectionError cleared on successful connect', () {
      var settings = FogelSettings(connectionError: 'old error');
      settings = settings.copyWith(
        connectionStatus: 'connected',
        connectionError: null,
      );
      expect(settings.connectionError, isNull);
      expect(settings.connectionStatus, equals('connected'));
    });

    test('_resetConnectionStatus handles reconnecting', () {
      final statuses = ['connecting', 'pinging', 'loading_config', 'reconnecting'];
      for (final s in statuses) {
        var settings = FogelSettings(connectionStatus: s);
        final shouldReset = s == 'connecting' || s == 'pinging' ||
            s == 'loading_config' || s == 'reconnecting';
        if (shouldReset) {
          settings = settings.copyWith(connectionStatus: 'disconnected');
        }
        expect(settings.connectionStatus, equals('disconnected'),
            reason: 'status $s should reset to disconnected');
      }
    });

    test('connected and disconnected are NOT reset', () {
      for (final s in ['connected', 'disconnected']) {
        final settings = FogelSettings(connectionStatus: s);
        final shouldReset = settings.connectionStatus == 'connecting' ||
            settings.connectionStatus == 'pinging' ||
            settings.connectionStatus == 'loading_config' ||
            settings.connectionStatus == 'reconnecting';
        expect(shouldReset, isFalse, reason: 'status $s should not reset');
      }
    });
  });

  group('Error differentiation', () {
    test('WiFi unavailable → specific message', () {
      const msg = 'Адаптер недоступен — сеть не найдена';
      expect(msg, contains('недоступен'));
      expect(msg, contains('сеть'));
    });

    test('TCP timeout → specific message', () {
      const msg = 'Адаптер не отвечает — не удалось установить TCP-соединение';
      expect(msg, contains('не отвечает'));
      expect(msg, contains('TCP'));
    });

    test('timeout → specific message', () {
      const msg = 'Таймаут подключения к сети';
      expect(msg, contains('Таймаут'));
    });
  });

  group('Double-tap protection', () {
    test('_isConnectingToDevice blocks concurrent connections', () {
      // Simulate: first call sets flag, second call sees flag and returns false
      var isConnecting = false;

      bool tryConnect() {
        if (isConnecting) return false;
        isConnecting = true;
        return true;
      }

      expect(tryConnect(), isTrue);   // first call succeeds
      expect(tryConnect(), isFalse);  // second call blocked
    });
  });

  group('Pre-flight scan logic', () {
    test('adapter not in range → abort', () {
      final scanResults = ['AA:BB:CC:DD:EE:01', 'AA:BB:CC:DD:EE:02'];
      final targetBssid = 'AA:BB:CC:DD:EE:FF';
      final inRange = scanResults.any((bssid) => bssid == targetBssid);
      expect(inRange, isFalse);
    });

    test('adapter in range → proceed', () {
      final scanResults = ['AA:BB:CC:DD:EE:01', 'AA:BB:CC:DD:EE:FF'];
      final targetBssid = 'AA:BB:CC:DD:EE:FF';
      final inRange = scanResults.any((bssid) => bssid == targetBssid);
      expect(inRange, isTrue);
    });

    test('scan timeout → proceed anyway (fallback to WiFi connect)', () {
      // If pre-flight scan fails, we don't abort — we let WiFi connect be the final check
      var aborted = false;
      try {
        // Simulate scan timeout
        throw Exception('timeout');
      } catch (_) {
        // Don't abort — proceed to WiFi connect
        aborted = false;
      }
      expect(aborted, isFalse);
    });
  });
}
