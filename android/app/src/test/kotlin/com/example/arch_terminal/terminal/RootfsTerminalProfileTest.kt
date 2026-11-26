package com.example.arch_terminal.terminal

import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertTrue
import org.junit.Test

class RootfsTerminalProfileTest {
    @Test
    fun writesInteractiveAnsiPromptAndColorAliases() {
        val root = createTempDirectory("rootfs-profile").toFile()
        try {
            RootfsTerminalProfile.apply(root)

            val profile = File(root, "etc/profile.d/99-arch-terminal-prompt.sh").readText()
            assertTrue(RootfsTerminalProfile.isConfigured(root))
            assertTrue(profile.contains("PROMPT_COMMAND=__arch_terminal_prompt_command"))
            assertTrue(profile.contains("alias ls='ls --color=auto'"))
            assertTrue(profile.contains("alias grep='grep --color=auto'"))
            assertTrue(profile.contains("alias pacman='pacman --color=auto'"))
            assertTrue(profile.contains("alias diff='diff --color=auto'"))
            assertTrue(profile.contains("alias git='git -c color.ui=auto'"))
            assertTrue(profile.contains("CLICOLOR=1"))
            assertTrue(profile.contains("COLORTERM=truecolor"))
            assertTrue(profile.contains("GREP_COLORS="))
            assertTrue(profile.contains("LESS_TERMCAP_md"))
            assertTrue(profile.contains("if [ \"\$(id -u)\" -eq 0 ] && ! command -v sudo"))
            assertTrue(profile.contains("sudo() {"))
            assertTrue(profile.contains("command \"\$@\""))
            assertTrue(profile.contains("__arch_terminal_env_probe()"))
            assertTrue(profile.contains("id -un"))
            assertTrue(profile.contains("df -Pk /"))
            assertTrue(profile.contains("repo_configured="))
            assertTrue(profile.contains("repo_mirror="))
            assertTrue(profile.contains("repo_names="))
            assertTrue(profile.contains("repo_database_count="))
            assertTrue(!profile.contains("pacman -Syy"))
        } finally {
            root.deleteRecursively()
        }
    }
}
