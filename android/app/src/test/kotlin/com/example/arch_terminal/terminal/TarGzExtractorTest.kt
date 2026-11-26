package com.example.arch_terminal.terminal

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.FilterOutputStream
import java.io.IOException
import java.nio.file.Files
import java.util.zip.GZIPOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class TarGzExtractorTest {
    @Test
    fun `counts files and reports compressed archive scan progress`() {
        val tar = ByteArrayOutputStream().apply {
            writeTarFile("etc/example.conf", "hello".toByteArray())
            write(ByteArray(1024))
        }.toByteArray()
        val compressed = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write(tar) }
        }.toByteArray()
        val updates = mutableListOf<TarGzExtractor.CountProgress>()

        val scan = TarGzExtractor.scan(
            ByteArrayInputStream(compressed),
            totalCompressedBytes = compressed.size.toLong(),
            onProgress = updates::add,
        )

        assertEquals(1, scan.fileCount)
        assertEquals(5, scan.materializedBytes)
        assertTrue(updates.isNotEmpty())
        assertEquals(compressed.size.toLong(), updates.last().scannedCompressedBytes)
        assertEquals(100, updates.last().percent)
    }

    @Test
    fun `scan ignores pax metadata when counting rootfs files and payload bytes`() {
        val tar = ByteArrayOutputStream().apply {
            writeTarEntry("PaxHeader", "36 SCHILY.xattr.security.SMACK64=value\n".toByteArray(), 'g')
            writeTarFile("etc/example.conf", "hello".toByteArray())
            write(ByteArray(1024))
        }.toByteArray()
        val compressed = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write(tar) }
        }.toByteArray()

        val scan = TarGzExtractor.scan(ByteArrayInputStream(compressed))

        assertEquals(1, scan.fileCount)
        assertEquals(5, scan.materializedBytes)
    }

    @Test
    fun `resumes extraction from the next completed tar entry`() {
        val tar = ByteArrayOutputStream().apply {
            writeTarFile("first.txt", "first".toByteArray())
            writeTarFile("second.txt", "second".toByteArray())
            write(ByteArray(1024))
        }.toByteArray()
        val compressed = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write(tar) }
        }.toByteArray()
        val destination = Files.createTempDirectory("arch-terminal-resume-").toFile()

        try {
            runCatching {
                TarGzExtractor.extract(
                    ByteArrayInputStream(compressed),
                    destination,
                    totalFiles = 2,
                    onEntryCompleted = { completedEntries, _ ->
                        if (completedEntries == 1L) error("simulated process stop")
                    },
                )
            }.getOrThrow()
        } catch (_: IllegalStateException) {
            // The first file is durable before the checkpoint callback reports the stop.
        }

        try {
            TarGzExtractor.extract(
                ByteArrayInputStream(compressed),
                destination,
                totalFiles = 2,
                startEntryIndex = 1L,
                initialExtractedFiles = 1,
            )
            assertEquals("first", destination.resolve("first.txt").readText())
            assertEquals("second", destination.resolve("second.txt").readText())
        } finally {
            destination.deleteRecursively()
        }
    }

    @Test
    fun `rejects a truncated archive instead of silently completing extraction`() {
        val tar = ByteArrayOutputStream().apply {
            writeTarFile("etc/incomplete.conf", "payload".toByteArray())
        }.toByteArray()
        val truncated = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write(tar) }
        }.toByteArray()
        val destination = Files.createTempDirectory("arch-terminal-truncated-").toFile()

        try {
            assertThrows(Exception::class.java) {
                TarGzExtractor.extract(ByteArrayInputStream(truncated), destination, totalFiles = 1)
            }
        } finally {
            destination.deleteRecursively()
        }
    }

    @Test
    fun `propagates a destination write failure before an entry checkpoint is marked complete`() {
        val tar = ByteArrayOutputStream().apply {
            writeTarFile("etc/write-failure.conf", "payload".toByteArray())
            write(ByteArray(1024))
        }.toByteArray()
        val compressed = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write(tar) }
        }.toByteArray()
        val destination = Files.createTempDirectory("arch-terminal-write-failure-").toFile()
        var completedEntries = 0

        try {
            assertThrows(IOException::class.java) {
                TarGzExtractor.extract(
                    source = ByteArrayInputStream(compressed),
                    destination = destination,
                    totalFiles = 1,
                    onEntryCompleted = { _, _ -> completedEntries++ },
                    outputFactory = { target -> failingOutput(target) },
                )
            }
            assertEquals(0, completedEntries)
            assertTrue(destination.resolve("etc/write-failure.conf").isFile)
        } finally {
            destination.deleteRecursively()
        }
    }

    @Test
    fun `rejects unsafe extraction paths`() {
        val tar = ByteArrayOutputStream().apply {
            writeTarFile("../outside.txt", "blocked".toByteArray())
            write(ByteArray(1024))
        }.toByteArray()
        val compressed = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write(tar) }
        }.toByteArray()
        val destination = Files.createTempDirectory("arch-terminal-unsafe-").toFile()

        try {
            assertThrows(IllegalArgumentException::class.java) {
                TarGzExtractor.extract(ByteArrayInputStream(compressed), destination, totalFiles = 1)
            }
        } finally {
            destination.deleteRecursively()
        }
    }

    @Test
    fun `reports byte heartbeat while copying a large rootfs file`() {
        val content = ByteArray(2 * 1024 * 1024) { 7 }
        val tar = ByteArrayOutputStream().apply {
            writeTarFile("usr/lib/large-file", content)
            write(ByteArray(1024))
        }.toByteArray()
        val compressed = ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write(tar) }
        }.toByteArray()
        val destination = Files.createTempDirectory("arch-terminal-extract-").toFile()
        val updates = mutableListOf<TarGzExtractor.Progress>()

        try {
            TarGzExtractor.extract(
                ByteArrayInputStream(compressed),
                destination,
                totalFiles = 1,
                onProgress = updates::add,
            )

            val fileHeartbeat = updates.last { it.currentEntry == "usr/lib/large-file" }
            assertTrue(fileHeartbeat.currentEntryBytes >= 1L * 1024L * 1024L)
            assertEquals(content.size.toLong(), fileHeartbeat.currentEntryBytes)
        } finally {
            destination.deleteRecursively()
        }
    }

    private fun ByteArrayOutputStream.writeTarFile(name: String, content: ByteArray) {
        writeTarEntry(name, content, '0')
    }

    private fun ByteArrayOutputStream.writeTarEntry(name: String, content: ByteArray, type: Char) {
        val header = ByteArray(512)
        name.toByteArray().copyInto(header, destinationOffset = 0)
        "0000644\u0000".toByteArray().copyInto(header, destinationOffset = 100)
        "%011o\u0000".format(content.size).toByteArray().copyInto(header, destinationOffset = 124)
        header[156] = type.code.toByte()
        write(header)
        write(content)
        write(ByteArray((512 - content.size % 512) % 512))
    }

    private fun failingOutput(target: File) = object : FilterOutputStream(FileOutputStream(target)) {
        override fun write(buffer: ByteArray, offset: Int, length: Int) {
            throw IOException("simulated storage write failure")
        }

        override fun write(value: Int) {
            throw IOException("simulated storage write failure")
        }
    }
}
