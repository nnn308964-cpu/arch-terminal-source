package com.example.arch_terminal.terminal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceFilePreviewPolicyTest {
    @Test
    fun `accepts only clean paths below guest sdcard`() {
        assertTrue(DeviceFilePreviewPolicy.isGuestPath("/sdcard/Download/readme.txt"))
        assertFalse(DeviceFilePreviewPolicy.isGuestPath("/sdcard/../data/private.txt"))
        assertFalse(DeviceFilePreviewPolicy.isGuestPath("/storage/emulated/0/readme.txt"))
    }

    @Test
    fun `classifies supported preview extensions without content sniffing`() {
        assertEquals(DeviceFilePreviewPolicy.KIND_TEXT, DeviceFilePreviewPolicy.kindFor("/sdcard/note.MD"))
        assertEquals(DeviceFilePreviewPolicy.KIND_IMAGE, DeviceFilePreviewPolicy.kindFor("/sdcard/photo.webp"))
        assertNull(DeviceFilePreviewPolicy.kindFor("/sdcard/archive.zip"))
    }

    @Test
    fun `enforces conservative byte and pixel limits`() {
        assertTrue(DeviceFilePreviewPolicy.isSizeAllowed(DeviceFilePreviewPolicy.KIND_TEXT, 1024))
        assertFalse(DeviceFilePreviewPolicy.isSizeAllowed(DeviceFilePreviewPolicy.KIND_TEXT, DeviceFilePreviewPolicy.MAX_TEXT_BYTES + 1))
        assertTrue(DeviceFilePreviewPolicy.isSizeAllowed(DeviceFilePreviewPolicy.KIND_IMAGE, 1024))
        assertFalse(DeviceFilePreviewPolicy.isSizeAllowed(DeviceFilePreviewPolicy.KIND_IMAGE, DeviceFilePreviewPolicy.MAX_IMAGE_BYTES + 1))
        assertTrue(DeviceFilePreviewPolicy.isPixelCountAllowed(2000, 2000))
        assertFalse(DeviceFilePreviewPolicy.isPixelCountAllowed(2001, 2000))
    }
}
