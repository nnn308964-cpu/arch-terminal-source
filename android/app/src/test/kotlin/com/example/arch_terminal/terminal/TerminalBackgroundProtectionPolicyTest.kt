package com.example.arch_terminal.terminal

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TerminalBackgroundProtectionPolicyTest {
    @Test
    fun keepsCpuWakeLockOnlyForAnActiveProtectedSession() {
        assertTrue(
            TerminalBackgroundProtectionPolicy.shouldHoldPartialWakeLock(
                sessionActive = true,
                backgroundProtectionEnabled = true,
                oneShotDeepSessionRequested = false,
            ),
        )
        assertTrue(
            TerminalBackgroundProtectionPolicy.shouldHoldPartialWakeLock(
                sessionActive = true,
                backgroundProtectionEnabled = false,
                oneShotDeepSessionRequested = true,
            ),
        )
        assertFalse(
            TerminalBackgroundProtectionPolicy.shouldHoldPartialWakeLock(
                sessionActive = false,
                backgroundProtectionEnabled = true,
                oneShotDeepSessionRequested = true,
            ),
        )
        assertFalse(
            TerminalBackgroundProtectionPolicy.shouldHoldPartialWakeLock(
                sessionActive = true,
                backgroundProtectionEnabled = false,
                oneShotDeepSessionRequested = false,
            ),
        )
    }
}
