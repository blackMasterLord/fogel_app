import 'package:flutter/material.dart';
import '../../models/fogel_settings.dart';

class ConnectionStateMachine {
  final ValueNotifier<FogelSettings> settings;
  FogelConnectionState _stage = FogelConnectionState.disconnected;

  ConnectionStateMachine(this.settings);

  FogelConnectionState get stage => _stage;
  bool get isActive => _stage != FogelConnectionState.disconnected;

  void toConnecting(String deviceAddress, String deviceName) {
    _stage = FogelConnectionState.connecting;
    settings.value = settings.value.copyWith(
      connectionStatus: FogelConnectionState.connecting,
      connectedDeviceAddress: deviceAddress,
      connectedDeviceName: deviceName,
      connectionError: null,
    );
  }

  void toPinging() {
    _stage = FogelConnectionState.pinging;
    settings.value = settings.value.copyWith(connectionStatus: FogelConnectionState.pinging);
  }

  void toLoadingConfig() {
    _stage = FogelConnectionState.loadingConfig;
    settings.value = settings.value.copyWith(
      connectionStatus: FogelConnectionState.loadingConfig,
      connectionError: null,
    );
  }

  void toConnected(List<String> protocols, List<int> speeds, int defaultSpeed, bool hasAuto) {
    _stage = FogelConnectionState.connected;
    settings.value = settings.value.copyWith(
      connectionStatus: FogelConnectionState.connected,
      availableProtocols: protocols,
      availableCanSpeeds: speeds,
      canSpeedDefault: defaultSpeed,
      hasAutoSpeed: hasAuto,
      canSpeed: defaultSpeed,
      clearSelectedProtocol: true,
      clearProtocolParams: true,
      clearProtocolCommands: true,
      connectionError: null,
    );
  }

  void toReconnecting() {
    _stage = FogelConnectionState.reconnecting;
    settings.value = settings.value.copyWith(connectionStatus: FogelConnectionState.reconnecting);
  }

  void toDisconnected() {
    _stage = FogelConnectionState.disconnected;
    settings.value = FogelSettings(
      themeSetting: settings.value.themeSetting,
      savedDevices: settings.value.savedDevices,
      wifiEnabled: settings.value.wifiEnabled,
    );
  }

  void setError(String message, {bool disconnectWifi = true}) {
    _stage = FogelConnectionState.disconnected;
    settings.value = FogelSettings(
      themeSetting: settings.value.themeSetting,
      savedDevices: settings.value.savedDevices,
      wifiEnabled: settings.value.wifiEnabled,
      connectionError: message,
    );
  }
}
