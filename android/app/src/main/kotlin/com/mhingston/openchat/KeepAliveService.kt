package com.mhingston.openchat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * A foreground service that keeps the process alive and holds WiFi/wake locks
 * while a streaming chat request is in progress.
 *
 * On Android 14+ (API 34+), startForeground() MUST be called with an explicit
 * foregroundServiceType; omitting it causes Android to kill the service within
 * 5 seconds. This class handles that requirement directly so we are not
 * dependent on a third-party plugin's native implementation.
 */
class KeepAliveService : Service() {

    companion object {
        private const val CHANNEL_ID = "openchat_request"
        private const val NOTIFICATION_ID = 1001
        private const val WAKE_LOCK_TAG = "openchat:keep_alive_wake"
        private const val WIFI_LOCK_TAG = "openchat:keep_alive_wifi"
        // Safety cap so a forgotten lock never drains the battery all day.
        private const val WAKE_LOCK_TIMEOUT_MS = 30 * 60 * 1000L // 30 min
    }

    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ requires explicit foreground service types.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireLocks()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── helpers ──────────────────────────────────────────────────────────────

    private fun ensureNotificationChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Request in progress",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while a chat request is running to keep the connection alive."
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("OpenChat")
            .setContentText("Waiting for response\u2026")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun acquireLocks() {
        try {
            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, WIFI_LOCK_TAG)
            wifiLock?.acquire()
        } catch (_: Exception) {}

        try {
            val pm = applicationContext.getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            wakeLock?.acquire(WAKE_LOCK_TIMEOUT_MS)
        } catch (_: Exception) {}
    }

    private fun releaseLocks() {
        try { wifiLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wifiLock = null
        wakeLock = null
    }
}
