package com.example.arch_terminal.terminal

import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RootfsNetworkConfigTest {
    @Test
    fun replacesBrokenResolverLinkTargetWithGuestLocalDnsConfiguration() {
        val root = createTempDirectory("rootfs-network").toFile()
        try {
            val etc = File(root, "etc").apply { mkdirs() }
            File(etc, "resolv.conf").writeText("stale resolver")

            RootfsNetworkConfig.apply(root)

            val resolver = File(etc, "resolv.conf")
            assertTrue(resolver.isFile)
            assertTrue(RootfsNetworkConfig.isConfigured(root))
            assertEquals(true, resolver.readText().contains("nameserver 1.1.1.1"))
            assertEquals(true, resolver.readText().contains("nameserver 8.8.8.8"))
            assertTrue(File(etc, "pacman.d/mirrorlist").readText().contains(RootfsNetworkConfig.MIRROR_URL))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun replacesSystemdResolverSymlinkUsedByThePublishedRootfs() {
        val root = createTempDirectory("rootfs-network-link").toFile()
        try {
            val etc = File(root, "etc").apply { mkdirs() }
            val resolver = File(etc, "resolv.conf")
            Files.createSymbolicLink(resolver.toPath(), Path.of("/run/systemd/resolve/resolv.conf"))

            RootfsNetworkConfig.apply(root)

            assertTrue(resolver.isFile)
            assertTrue(RootfsNetworkConfig.isConfigured(root))
        } finally {
            root.deleteRecursively()
        }
    }
}
