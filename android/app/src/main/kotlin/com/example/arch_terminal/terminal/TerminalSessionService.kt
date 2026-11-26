package com.example.arch_terminal.terminal

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.arch_terminal.MainActivity

/**
 * Keeps a user-visible terminal session in foreground priority while the
 * Flutter PTY is running. It deliberately does not claim to resurrect a PTY
 * after Android kills the process: that would expose a misleading stale state.
 */
class TerminalSessionService : Service() {
    companion object {
        private const val ACTION_START = "com.example.arch_terminal.action.START_TERMINAL_SESSION"
        private const val ACTION_END = "com.example.arch_terminal.action.END_TERMINAL_SESSION"
        private const val ACTION_TOGGLE_DEEP = "com.example.arch_terminal.action.TOGGLE_DEEP_TERMINAL_SESSION"
        private const val ACTION_SET_BACKGROUND_PROTECTION = "com.example.arch_terminal.action.SET_BACKGROUND_PROTECTION"
        private const val ACTION_NETWORK_DIAGNOSTIC = "com.example.arch_terminal.action.NETWORK_DIAGNOSTIC"
        private const val EXTRA_NETWORK_DIAGNOSTIC = "network_diagnostic"
        private const val EXTRA_BACKGROUND_PROTECTION_ENABLED = "background_protection_enabled"
        private const val CHANNEL_ID = "arch_terminal_session"
        private const val NOTIFICATION_ID = 4102
        private const val PREFS = "terminal_session_runtime"
        private const val KEY_DEEP_ON_NEXT_SESSION = "deep_on_next_session"
        private const val KEY_RESTART_ON_NEXT_LAUNCH = "restart_on_next_launch"
        private const val KEY_BACKGROUND_PROTECTION_ENABLED = "background_protection_enabled"
        private const val KEY_RECONNECT_PENDING = "reconnect_pending"
        @Volatile private var activeInCurrentProcess = false
        @Volatile private var deepInCurrentProcess = false

        fun start(context: Context) = ContextCompat.startForegroundService(
            context,
            Intent(context, TerminalSessionService::class.java).setAction(ACTION_START),
        )

        fun stop(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_RECONNECT_PENDING)
                .apply()
            context.stopService(Intent(context, TerminalSessionService::class.java))
        }

        /**
         * Persists the explicit user choice. When a live PTY exists, asks the
         * foreground service to acquire or release its partial wake lock too.
         * It deliberately does not start a foreground notification for a
         * non-existent session.
         */
        fun setBackgroundProtection(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_BACKGROUND_PROTECTION_ENABLED, enabled)
                .apply()
            if (enabled && activeInCurrentProcess) {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(KEY_RECONNECT_PENDING, true)
                    .apply()
            }
            if (activeInCurrentProcess) {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, TerminalSessionService::class.java)
                        .setAction(ACTION_SET_BACKGROUND_PROTECTION)
                        .putExtra(EXTRA_BACKGROUND_PROTECTION_ENABLED, enabled),
                )
            }
        }

        fun isBackgroundProtectionEnabled(context: Context): Boolean = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_BACKGROUND_PROTECTION_ENABLED, false)

        fun isReconnectPending(context: Context): Boolean = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_RECONNECT_PENDING, false)

        fun reportNetworkDiagnostic(context: Context, message: String) {
            if (message.isBlank()) return
            ContextCompat.startForegroundService(
                context,
                Intent(context, TerminalSessionService::class.java)
                    .setAction(ACTION_NETWORK_DIAGNOSTIC)
                    .putExtra(EXTRA_NETWORK_DIAGNOSTIC, message.take(300)),
            )
        }

        fun acknowledgeEndRequest(context: Context) {
            endRequestFile(context).delete()
            // The next automatic session (after the user opens the app again)
            // should restore foreground protection, but the ending session must
            // release its wake lock and service immediately.
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_DEEP_ON_NEXT_SESSION, true)
                .putBoolean(KEY_RESTART_ON_NEXT_LAUNCH, true)
                .apply()
            stop(context)
        }

        private fun scheduleDeepRestart(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_DEEP_ON_NEXT_SESSION, true)
                .putBoolean(KEY_RESTART_ON_NEXT_LAUNCH, true)
                .apply()
        }

        fun isRestartPending(context: Context): Boolean = context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_RESTART_ON_NEXT_LAUNCH, false)

        fun consumeRestartRequest(context: Context): Boolean {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val pending = preferences.getBoolean(KEY_RESTART_ON_NEXT_LAUNCH, false)
            if (pending) preferences.edit().remove(KEY_RESTART_ON_NEXT_LAUNCH).apply()
            return pending
        }

        fun isEndRequested(context: Context): Boolean = endRequestFile(context).isFile

        /**
         * The PTY belongs to this process. Do not persist this flag: a restored
         * preference after a process kill would falsely claim that a terminal is
         * still available for Flutter to reconnect to.
         */
        fun isActive(context: Context): Boolean = activeInCurrentProcess

        fun isDeep(context: Context): Boolean = deepInCurrentProcess

        private fun endRequestFile(context: Context) = java.io.File(context.filesDir, "terminal-session/end-request")

        private fun consumeDeepNextSession(context: Context): Boolean {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val enabled = preferences.getBoolean(KEY_DEEP_ON_NEXT_SESSION, false)
            if (enabled) preferences.edit().remove(KEY_DEEP_ON_NEXT_SESSION).apply()
            return enabled
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        when (intent?.action) {
            ACTION_NETWORK_DIAGNOSTIC -> {
                networkDiagnostic = intent.getStringExtra(EXTRA_NETWORK_DIAGNOSTIC)
                if (activeInCurrentProcess) startForeground(NOTIFICATION_ID, notification())
                return START_NOT_STICKY
            }
            ACTION_END -> {
                val plan = TerminalSessionEndPolicy.fromNotification()
                // The PTY is hosted by the Flutter process. Killing our own app
                // process is the only immediate, reliable way to terminate it
                // without making the user reopen the UI. A later launch starts
                // a fresh deep session from the saved one-shot restart intent.
                endRequestFile(this).delete()
                getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .remove(KEY_RECONNECT_PENDING)
                    .apply()
                setDeep(false)
                activeInCurrentProcess = false
                networkDiagnostic = null
                if (plan.restartDeepOnNextLaunch) scheduleDeepRestart(this)
                if (plan.removeForegroundNotification) stopForegroundCompat()
                stopSelf()
                if (plan.terminateHostProcess) {
                    android.os.Process.killProcess(android.os.Process.myPid())
                }
                return START_NOT_STICKY
            }
            ACTION_TOGGLE_DEEP -> {
                if (activeInCurrentProcess) {
                    val enabled = !isBackgroundProtectionEnabled(this)
                    getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(KEY_BACKGROUND_PROTECTION_ENABLED, enabled)
                        .apply()
                    setDeep(enabled)
                    startForeground(NOTIFICATION_ID, notification())
                }
                return START_NOT_STICKY
            }
            ACTION_SET_BACKGROUND_PROTECTION -> {
                if (activeInCurrentProcess) {
                    val enabled = intent.getBooleanExtra(
                        EXTRA_BACKGROUND_PROTECTION_ENABLED,
                        isBackgroundProtectionEnabled(this),
                    )
                    setDeep(enabled)
                    startForeground(NOTIFICATION_ID, notification())
                }
                return START_NOT_STICKY
            }
        }
        activeInCurrentProcess = true
        networkDiagnostic = null
        if (isBackgroundProtectionEnabled(this)) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_RECONNECT_PENDING, true)
                .apply()
        }
        val oneShotDeepSessionRequested = consumeDeepNextSession(this)
        setDeep(
            TerminalBackgroundProtectionPolicy.shouldHoldPartialWakeLock(
                sessionActive = activeInCurrentProcess,
                backgroundProtectionEnabled = isBackgroundProtectionEnabled(this),
                oneShotDeepSessionRequested = oneShotDeepSessionRequested,
            ),
        )
        startForeground(NOTIFICATION_ID, notification())
        // The guest PTY belongs to the app process. If that process is killed,
        // restarting an empty service would not restore the guest process.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // A task swipe or process reclaim must not erase the opt-in reconnect
        // marker. The Flutter activity will recreate the PTY on the next launch.
        if (activeInCurrentProcess && isBackgroundProtectionEnabled(this)) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_RECONNECT_PENDING, true)
                .apply()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        setDeep(false)
        networkDiagnostic = null
        activeInCurrentProcess = false
        super.onDestroy()
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var networkDiagnostic: String? = null

    private fun setDeep(enabled: Boolean) {
        if (deepInCurrentProcess == enabled) return
        deepInCurrentProcess = enabled
        if (enabled) {
            val manager = getSystemService(PowerManager::class.java)
            wakeLock = manager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:ArchDeepSession").apply { acquire() }
        } else {
            wakeLock?.takeIf { it.isHeld }?.release()
            wakeLock = null
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, runtimeText("جلسة Arch Terminal", "Arch Terminal session"), NotificationManager.IMPORTANCE_LOW).apply {
                    description = runtimeText("يبقى هذا الإشعار أثناء تشغيل جلسة Arch في الخلفية", "Shown while an Arch session runs in the background")
                },
            )
        }
    }

    private fun notification() = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_sys_warning)
        .setContentTitle(runtimeText("Arch Terminal يعمل", "Arch Terminal is running"))
        .setContentText(
            networkDiagnostic ?: if (deepInCurrentProcess) {
                runtimeText("حماية الخلفية نشطة؛ تبقى عمليات Arch محمية قدر الإمكان. اضغط لفتح الطرفية.", "Background protection is active; Arch processes are kept alive as much as Android permits. Tap to open the terminal.")
            } else {
                runtimeText("جلسة Arch نشطة في الخلفية. اضغط لفتح الطرفية.", "An Arch session is active in the background. Tap to open the terminal.")
            },
        )
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setContentIntent(
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        .addAction(
            android.R.drawable.ic_menu_view,
            runtimeText("فتح الطرفية", "Open terminal"),
            PendingIntent.getActivity(
                this,
                1,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        .addAction(
            android.R.drawable.ic_lock_idle_alarm,
            runtimeText(
                if (isBackgroundProtectionEnabled(this)) "إيقاف حماية الخلفية" else "حماية بالخلفية",
                if (isBackgroundProtectionEnabled(this)) "Disable background protection" else "Protect in background",
            ),
            PendingIntent.getService(
                this,
                2,
                Intent(this, TerminalSessionService::class.java).setAction(ACTION_TOGGLE_DEEP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        .addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            runtimeText("إنهاء الجلسة", "End session"),
            PendingIntent.getService(
                this,
                3,
                Intent(this, TerminalSessionService::class.java).setAction(ACTION_END),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        .build()

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
