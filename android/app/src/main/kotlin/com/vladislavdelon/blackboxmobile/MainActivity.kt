package com.vladislavdelon.blackboxmobile

import android.content.Intent
import android.os.Build
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
                when (call.method) {
                    "call_json" -> {
                        val method = call.argument<String>("method") ?: ""
                        val argsJson = call.argument<String>("argsJson") ?: "{}"
                        Thread {
                            val out: String = try {
                                bridge.callAttr("call_json", method, argsJson).toString()
                            } catch (e: Exception) {
                                """{"ok": false, "error": "${e.message?.replace("\"", "'")}"}"""
                            }
                            runOnUiThread { result.success(out) }
                        }.start()
                    }
                    "start_analysis_service" -> {
                        val args = call.argument<String>("args") ?: "{}"
                        val soundThreshold = call.argument<Double>("sound_threshold") ?: 1.5
                        val intent = Intent(this, AnalysisService::class.java)
                        intent.putExtra(AnalysisService.EXTRA_ARGS, args)
                        intent.putExtra(AnalysisService.EXTRA_SOUND_THRESHOLD, soundThreshold)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success("ok")
                    }
                    "stop_analysis_service" -> {
                        stopService(Intent(this, AnalysisService::class.java))
                        result.success("ok")
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
