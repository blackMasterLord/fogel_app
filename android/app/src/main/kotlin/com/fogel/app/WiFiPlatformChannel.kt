package com.fogel.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.Manifest
import android.util.Log
import androidx.core.content.ContextCompat
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.Executors

class WiFiPlatformChannel(private val context: Context) {

    companion object {
        private const val METHOD_CHANNEL = "com.fogel.app/wifi"
        private const val EVENT_CHANNEL = "com.fogel.app/wifi/events"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var wifiStateReceiver: BroadcastReceiver? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private val wifiManager: WifiManager by lazy {
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }

    private val connectivityManager: ConnectivityManager by lazy {
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openWifiSettings" -> {
                    openWifiSettings()
                    result.success(true)
                }
                "getConnectedSSID" -> {
                    result.success(getConnectedSSID())
                }
                "isWifiEnabled" -> {
                    result.success(isWifiEnabled())
                }
                "enableWifi" -> {
                    enableWifi()
                    result.success(true)
                }
                "showWifiPanel" -> {
                    showWifiPanel()
                    result.success(true)
                }
                "scanNetworks" -> {
                    scanNetworks(result)
                }
                "getGatewayIp" -> {
                    result.success(getGatewayIp())
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startNetworkCallback()
                }

                override fun onCancel(arguments: Any?) {
                    stopNetworkCallback()
                    eventSink = null
                }
            }
        )
    }

    private fun getGatewayIp(): String? {
        val dhcp = wifiManager.dhcpInfo ?: return null
        val ip = dhcp.gateway
        if (ip == 0) return null
        return "${ip and 0xFF}.${(ip shr 8) and 0xFF}.${(ip shr 16) and 0xFF}.${(ip shr 24) and 0xFF}"
    }

    // Manual signal level calculation — replaces deprecated WifiManager.calculateSignalLevel (API 31+)
    private fun calculateSignalLevel(rssi: Int): Int {
        return when { rssi >= -50 -> 5; rssi >= -60 -> 4; rssi >= -70 -> 3; rssi >= -80 -> 2; rssi >= -90 -> 1; else -> 0 }
    }

    private fun openWifiSettings() {
        val intent = Intent(Settings.ACTION_WIFI_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun getConnectedSSID(): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = connectivityManager.activeNetwork ?: return null
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return null
            if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return null

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val transportInfo = capabilities.transportInfo
                if (transportInfo is android.net.wifi.WifiInfo) {
                    val ssid = transportInfo.ssid
                    if (ssid != null && ssid != "<unknown ssid>" && ssid.isNotEmpty()) {
                        return ssid.removeSurrounding("\"")
                    }
                }
            }
        }

        @Suppress("DEPRECATION")
        val connectionInfo = wifiManager.connectionInfo
        if (connectionInfo.networkId == -1) return null

        val ssid = connectionInfo.ssid
        if (ssid == null || ssid == "<unknown ssid>") return null
        return ssid.removeSurrounding("\"")
    }

    @Suppress("DEPRECATION")
    private fun isWifiEnabled(): Boolean {
        return wifiManager.isWifiEnabled
    }

    private fun enableWifi() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            wifiManager.isWifiEnabled = true
        } else {
            showWifiPanel()
        }
    }

    private fun showWifiPanel() {
        val launched = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val intent = Intent(Settings.Panel.ACTION_WIFI).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
        } else {
            false
        }

        if (!launched) {
            openWifiSettings()
        }

        listenForWifiEnabled()
    }

    private fun listenForWifiEnabled() {
        wifiStateReceiver?.let {
            try { context.applicationContext.unregisterReceiver(it) } catch (_: Exception) {}
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action == WifiManager.WIFI_STATE_CHANGED_ACTION) {
                    val state = intent.getIntExtra(
                        WifiManager.EXTRA_WIFI_STATE,
                        WifiManager.WIFI_STATE_UNKNOWN
                    )
                    if (state == WifiManager.WIFI_STATE_ENABLED) {
                        val launch = context.packageManager
                            .getLaunchIntentForPackage(context.packageName)
                        launch?.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        if (launch != null) {
                            context.startActivity(launch)
                        }
                        try {
                            context.applicationContext.unregisterReceiver(this)
                        } catch (_: Exception) {}
                        wifiStateReceiver = null
                    }
                }
            }
        }

        wifiStateReceiver = receiver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            context.applicationContext.registerReceiver(receiver, IntentFilter(WifiManager.WIFI_STATE_CHANGED_ACTION), Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.applicationContext.registerReceiver(receiver, IntentFilter(WifiManager.WIFI_STATE_CHANGED_ACTION))
        }

        mainHandler.postDelayed({
            try {
                context.applicationContext.unregisterReceiver(receiver)
            } catch (_: Exception) {}
            if (wifiStateReceiver === receiver) {
                wifiStateReceiver = null
            }
        }, 30_000L)
    }

    private fun scanNetworks(result: MethodChannel.Result) {
        val hasLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        } else true
        val hasNearby = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.NEARBY_WIFI_DEVICES) == PackageManager.PERMISSION_GRANTED
        } else true
        Log.d("WiFiChannel", "[SCAN-NATIVE] startScan: hasLocation=$hasLocation hasNearby=$hasNearby sdk=${Build.VERSION.SDK_INT}")

        // When already connected to a network, use cached results to avoid
        // interrupting the active WiFi connection (startScan can cause brief drops).
        val connectedSsid = getConnectedSSID()
        if (connectedSsid != null && connectedSsid.isNotEmpty()) {
            Log.d("WiFiChannel", "[SCAN-NATIVE] connected to $connectedSsid, returning cached results")
            @Suppress("DEPRECATION")
            val cached = wifiManager.scanResults?.map {
                mapOf(
                    "ssid" to (it.SSID ?: ""),
                    "bssid" to (it.BSSID ?: ""),
                    "signalLevel" to calculateSignalLevel(it.level),
                    "capabilities" to (it.capabilities ?: "")
                )
            } ?: emptyList()
            result.success(cached)
            return
        }

        // registerScanResultsCallback — not deprecated (API 28+)
        val scanSuccess = wifiManager.startScan()
        Log.d("WiFiChannel", "[SCAN-NATIVE] startScan returned $scanSuccess")
        if (!scanSuccess) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        val resultSent = AtomicBoolean(false)
        val callback = object : WifiManager.ScanResultsCallback() {
            override fun onScanResultsAvailable() {
                if (!resultSent.getAndSet(true)) return
                wifiManager.unregisterScanResultsCallback(this)
                @Suppress("DEPRECATION")
                val networks = wifiManager.scanResults?.map {
                    mapOf(
                        "ssid" to (it.SSID ?: ""),
                        "bssid" to (it.BSSID ?: ""),
                        "signalLevel" to calculateSignalLevel(it.level),
                        "capabilities" to (it.capabilities ?: ""),
                    )
                } ?: emptyList()
                result.success(networks)
            }
        }
        wifiManager.registerScanResultsCallback(executor, callback)

        mainHandler.postDelayed({
            wifiManager.unregisterScanResultsCallback(callback)
            if (!resultSent.getAndSet(true)) {
                @Suppress("DEPRECATION")
                val cached = wifiManager.scanResults?.map {
                    mapOf("ssid" to (it.SSID ?: ""), "bssid" to (it.BSSID ?: ""),
                          "signalLevel" to calculateSignalLevel(it.level),
                          "capabilities" to (it.capabilities ?: ""))
                } ?: emptyList()
                result.success(cached)
            }
        }, 4000L)
    }

    private fun startNetworkCallback() {
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                mainHandler.post {
                    eventSink?.success(mapOf("event" to "connected", "ssid" to getConnectedSSID()))
                }
            }

            override fun onLost(network: Network) {
                mainHandler.post {
                    eventSink?.success(mapOf("event" to "disconnected"))
                }
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                mainHandler.post {
                    eventSink?.success(mapOf("event" to "changed", "ssid" to getConnectedSSID()))
                }
            }
        }

        connectivityManager.registerNetworkCallback(request, networkCallback!!)
    }

    private fun stopNetworkCallback() {
        if (networkCallback != null) {
            try {
                connectivityManager.unregisterNetworkCallback(networkCallback!!)
            } catch (_: Exception) {}
            networkCallback = null
        }
    }

    fun cleanup() {
        stopNetworkCallback()

        wifiStateReceiver?.let {
            try { context.applicationContext.unregisterReceiver(it) } catch (_: Exception) {}
            wifiStateReceiver = null
        }
    }
}
