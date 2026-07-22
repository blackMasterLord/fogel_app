package dev.cantini.op_wifi_utils

import android.content.Context
import android.net.wifi.WifiNetworkSpecifier
import android.net.NetworkRequest
import android.net.NetworkCapabilities
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.Manifest
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

  private fun hasWifiPermission(): Boolean {
    val perm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.NEARBY_WIFI_DEVICES
              else Manifest.permission.ACCESS_FINE_LOCATION
    if (ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED) return true
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) return true
    return false
  }

  private fun connectToWifi(ssid: String, password: String?, bssid: String?, result: Result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) { result.error("UNSUPPORTED", "Only Android 10+ is supported", null); return }
    if (!hasWifiPermission()) { result.error("PERMISSION_REQUIRED", "NEARBY_WIFI_DEVICES or ACCESS_FINE_LOCATION permission required", null); return }

    try {
      val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
      if (!bssid.isNullOrEmpty()) builder.setBssid(android.net.MacAddress.fromString(bssid))
      if (!password.isNullOrEmpty()) builder.setWpa2Passphrase(password)
      val wifiSpecifier = builder.build()

      val networkRequest = NetworkRequest.Builder()
        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
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
      Log.e("OpWifiUtils", "Unexpected exception in connectToWifi: $e")
      Handler(Looper.getMainLooper()).post { result.error("EXCEPTION", "Unexpected error: ${e.localizedMessage}", null) }
    }
  }

  private fun disconnectFromWifi(ssid: String, result: Result) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      try { connectivityManager?.bindProcessToNetwork(null) } catch (e: Exception) { Log.w("OpWifiUtils", "Failed to unbind: $e") }
      activeCallback?.let {
        try { connectivityManager?.unregisterNetworkCallback(it); activeCallback = null } catch (e: Exception) { Log.w("OpWifiUtils", "Error unregistering: $e") }
      }
      result.success(true)
    } else result.error("UNSUPPORTED", "Disconnect only supported on Android 6.0+", null)
  }

  private fun getCurrentSsid(result: Result) {
    if (!hasWifiPermission()) { Handler(Looper.getMainLooper()).post { result.error("PERMISSION_REQUIRED", "Permission required", null) }; return }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      val lm = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
      if (!lm.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) && !lm.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER))
        { Handler(Looper.getMainLooper()).post { result.error("LOCATION_DISABLED", "Location disabled", null) }; return }
    }
    val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    val ssid = wm.connectionInfo.ssid?.removePrefix("\"")?.removeSuffix("\"")
    if (ssid == null || ssid == "<unknown ssid>") Handler(Looper.getMainLooper()).post { result.error("UNKNOWN_CURRENT_SSID", "Unknown SSID", null) }
    else Handler(Looper.getMainLooper()).post { result.success(ssid) }
  }

  private fun getCurrentBssid(result: Result) {
    if (!hasWifiPermission()) { Handler(Looper.getMainLooper()).post { result.error("PERMISSION_REQUIRED", "Permission required", null) }; return }
    val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    val bssid = wm.connectionInfo.bssid
    if (bssid == null || bssid == "00:00:00:00:00:00") Handler(Looper.getMainLooper()).post { result.error("UNKNOWN_CURRENT_BSSID", "Unknown BSSID", null) }
    else Handler(Looper.getMainLooper()).post { result.success(bssid) }
  }
}
