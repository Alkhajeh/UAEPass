package com.example.uaepass

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.NewIntentListener

class UaepassPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, NewIntentListener {
    private var applicationContext: Context? = null
    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var callbackScheme: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ae.uaepass/flutter_auth/callbacks")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        onDetachedFromActivity()
        callbackScheme = null
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setCallbackScheme" -> {
                val scheme = call.arguments
                if (scheme != null && (scheme !is String || scheme.isEmpty())) {
                    result.error("invalid_scheme", "Expected a nonempty callback scheme or null.", null)
                    return
                }
                callbackScheme = scheme
                result.success(null)
            }
            "isAppInstalled" -> {
                val appPackage = when (call.arguments) {
                    "staging" -> STAGING_PACKAGE
                    "production" -> PRODUCTION_PACKAGE
                    else -> null
                }
                result.success(appPackage != null && isAppInstalled(appPackage))
            }
            "launchApp" -> result.success(launchApp(call.arguments as? String))
            else -> result.notImplemented()
        }
    }

    private fun isAppInstalled(appPackage: String): Boolean {
        val packageManager = applicationContext?.packageManager ?: return false
        return try {
            packageManager.getApplicationInfo(appPackage, 0).enabled
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun launchApp(rawUri: String?): Boolean {
        val activity = activityBinding?.activity ?: return false
        val uri = rawUri?.let(Uri::parse) ?: return false
        val appPackage = when (uri.scheme) {
            "uaepassstg" -> STAGING_PACKAGE
            "uaepass" -> PRODUCTION_PACKAGE
            else -> return false
        }
        return try {
            val intent = Intent(Intent.ACTION_VIEW, uri)
                .setPackage(appPackage)
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    override fun onNewIntent(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_VIEW) return false

        val callback = intent.data ?: return false
        val scheme = callbackScheme ?: return false
        if (callback.scheme != scheme || (callback.host != "success" && callback.host != "failure")) {
            return false
        }

        val activeChannel = channel ?: return false
        activeChannel.invokeMethod("onCallback", callback.toString())
        return true
    }

    private companion object {
        const val STAGING_PACKAGE = "ae.uaepass.mainapp.stg"
        const val PRODUCTION_PACKAGE = "ae.uaepass.mainapp"
    }
}
