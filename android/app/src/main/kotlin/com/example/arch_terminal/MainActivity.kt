package com.example.arch_terminal

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.Settings
import com.example.arch_terminal.terminal.ArchInstaller
import com.example.arch_terminal.terminal.ArchSetupService
import com.example.arch_terminal.terminal.ArchSetupState
import com.example.arch_terminal.terminal.AndroidSoundFeedback
import com.example.arch_terminal.terminal.DeviceStorageAccess
import com.example.arch_terminal.terminal.DeviceFilePreviewPolicy
import com.example.arch_terminal.terminal.RootfsDownloadManager
import com.example.arch_terminal.terminal.RootfsNetworkConfig
import com.example.arch_terminal.terminal.RootfsStorage
import com.example.arch_terminal.terminal.TerminalSessionService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.example.arch_terminal/local_runtime"
        private const val PROGRESS_CHANNEL = "com.example.arch_terminal/setup_progress"
        private val SUPPORTED_ABIS = setOf("arm64-v8a", "armeabi-v7a")
        private const val REQUEST_NOTIFICATION = 7001
        private const val REQUEST_STORAGE = 7002
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        StartupDiagnostics.begin("STARTUP_03_MAIN_ACTIVITY_CREATE")
        try {
            super.onCreate(savedInstanceState)
            // If Android reclaimed a user-initiated RootFS setup, continue from the
            // persisted partial archive as soon as the user reopens the app.
            ArchSetupService.resumeIfPending(this)
            StartupDiagnostics.ok("STARTUP_03_MAIN_ACTIVITY_CREATE")
        } catch (error: Throwable) {
            StartupDiagnostics.failed("STARTUP_03_MAIN_ACTIVITY_CREATE", error)
            throw error
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        StartupDiagnostics.begin("STARTUP_04_FLUTTER_ENGINE")
        try {
            super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var unsubscribe: (() -> Unit)? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    unsubscribe?.invoke()
                    unsubscribe = ArchSetupState.subscribe(this@MainActivity) { progress ->
                        runOnUiThread { events.success(progress.asMap()) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    unsubscribe?.invoke()
                    unsubscribe = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> runCatching { runtimeStatus() }
                        .onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "installArch" -> {
                        ArchSetupService.start(this)
                        result.success(
                            runtimeStatus(message = "بدأ إعداد Arch في الخلفية. سيبقى إشعار التقدم ظاهراً أثناء التنزيل والتثبيت.") +
                                mapOf("setupStarted" to true),
                        )
                    }
                    "cancelArchDownload" -> {
                        ArchSetupService.cancelDownload(this)
                        result.success(
                            runtimeStatus(message = localized(
                                "طُلب إلغاء تنزيل Arch؛ سيُحفظ الجزء المكتمل للاستئناف.",
                                "Arch download cancellation was requested; the completed part will be kept for resume.",
                            )),
                        )
                    }
                    "requestAllFilesAccess" -> requestAllFilesAccess(result)
                    "rootfsStorageSettings" -> runCatching { rootfsStorageSettings() }
                        .onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "setRootfsStorageMode" -> runCatching {
                        setRootfsStorageMode(call.argument<String>("mode"))
                    }.onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "openRootfsLocation" -> runCatching { openRootfsLocation() }
                        .onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "requestBatteryOptimizationExemption" -> {
                        requestBatteryOptimizationExemption()
                        result.success(runtimeStatus())
                    }
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "startTerminalSessionService" -> runCatching {
                        TerminalSessionService.start(this)
                        runtimeStatus(message = localized("جلسة Arch محمية بإشعار الخلفية.", "Arch session is protected by a background notification."))
                    }.onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "stopTerminalSessionService" -> {
                        TerminalSessionService.stop(this)
                        result.success(runtimeStatus())
                    }
                    "setTerminalBackgroundProtection" -> runCatching {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        TerminalSessionService.setBackgroundProtection(this, enabled)
                        runtimeStatus(
                            message = localized(
                                if (enabled) {
                                    "وضع حماية جلسة Arch في الخلفية مفعّل. سيستخدم إشعاراً مستمراً وحماية CPU أثناء الجلسة."
                                } else {
                                    "وضع حماية جلسة Arch في الخلفية متوقف."
                                },
                                if (enabled) {
                                    "Arch background-protection mode is enabled. It uses an ongoing notification and CPU protection while the session runs."
                                } else {
                                    "Arch background-protection mode is disabled."
                                },
                            ),
                        )
                    }.onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "acknowledgeTerminalEndRequest" -> {
                        TerminalSessionService.acknowledgeEndRequest(this)
                        result.success(null)
                    }
                    "consumeTerminalRestartRequest" -> result.success(TerminalSessionService.consumeRestartRequest(this))
                    "reportPacmanNetworkFailure" -> {
                        TerminalSessionService.reportNetworkDiagnostic(this, call.argument<String>("message").orEmpty())
                        result.success(null)
                    }
                    "readDeepSessionTranscript" -> result.success(readDeepSessionTranscript())
                    "previewDeviceFile" -> {
                        val path = call.argument<String>("path")
                        Thread {
                            runCatching { previewDeviceFile(path) }
                                .onSuccess { preview -> runOnUiThread { result.success(preview) } }
                                .onFailure { error -> runOnUiThread {
                                    result.error("DEVICE_FILE_PREVIEW_ERROR", error.message, null)
                                } }
                        }.start()
                    }
                    "appendDeepSessionTranscript" -> {
                        appendDeepSessionTranscript(call.argument<String>("text").orEmpty())
                        result.success(null)
                    }
                    "shareTerminalLog" -> runCatching {
                        shareTerminalLog(call.argument<String>("text").orEmpty())
                    }.onSuccess { result.success(null) }
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "terminalPreferences" -> result.success(terminalPreferences())
                    "setTerminalPreferences" -> runCatching {
                        setTerminalPreferences(
                            fontSize = call.argument<Number>("fontSize")?.toFloat(),
                            language = call.argument<String>("language"),
                            sessionName = call.argument<String>("sessionName"),
                            soundEnabled = call.argument<Boolean>("soundEnabled"),
                            soundVolume = call.argument<Number>("soundVolume")?.toFloat(),
                        )
                    }.onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "playSoundFeedback" -> {
                        AndroidSoundFeedback.play(this, call.argument<String>("event").orEmpty())
                        result.success(null)
                    }
                    "archCommand" -> runCatching { archCommand() }
                        .onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "archLaunchDiagnostics" -> runCatching { archLaunchDiagnostics() }
                        .onSuccess(result::success)
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    "openStartupDiagnostics" -> runCatching { openStartupDiagnostics() }
                        .onSuccess { result.success(null) }
                        .onFailure { result.error("LOCAL_RUNTIME_ERROR", it.message, null) }
                    else -> result.notImplemented()
                }
            }
            StartupDiagnostics.ok("STARTUP_04_FLUTTER_ENGINE")
        } catch (error: Throwable) {
            StartupDiagnostics.failed("STARTUP_04_FLUTTER_ENGINE", error)
            throw error
        }
    }

    private fun installArchAsync(result: MethodChannel.Result) {
        Thread {
            try {
                val payload = installArch()
                runOnUiThread { result.success(payload) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("LOCAL_RUNTIME_ERROR", error.message ?: "تعذر تجهيز Arch Linux", null)
                }
            }
        }.start()
    }

    private fun installArch(): Map<String, Any?> {
        val abi = currentAbi()
            ?: return runtimeStatus(message = "هذه المعمارية غير مدعومة حالياً. يدعم التطبيق ARM64 وARM32.")
        val installer = ArchInstaller(this, abi)
        val prootAsset = prootAssetPath(abi)
        if (!assetExists(prootAsset)) {
            return runtimeStatus(message = "ملف PRoot غير موجود للمعمارية $abi.")
        }

        if (installer.isInstalled()) {
            val proot = ensureProotBinary(abi)
            return runtimeStatus(
                message = "Arch $abi جاهز للاستخدام محلياً.",
                installer = installer,
                proot = proot,
                alreadyInstalled = true,
            ) + mapOf("installed" to true)
        }

        val archive = RootfsDownloadManager(this).downloadAndVerify(abi)
        val installed = try {
            installer.installIfNeeded(archive)
        } finally {
            // Keep a verified public archive so a later reinstall can detect it,
            // verify it again, and extract without another network download.
            if (installer.isInstalled() && !RootfsStorage(this).retentionEnabled()) archive.delete()
        }
        val proot = ensureProotBinary(abi)
        return runtimeStatus(
            message = "تم تنزيل والتحقق من Arch $abi ثم تثبيته محلياً.",
            installer = installer,
            proot = proot,
            alreadyInstalled = installed.alreadyInstalled,
        ) + mapOf("installed" to true)
    }

    private fun terminalPreferences(): Map<String, Any> {
        val preferences = getSharedPreferences("terminal_ui", MODE_PRIVATE)
        return mapOf(
            "fontSize" to preferences.getFloat("fontSize", 12f).toDouble(),
            "language" to preferences.getString("language", "ar")!!,
            "sessionName" to preferences.getString("sessionName", "Arch")!!,
            "soundEnabled" to preferences.getBoolean("soundEnabled", true),
            "soundVolume" to preferences.getFloat("soundVolume", 0.35f).toDouble(),
        )
    }

    private fun setTerminalPreferences(
        fontSize: Float?,
        language: String?,
        sessionName: String?,
        soundEnabled: Boolean?,
        soundVolume: Float?,
    ): Map<String, Any> {
        val preferences = getSharedPreferences("terminal_ui", MODE_PRIVATE)
        preferences.edit().apply {
            fontSize?.let { putFloat("fontSize", it.coerceIn(7f, 20f)) }
            language?.takeIf { it == "ar" || it == "en" }?.let { putString("language", it) }
            sessionName?.trim()?.take(32)?.takeIf { it.isNotEmpty() }?.let { putString("sessionName", it) }
            soundEnabled?.let { putBoolean("soundEnabled", it) }
            soundVolume?.let { putFloat("soundVolume", it.coerceIn(0f, 1f)) }
        }.apply()
        return terminalPreferences()
    }

    private fun localized(arabic: String, english: String): String {
        val language = getSharedPreferences("terminal_ui", MODE_PRIVATE).getString("language", "ar")
        return if (language == "en") english else arabic
    }

    private fun runtimeStatus(
        message: String? = null,
        installer: ArchInstaller? = currentAbi()?.let { ArchInstaller(this, it) },
        proot: File? = currentAbi()?.let { File(filesDir, prootAssetPath(it)) },
        alreadyInstalled: Boolean? = null,
    ): Map<String, Any?> {
        val abi = currentAbi()
        val supported = abi != null
        val effectiveInstaller = if (supported) installer else null
        val effectiveProot = if (supported) proot else null
        val bundledProot = abi?.let { assetExists(prootAssetPath(it)) } == true
        val installed = effectiveInstaller?.isInstalled() == true
        val artifact = abi?.let { RootfsDownloadManager.artifactFor(it) }
        val storage = RootfsStorage(this)
        return mapOf(
            "supported" to supported,
            "abi" to abi,
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "installed" to installed,
            "alreadyInstalled" to alreadyInstalled,
            "pacmanSandboxDisabled" to (installed && effectiveInstaller.isPacmanSandboxDisabled()),
            "prootAvailable" to (effectiveProot?.let { it.isFile && it.canExecute() } == true || bundledProot),
            "prootAssetBundled" to bundledProot,
            "rootfsDownloadUrl" to artifact?.url,
            "rootfsSha256" to artifact?.sha256,
            "rootfsPath" to effectiveInstaller?.rootfsDir?.absolutePath,
            "storagePath" to Environment.getExternalStorageDirectory().absolutePath,
            "allFilesAccess" to hasAllFilesAccess(),
            "batteryOptimizationIgnored" to isIgnoringBatteryOptimization(),
            "notificationGranted" to hasNotificationPermission(),
            "terminalSessionForeground" to TerminalSessionService.isActive(this),
            "terminalSessionDeep" to TerminalSessionService.isDeep(this),
            "terminalBackgroundProtectionEnabled" to TerminalSessionService.isBackgroundProtectionEnabled(this),
            "terminalReconnectPending" to TerminalSessionService.isReconnectPending(this),
            "terminalEndRequested" to TerminalSessionService.isEndRequested(this),
            "terminalRestartPending" to TerminalSessionService.isRestartPending(this),
            "rootfsDnsConfigured" to (installed && RootfsNetworkConfig.isConfigured(effectiveInstaller.rootfsDir)),
            "rootfsMirrorUrl" to RootfsNetworkConfig.MIRROR_URL,
            "message" to (message ?: when {
                !supported -> localized("المعمارية الحالية غير مدعومة من إصدار Android.", "This Android ABI is not supported by the app.")
                installed -> localized("Arch rootfs مثبت محلياً للمعمارية $abi.", "Arch rootfs is installed locally for $abi.")
                else -> localized("نزّل Arch Linux للمعمارية $abi عند الضغط على «تنزيل وإعداد Arch».", "Download Arch Linux for $abi from Download and set up Arch.")
            }),
        ) + deviceStorageStatus() + storage.status(artifact) + ArchSetupState.asMap(this)
    }

    private fun archCommand(): Map<String, String> {
        val abi = checkNotNull(currentAbi()) {
            localized("المعمارية الحالية غير مدعومة من إصدار Android.", "This Android ABI is not supported.")
        }
        val installer = ArchInstaller(this, abi)
        check(installer.isInstalled()) { localized("نزّل وثبّت Arch Linux للمعمارية $abi أولاً.", "Download and install Arch Linux for $abi first.") }
        val proot = ensureProotBinary(abi)
        val prootTmp = ensureProotTmpDirectory(abi)
        check(proot.isFile && proot.canExecute()) { localized("ملف PRoot غير متاح للمعمارية $abi.", "PRoot is unavailable for $abi.") }
        return mapOf(
            "abi" to abi,
            "prootPath" to proot.absolutePath,
            "prootTmpPath" to prootTmp.absolutePath,
            "rootfsPath" to installer.rootfsDir.absolutePath,
            "storagePath" to Environment.getExternalStorageDirectory().absolutePath,
            "deviceStorageGranted" to hasAllFilesAccess().toString(),
            "deviceStorageGuestPath" to DeviceStorageAccess.GUEST_PATH,
        )
    }

    /** Returns ARM32 boot-path checks without starting a guest process. */
    private fun archLaunchDiagnostics(): Map<String, Any?> {
        val abi = currentAbi()
        val installer = abi?.let { ArchInstaller(this, it) }
        val rootfs = installer?.rootfsDir
        val proot = abi?.let { File(filesDir, prootAssetPath(it)) }
        val tmp = abi?.let { File(filesDir, "proot-tmp/$it") }
        val guestEnv = rootfs?.let { File(it, "usr/bin/env") }
        val guestLoader = rootfs?.let { File(it, "usr/lib/ld-linux-armhf.so.3") }
        val guestLoaderViaLib = rootfs?.let { File(it, "lib/ld-linux-armhf.so.3") }
        return mapOf(
            "abi" to abi,
            "arm32" to (abi == "armeabi-v7a"),
            "rootfsPath" to rootfs?.absolutePath,
            "rootfsInstalled" to (installer?.isInstalled() == true),
            "prootPath" to proot?.absolutePath,
            "prootReady" to (proot?.isFile == true && proot.canExecute()),
            "prootTmpPath" to tmp?.absolutePath,
            "prootTmpWritable" to (tmp?.isDirectory == true && tmp.canWrite()),
            "guestEnvPath" to guestEnv?.absolutePath,
            "guestEnvReady" to (guestEnv?.isFile == true && guestEnv.canExecute()),
            "guestLoaderPath" to guestLoader?.absolutePath,
            "guestLoaderReady" to (guestLoader?.isFile == true && guestLoader.canExecute()),
            "guestLoaderViaLibPath" to guestLoaderViaLib?.absolutePath,
            "guestLoaderViaLibReady" to (guestLoaderViaLib?.isFile == true && guestLoaderViaLib.canExecute()),
        )
    }

    private fun deepTranscriptFile(): File = File(filesDir, "terminal-session/deep-transcript.log")

    private fun readDeepSessionTranscript(): String = deepTranscriptFile()
        .takeIf { it.isFile }
        ?.readText()
        .orEmpty()

    private fun previewDeviceFile(guestPath: String?): Map<String, Any> {
        check(hasAllFilesAccess()) {
            localized("امنح إذن ملفات الجهاز أولاً ثم ابدأ جلسة Arch جديدة.", "Grant device-file access first, then start a new Arch session.")
        }
        val requested = guestPath?.trim().orEmpty()
        check(DeviceFilePreviewPolicy.isGuestPath(requested)) {
            localized("لا يمكن معاينة إلا ملف داخل /sdcard.", "Only a file inside /sdcard can be previewed.")
        }
        val kind = checkNotNull(DeviceFilePreviewPolicy.kindFor(requested)) {
            localized("نوع هذا الملف غير مدعوم للمعاينة المحلية.", "This file type is not supported for local preview.")
        }
        val storageRoot = Environment.getExternalStorageDirectory().canonicalFile
        val relativePath = requested.removePrefix(DeviceStorageAccess.GUEST_PATH).trimStart('/')
        val file = File(storageRoot, relativePath).canonicalFile
        check(file.toPath().startsWith(storageRoot.toPath()) && file.isFile && file.canRead()) {
            localized("تعذر فتح الملف المحدد محلياً.", "The selected file cannot be opened locally.")
        }
        val sizeBytes = file.length()
        check(DeviceFilePreviewPolicy.isSizeAllowed(kind, sizeBytes)) {
            val limit = if (kind == DeviceFilePreviewPolicy.KIND_TEXT) {
                DeviceFilePreviewPolicy.MAX_TEXT_BYTES / 1024
            } else {
                DeviceFilePreviewPolicy.MAX_IMAGE_BYTES / (1024 * 1024)
            }
            localized(
                "حجم الملف يتجاوز حد المعاينة المحلي ($limit ${if (kind == DeviceFilePreviewPolicy.KIND_TEXT) "KiB" else "MiB"}).",
                "The file exceeds the local preview limit ($limit ${if (kind == DeviceFilePreviewPolicy.KIND_TEXT) "KiB" else "MiB"}).",
            )
        }
        return when (kind) {
            DeviceFilePreviewPolicy.KIND_TEXT -> {
                val bytes = file.readBytes()
                check(!bytes.contains(0)) {
                    localized("لا يمكن معاينة ملف ثنائي كنص.", "A binary file cannot be previewed as text.")
                }
                mapOf(
                    "kind" to kind,
                    "path" to requested,
                    "sizeBytes" to sizeBytes,
                    "text" to bytes.toString(Charsets.UTF_8),
                )
            }
            DeviceFilePreviewPolicy.KIND_IMAGE -> {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, options)
                check(DeviceFilePreviewPolicy.isPixelCountAllowed(options.outWidth, options.outHeight)) {
                    localized(
                        "أبعاد الصورة غير صالحة أو تتجاوز حد المعاينة المحلي.",
                        "Image dimensions are invalid or exceed the local preview limit.",
                    )
                }
                mapOf(
                    "kind" to kind,
                    "path" to requested,
                    "sizeBytes" to sizeBytes,
                    "width" to options.outWidth,
                    "height" to options.outHeight,
                    "bytes" to file.readBytes(),
                )
            }
            else -> error("Unsupported device-file preview kind")
        }
    }

    private fun appendDeepSessionTranscript(text: String) {
        if (text.isEmpty()) return
        val file = deepTranscriptFile()
        file.parentFile?.mkdirs()
        file.appendText(text)
        val maxBytes = 512 * 1024
        if (file.length() > maxBytes) {
            val bytes = file.readBytes()
            file.writeBytes(bytes.copyOfRange((bytes.size - maxBytes).coerceAtLeast(0), bytes.size))
        }
    }

    private fun shareTerminalLog(text: String) {
        check(text.isNotBlank()) { localized("لا يوجد سجل طرفية لتصديره بعد.", "There is no terminal log to export yet.") }
        startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, text.takeLast(512 * 1024)),
                localized("تصدير سجل Arch Terminal", "Export Arch Terminal log"),
            ),
        )
    }

    private fun openStartupDiagnostics() {
        startActivity(Intent(this, CrashReportActivity::class.java))
    }

    private fun ensureProotBinary(abi: String): File {
        val assetPath = prootAssetPath(abi)
        val target = File(filesDir, assetPath)
        if (target.isFile && target.canExecute()) return target
        target.parentFile?.mkdirs()
        assets.open(assetPath).use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        }
        check(target.setExecutable(true, false)) { "تعذر جعل PRoot قابلاً للتنفيذ للمعمارية $abi" }
        return target
    }

    /**
     * PRoot creates probe and loader-support files before the guest root is
     * active. Android app processes cannot rely on a host-visible `/tmp`, so
     * provide an app-private, writable directory explicitly.
     */
    private fun ensureProotTmpDirectory(abi: String): File {
        val directory = File(filesDir, "proot-tmp/$abi")
        check(directory.exists() || directory.mkdirs()) { "تعذر إنشاء المسار المؤقت لـ PRoot" }
        check(directory.isDirectory && directory.canWrite()) { "مسار PRoot المؤقت غير قابل للكتابة" }
        directory.setReadable(true, false)
        directory.setWritable(true, true)
        directory.setExecutable(true, false)
        return directory.canonicalFile
    }

    private fun currentAbi(): String? = Build.SUPPORTED_ABIS.firstOrNull { it in SUPPORTED_ABIS }

    private fun prootAssetPath(abi: String): String = "bin/$abi/proot"

    private fun assetExists(assetPath: String): Boolean = try {
        assets.open(assetPath).use { }
        true
    } catch (_: Exception) {
        false
    }

    private fun hasAllFilesAccess(): Boolean = DeviceStorageAccess.isGranted(
        sdkInt = Build.VERSION.SDK_INT,
        manageExternalStorageGranted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager(),
        legacyWriteGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED),
    )

    private fun deviceStorageStatus(): Map<String, Any?> {
        val granted = hasAllFilesAccess()
        return mapOf(
            "deviceStorageGranted" to granted,
            "deviceStorageGuestPath" to DeviceStorageAccess.GUEST_PATH,
            "deviceStorageHostPath" to Environment.getExternalStorageDirectory().absolutePath,
            "deviceStorageWillBind" to DeviceStorageAccess.shouldBind(granted),
            "deviceStorageCommand" to "cd ${DeviceStorageAccess.GUEST_PATH}",
        )
    }

    private fun openAllFilesSettings() {
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName"),
                ),
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !hasAllFilesAccess() ->
                requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_STORAGE)
        }
    }

    private fun rootfsStorageSettings(): Map<String, Any?> =
        RootfsStorage(this).status(currentAbi()?.let { RootfsDownloadManager.artifactFor(it) })

    private fun setRootfsStorageMode(mode: String?): Map<String, Any?> {
        val storage = RootfsStorage(this)
        val selected = storage.setLocation(mode ?: RootfsStorage.Location.INTERNAL.wireName)
        return rootfsStorageSettings() + mapOf(
            "rootfsStorageChanged" to true,
            "rootfsStorageMode" to selected.wireName,
            "requiresStoragePermission" to (selected == RootfsStorage.Location.PERSISTENT && !storage.canUsePersistentLocation()),
        )
    }

    private fun openRootfsLocation(): Map<String, Any?> {
        val storage = RootfsStorage(this)
        val details = rootfsStorageSettings()
        if (storage.location() == RootfsStorage.Location.PERSISTENT && !storage.canUsePersistentLocation()) {
            openAllFilesSettings()
            return details + mapOf("openedStoragePermission" to true)
        }
        val directory = if (storage.location() == RootfsStorage.Location.PERSISTENT) storage.publicDirectory() else filesDir
        directory.mkdirs()
        if (storage.location() == RootfsStorage.Location.PERSISTENT) {
            // Do not ACTION_VIEW a raw DocumentsProvider URI: Android rejects it
            // unless the app owns a persisted SAF grant. The system folder picker
            // is the supported route and never exposes that permission error.
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                .addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                .addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            if (intent.resolveActivity(packageManager) != null) startActivity(intent)
        }
        return details + mapOf(
            "openedRootfsLocation" to (storage.location() == RootfsStorage.Location.PERSISTENT),
            "openedFolderPicker" to (storage.location() == RootfsStorage.Location.PERSISTENT),
            "rootfsStoragePath" to directory.absolutePath,
        )
    }

    private fun isIgnoringBatteryOptimization(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || isIgnoringBatteryOptimization()) return
        startActivity(
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName"),
            ),
        )
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun requestAllFilesAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.M..Build.VERSION_CODES.Q && !hasAllFilesAccess()) {
            pendingPermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_STORAGE)
            return
        }
        openAllFilesSettings()
        result.success(runtimeStatus())
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNotificationPermission()) {
            pendingPermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION)
            return
        }
        result.success(runtimeStatus())
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION || requestCode == REQUEST_STORAGE) {
            pendingPermissionResult?.success(runtimeStatus())
            pendingPermissionResult = null
        }
    }
}
