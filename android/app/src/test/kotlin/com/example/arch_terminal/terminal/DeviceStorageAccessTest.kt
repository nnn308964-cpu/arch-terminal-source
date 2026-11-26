package com.example.arch_terminal.terminal

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceStorageAccessTest {
    @Test
    fun `requires all files grant on Android 11 and later`() {
        assertFalse(DeviceStorageAccess.isGranted(30, false, true))
        assertTrue(DeviceStorageAccess.isGranted(30, true, false))
    }

    @Test
    fun `supports legacy storage permission before scoped storage`() {
        assertFalse(DeviceStorageAccess.isGranted(28, false, false))
        assertTrue(DeviceStorageAccess.isGranted(28, false, true))
        assertTrue(DeviceStorageAccess.isGranted(22, false, false))
    }

    @Test
    fun `does not claim broad device file binding on Android 10 without a folder grant`() {
        assertFalse(DeviceStorageAccess.isGranted(29, false, true))
    }

    @Test
    fun `bind happens only when access is granted`() {
        assertFalse(DeviceStorageAccess.shouldBind(false))
        assertTrue(DeviceStorageAccess.shouldBind(true))
    }
}
