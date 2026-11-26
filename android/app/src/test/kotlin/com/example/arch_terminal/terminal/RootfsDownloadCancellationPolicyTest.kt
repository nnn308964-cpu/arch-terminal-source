package com.example.arch_terminal.terminal

import android.content.ContextWrapper
import java.io.ByteArrayInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import org.junit.Assert.assertThrows
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootfsDownloadCancellationPolicyTest {
    @Test
    fun `keeps download running without user request or worker interruption`() {
        assertFalse(RootfsDownloadCancellationPolicy.shouldCancel(userRequested = false, workerInterrupted = false))
    }

    @Test
    fun `stops download when user requests cancellation so partial bytes are preserved by caller`() {
        assertTrue(RootfsDownloadCancellationPolicy.shouldCancel(userRequested = true, workerInterrupted = false))
    }

    @Test
    fun `stops download when the service worker is interrupted`() {
        assertTrue(RootfsDownloadCancellationPolicy.shouldCancel(userRequested = false, workerInterrupted = true))
    }

    @Test
    fun `download manager exits on a user cancellation before it opens storage or the network`() {
        val manager = RootfsDownloadManager(
            context = object : ContextWrapper(null) {},
            isCancellationRequested = { true },
        )

        assertThrows(RootfsDownloadCancelledException::class.java) {
            manager.downloadAndVerify("arm64-v8a")
        }
    }

    @Test
    fun `cancellation during a response keeps the already written partial archive bytes`() {
        val partial = Files.createTempFile("rootfs-cancel-", ".part").toFile()
        var cancelled = false
        val source = ByteArray(128 * 1024) { 7 }

        try {
            assertThrows(RootfsDownloadCancelledException::class.java) {
                ByteArrayInputStream(source).use { input ->
                    FileOutputStream(partial).use { output ->
                        RootfsDownloadStreamCopier.copy(
                            input = input,
                            output = output,
                            checkCancellation = {
                                if (cancelled) throw RootfsDownloadCancelledException()
                            },
                            onBytesWritten = { cancelled = true },
                        )
                    }
                }
            }
            assertTrue(partial.length() in 1 until source.size.toLong())
        } finally {
            partial.delete()
        }
    }
}
