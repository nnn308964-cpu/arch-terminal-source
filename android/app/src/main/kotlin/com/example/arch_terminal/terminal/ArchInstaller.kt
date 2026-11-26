package com.example.arch_terminal.terminal

import android.content.Context
import java.io.File
import java.io.FileInputStream
import java.io.IOException

class ArchInstaller(
    private val context: Context,
    val abi: String,
    private val usableSpaceProvider: () -> Long = { context.filesDir.usableSpace },
    private val textResolver: (String, String) -> String = { arabic, english -> context.runtimeText(arabic, english) },
) {
    private fun text(arabic: String, english: String) = textResolver(arabic, english)

    data class Result(
        val rootfsPath: String,
        val alreadyInstalled: Boolean,
    )

    companion object {
        private const val INSTALL_MARKER = ".arch_terminal_ready"
        private const val AID_INET_GROUP = "aid_inet:x:3003:root,bin,daemon"
    }

    val rootfsDir: File
        get() = File(context.filesDir, "arch/$abi")

    fun isInstalled(): Boolean {
        if (!File(rootfsDir, INSTALL_MARKER).isFile) return false
        return runCatching {
            // Upgrade an existing RootFS in place as well as a newly extracted
            // one, so pacman works immediately after the app update.
            ensureRuntimeFiles()
            true
        }.getOrDefault(false)
    }

    fun isPacmanSandboxDisabled(): Boolean = File(rootfsDir, "etc/pacman.conf")
        .takeIf { it.isFile }
        ?.useLines { lines -> lines.any { it.trim() == "DisableSandbox" } }
        ?: false

    /** Extracts a previously verified download into an atomic staging directory. */
    @Synchronized
    fun installIfNeeded(
        archiveFile: File,
        onCountProgress: (TarGzExtractor.CountProgress) -> Unit = {},
        onExtractStart: (Int) -> Unit = {},
        onExtractProgress: (TarGzExtractor.Progress) -> Unit = {},
    ): Result {
        if (isInstalled()) {
            ensureRuntimeFiles()
            return Result(rootfsDir.absolutePath, alreadyInstalled = true)
        }
        check(archiveFile.isFile) { text("ملف Arch Linux الذي تم تنزيله غير موجود", "The downloaded Arch Linux file is missing") }

        val staging = File(context.filesDir, "arch.$abi.installing")
        val checkpointFile = File(context.filesDir, "arch.$abi.extracting.checkpoint")

        try {
            val scan = FileInputStream(archiveFile).buffered().use { archive ->
                TarGzExtractor.scan(archive, archiveFile.length(), onCountProgress)
            }
            check(scan.fileCount > 0) { text("أرشيف Arch Linux لا يحتوي على ملفات قابلة للاستخراج", "The Arch Linux archive contains no extractable files") }

            // The archive already consumes its storage before this preflight
            // runs. Staging is renamed in place, so only its materialized
            // payload plus filesystem metadata is additional app storage.
            val savedCheckpoint = ExtractionCheckpoint.read(checkpointFile)
                ?.takeIf { it.isCompatible(archiveFile.length(), scan.fileCount) }
            if (savedCheckpoint == null) {
                if (staging.exists()) staging.deleteRecursively()
                checkpointFile.delete()
                staging.mkdirs()
            } else {
                staging.mkdirs()
            }

            val requiredBytes = RootfsSpaceEstimator.requiredAdditionalBytes(scan.materializedBytes)
            val freeBytes = usableSpaceProvider()
            check(RootfsSpaceEstimator.hasCapacity(freeBytes, scan.materializedBytes)) {
                text(
                    "لا توجد مساحة داخلية كافية لاستخراج Arch Linux. المطلوب نحو ${toMiB(requiredBytes)} MiB والمتاح ${toMiB(freeBytes)} MiB.",
                    "There is not enough internal space to extract Arch Linux. About ${toMiB(requiredBytes)} MiB is required; ${toMiB(freeBytes)} MiB is available.",
                )
            }

            onExtractStart(scan.fileCount)
            FileInputStream(archiveFile).buffered().use { archive ->
                TarGzExtractor.extract(
                    source = archive,
                    destination = staging,
                    totalFiles = scan.fileCount,
                    startEntryIndex = savedCheckpoint?.completedEntries ?: 0L,
                    initialExtractedFiles = savedCheckpoint?.completedFiles ?: 0,
                    onEntryCompleted = { completedEntries, completedFiles ->
                        ExtractionCheckpoint(
                            archiveLength = archiveFile.length(),
                            totalFiles = scan.fileCount,
                            completedEntries = completedEntries,
                            completedFiles = completedFiles,
                        ).writeAtomically(checkpointFile)
                    },
                    onProgress = onExtractProgress,
                )
            }
            patchGroupFile(staging)
            File(staging, "sdcard").mkdirs()
            File(staging, "tmp").mkdirs()
            File(staging, "proc").mkdirs()
            File(staging, "sys").mkdirs()
            File(staging, "dev").mkdirs()
            RootfsNetworkConfig.apply(staging)
            RootfsTerminalProfile.apply(staging)
            verifyRuntimeLayout(staging)
            File(staging, INSTALL_MARKER).writeText("arch-terminal-$abi-v4\n")

            if (rootfsDir.exists()) rootfsDir.deleteRecursively()
            rootfsDir.parentFile?.mkdirs()
            check(staging.renameTo(rootfsDir)) { text("تعذر تثبيت Arch Linux للمعمارية $abi", "Unable to install Arch Linux for $abi") }
            checkpointFile.delete()
            ensureRuntimeFiles()
            return Result(rootfsDir.absolutePath, alreadyInstalled = false)
        } catch (error: Throwable) {
            // Keep the staging directory and checkpoint so a later service run
            // can skip completed tar entries. A changed archive invalidates
            // this state before extraction starts.
            val rootCause = generateSequence(error) { it.cause }.last()
            val detail = rootCause.message?.take(360) ?: rootCause.javaClass.simpleName
            throw IOException(
                text(
                    "فشل تثبيت Arch Linux للمعمارية $abi. السبب: ${rootCause.javaClass.simpleName}: $detail",
                    "Arch Linux installation failed for $abi. Cause: ${rootCause.javaClass.simpleName}: $detail",
                ),
                error,
            )
        }
    }

    private fun ensureRuntimeFiles() {
        File(rootfsDir, "sdcard").mkdirs()
        File(rootfsDir, "tmp").mkdirs()
        File(rootfsDir, "proc").mkdirs()
        File(rootfsDir, "sys").mkdirs()
        File(rootfsDir, "dev").mkdirs()
        RootfsNetworkConfig.apply(rootfsDir)
        RootfsTerminalProfile.apply(rootfsDir)
        patchGroupFile(rootfsDir)
        patchPacmanSandbox(rootfsDir)
        verifyRuntimeLayout(rootfsDir)
    }

    /**
     * Pacman 7 sandboxes downloads using Landlock and an `alpm` user. Android
     * kernels exposed through PRoot do not provide Landlock, which makes every
     * package transaction fail before a download can start. Disable that
     * optional pacman sandbox only inside this PRoot guest.
     */
    private fun patchPacmanSandbox(root: File) {
        val config = File(root, "etc/pacman.conf")
        if (!config.isFile) return
        val current = config.readText()
        val patched = PacmanConfigPatcher.apply(current)
        if (patched != current) config.writeText(patched)
    }

    private fun verifyRuntimeLayout(root: File) {
        check(RootfsNetworkConfig.isConfigured(root)) {
            text("إعداد DNS داخل RootFS غير صالح: ${File(root, "etc/resolv.conf").absolutePath}", "The RootFS DNS configuration is invalid: ${File(root, "etc/resolv.conf").absolutePath}")
        }
        check(RootfsTerminalProfile.isConfigured(root)) {
            text("ملف تلوين الطرفية غير صالح داخل RootFS.", "The RootFS terminal color profile is invalid.")
        }
        if (abi != "armeabi-v7a") return
        val loader = File(root, "lib/ld-linux-armhf.so.3")
        check(loader.isFile) {
            text(
                "محمل ARM32 الديناميكي مفقود: ${loader.absolutePath}. أعد تنزيل RootFS ARM32.",
                "The ARM32 dynamic loader is missing: ${loader.absolutePath}. Download the ARM32 RootFS again.",
            )
        }
        check(File(root, "usr/bin/env").isFile) {
            text("برنامج /usr/bin/env مفقود من RootFS ARM32.", "/usr/bin/env is missing from the ARM32 RootFS.")
        }
    }

    private fun patchGroupFile(root: File) {
        val etc = File(root, "etc")
        etc.mkdirs()
        val group = File(etc, "group")
        val old = if (group.isFile) group.readText() else ""
        if (!old.lineSequence().any { it.startsWith("aid_inet:") }) {
            val suffix = if (old.isEmpty() || old.endsWith('\n')) old else "$old\n"
            group.writeText(suffix + AID_INET_GROUP + "\n")
        }
    }

    private fun toMiB(bytes: Long): Long = bytes / (1024L * 1024L)
}
