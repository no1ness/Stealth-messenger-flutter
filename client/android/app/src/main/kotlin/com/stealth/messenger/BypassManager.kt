package com.stealth.messenger

import android.content.Context
import android.util.Log
import java.io.File

object BypassManager {
    private const val TAG = "BypassManager"
    const val SOCKS_PORT = 10808
    const val HTTP_PORT = 10809

    private var process: Process? = null
    private var running = false

    fun startBypass(context: Context, serverIp: String, uuid: String, publicKey: String, shortId: String) {
        if (running) {
            Log.w(TAG, "startBypass called but already running — ignoring")
            return
        }

        val binary = File(context.filesDir, "sing-box")
        if (!binary.exists()) {
            Log.e(TAG, "sing-box binary not found at ${binary.absolutePath}")
            return
        }
        binary.setExecutable(true)

        val config = buildClientConfig(serverIp, uuid, publicKey, shortId)
        val configFile = File(context.filesDir, "bypass_config.json")
        configFile.writeText(config)

        try {
            process = ProcessBuilder(
                binary.absolutePath, "run", "-c", configFile.absolutePath
            )
                .directory(context.filesDir)
                .redirectErrorStream(true)
                .start()
            running = true
            Log.i(TAG, "started (mode: binary)")
        } catch (e: Exception) {
            Log.e(TAG, "start failed: $e")
            running = false
        }
    }

    fun stopBypass() {
        process?.let { p ->
            p.destroy()
            p.waitFor()
        }
        process = null
        running = false
        Log.i(TAG, "stopped")
    }

    fun isRunning(): Boolean = running

    private fun buildClientConfig(serverIp: String, uuid: String, publicKey: String, shortId: String): String {
        return """{
  "inbounds": [
    {"type": "socks", "tag": "socks-in", "listen": "127.0.0.1", "listen_port": $SOCKS_PORT},
    {"type": "http", "tag": "http-in", "listen": "127.0.0.1", "listen_port": $HTTP_PORT}
  ],
  "outbounds": [{
    "type": "vless", "tag": "vless-out",
    "server": "$serverIp", "server_port": 443,
    "uuid": "$uuid", "flow": "xtls-rprx-vision",
    "tls": {
      "server_name": "telemost.yandex.ru",
      "reality": {
        "enabled": true, "public_key": "$publicKey", "short_id": "$shortId"
      }
    }
  }]
}"""
    }
}
