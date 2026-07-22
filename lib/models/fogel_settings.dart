import 'package:flutter/foundation.dart';

enum AppThemeSetting { light, dark, system }

class SavedDevice {
  final String address;
  final String name;
  final String password;

  SavedDevice({
    required this.address,
    required this.name,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'address': address,
    'name': name,
    'password': password,
  };

  factory SavedDevice.fromJson(Map<String, dynamic> json) => SavedDevice(
    address: json['address'],
    name: json['name'],
    password: json['password'],
  );
}

class CanMessage {
  final bool isExtended;
  final int id;
  final int dlc;
  final List<int> data;
  final int period;
  final int count;
  final DateTime timestamp;

  CanMessage({
    required this.isExtended,
    required this.id,
    required this.dlc,
    required this.data,
    this.period = 0,
    this.count = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// BMS data from TICK messages — frequently updated, kept separate
/// so UI rebuilds don't cascade through all globalSettings listeners.
class BmsData {
  final double? batteryVoltage;
  final double? soc;
  final double? temperature;
  final double? chargeCurrent;
  final double? dischargeCurrent;
  final int? cellCount;
  final List<double> cellVoltages;
  final bool chargeOn;
  final bool dischargeOn;
  final bool prechargeOn;
  final int totalMessages;
  final int uniqueMessages;

  const BmsData({
    this.batteryVoltage,
    this.soc,
    this.temperature,
    this.chargeCurrent,
    this.dischargeCurrent,
    this.cellCount,
    this.cellVoltages = const [],
    this.chargeOn = false,
    this.dischargeOn = false,
    this.prechargeOn = false,
    this.totalMessages = 0,
    this.uniqueMessages = 0,
  });

  BmsData copyWith({
    double? batteryVoltage,
    double? soc,
    double? temperature,
    double? chargeCurrent,
    double? dischargeCurrent,
    int? cellCount,
    List<double>? cellVoltages,
    bool? chargeOn,
    bool? dischargeOn,
    bool? prechargeOn,
    int? totalMessages,
    int? uniqueMessages,
  }) {
    return BmsData(
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      soc: soc ?? this.soc,
      temperature: temperature ?? this.temperature,
      chargeCurrent: chargeCurrent ?? this.chargeCurrent,
      dischargeCurrent: dischargeCurrent ?? this.dischargeCurrent,
      cellCount: cellCount ?? this.cellCount,
      cellVoltages: cellVoltages ?? this.cellVoltages,
      chargeOn: chargeOn ?? this.chargeOn,
      dischargeOn: dischargeOn ?? this.dischargeOn,
      prechargeOn: prechargeOn ?? this.prechargeOn,
      totalMessages: totalMessages ?? this.totalMessages,
      uniqueMessages: uniqueMessages ?? this.uniqueMessages,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BmsData &&
      batteryVoltage == other.batteryVoltage &&
      soc == other.soc &&
      temperature == other.temperature &&
      chargeCurrent == other.chargeCurrent &&
      dischargeCurrent == other.dischargeCurrent &&
      cellCount == other.cellCount &&
      chargeOn == other.chargeOn &&
      dischargeOn == other.dischargeOn &&
      prechargeOn == other.prechargeOn &&
      totalMessages == other.totalMessages &&
      uniqueMessages == other.uniqueMessages &&
      listEquals(cellVoltages, other.cellVoltages);

  @override
  int get hashCode => Object.hash(
      batteryVoltage, soc, temperature, chargeCurrent, dischargeCurrent,
      cellCount, chargeOn, dischargeOn, prechargeOn,
      totalMessages, uniqueMessages, Object.hashAll(cellVoltages));
}

final ValueNotifier<BmsData> bmsNotifier = ValueNotifier(const BmsData());

/// CAN frame statistics — updated at TICK frequency but consumed only by CanAnalyzerTab.
/// Separate from [globalSettings] to avoid cascading rebuilds across the entire app.
class CanStats {
  final int totalMessages;
  final int uniqueMessages;

  const CanStats({this.totalMessages = 0, this.uniqueMessages = 0});

  @override
  bool operator ==(Object other) =>
      other is CanStats &&
      totalMessages == other.totalMessages &&
      uniqueMessages == other.uniqueMessages;

  @override
  int get hashCode => Object.hash(totalMessages, uniqueMessages);
}

final ValueNotifier<CanStats> canStatsNotifier = ValueNotifier(const CanStats());

class FogelSettings {
  final AppThemeSetting themeSetting;
  final String connectionStatus;

  bool get isConnecting =>
      connectionStatus == 'connecting' ||
      connectionStatus == 'pinging' ||
      connectionStatus == 'loading_config' ||
      connectionStatus == 'reconnecting';

  bool get isConnectedOrConnecting =>
      connectionStatus == 'connected' || isConnecting;
  final int? canSpeed;
  final int canSpeedDefault;
  final bool hasAutoSpeed;
  final bool isAutoSpeed;
  final bool isAutoDetecting;
  final int? currentScanningSpeed;
  final List<int> availableCanSpeeds;
  final String? selectedProtocol;
  final List<String> availableProtocols;
  final String connectedDeviceName;
  final String connectedDeviceAddress;
  final List<SavedDevice> savedDevices;
  final String? connectionError;

  // Protocol-specific config (from GET_PROTOCOL)
  final List<String> protocolParams;
  final List<String> protocolCommands;

  // CAN nodes (cleared on speed/protocol change)
  final List<dynamic> canNodes;

  // WiFi state
  final bool wifiEnabled;

  // Auth state
  final String? passwordError;
  final int authAttemptsLeft;

  FogelSettings({
    this.themeSetting = AppThemeSetting.system,
    this.wifiEnabled = false,
    this.connectionStatus = 'disconnected',
    this.canSpeed,
    this.canSpeedDefault = 250,
    this.hasAutoSpeed = false,
    this.isAutoSpeed = false,
    this.isAutoDetecting = false,
    this.currentScanningSpeed,
    this.availableCanSpeeds = const [],
    this.selectedProtocol,
    this.availableProtocols = const [],
    this.connectedDeviceName = '',
    this.connectedDeviceAddress = '',
    this.savedDevices = const [],
    this.connectionError,
    this.protocolParams = const [],
    this.protocolCommands = const [],
    this.canNodes = const [],
    this.passwordError,
    this.authAttemptsLeft = 5,
  });

  FogelSettings copyWith({
    AppThemeSetting? themeSetting,
    String? connectionStatus,
    int? canSpeed,
    int? canSpeedDefault,
    bool? hasAutoSpeed,
    bool? isAutoSpeed,
    bool? isAutoDetecting,
    int? currentScanningSpeed,
    bool clearCurrentScanningSpeed = false,
    List<int>? availableCanSpeeds,
    String? selectedProtocol,
    bool clearSelectedProtocol = false,
    List<String>? availableProtocols,
    String? connectedDeviceName,
    String? connectedDeviceAddress,
    List<SavedDevice>? savedDevices,
    String? connectionError,
    List<String>? protocolParams,
    bool clearProtocolParams = false,
    List<String>? protocolCommands,
    bool clearProtocolCommands = false,
    List<dynamic>? canNodes,
    String? passwordError,
    bool clearPasswordError = false,
    int? authAttemptsLeft,
    bool? wifiEnabled,
  }) {
    return FogelSettings(
      themeSetting: themeSetting ?? this.themeSetting,
      wifiEnabled: wifiEnabled ?? this.wifiEnabled,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      canSpeed: canSpeed ?? this.canSpeed,
      canSpeedDefault: canSpeedDefault ?? this.canSpeedDefault,
      hasAutoSpeed: hasAutoSpeed ?? this.hasAutoSpeed,
      isAutoSpeed: isAutoSpeed ?? this.isAutoSpeed,
      isAutoDetecting: isAutoDetecting ?? this.isAutoDetecting,
      currentScanningSpeed: clearCurrentScanningSpeed ? null : (currentScanningSpeed ?? this.currentScanningSpeed),
      availableCanSpeeds: availableCanSpeeds ?? this.availableCanSpeeds,
      selectedProtocol: clearSelectedProtocol ? null : (selectedProtocol ?? this.selectedProtocol),
      availableProtocols: availableProtocols ?? this.availableProtocols,
      connectedDeviceName: connectedDeviceName ?? this.connectedDeviceName,
      connectedDeviceAddress: connectedDeviceAddress ?? this.connectedDeviceAddress,
      savedDevices: savedDevices ?? this.savedDevices,
      connectionError: connectionError,
      protocolParams: clearProtocolParams ? const [] : (protocolParams ?? this.protocolParams),
      protocolCommands: clearProtocolCommands ? const [] : (protocolCommands ?? this.protocolCommands),
      canNodes: canNodes ?? this.canNodes,
      passwordError: clearPasswordError ? null : (passwordError ?? this.passwordError),
      authAttemptsLeft: authAttemptsLeft ?? this.authAttemptsLeft,
    );
  }
}

final ValueNotifier<FogelSettings> globalSettings = ValueNotifier(FogelSettings());
