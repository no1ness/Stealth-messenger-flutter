package com.stealth.messenger

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.stealth.messenger/bypass"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val serverIp = call.argument<String>("serverIp")!!
                    val uuid = call.argument<String>("uuid")!!
                    val publicKey = call.argument<String>("publicKey")!!
                    val shortId = call.argument<String>("shortId")!!
                    BypassManager.startBypass(this, serverIp, uuid, publicKey, shortId)
                    result.success(true)
                }
                "stop" -> {
                    BypassManager.stopBypass()
                    result.success(true)
                }
                "state" -> {
                    result.success(BypassManager.isRunning())
                }
                else -> result.notImplemented()
            }
        }
    }
}
