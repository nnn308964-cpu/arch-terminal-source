package com.example.arch_terminal.terminal

/**
 * Keeps the user-visible background-protection decision separate from a PTY's
 * lifecycle. Android may still reclaim the host process, so this policy never
 * claims that it can restore a killed guest process.
 */
object TerminalBackgroundProtectionPolicy {
    fun shouldHoldPartialWakeLock(
        sessionActive: Boolean,
        backgroundProtectionEnabled: Boolean,
        oneShotDeepSessionRequested: Boolean,
    ): Boolean = sessionActive && (backgroundProtectionEnabled || oneShotDeepSessionRequested)
}
