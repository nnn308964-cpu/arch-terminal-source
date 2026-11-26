package com.example.arch_terminal.terminal

/** Describes the immediate behavior of the notification's explicit end action. */
internal object TerminalSessionEndPolicy {
    data class Plan(
        val removeForegroundNotification: Boolean,
        val terminateHostProcess: Boolean,
        val restartDeepOnNextLaunch: Boolean,
    )

    fun fromNotification(): Plan = Plan(
        removeForegroundNotification = true,
        terminateHostProcess = true,
        restartDeepOnNextLaunch = true,
    )
}
