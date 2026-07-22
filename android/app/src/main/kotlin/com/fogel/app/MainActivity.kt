package com.fogel.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private lateinit var wifiChannel: WiFiPlatformChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wifiChannel = WiFiPlatformChannel(this)
        wifiChannel.register(flutterEngine)
    }

    override fun onDestroy() {
        if (::wifiChannel.isInitialized) {
            wifiChannel.cleanup()
        }
        super.onDestroy()
    }
}
