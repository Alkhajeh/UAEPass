package com.example.uaepass

import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.NewIntentListener

class UaepassPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, NewIntentListener {
    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var callbackScheme: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "ae.uaepass/flutter_auth/callbacks")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        onDetachedFromActivity()
        callbackScheme = null
        channel?.setMethodCallHandler(null)
        channel = null
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
        if (call.method != "setCallbackScheme") {
            result.notImplemented()
            return
        }

        val scheme = call.arguments
        if (scheme != null && (scheme !is String || scheme.isEmpty())) {
            result.error("invalid_scheme", "Expected a nonempty callback scheme or null.", null)
            return
        }
        callbackScheme = scheme
        result.success(null)
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
}
