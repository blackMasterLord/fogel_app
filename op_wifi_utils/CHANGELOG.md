# Changelog
## [1.5.0] – 2026-05-22

### Changed
- Raised the minimum Dart SDK requirement to `^3.12.0`.
- Raised the minimum Flutter SDK requirement to `>=3.44.0`.
- Migrated the Android plugin build to Flutter's Built-in Kotlin model.
- Updated Android Gradle tooling for future Flutter compatibility.
- Migrated the iOS plugin to support Swift Package Manager.
- Updated the example app Android/iOS projects to match the new native toolchain requirements.

### Notes
- No Dart API changes.
- This release is intended to keep the plugin compatible with newer Flutter toolchains.
- CocoaPods support is still preserved through the plugin podspec for compatibility with apps that have not fully migrated to Swift Package Manager.

## [1.4.3] – 2026-03-16
### Changed
- Widened `op_result` dependency constraint from `=0.3.0` to `>=0.3.0 <0.5.0` to support `0.4.x`.

## [1.4.2] – 2025-09-27
### Changed
- **Dart (`connectToWifi`)**
  - Increased default timeout from **15s → 30s** to reduce spurious timeouts on slower devices.
  - Platform-specific timeout behavior:
    - **iOS:** still throws `READY_TIMEOUT` on Dart-side timeout.
    - **Android:** on Dart-side timeout we now return `false` (mapped to `UNAVAILABLE`) instead of throwing, making timeouts a retryable condition rather than an exception.
  - Clarified inline docs around `joinOnce` and timeout semantics.

- **Android**
  - Proactively **unregister** any previous `NetworkCallback` before issuing a new request to avoid callback leaks.
  - **Bind** the process to the acquired Wi-Fi network on `onAvailable`; **unbind** on `onLost` and during disconnect for clean routing.
  - On `onUnavailable`, cleanly **unregister** the callback and reset internal state. 
  - `disconnectFromWifi`: reliably **unbinds** and **unregisters** the active callback; improved logging.

### Notes
- No breaking API changes.
- iOS native code unchanged in this release.

## [1.4.1] – 2025-09-13
### Fixed
- **iOS:**
  - Reverted to the simpler and more reliable 1.2.2-style connection flow (`apply → short settle delay → optional SSID peek`) for improved first-attempt stability.
  - Treats `alreadyAssociated` as a success case when the OS reports the SSID is already connected.
  - Added a single-call guard around `FlutterResult` to prevent double completion.
  - Ensured `NEHotspotConfigurationManager.apply(...)` always runs on the main thread, with a diagnostic log if invoked off-thread.
  - Expanded error mapping for clearer feedback:
    - `INVALID_PASSWORD` for wrong passphrases
    - `PERMISSION_REQUIRED` when location/Wi-Fi permissions are missing
    - `UNAVAILABLE` when Wi-Fi is off, OS is busy, or another join is pending
    - `UNKNOWN_CURRENT_SSID` when the current network cannot be determined
    - `NEHOTSPOT_UNKNOWN` for unmapped `NEHotspotConfigurationErrorDomain` cases
    - Fallback to `UNKNOWN` for unexpected system errors

### Notes
- No API changes. Dart interface remains the same.
- Android side unchanged from 1.4.0.
- This patch focuses purely on improving reliability and diagnostics of iOS hotspot connections.

## [1.4.0] – 2025-09-11
### Added
- **iOS:** `connectToWifi` now supports an optional readiness phase with new parameters:
  - `waitForReady`, `probeHost`, `probePort`, `totalTimeout`, `step`

### Improved
- **iOS:**
  - Treats `alreadyAssociated` as success when reconnecting to a known SSID.
  - Uses `NEHotspotNetwork.fetchCurrent` + TCP probe (Network framework) for robust readiness.
  - Single-call guard around `FlutterResult` to prevent double completion.
  - Clearer error mapping (`INVALID_PASSWORD`, `PERMISSION_REQUIRED`, `UNAVAILABLE`, etc.).
- **Android (API 29+):**
  - Added a timeout to `ConnectivityManager.requestNetwork(..., timeoutMs)` to avoid rare indefinite waits when the OS can’t attach.
  - Unbind the process (`bindProcessToNetwork(null)`) in `onLost` to cleanly release the hotspot route if the network disappears/roams.
  - Guard unbind against the last bound `Network` to avoid touching unrelated networks.

### Fixed
- **iOS:** Resolved the race where `connectToWifi` reported success but the first HTTP command failed with `errno 51 (Network is unreachable)`.

### Notes
- No breaking API changes. Android changes only make failure/roam cases more deterministic.

## [1.3.0] - 2025-06-12
### Fixed
- Android: Prevented rare crash in `connectToWifi` caused by multiple invocations of `result.success/error` due to network callback races. Now uses an `AtomicBoolean` guard to ensure only one result is returned.
- iOS: Prevented potential crash in `connectToWifi` by wrapping `FlutterResult` in a single-call-safe closure to avoid double invocation under race conditions.

### Improved
- Android: Finalized safe binding and callback cleanup during Wi-Fi connection flow, ensuring `bindProcessToNetwork` and `unregisterNetworkCallback` are used defensively.
- iOS: `getCurrentSsid` now gracefully handles missing permissions, unavailable interfaces, and unsupported cases with informative errors.
- Internal: Aligned native implementations for both platforms with consistent safeguards and cleaned up error handling.

## [1.2.2] - 2025-04-18
### Fixed
- Properly unregisters the network callback in `disconnectFromWifi` on Android 10+ to fully release temporary Wi-Fi connections established via `WifiNetworkSpecifier`.
- Prevents lingering connections and ensures the system cleans up the app-bound network reliably after disconnect.

### Improved
- Strengthened `disconnectFromWifi` behavior on Android by combining `bindProcessToNetwork(null)` with `unregisterNetworkCallback` when applicable, as per platform requirements for Android 10+.

## [1.2.1] - 2025-04-17
### Fixed
- Fixed a critical issue introduced in `v1.2.0` where `connectToWifi` on Android incorrectly returned `INVALID_PASSWORD` due to unreliable SSID validation after connection.
- The plugin now trusts the system connection callback (`onAvailable`) on Android 10+ and does not rely on `WifiManager.connectionInfo.ssid`, which may return `<unknown ssid>`.
- Ensures proper use of `UNAVAILABLE` as a general error when the connection fails without specific cause.

### Added
- New `OpWifiUtilsError.unavailable` error type to represent general connection failures on Android (e.g., network out of range, wrong password, or timeout).

## [1.2.0] - 2025-04-15
### Changed
- All `result.success` and `result.error` calls in Android native code are now wrapped in `Handler(Looper.getMainLooper()).post { ... }` to ensure safe main thread return.
- This change improves stability and avoids potential crashes or UI threading issues across different Android versions and manufacturers.
- Also avoids blocking the main thread while waiting for platform responses, improving compatibility with Flutter's MethodChannel behavior.

## [1.1.0] - 2025-04-14
- Improved `connectToWifi` behavior on iOS:  
  - Handles iOS error code 2 (invalid password format) and maps it to `INVALID_PASSWORD`.
  - Verifies actual connection by comparing current SSID after a short delay.
  - Distinguishes `SSID_NOT_FOUND` from other connection issues.
- Improved `connectToWifi` behavior on Android:
  - After `onAvailable`, verifies the actual connected SSID.
  - If the SSID doesn't match the expected one, returns `INVALID_PASSWORD` to indicate likely credential issues.

## [1.0.1] - 2025-04-03
- README and pubspec wording improved for clarity and consistency

## [1.0.0] - 2025-04-03
- Initial release 🎉
- Connect to Wi-Fi with optional password (iOS and Android)
- Disconnect from Wi-Fi network
- Check current connected SSID
- Full OpResult-based error handling
- joinOnce option supported on iOS
- Example app included for both platforms