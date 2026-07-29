import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fogel_app/services/connection/connection_state_machine.dart';
import 'package:fogel_app/models/fogel_settings.dart';

void main() {
  late ValueNotifier<FogelSettings> settings;

  setUp(() {
    settings = ValueNotifier(FogelSettings(themeSetting: AppThemeSetting.system));
  });

  tearDown(() {
    settings.dispose();
  });

  group('ConnectionStateMachine', () {
    test('initial state is disconnected', () {
      final fsm = ConnectionStateMachine(settings);
      expect(fsm.stage, FogelConnectionState.disconnected);
    });

    test('disconnected -> connecting -> pinging', () {
      final fsm = ConnectionStateMachine(settings);
      fsm.toConnecting('DEVICE', 'TestDevice');
      expect(fsm.stage, FogelConnectionState.connecting);
      fsm.toPinging();
      expect(fsm.stage, FogelConnectionState.pinging);
    });

    test('pinging -> loadingConfig -> connected', () {
      final fsm = ConnectionStateMachine(settings);
      fsm.toConnecting('DEVICE', 'TestDevice');
      fsm.toPinging();
      fsm.toLoadingConfig();
      expect(fsm.stage, FogelConnectionState.loadingConfig);
      fsm.toConnected(['p1'], [500], 500, false);
      expect(fsm.stage, FogelConnectionState.connected);
    });

    test('connected -> reconnecting -> disconnected', () {
      final fsm = ConnectionStateMachine(settings);
      fsm.toConnecting('DEVICE', 'TestDevice');
      fsm.toPinging();
      fsm.toLoadingConfig();
      fsm.toConnected(['p1'], [500], 500, false);
      fsm.toReconnecting();
      expect(fsm.stage, FogelConnectionState.reconnecting);
      fsm.toDisconnected();
      expect(fsm.stage, FogelConnectionState.disconnected);
    });
  });
}
