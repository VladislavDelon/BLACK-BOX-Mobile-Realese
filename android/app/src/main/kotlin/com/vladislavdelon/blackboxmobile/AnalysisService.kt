package com.vladislavdelon.blackboxmobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import org.json.JSONObject

class AnalysisService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var running = false
    private var soundThreshold = 1.5
    private val alerted = mutableSetOf<String>()

    companion object {
        const val CHANNEL_ID = "blackbox_analysis"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_ARGS = "args"
        const val EXTRA_SOUND_THRESHOLD = "sound_threshold"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val args = intent?.getStringExtra(EXTRA_ARGS) ?: "{}"
        soundThreshold = intent?.getDoubleExtra(EXTRA_SOUND_THRESHOLD, 1.5) ?: 1.5
        alerted.clear()
        startForeground(NOTIFICATION_ID, buildNotification("Запуск анализа..."))
        acquireWakeLock()
        running = true

        Thread {
            try {
                if (!Python.isStarted()) {
                    Python.start(AndroidPlatform(this))
                }
                val py = Python.getInstance()
                val bridge = py.getModule("bbcore.bridge")
                val startRes = bridge.callAttr("call_json", "start_analysis", args).toString()
                val startObj = JSONObject(startRes)
                if (startObj.optBoolean("ok")) {
                    pollProgress()
                } else {
                    updateNotification("Ошибка запуска анализа")
                    stopService()
                }
            } catch (e: Exception) {
                e.printStackTrace()
                updateNotification("Ошибка: ${e.message}")
                stopService()
            }
        }.start()

        return START_STICKY
    }

    private fun pollProgress() {
        while (running) {
            try {
                val py = Python.getInstance()
                val bridge = py.getModule("bbcore.bridge")
                val res = bridge.callAttr("call_json", "get_analysis_progress", "{}").toString()
                val obj = JSONObject(res)
                if (obj.optBoolean("ok")) {
                    val status = obj.getString("status")
                    val progress = obj.getJSONArray("progress")
                    if (progress.length() > 0) {
                        for (i in 0 until progress.length()) {
                            val e = progress.getJSONObject(i)
                            val symbol = e.optString("symbol", "")
                            val signal = e.optString("signal", "")
                            val pct = e.optDouble("pct", 0.0)
                            if ((signal == "LONG" || signal == "SHORT") && Math.abs(pct) >= soundThreshold) {
                                if (alerted.add("$symbol:$signal")) {
                                    playNotificationSound()
                                }
                            }
                        }
                        val last = progress.getJSONObject(progress.length() - 1)
                        val symbol = last.optString("symbol", "")
                        val st = last.optString("status", "...")
                        updateNotification("$symbol: $st")
                    } else {
                        updateNotification("Анализ: подготовка...")
                    }

                    if (status == "done" || status == "error" || status == "cancelled") {
                        val finalText = if (status == "done") "Анализ завершён" else "Анализ остановлен"
                        updateNotification(finalText)
                        Thread.sleep(2000)
                        stopService()
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            Thread.sleep(1200)
        }
    }

    private fun playNotificationSound() {
        try {
            val notification: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            RingtoneManager.getRingtone(applicationContext, notification)?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun buildNotification(text: String): android.app.Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("BLACK BOX — анализ")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentIntent(pi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Анализ в фоне",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Уведомления о фоновом анализе"
            nm.createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "blackbox:analysis")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(60 * 60 * 1000L) // максимум 1 час
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopService() {
        running = false
        wakeLock?.release()
        stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        super.onDestroy()
    }
}
