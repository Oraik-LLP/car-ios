package com.oraik.fixease

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fixease/device"
        ).setMethodCallHandler { call, result ->
            if (call.method != "getDeviceId") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val deviceId = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ANDROID_ID
            )

            if (deviceId.isNullOrBlank()) {
                result.error(
                    "device_id_unavailable",
                    "Could not resolve this Android device identifier.",
                    null
                )
                return@setMethodCallHandler
            }

            result.success(deviceId)
        }
    }
}
