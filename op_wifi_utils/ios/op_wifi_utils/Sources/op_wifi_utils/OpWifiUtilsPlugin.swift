import CoreLocation
import Flutter
import UIKit
import NetworkExtension
import SystemConfiguration.CaptiveNetwork

public class SwiftOpWifiUtilsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "op_wifi_utils", binaryMessenger: registrar.messenger())
    let instance = SwiftOpWifiUtilsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "connectToWifi":
      guard let args = call.arguments as? [String: Any],
            let ssid = args["ssid"] as? String else {
        result(FlutterError(code: "MISSING_SSID", message: "SSID is required", details: nil))
        return
      }
      let password = args["password"] as? String
      let joinOnce = args["joinOnce"] as? Bool ?? true
      connectToWifi(ssid: ssid, password: password, joinOnce: joinOnce, result: result)      

    case "disconnectFromWifi":
      handleDisconnectFromWifi(call, result: result)

    case "isAvailable":
      result(true) // not final
      
    case "getCurrentSsid":
      getCurrentSsid(result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func connectToWifi(ssid: String, password: String?, joinOnce: Bool, result: @escaping FlutterResult) {
    // Build configuration (treat empty password as "no password")
    let config: NEHotspotConfiguration =
      (password?.isEmpty == false)
        ? NEHotspotConfiguration(ssid: ssid, passphrase: password!, isWEP: false)
        : NEHotspotConfiguration(ssid: ssid)
    config.joinOnce = joinOnce

    
    #if DEBUG
      // Quick visibility: is there a stored profile right now?
      // NEHotspotConfigurationManager.shared.getConfiguredSSIDs { configured in
      //   NSLog("[OpWifiUtils] [DEBUG] configured.contains(\(ssid)) = \(configured.contains(ssid))")
      // }
    #endif
    

    let runApply = {
      NEHotspotConfigurationManager.shared.apply(config) { error in
        if let e = error as NSError? {
          // Always log the canonical info so we can see the *real* reason
          NSLog("[OpWifiUtils] apply error: domain=%@ code=%ld msg=%@", e.domain, e.code, e.localizedDescription)

          // Old numeric codes some iOS builds still return:
          let errorCodeAlreadyConnected = -10001
          let errorInvalidPasswordFmt  = 2        // e.g. too short
          let errorInternal8           = 8        // opaque "internal error"

          // 0) Already associated → treat as success (common fast path)
          if e.code == errorCodeAlreadyConnected {
            result(true)
            return
          }

          // Prefer enum mapping when available
          // ...
          if e.domain == NEHotspotConfigurationErrorDomain {
            // Map using rawValue to support older SDKs
            let code = e.code

            if code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
              result(true); return
            }
            if code == NEHotspotConfigurationError.userDenied.rawValue {
              result(FlutterError(code: "PERMISSION_REQUIRED", message: e.localizedDescription, details: nil)); return
            }
            if code == NEHotspotConfigurationError.invalidSSID.rawValue ||
              code == NEHotspotConfigurationError.invalid.rawValue {
              result(FlutterError(code: "INVALID_SSID", message: e.localizedDescription, details: nil)); return
            }
            if code == NEHotspotConfigurationError.invalidWPAPassphrase.rawValue ||
              code == NEHotspotConfigurationError.invalidWEPPassphrase.rawValue {
              result(FlutterError(code: "INVALID_PASSWORD", message: e.localizedDescription, details: nil)); return
            }
            if code == NEHotspotConfigurationError.pending.rawValue ||
              code == NEHotspotConfigurationError.systemConfiguration.rawValue {
              // OS busy / Wi-Fi off / another join in progress
              result(FlutterError(code: "UNAVAILABLE", message: e.localizedDescription, details: nil)); return
            }
            if code == 8 {
              result(FlutterError(code: "UNAVAILABLE", message: e.localizedDescription, details: nil)); return
            }

            // Unknown NEHotspot bucket (future iOS)
            result(FlutterError(code: "NEHOTSPOT_UNKNOWN", message: e.localizedDescription, details: "(\(e.domain), \(e.code))")); return
          }

          // Legacy numeric fallbacks (keep these after the NE block)
          if e.code == errorInvalidPasswordFmt {
            result(FlutterError(code: "INVALID_PASSWORD", message: e.localizedDescription, details: nil)); return
          }
          if e.code == errorInternal8 {
            result(FlutterError(code: "UNAVAILABLE", message: e.localizedDescription, details: nil)); return
          }

          // Non-NE domain
          result(FlutterError(code: "OS_UNKNOWN", message: e.localizedDescription, details: "(\(e.domain), \(e.code))"));
          return
        }

        // Success path: optionally sanity-check SSID, but do not fail the call
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
          self.getCurrentSsid { currentSsidResult in
            if let cur = currentSsidResult as? String, cur != ssid {
              NSLog("[OpWifiUtils] joined, but SSID peek mismatch (expected=%@ got=%@) — ignoring and proceeding", ssid, cur)
            }
            // Always succeed after apply success (ssid matching is flaky, mismatch should not cause a failure)
            result(true) 
          }
        }        
      }
    }

    if Thread.isMainThread {
      runApply()
    } else {
      NSLog("[OpWifiUtils] connectToWifi called off main thread → dispatching to main")
      DispatchQueue.main.async { runApply() }
    }
  }

  private func handleDisconnectFromWifi(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let ssid = args["ssid"] as? String, !ssid.isEmpty else {
      result(FlutterError(code: "MISSING_SSID", message: "SSID is required", details: nil))
      return
    }

    let run = {
      // This forgets the config; iOS may remain associated until it roams.
      NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
      result(true)
    }

    if Thread.isMainThread { run() } else {
      DispatchQueue.main.async { run() }
    }
  }

  private func getCurrentSsid(result: @escaping FlutterResult) {
    // Use instance-based status on iOS 14+, fall back on older iOS
    let status: CLAuthorizationStatus = {
      if #available(iOS 14.0, *) {
        return CLLocationManager().authorizationStatus
      } else {
        return CLLocationManager.authorizationStatus()
      }
    }()

    // Treat denied/restricted (and optionally notDetermined) as permission required
    if status == .denied || status == .restricted {
      result(FlutterError(code: "PERMISSION_REQUIRED",
                          message: "Location permission is denied",
                          details: nil))
      return
    }
    // If you prefer to block until the app requests permission, uncomment:
    // if status == .notDetermined {
    //   result(FlutterError(code: "PERMISSION_REQUIRED",
    //                       message: "Location permission not determined",
    //                       details: nil))
    //   return
    // }

    if let interfaces = CNCopySupportedInterfaces() as NSArray? {
      for interface in interfaces {
        if let info = CNCopyCurrentNetworkInfo(interface as! CFString) as NSDictionary?,
          let ssid = info[kCNNetworkInfoKeySSID as String] as? String {
          result(ssid)
          return
        }
      }
    }

    // Not connected / no permission to read / other limitation
    result(FlutterError(code: "UNKNOWN_CURRENT_SSID",
                        message: "Could not determine current SSID",
                        details: "The device might not be connected to Wi-Fi, or entitlements/permissions are missing."))
  }
  
}
