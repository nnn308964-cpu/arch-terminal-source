package com.example.arch_terminal.terminal

import android.content.Context
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** A user-requested stop; the partial archive remains available for HTTP Range resume. */
class RootfsDownloadCancelledException : IOException("RootFS download was cancelled by the user")

/** Downloads only the RootFS that matches the running Android ABI and reports progress. */
class RootfsDownloadManager(
    private val context: Context,
    private val providedStorage: RootfsStorage? = null,
    private val isCancellationRequested: () -> Boolean = { false },
) {
    private val storage: RootfsStorage by lazy(LazyThreadSafetyMode.NONE) { providedStorage ?: RootfsStorage(context) }
    private fun text(arabic: String, english: String) = context.runtimeText(arabic, english)
    data class Artifact(val abi: String, val fileName: String, val url: String, val sha256: String)

    data class Progress(
        val phase: String,
        val message: String,
        val percent: Int? = null,
        val bytesDownloaded: Long = 0,
        val totalBytes: Long = -1,
        val bytesPerSecond: Long = 0,
        val archiveSource: String? = null,
    )

    companion object {
        private const val RELEASE =
            "https://github.com/nnn308964-cpu/arch-terminal-source/releases/download/arch-rootfs-v010"
        private val artifacts = mapOf(
            "arm64-v8a" to Artifact("arm64-v8a", "arch-aarch64.tar", "$RELEASE/arch-aarch64.tar", "42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319"),
            "armeabi-v7a" to Artifact("armeabi-v7a", "arch-armv7.tar", "$RELEASE/arch-armv7.tar", "ebe0fa119dea45e3af0aa61785676bdbf417bc5f754d529b87255dbf0ca4e3f0"),
        )

        fun artifactFor(abi: String): Artifact? = artifacts[abi]
    }

    @Throws(IOException::class)
    fun downloadAndVerify(abi: String, onProgress: (Progress) -> Unit = {}): File {
        ensureNotCancelled()
        val artifact = artifactFor(abi) ?: throw IOException(text("لا يوجد ملف Arch Linux منشور للمعمارية $abi", "No Arch Linux file is published for $abi"))
        if (storage.canUsePersistentLocation()) {
            val retained = File(storage.publicDirectory(), artifact.fileName)
            if (retained.isFile) {
                onProgress(Progress("verifying", text("تم العثور على ملف Arch محفوظ في التخزين العام؛ جارٍ التحقق من سلامته…", "A saved Arch file was found in shared storage; verifying its integrity…"), bytesDownloaded = retained.length(), totalBytes = retained.length(), archiveSource = "public"))
            }
            if (retained.isFile && sha256(retained).equals(artifact.sha256, ignoreCase = true)) {
                storage.setLocation(RootfsStorage.Location.PERSISTENT.wireName)
                onProgress(Progress("verified", text("تم العثور على ملف Arch Linux المحفوظ من تثبيت سابق والتحقق منه.", "A saved Arch Linux file from a previous installation was verified."), 100, retained.length(), retained.length(), archiveSource = "public"))
                return retained
            }
        }
        val downloadDir = storage.archiveDirectory()
        val target = File(downloadDir, artifact.fileName)
        if (target.isFile) {
            onProgress(Progress("verifying", text("تم العثور على ملف Arch محفوظ؛ جارٍ التحقق من سلامته…", "A saved Arch file was found; verifying its integrity…"), bytesDownloaded = target.length(), totalBytes = target.length(), archiveSource = if (storage.retentionEnabled()) "public" else "local"))
        }
        if (target.isFile && sha256(target).equals(artifact.sha256, ignoreCase = true)) {
            val location = if (storage.retentionEnabled()) text("المحفوظ بعد إعادة التثبيت", "saved after reinstall") else text("المحلي", "local")
            onProgress(Progress("verified", text("ملف Arch Linux $location موجود وتم التحقق منه.", "The $location Arch Linux file was verified."), 100, target.length(), target.length(), archiveSource = if (storage.retentionEnabled()) "public" else "local"))
            return target
        }
        target.delete()

        val partial = File(downloadDir, ".${artifact.fileName}.part")
        try {
            // A process can die after the final byte is flushed but before the
            // file is atomically renamed. Verify that exact case locally before
            // opening a new connection (which could otherwise receive HTTP 416).
            if (partial.isFile && partial.length() > 0L && sha256(partial).equals(artifact.sha256, ignoreCase = true)) {
                check(partial.renameTo(target)) { text("تعذر اعتماد ملف Arch Linux الذي تم تنزيله", "Unable to finalize the downloaded Arch Linux file") }
                onProgress(Progress("verified", text("تم استعادة ملف Arch Linux المكتمل والتحقق منه.", "A completed Arch Linux file was recovered and verified."), 100, target.length(), target.length(), archiveSource = "local"))
                return target
            }
            val existingPartialBytes = partial.takeIf { it.isFile }?.length() ?: 0L
            val connectionMessage = if (existingPartialBytes > 0L) {
                text("جارٍ استئناف تنزيل Arch Linux المحفوظ…", "Resuming the saved Arch Linux download…")
            } else {
                text("جارٍ الاتصال بمستودع Arch Linux…", "Connecting to the Arch Linux repository…")
            }
            onProgress(Progress("connecting", connectionMessage, bytesDownloaded = existingPartialBytes, archiveSource = "network"))
            ensureNotCancelled()
            val connection = (URL(artifact.url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 20_000
                readTimeout = 60_000
                instanceFollowRedirects = true
                setRequestProperty("Accept", "application/octet-stream")
                if (existingPartialBytes > 0L) setRequestProperty("Range", "bytes=$existingPartialBytes-")
            }
            try {
                val code = connection.responseCode
                if (code !in 200..299) throw IOException(text("تعذر تنزيل Arch Linux (HTTP $code)", "Unable to download Arch Linux (HTTP $code)"))
                ensureNotCancelled()
                val plan = RootfsDownloadResumePolicy.responsePlan(
                    existingPartialBytes = existingPartialBytes,
                    responseCode = code,
                    responseContentLength = connection.contentLengthLong,
                    contentRange = connection.getHeaderField("Content-Range"),
                )
                val total = plan.totalBytes
                var downloaded = plan.initialBytes
                val startedAt = System.nanoTime()
                var lastUpdate = startedAt
                connection.inputStream.buffered(64 * 1024).use { input ->
                    FileOutputStream(partial, plan.append).buffered(64 * 1024).use { output ->
                        RootfsDownloadStreamCopier.copy(
                            input = input,
                            output = output,
                            checkCancellation = ::ensureNotCancelled,
                        ) { count ->
                            downloaded += count
                            val now = System.nanoTime()
                            if (now - lastUpdate >= 250_000_000L || (total > 0 && downloaded == total)) {
                                val seconds = (now - startedAt) / 1_000_000_000.0
                                val speed = if (seconds > 0) (downloaded / seconds).toLong() else 0L
                                val percent = if (total > 0) ((downloaded * 100) / total).toInt().coerceIn(0, 100) else null
                                onProgress(Progress("downloading", text("جارٍ تنزيل Arch Linux المطابق لجهازك…", "Downloading the Arch Linux image for your device…"), percent, downloaded, total, speed, archiveSource = "network"))
                                lastUpdate = now
                            }
                        }
                    }
                }
            } finally {
                connection.disconnect()
            }

            onProgress(Progress("verifying", text("اكتمل التنزيل — جارٍ التحقق من SHA-256…", "Download completed — verifying SHA-256…"), 100, partial.length(), partial.length(), archiveSource = "network"))
            val actual = sha256(partial)
            if (!actual.equals(artifact.sha256, ignoreCase = true)) throw IOException(text("فشل التحقق من سلامة ملف Arch Linux (SHA-256)", "Arch Linux file integrity verification failed (SHA-256)"))
            check(partial.renameTo(target)) { text("تعذر اعتماد ملف Arch Linux الذي تم تنزيله", "Unable to finalize the downloaded Arch Linux file") }
            onProgress(Progress("verified", text("تم التحقق من ملف Arch Linux بنجاح.", "Arch Linux file verified successfully."), 100, target.length(), target.length(), archiveSource = "network"))
            return target
        } catch (error: Throwable) {
            // Preserve streamable partial bytes after a transient network error
            // or an Android process reclaim. The next service delivery requests
            // only the missing HTTP range; SHA-256 still guards finalization.
            if (error is IOException) throw error
            throw IOException(text("فشل تنزيل Arch Linux للمعمارية $abi", "Arch Linux download failed for $abi"), error)
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun ensureNotCancelled() {
        if (RootfsDownloadCancellationPolicy.shouldCancel(isCancellationRequested(), Thread.currentThread().isInterrupted)) {
            throw RootfsDownloadCancelledException()
        }
    }
}
