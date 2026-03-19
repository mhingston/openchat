package com.mhingston.openchat

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val keepAliveChannel = "com.mhingston.openchat/keep_alive"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            keepAliveChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = Intent(this, KeepAliveService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, KeepAliveService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
