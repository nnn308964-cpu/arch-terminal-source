package com.example.arch_terminal.terminal

/**
 * Describes access to user-owned shared storage. The guest always has an
 * empty /sdcard directory from the RootFS; it is bound to the device only
 * when Android has granted the corresponding storage capability.
 */
object DeviceStorageAccess {
    const val GUEST_PATH = "/sdcard"

    fun isGranted(
        sdkInt: Int,
        manageExternalStorageGranted: Boolean,
        legacyWriteGranted: Boolean,
    ): Boolean = when {
        sdkInt >= 30 -> manageExternalStorageGranted
        sdkInt >= 29 -> false
        sdkInt >= 23 -> legacyWriteGranted
        else -> true
    }

    fun shouldBind(granted: Boolean): Boolean = granted
}
