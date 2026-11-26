package com.example.arch_terminal.terminal

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.arch_terminal.R
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.Future

class ArchSetupService : Service() {
    companion object {
        private const val ACTION_START = "com.example.arch_terminal.action.SETUP_ARCH"
        private const val ACTION_CANCEL_DOWNLOAD = "com.example.arch_terminal.action.CANCEL_ROOTFS_DOWNLOAD"
        private const val CHANNEL_ID = "arch_setup_progress"
        private const val NOTIFICATION_ID = 4101
        fun start(context: Context) = ContextCompat.startForegroundService(
            context, Intent(context, ArchSetupService::class.java).setAction(ACTION_START)
        )

        fun cancelDownload(context: Context) = ContextCompat.startForegroundService(
            context, Intent(context, ArchSetupService::class.java).setAction(ACTION_CANCEL_DOWNLOAD)
        )

        /**
         * Restarts only an interrupted setup that has streamable bytes on disk.
         * A fully downloaded archive is verified by [RootfsDownloadManager]
         * before any network request, while a partial archive is resumed with
         * HTTP Range from its exact current length.
         */
        fun resumeIfPending(context: Context): Boolean {
            val abi = Build.SUPPORTED_ABIS.firstOrNull { it == "arm64-v8a" || it == "armeabi-v7a" }
                ?: return false
            val artifact = RootfsDownloadManager.artifactFor(abi) ?: return false
            val installer = ArchInstaller(context, abi)
            val partial = File(RootfsStorage(context).archiveDirectory(), ".${artifact.fileName}.part")
            val shouldResume = RootfsAutoResumePolicy.shouldResume(
                wasRunning = ArchSetupState.snapshot(context).running,
                rootfsInstalled = installer.isInstalled(),
                partialBytes = partial.takeIf { it.isFile }?.length() ?: 0L,
            )
            if (shouldResume) start(context)
            return shouldResume
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var started = false
    @Volatile private var cancellationRequested = false
    private var setupFuture: Future<*>? = null
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL_DOWNLOAD) {
            cancelActiveDownload()
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START || started) return START_REDELIVER_INTENT
        started = true
        cancellationRequested = false
        createChannel()
        publish(SetupProgress(running = true, phase = "preparing", message = runtimeText("جارٍ تجهيز إعداد Arch Linux…", "Preparing Arch Linux setup…")))
        startForeground(NOTIFICATION_ID, notification(ArchSetupState.snapshot(this)))
        acquireWakeLock()
        setupFuture = executor.submit { runSetup() }
        // This user-initiated job can be redelivered after a process reclaim;
        // the downloader resumes a saved byte range instead of starting over.
        return START_REDELIVER_INTENT
    }

    private fun runSetup() {
        try {
            val abi = Build.SUPPORTED_ABIS.firstOrNull { it == "arm64-v8a" || it == "armeabi-v7a" }
                ?: error(runtimeText("يدعم التطبيق ARM64 وARM32 فقط.", "Only ARM64 and ARM32 are supported."))
            val installer = ArchInstaller(this, abi)
            val storage = RootfsStorage(this)
            if (!installer.isInstalled()) {
                var archiveSource = "network"
                var extractionMonitor: ExtractionStallMonitor? = null
                val archive = RootfsDownloadManager(this, storage, isCancellationRequested = {
                    cancellationRequested || Thread.currentThread().isInterrupted
                }).downloadAndVerify(abi) { progress ->
                    archiveSource = progress.archiveSource ?: archiveSource
                    publish(SetupProgress(true, progress.phase, progress.message, progress.percent, progress.bytesDownloaded, progress.totalBytes, progress.bytesPerSecond, archiveSource = archiveSource))
                }
                publish(SetupProgress(running = true, phase = "counting", message = runtimeText("تم التحقق من الأرشيف؛ جارٍ فحص حجم وعدد ملفات Arch Linux قبل الاستخراج…", "Archive verified; scanning Arch Linux size and file count before extraction…"), archiveSource = archiveSource))
                installer.installIfNeeded(archive, onCountProgress = { progress ->
                    publish(
                        SetupProgress(
                            running = true,
                            phase = "counting",
                            message = runtimeText(
                                "جارٍ فحص أرشيف Arch المضغوط قبل الاستخراج — ${progress.percent ?: 0}%.",
                                "Scanning the compressed Arch archive before extraction — ${progress.percent ?: 0}%.",
                            ),
                            percent = progress.percent,
                            bytesDownloaded = progress.scannedCompressedBytes,
                            totalBytes = progress.totalCompressedBytes,
                            archiveSource = archiveSource,
                        ),
                    )
                }, onExtractStart = { totalFiles ->
                    extractionMonitor = ExtractionStallMonitor {
                        publish(
                            SetupProgress(
                                running = true,
                                phase = "extracting",
                                message = runtimeText(
                                    "لم يتغير تقدم استخراج Arch لمدة دقيقتين؛ جارٍ متابعة الملف الحالي. إذا توقف كلياً سيُحفظ ما اكتمل للاستئناف.",
                                    "Arch extraction has made no progress for two minutes; continuing the current file. Completed entries remain saved for resume.",
                                ),
                                failureDetail = runtimeText("لا توجد حركة في عدد الملفات أو البايتات خلال مهلة المراقبة.", "No file or byte movement was observed during the watchdog timeout."),
                                totalFiles = totalFiles,
                                archiveSource = archiveSource,
                            ),
                        )
                    }.also { it.start() }
                    publish(
                        SetupProgress(
                            running = true,
                            phase = "extracting",
                            message = runtimeText("جارٍ استخراج ملفات Arch Linux — 0 من $totalFiles ملفاً.", "Extracting Arch Linux files — 0 of $totalFiles files."),
                            percent = 0,
                            totalFiles = totalFiles,
                            archiveSource = archiveSource,
                        ),
                    )
                }) { progress ->
                    extractionMonitor?.heartbeat()
                    val remaining = progress.secondsRemaining?.let {
                        runtimeText(" — المتبقي تقريباً ${formatDuration(it)}", " — about ${formatDuration(it)} remaining")
                    } ?: ""
                    val activeFile = progress.currentEntry?.let { entry ->
                        val current = formatByteSize(progress.currentEntryBytes)
                        val total = formatByteSize(progress.currentEntrySize)
                        runtimeText(
                            "جارٍ نسخ ملف كبير: ${entry.substringAfterLast('/')} — $current من $total.",
                            "Copying a large file: ${entry.substringAfterLast('/')} — $current of $total.",
                        )
                    }
                    publish(
                        SetupProgress(
                            running = true,
                            phase = "extracting",
                            message = activeFile ?: runtimeText("جارٍ استخراج ملفات Arch Linux — ${progress.extractedFiles} من ${progress.totalFiles} ملفاً$remaining.", "Extracting Arch Linux files — ${progress.extractedFiles} of ${progress.totalFiles} files$remaining."),
                            percent = progress.percent,
                            extractedFiles = progress.extractedFiles,
                            totalFiles = progress.totalFiles,
                            filesPerSecond = progress.filesPerSecond,
                            secondsRemaining = progress.secondsRemaining,
                            archiveSource = archiveSource,
                        ),
                    )
                }
                extractionMonitor?.close()
                if (installer.isInstalled() && !storage.retentionEnabled()) archive.delete()
            }
            ensureProot(abi)
            publish(SetupProgress(phase = "complete", message = runtimeText("اكتمل إعداد Arch $abi محلياً.", "Arch $abi setup completed locally."), percent = 100))
        } catch (_: RootfsDownloadCancelledException) {
            val snapshot = ArchSetupState.snapshot(this)
            publish(
                SetupProgress(
                    phase = "cancelled",
                    message = runtimeText(
                        "تم إلغاء تنزيل Arch Linux. حُفظ الجزء المكتمل وسيُستأنف عند اختيار المتابعة.",
                        "Arch Linux download was cancelled. The completed part was kept and will resume when you continue.",
                    ),
                    bytesDownloaded = snapshot.bytesDownloaded,
                    totalBytes = snapshot.totalBytes,
                    archiveSource = "network",
                ),
            )
        } catch (error: Throwable) {
            // The next service run can resume from the atomic extraction checkpoint.
            val rootCause = generateSequence(error) { it.cause }.last()
            val detail = "${rootCause.javaClass.simpleName}: ${rootCause.message ?: runtimeText("لا توجد رسالة إضافية", "No additional message")}".take(420)
            publish(SetupProgress(phase = "error", message = runtimeText("فشل إعداد Arch Linux في مرحلة ${ArchSetupState.snapshot(this).phase}.", "Arch Linux setup failed during ${ArchSetupState.snapshot(this).phase}."), failureDetail = detail))
        } finally {
            started = false
            setupFuture = null
            releaseWakeLock()
            // Keep the final complete/error notification visible after the
            // foreground operation ends so a background failure is not silent.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(false)
            }
            stopSelf()
        }
    }

    private fun cancelActiveDownload() {
        val phase = ArchSetupState.snapshot(this).phase
        if (phase !in setOf("connecting", "downloading", "verifying")) return
        cancellationRequested = true
        publish(
            SetupProgress(
                running = true,
                phase = "cancelling",
                message = runtimeText("جارٍ إيقاف التنزيل وحفظ الجزء المكتمل…", "Stopping the download and keeping the completed part…"),
            ),
        )
        setupFuture?.cancel(true)
    }

    private fun ensureProot(abi: String): File {
        val asset = "bin/$abi/proot"
        val target = File(filesDir, asset)
        if (target.isFile && target.canExecute()) return target
        target.parentFile?.mkdirs()
        assets.open(asset).use { input -> FileOutputStream(target).use { output -> input.copyTo(output) } }
        check(target.setExecutable(true, false)) { runtimeText("تعذر تجهيز PRoot", "Unable to prepare PRoot") }
        return target
    }

    private fun publish(progress: SetupProgress) {
        ArchSetupState.update(this, progress)
        runCatching {
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(progress))
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, runtimeText("إعداد Arch Linux", "Arch Linux setup"), NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    private fun notification(progress: SetupProgress) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_sys_download)
        .setContentTitle("Arch Terminal")
        .setContentText(progress.message)
        .setOnlyAlertOnce(true)
        .setOngoing(progress.running)
        .setProgress(100, progress.percent ?: 0, progress.percent == null)
        .build()

    private fun formatDuration(seconds: Long): String = when {
        seconds <= 0L -> runtimeText("لحظات", "moments")
        seconds < 60L -> runtimeText("$seconds ثانية", "$seconds seconds")
        seconds < 3600L -> runtimeText("${seconds / 60} دقيقة", "${seconds / 60} minutes")
        else -> runtimeText("${seconds / 3600} ساعة و${(seconds % 3600) / 60} دقيقة", "${seconds / 3600} hours and ${(seconds % 3600) / 60} minutes")
    }

    private fun formatByteSize(bytes: Long): String = when {
        bytes < 1024L -> "$bytes B"
        bytes < 1024L * 1024L -> "${bytes / 1024L} KiB"
        else -> "${bytes / (1024L * 1024L)} MiB"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:ArchRootfsSetup")
            .apply { acquire() }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    override fun onDestroy() {
        releaseWakeLock()
        executor.shutdownNow()
        super.onDestroy()
    }
}
