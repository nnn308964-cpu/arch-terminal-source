package com.example.arch_terminal.terminal

/** Adds PRoot-compatible and terminal-color pacman options without duplicating them. */
internal object PacmanConfigPatcher {
    private const val marker = "# Arch Terminal: PRoot does not provide the Landlock sandbox required by pacman."
    private const val colorMarker = "# Arch Terminal: retain ANSI package colors in the terminal."

    fun apply(config: String): String {
        val additions = buildString {
            if (!config.lineSequence().any { it.trim() == "DisableSandbox" }) append("$marker\nDisableSandbox\n")
            if (!config.lineSequence().any { it.trim() == "Color" }) append("$colorMarker\nColor\n")
        }
        if (additions.isEmpty()) return config

        val options = Regex("(?m)^\\[options]\\s*$").find(config)
        return if (options == null) {
            config.trimEnd() + "\n\n[options]\n$additions"
        } else {
            val insertAt = config.indexOf('\n', options.range.last).let { if (it < 0) config.length else it + 1 }
            config.substring(0, insertAt) + additions + config.substring(insertAt)
        }
    }
}
