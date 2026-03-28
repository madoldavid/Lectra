package com.goydave.lectra

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import com.aboutyou.dart_packages.sign_in_with_apple.SignInWithApplePlugin
import com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin
import com.llfbandit.app_links.AppLinksPlugin
import com.llfbandit.record.RecordPlugin
import com.ryanheise.audio_session.AudioSessionPlugin
import com.ryanheise.just_audio.JustAudioPlugin
import com.tekartik.sqflite.SqflitePlugin
import dev.fluttercommunity.plus.share.SharePlusPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin
import io.flutter.plugins.imagepicker.ImagePickerPlugin
import io.flutter.plugins.pathprovider.PathProviderPlugin
import io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin
import io.flutter.plugins.urllauncher.UrlLauncherPlugin
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin

class MainActivity: FlutterActivity() {
    private val batteryChannel = "lectra/battery_optimization"
    private val logTag = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        registerPluginsSafely(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            batteryChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    result.success(requestIgnoreBatteryOptimizations())
                }

                "openBatteryOptimizationSettings" -> {
                    result.success(openBatteryOptimizationSettings())
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun registerPluginsSafely(flutterEngine: FlutterEngine) {
        // Generated registration can fail hard if one plugin crashes at init.
        // Register plugin-by-plugin so one failure doesn't break the app.
        addPluginIfMissing(flutterEngine, AppLinksPlugin(), AppLinksPlugin::class.java)
        addPluginIfMissing(flutterEngine, AudioSessionPlugin(), AudioSessionPlugin::class.java)
        addPluginIfMissing(
            flutterEngine,
            FFmpegKitFlutterPlugin(),
            FFmpegKitFlutterPlugin::class.java,
        )
        addPluginIfMissing(
            flutterEngine,
            FlutterAndroidLifecyclePlugin(),
            FlutterAndroidLifecyclePlugin::class.java,
        )
        addPluginIfMissing(flutterEngine, ImagePickerPlugin(), ImagePickerPlugin::class.java)
        addPluginIfMissing(flutterEngine, JustAudioPlugin(), JustAudioPlugin::class.java)
        addPluginIfMissing(flutterEngine, PathProviderPlugin(), PathProviderPlugin::class.java)
        addPluginIfMissing(flutterEngine, RecordPlugin(), RecordPlugin::class.java)
        addPluginIfMissing(flutterEngine, SharePlusPlugin(), SharePlusPlugin::class.java)
        addPluginIfMissing(
            flutterEngine,
            SharedPreferencesPlugin(),
            SharedPreferencesPlugin::class.java,
        )
        addPluginIfMissing(
            flutterEngine,
            SignInWithApplePlugin(),
            SignInWithApplePlugin::class.java,
        )
        addPluginIfMissing(flutterEngine, SqflitePlugin(), SqflitePlugin::class.java)
        addPluginIfMissing(flutterEngine, UrlLauncherPlugin(), UrlLauncherPlugin::class.java)
        addPluginIfMissing(flutterEngine, WebViewFlutterPlugin(), WebViewFlutterPlugin::class.java)
    }

    private fun <T : FlutterPlugin> addPluginIfMissing(
        flutterEngine: FlutterEngine,
        plugin: T,
        clazz: Class<out FlutterPlugin>,
    ) {
        if (flutterEngine.plugins.has(clazz)) {
            return
        }
        try {
            flutterEngine.plugins.add(plugin)
        } catch (t: Throwable) {
            Log.e(logTag, "Failed to register plugin ${clazz.simpleName}", t)
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        return try {
            if (isIgnoringBatteryOptimizations()) {
                true
            } else {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        return try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            true
        } catch (_: Exception) {
            false
        }
    }
}
