package com.vladislavdelon.blackboxmobile

import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "bb/core"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
        val py = Python.getInstance()
        val bridge: PyObject = py.getModule("bbcore.bridge")

        // Инициализация: передаём приватную папку приложения для хранения ключей
        try {
            bridge.callAttr("init", filesDir.absolutePath)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val method = call.method
                val argsJson = call.argument<String>("argsJson") ?: "{}"
                // Сетевые вызовы (биржи) — в фоне, чтобы не блокировать UI
                Thread {
                    val out: String = try {
                        bridge.callAttr("call_json", method, argsJson).toString()
                    } catch (e: Exception) {
                        """{"ok": false, "error": "${e.message?.replace("\"", "'")}"}"""
                    }
                    runOnUiThread { result.success(out) }
                }.start()
            }
    }
}
