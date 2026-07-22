# op_wifi_utils

**A lightweight Flutter plugin** using modern Android and iOS APIs to:

- Connect to Wi-Fi
- Disconnect from Wi-Fi
- Retrieve the current SSID

Built with `OpResult` for structured error handling.

---

## ✨ Features

- Connect to Wi-Fi with optional password
- Disconnect from a given SSID
- Check current SSID
- Check platform support
- Returns `OpResult<T>` with clear error types
- Android and iOS support

---

## Platform support and setup
This plugin relies on modern platform APIs introduced in recent Android and iOS versions to ensure secure and consistent Wi-Fi management across devices.

| Platform | Minimum Version | Notes |
|----------|------------------|-------|
| Android  | 10 (API 29)      | Uses WifiNetworkSpecifier for secure, app-scoped connections. All connections are temporary and may not be visible in the system UI. SSID visibility may be limited (e.g., `<unknown ssid>`); the plugin returns an `OpWifiUtilsError.unknownCurrentSsid` error in this case. |
| iOS      | 11+              | Based on NEHotspotConfiguration. Supports persistent or join-once connections. Requires Hotspot Configuration entitlement and location permissions. |

### Android

Add the following to your `AndroidManifest.xml` based on the features you use:

```xml
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```
**Location Services** must be enabled on the device to retrieve the current SSID.

### iOS

For all methods, include the following in ios/Runner/Info.plist:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>The app needs local network access to connect to your device.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>The app requires access to your location to manage Wi-Fi connections.</string>
```
**Hotspot Configuration** entitlement must be enabled (in Capabilities, UI toggle in Xcode)

---

## Installation

With flutter pub:

```shell
> flutter pub add op_wifi_utils
```

---

## Usage

```dart
final result = await OpWifiUtils.connectToWifi(
  ssid: 'MyNetwork',
  password: 'password123',
  joinOnce: true, // optional for iOS, has no effect on Android
);

if (result.isSuccess) {
  print('Connected!');
} else {  
  if (result.error.type == OpWifiUtilsError.invalidPassword) {
    print('Incorrect password');
  }
}
```

```dart
final disconnect = await OpWifiUtils.disconnectFromWifi('MyNetwork');
```

```dart
final ssid = await OpWifiUtils.getCurrentSsid();
if (ssid.isSuccess) {
  print('Connected to: ${ssid.value}');
}
```

---

## Error types

All errors are strongly typed via `OpWifiUtilsError` enum:

```dart
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
  unknownError,
}
```

---

## 📄 License

This package is licensed under the BSD 3-Clause License. See the LICENSE file for details.
