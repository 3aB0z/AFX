package com.example.frontend

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.util.Log

class MainActivity : FlutterActivity() {
    private val channelId = "com.example.frontend/socket_background"
    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "🎯 configureFlutterEngine called")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelId)
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "📞 MethodChannel call: ${call.method}")
                when (call.method) {
                    "startBackgroundService" -> {
                        Log.d(TAG, "🚀 startBackgroundService called from Flutter")
                        startBackgroundService()
                        result.success(null)
                        Log.d(TAG, "✅ startBackgroundService completed")
                    }
                    else -> {
                        Log.w(TAG, "⚠️ Unknown method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }
    }

    private fun startBackgroundService() {
        Log.d(TAG, "🔧 Starting background service...")
        val intent = Intent(this, SocketBackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Log.d(TAG, "✅ Using startForegroundService (Android 8+)")
            startForegroundService(intent)
        } else {
            Log.d(TAG, "✅ Using startService (Android < 8)")
            startService(intent)
        }
        Log.d(TAG, "✅ Background service started")
    }
}
