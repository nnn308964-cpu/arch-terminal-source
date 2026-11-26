package com.example.arch_terminal.terminal

import java.io.File

/** Supplies a guest-local resolver because the ARM rootfs links resolv.conf to systemd's absent /run tree. */
internal object RootfsNetworkConfig {
    const val MIRROR_URL = "http://mirror.archlinuxarm.org/${'$'}arch/${'$'}repo"
    private const val CONTENT = """# Managed by Arch Terminal for PRoot networking.
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:2 attempts:3
"""
    private const val MIRRORLIST = """# Managed by Arch Terminal. Official Arch Linux ARM GeoIP mirror.
Server = http://mirror.archlinuxarm.org/${'$'}arch/${'$'}repo
"""

    fun apply(root: File) {
        val etc = File(root, "etc")
        check(etc.exists() || etc.mkdirs()) { "Unable to create guest /etc" }
        val resolvConf = File(etc, "resolv.conf")
        // The published RootFS points this at /run/systemd/resolve/resolv.conf,
        // but PRoot does not run systemd and therefore exposes a broken link.
        if (resolvConf.exists() || resolvConf.delete()) {
            check(resolvConf.delete() || !resolvConf.exists()) { "Unable to replace guest /etc/resolv.conf" }
        }
        resolvConf.writeText(CONTENT)
        val mirrorlist = File(etc, "pacman.d/mirrorlist")
        mirrorlist.parentFile?.mkdirs()
        mirrorlist.writeText(MIRRORLIST)
    }

    fun isConfigured(root: File): Boolean = File(root, "etc/resolv.conf")
        .takeIf { it.isFile }
        ?.readText()
        ?.let { resolver ->
            resolver.contains("nameserver 1.1.1.1") &&
                resolver.contains("nameserver 8.8.8.8") &&
                File(root, "etc/pacman.d/mirrorlist").readText().contains(MIRROR_URL)
        }
        ?: false
}
