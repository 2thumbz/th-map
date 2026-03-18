package com.example.my_nav_app

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.my_nav_app/config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApiKey" -> {
                        val ai = applicationContext.packageManager
                            .getApplicationInfo(applicationContext.packageName, PackageManager.GET_META_DATA)
                        val key = ai.metaData.getString("com.google.android.geo.API_KEY")
                        if (key != null) result.success(key)
                        else result.error("NO_KEY", "API key not found in manifest", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}