package com.example.arch_terminal.terminal

import android.content.Context
import android.content.ContextWrapper
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.util.zip.GZIPOutputStream
import org.junit.Assert.assertTrue
import org.junit.Test

class ArchInstallerTest {
    @Test
    fun `extracts a verified archive into an atomically ready arm64 rootfs`() {
        val filesDir = Files.createTempDirectory("arch-installer-success-").toFile()
        val archive = File(filesDir, "rootfs.tar.gz").apply { writeBytes(singleFileArchive()) }
        val context = object : ContextWrapper(null) {
            override fun getFilesDir(): File = filesDir
        }
        val extractedFiles = mutableListOf<Int>()
        val installer = ArchInstaller(
            context = context,
            abi = "arm64-v8a",
            usableSpaceProvider = { Long.MAX_VALUE },
            textResolver = { _, english -> english },
        )

        try {
            val result = installer.installIfNeeded(
                archive,
                onExtractStart = { total -> extractedFiles += total },
                onExtractProgress = { progress -> extractedFiles += progress.extractedFiles },
            )

            assertTrue(!result.alreadyInstalled)
            assertTrue(File(result.rootfsPath, "etc/example.conf").readText() == "hello")
            assertTrue(File(result.rootfsPath, ".arch_terminal_ready").isFile)
            assertTrue(File(result.rootfsPath, "etc/profile.d/99-arch-terminal-prompt.sh").isFile)
            assertTrue(File(filesDir, "arch.arm64-v8a.installing").exists().not())
            assertTrue(File(filesDir, "arch.arm64-v8a.extracting.checkpoint").exists().not())
            assertTrue(extractedFiles.any { it >= 1 })
        } finally {
            filesDir.deleteRecursively()
        }
    }

    @Test
    fun `reports insufficient internal storage before extraction can write a partial rootfs`() {
        val filesDir = Files.createTempDirectory("arch-installer-space-").toFile()
        val archive = File(filesDir, "rootfs.tar.gz").apply { writeBytes(singleFileArchive()) }
        val context = object : ContextWrapper(null) {
            override fun getFilesDir(): File = filesDir
        }
        val installer = ArchInstaller(
            context = context,
            abi = "arm64-v8a",
            usableSpaceProvider = { 0L },
            textResolver = { _, english -> english },
        )

        try {
            val failure = runCatching { installer.installIfNeeded(archive) }.exceptionOrNull()
            assertTrue(failure is java.io.IOException)
            assertTrue(failure?.message.orEmpty().contains("not enough internal space"))
            assertTrue(!File(filesDir, "arch.arm64-v8a/.arch_terminal_ready").exists())
        } finally {
            filesDir.deleteRecursively()
        }
    }

    private fun singleFileArchive(): ByteArray {
        val tar = ByteArrayOutputStream().apply {
            val header = ByteArray(512)
            "etc/example.conf".toByteArray().copyInto(header)
            "0000644\u0000".toByteArray().copyInto(header, destinationOffset = 100)
            "%011o\u0000".format(5).toByteArray().copyInto(header, destinationOffset = 124)
            header[156] = '0'.code.toByte()
            write(header)
            write("hello".toByteArray())
            write(ByteArray(507))
            write(ByteArray(1024))
        }.toByteArray()
        return ByteArrayOutputStream().apply {
            GZIPOutputStream(this).use { it.write(tar) }
        }.toByteArray()
    }
}
