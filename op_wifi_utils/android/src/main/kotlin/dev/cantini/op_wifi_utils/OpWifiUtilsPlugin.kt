package dev.cantini.op_wifi_utils

import android.content.Context
import android.net.wifi.WifiNetworkSpecifier
import android.net.NetworkRequest
import android.net.NetworkCapabilities
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.net.wifi.WifiConfiguration
import android.Manifest
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import android.os.Build
import android.util.Log
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicBoolean
import android.net.Network
import android.net.LinkProperties
import android.net.NetworkInfo

class OpWifiUtilsPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var context: Context
  private lateinit var channel: MethodChannel
  private var dhcpEventChannel: EventChannel? = null
  private var dhcpEventSink: EventChannel.EventSink? = null
  private var connectivityManager: ConnectivityManager? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "op_wifi_utils")
    channel.setMethodCallHandler(this)
    connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    dhcpEventChannel = EventChannel(binding.binaryMessenger, "com.fogel.app/wifi/dhcp")
    dhcpEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(args: Any?, events: EventChannel.EventSink) { dhcpEventSink = events }
      override fun onCancel(args: Any?) { dhcpEventSink = null }
    })
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    dhcpEventChannel?.setStreamHandler(null)
    dhcpEventSink = null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "connectToWifi" -> {
        val ssid = call.argument<String>("ssid") ?: return result.error("MISSING_SSID", "SSID is required", null)
        val password = call.argument<String>("password")
        val bssid = call.argument<String>("bssid")
        val joinOnce = call.argument<Boolean>("joinOnce") ?: true
        if (!joinOnce) Log.w("OpWifiUtils", "joinOnce=false ignored")
        connectToWifi(ssid, password, bssid, result)
      }
      "disconnectFromWifi" -> {
        val ssid = call.argument<String>("ssid") ?: return result.error("MISSING_SSID", "SSID is required", null)
        disconnectFromWifi(ssid, result)
      }
      "isAvailable" -> result.success(true)
      "getCurrentSsid" -> getCurrentSsid(result)
      "getCurrentBssid" -> getCurrentBssid(result)
      else -> result.notImplemented()
    }
  }

  private var activeCallback: ConnectivityManager.NetworkCallback? = null
  private var legacyNetworkId: Int = -1
  private var legacyReceiver: BroadcastReceiver? = null

  private fun hasWifiPermission(): Boolean {
    val perm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.NEARBY_WIFI_DEVICES
              else Manifest.permission.ACCESS_FINE_LOCATION
    if (ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED) return true
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) return true
    return false
  }

  // =========================================================================
  // Unified connectToWifi — branches by SDK
  // =========================================================================

  private fun connectToWifi(ssid: String, password: String?, bssid: String?, result: Result) {
    if (!hasWifiPermission()) {
      result.error("PERMISSION_REQUIRED", "NEARBY_WIFI_DEVICES or ACCESS_FINE_LOCATION permission required", null)
      return
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      connectWithSpecifier(ssid, password, bssid, result)
    } else {
      connectWithLegacy(ssid, password, bssid, result)
    }
  }

  // =========================================================================
  // SpecifierConnectionStrategy (API 29+)
  // =========================================================================

  private fun connectWithSpecifier(ssid: String, password: String?, bssid: String?, result: Result) {
    try {
      val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
      if (!bssid.isNullOrEmpty()) builder.setBssid(android.net.MacAddress.fromString(bssid))
      if (!password.isNullOrEmpty()) builder.setWpa2Passphrase(password)
      val wifiSpecifier = builder.build()

      val networkRequest = NetworkRequest.Builder()
        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
        .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .setNetworkSpecifier(wifiSpecifier)
        .build()

      try { activeCallback?.let { connectivityManager?.unregisterNetworkCallback(it); Log.d("OpWifiUtils", "Cleaned up previous callback") } }
      catch (e: Exception) { Log.w("OpWifiUtils", "Exception while cleaning old callback: $e") }

      val resultHandled = AtomicBoolean(false)

      val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
          if (!resultHandled.compareAndSet(false, true)) return
          try { connectivityManager?.bindProcessToNetwork(network) } catch (e: Exception) { Log.e("OpWifiUtils", "Error binding: $e") }
          Handler(Looper.getMainLooper()).post { result.success(true) }
        }
        override fun onUnavailable() {
          if (!resultHandled.compareAndSet(false, true)) return
          try { activeCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }; activeCallback = null }
          catch (e: Exception) { Log.w("OpWifiUtils", "unregister in onUnavailable: $e") }
          Handler(Looper.getMainLooper()).post { result.error("UNAVAILABLE", "Could not connect to the Wi-Fi network", null) }
        }
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) { Log.d("OpWifiUtils", "Capabilities changed: $capabilities") }
        override fun onLinkPropertiesChanged(network: Network, props: LinkProperties) {
          val ip = props.linkAddresses?.firstOrNull()?.address?.hostAddress
          if (ip != null) Handler(Looper.getMainLooper()).post { dhcpEventSink?.success(true) }
        }
        override fun onLost(network: Network) { Log.w("OpWifiUtils", "Lost network: $network") }
        override fun onLosing(network: Network, maxMsToLive: Int) { Log.w("OpWifiUtils", "Losing network in $maxMsToLive ms") }
      }

      connectivityManager?.requestNetwork(networkRequest, callback)
      activeCallback = callback
    } catch (e: Exception) {
      Log.e("OpWifiUtils", "Specifier error: $e")
      Handler(Looper.getMainLooper()).post { result.error("EXCEPTION", "Unexpected error: ${e.localizedMessage}", null) }
    }
  }

  // =========================================================================
  // LegacyConnectionStrategy (API 21-28) — WifiConfiguration
  // =========================================================================

  private fun connectWithLegacy(ssid: String, password: String?, bssid: String?, result: Result) {
    try {
      val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
      if (!wifiManager.isWifiEnabled) {
        result.error("WIFI_DISABLED", "Wi-Fi is disabled", null)
        return
      }

      val config = WifiConfiguration().apply {
        SSID = "\"$ssid\""
        if (!password.isNullOrEmpty()) {
          preSharedKey = "\"$password\""
          allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
        } else {
          allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
        }
        if (!bssid.isNullOrEmpty()) {
          BSSID = bssid
        }
      }

      val networkId = wifiManager.addNetwork(config)
      if (networkId == -1) {
        result.error("ADD_NETWORK_FAILED", "Failed to add Wi-Fi network", null)
        return
      }
      legacyNetworkId = networkId

      wifiManager.disconnect()
      wifiManager.enableNetwork(networkId, true)

      val receiverHandled = AtomicBoolean(false)

      val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
          if (receiverHandled.get()) return
          when (intent?.action) {
            WifiManager.NETWORK_STATE_CHANGED_ACTION -> {
              val info: NetworkInfo? = intent.getParcelableExtra(WifiManager.EXTRA_NETWORK_INFO)
              if (info?.isConnected == true) {
                val connectedSsid = wifiManager.connectionInfo.ssid?.removePrefix("\"")?.removeSuffix("\"")
                if (connectedSsid == ssid) {
                  if (receiverHandled.compareAndSet(false, true)) {
                    unregisterLegacyReceiver()
                    Handler(Looper.getMainLooper()).post { result.success(true) }
                  }
                }
              }
            }
            WifiManager.SUPPLICANT_STATE_CHANGED_ACTION -> {
              val errorCode = intent.getIntExtra(WifiManager.EXTRA_SUPPLICANT_ERROR, -1)
              if (errorCode == WifiManager.ERROR_AUTHENTICATING) {
                if (receiverHandled.compareAndSet(false, true)) {
                  unregisterLegacyReceiver()
                  Handler(Looper.getMainLooper()).post { result.error("PROBABLE_WRONG_PASSWORD", "Authentication failed", null) }
                }
              }
            }
          }
        }
      }

      val filter = IntentFilter().apply {
        addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
        addAction(WifiManager.SUPPLICANT_STATE_CHANGED_ACTION)
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        context.applicationContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
      } else {
        context.applicationContext.registerReceiver(receiver, filter)
      }
      legacyReceiver = receiver

      // 20 second timeout
      Handler(Looper.getMainLooper()).postDelayed({
        if (receiverHandled.compareAndSet(false, true)) {
          unregisterLegacyReceiver()
          Handler(Looper.getMainLooper()).post { result.error("TIMEOUT", "Connection attempt timed out", null) }
        }
      }, 20_000L)

      wifiManager.reconnect()

    } catch (e: Exception) {
      Log.e("OpWifiUtils", "Legacy error: $e")
      Handler(Looper.getMainLooper()).post { result.error("EXCEPTION", "Unexpected error: ${e.localizedMessage}", null) }
    }
  }

  private fun unregisterLegacyReceiver() {
    legacyReceiver?.let {
      try { context.applicationContext.unregisterReceiver(it) } catch (_: Exception) {}
      legacyReceiver = null
    }
  }

  // =========================================================================
  // Disconnect
  // =========================================================================

  private fun disconnectFromWifi(ssid: String, result: Result) {
    try {
      // Specifier cleanup
      connectivityManager?.bindProcessToNetwork(null)
      activeCallback?.let {
        try { connectivityManager?.unregisterNetworkCallback(it); activeCallback = null } catch (e: Exception) { Log.w("OpWifiUtils", "Error unregistering: $e") }
      }
      // Legacy cleanup
      if (legacyNetworkId != -1) {
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiManager.disconnect()
        wifiManager.disableNetwork(legacyNetworkId)
        wifiManager.removeNetwork(legacyNetworkId)
        legacyNetworkId = -1
      }
      unregisterLegacyReceiver()
      result.success(true)
    } catch (e: Exception) {
      Log.e("OpWifiUtils", "Disconnect error: $e")
      result.error("EXCEPTION", "Disconnect failed: ${e.localizedMessage}", null)
    }
  }

  private fun getCurrentSsid(result: Result) {
    if (!hasWifiPermission()) { Handler(Looper.getMainLooper()).post { result.error("PERMISSION_REQUIRED", "Permission required", null) }; return }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      val lm = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
      if (!lm.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) && !lm.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER))
        { Handler(Looper.getMainLooper()).post { result.error("LOCATION_DISABLED", "Location disabled", null) }; return }
    }
    val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    @Suppress("DEPRECATION")
    val ssid = wm.connectionInfo.ssid?.removePrefix("\"")?.removeSuffix("\"")
    if (ssid == null || ssid == "<unknown ssid>") Handler(Looper.getMainLooper()).post { result.error("UNKNOWN_CURRENT_SSID", "Unknown SSID", null) }
    else Handler(Looper.getMainLooper()).post { result.success(ssid) }
  }

  private fun getCurrentBssid(result: Result) {
    if (!hasWifiPermission()) { Handler(Looper.getMainLooper()).post { result.error("PERMISSION_REQUIRED", "Permission required", null) }; return }
    val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    @Suppress("DEPRECATION")
    val bssid = wm.connectionInfo.bssid
    if (bssid == null || bssid == "00:00:00:00:00:00") Handler(Looper.getMainLooper()).post { result.error("UNKNOWN_CURRENT_BSSID", "Unknown BSSID", null) }
    else Handler(Looper.getMainLooper()).post { result.success(bssid) }
  }
}
