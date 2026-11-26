package com.example.arch_terminal.terminal

import android.content.Context

/** In-process state that is also mirrored in the foreground-service notification. */
data class SetupProgress(
    val running: Boolean = false,
    val phase: String = "idle",
    val message: String = "لم يبدأ إعداد Arch بعد.",
    val percent: Int? = null,
    val bytesDownloaded: Long = 0,
    val totalBytes: Long = -1,
    val bytesPerSecond: Long = 0,
    val extractedFiles: Int = 0,
    val totalFiles: Int = 0,
    val filesPerSecond: Long = 0,
    val secondsRemaining: Long? = null,
    val archiveSource: String? = null,
    val failureDetail: String? = null,
) {
    fun asMap(): Map<String, Any?> = mapOf(
        "setupRunning" to running,
        "setupPhase" to phase,
        "setupMessage" to message,
        "setupPercent" to percent,
        "setupBytesDownloaded" to bytesDownloaded,
        "setupTotalBytes" to totalBytes,
        "setupBytesPerSecond" to bytesPerSecond,
        "setupExtractedFiles" to extractedFiles,
        "setupTotalFiles" to totalFiles,
        "setupFilesPerSecond" to filesPerSecond,
        "setupSecondsRemaining" to secondsRemaining,
        "setupArchiveSource" to archiveSource,
        "setupFailureDetail" to failureDetail,
    )
}

object ArchSetupState {
    private val lock = Any()
    private var current = SetupProgress()
    private val listeners = mutableSetOf<(SetupProgress) -> Unit>()
    private var restored = false
    private var lastPersistedPhase = ""
    private var lastPersistedAt = 0L

    fun update(context: Context, value: SetupProgress) {
        val callbacks = synchronized(lock) {
            restoreIfNeeded(context)
            current = value
            persistIfNeeded(context, value)
            listeners.toList()
        }
        callbacks.forEach { it(value) }
    }

    fun snapshot(context: Context): SetupProgress = synchronized(lock) {
        restoreIfNeeded(context)
        current
    }

    fun asMap(context: Context): Map<String, Any?> = snapshot(context).asMap()

    fun subscribe(context: Context, listener: (SetupProgress) -> Unit): () -> Unit {
        val value = synchronized(lock) {
            restoreIfNeeded(context)
            listeners.add(listener)
            current
        }
        listener(value)
        return { synchronized(lock) { listeners.remove(listener) } }
    }

    private fun restoreIfNeeded(context: Context) {
        if (restored) return
        restored = true
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(KEY_PRESENT, false)) return
        current = SetupProgress(
            running = preferences.getBoolean(KEY_RUNNING, false),
            phase = preferences.getString(KEY_PHASE, "idle") ?: "idle",
            message = preferences.getString(KEY_MESSAGE, "لم يبدأ إعداد Arch بعد.") ?: "لم يبدأ إعداد Arch بعد.",
            percent = preferences.getInt(KEY_PERCENT, -1).takeIf { it >= 0 },
            bytesDownloaded = preferences.getLong(KEY_BYTES_DOWNLOADED, 0L),
            totalBytes = preferences.getLong(KEY_TOTAL_BYTES, -1L),
            bytesPerSecond = preferences.getLong(KEY_BYTES_PER_SECOND, 0L),
            extractedFiles = preferences.getInt(KEY_EXTRACTED_FILES, 0),
            totalFiles = preferences.getInt(KEY_TOTAL_FILES, 0),
            filesPerSecond = preferences.getLong(KEY_FILES_PER_SECOND, 0L),
            secondsRemaining = preferences.getLong(KEY_SECONDS_REMAINING, -1L).takeIf { it >= 0L },
            archiveSource = preferences.getString(KEY_ARCHIVE_SOURCE, null),
            failureDetail = preferences.getString(KEY_FAILURE_DETAIL, null),
        )
        lastPersistedPhase = current.phase
    }

    private fun persistIfNeeded(context: Context, value: SetupProgress) {
        val now = System.currentTimeMillis()
        val terminalState = value.phase == "complete" || value.phase == "error"
        val phaseChanged = value.phase != lastPersistedPhase
        if (!terminalState && !phaseChanged && now - lastPersistedAt < PERSIST_INTERVAL_MS) return
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_PRESENT, true)
            .putBoolean(KEY_RUNNING, value.running)
            .putString(KEY_PHASE, value.phase)
            .putString(KEY_MESSAGE, value.message)
            .putInt(KEY_PERCENT, value.percent ?: -1)
            .putLong(KEY_BYTES_DOWNLOADED, value.bytesDownloaded)
            .putLong(KEY_TOTAL_BYTES, value.totalBytes)
            .putLong(KEY_BYTES_PER_SECOND, value.bytesPerSecond)
            .putInt(KEY_EXTRACTED_FILES, value.extractedFiles)
            .putInt(KEY_TOTAL_FILES, value.totalFiles)
            .putLong(KEY_FILES_PER_SECOND, value.filesPerSecond)
            .putLong(KEY_SECONDS_REMAINING, value.secondsRemaining ?: -1L)
            .putString(KEY_ARCHIVE_SOURCE, value.archiveSource)
            .putString(KEY_FAILURE_DETAIL, value.failureDetail)
            .apply()
        lastPersistedPhase = value.phase
        lastPersistedAt = now
    }

    private const val PREFERENCES = "arch_setup_progress"
    private const val KEY_PRESENT = "present"
    private const val KEY_RUNNING = "running"
    private const val KEY_PHASE = "phase"
    private const val KEY_MESSAGE = "message"
    private const val KEY_PERCENT = "percent"
    private const val KEY_BYTES_DOWNLOADED = "bytes_downloaded"
    private const val KEY_TOTAL_BYTES = "total_bytes"
    private const val KEY_BYTES_PER_SECOND = "bytes_per_second"
    private const val KEY_EXTRACTED_FILES = "extracted_files"
    private const val KEY_TOTAL_FILES = "total_files"
    private const val KEY_FILES_PER_SECOND = "files_per_second"
    private const val KEY_SECONDS_REMAINING = "seconds_remaining"
    private const val KEY_ARCHIVE_SOURCE = "archive_source"
    private const val KEY_FAILURE_DETAIL = "failure_detail"
    private const val PERSIST_INTERVAL_MS = 4_000L
}
