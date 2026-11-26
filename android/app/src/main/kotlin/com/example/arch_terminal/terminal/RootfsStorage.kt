package com.example.arch_terminal.terminal

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import java.io.File
import java.io.IOException

/**
 * Controls where the verified RootFS archive is retained. The public location
 * survives application uninstall; the installed filesystem itself remains
 * private and is rebuilt from that archive after a reinstall.
 */
class RootfsStorage(private val context: Context) {
    private fun text(arabic: String, english: String) = context.runtimeText(arabic, english)

    enum class Location(val wireName: String) {
        INTERNAL("internal"),
        PERSISTENT("persistent"),
    }

    companion object {
        private const val PREFS = "arch_terminal_storage"
        private const val KEY_LOCATION = "rootfs_location"
        private const val PUBLIC_FOLDER = "ArchTerminal/rootfs"
    }

    private val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun location(): Location = when (preferences.getString(KEY_LOCATION, Location.INTERNAL.wireName)) {
        Location.PERSISTENT.wireName -> Location.PERSISTENT
        else -> Location.INTERNAL
    }

    fun hasExplicitLocation(): Boolean = preferences.contains(KEY_LOCATION)

    fun setLocation(value: String): Location {
        val selected = if (value == Location.PERSISTENT.wireName) Location.PERSISTENT else Location.INTERNAL
        preferences.edit().putString(KEY_LOCATION, selected.wireName).apply()
        return selected
    }

    fun archiveDirectory(): File {
        if (location() == Location.PERSISTENT) {
            if (!canUsePersistentLocation()) {
                throw IOException(text(
                    "يلزم منح إذن مساحة التخزين قبل استخدام الحفظ المستمر لملف Arch Linux.",
                    "Storage access must be granted before using persistent storage for the Arch Linux file.",
                ))
            }
            return publicDirectory().also { directory ->
                check(directory.exists() || directory.mkdirs()) {
                    text("تعذر إنشاء مجلد RootFS الدائم", "Unable to create the persistent RootFS folder")
                }
            }
        }
        return File(context.filesDir, "downloads/rootfs").also { directory ->
            check(directory.exists() || directory.mkdirs()) {
                text("تعذر إنشاء مجلد التنزيل المحلي", "Unable to create the local download folder")
            }
        }
    }

    fun publicDirectory(): File = File(Environment.getExternalStorageDirectory(), PUBLIC_FOLDER)

    fun canUsePersistentLocation(): Boolean = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> Environment.isExternalStorageManager()
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> false
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        else -> true
    }

    fun retentionEnabled(): Boolean = location() == Location.PERSISTENT

    fun status(artifact: RootfsDownloadManager.Artifact?): Map<String, Any?> {
        val directory = if (location() == Location.PERSISTENT) publicDirectory() else File(context.filesDir, "downloads/rootfs")
        val archive = artifact?.let { File(directory, it.fileName) }
        return mapOf(
            "rootfsStorageMode" to location().wireName,
            "rootfsStoragePersistent" to retentionEnabled(),
            "rootfsStorageReady" to (location() == Location.INTERNAL || canUsePersistentLocation()),
            "rootfsStoragePath" to directory.absolutePath,
            "rootfsArchivePath" to archive?.absolutePath,
            "rootfsArchivePresent" to (archive?.isFile == true),
            "publicStorageGranted" to canUsePersistentLocation(),
            "rootfsPublicArchivePresent" to (artifact?.let { File(publicDirectory(), it.fileName).isFile } == true),
            "rootfsStorageCommand" to "cd '${directory.absolutePath}'",
        )
    }
}
