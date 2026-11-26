package com.example.arch_terminal.terminal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PacmanConfigPatcherTest {
    @Test
    fun addsDisableSandboxAndColorInsideOptions() {
        val patched = PacmanConfigPatcher.apply("[options]\nHoldPkg = pacman\n[core]\nInclude = /etc/pacman.d/mirrorlist\n")

        assertTrue(patched.contains("[options]\n# Arch Terminal: PRoot does not provide the Landlock sandbox required by pacman.\nDisableSandbox\n"))
        assertTrue(patched.contains("# Arch Terminal: retain ANSI package colors in the terminal.\nColor\nHoldPkg"))
    }

    @Test
    fun keepsExistingPacmanOptionsUnchanged() {
        val config = "[options]\nDisableSandbox\nColor\n[core]\n"

        assertEquals(config, PacmanConfigPatcher.apply(config))
    }
}
