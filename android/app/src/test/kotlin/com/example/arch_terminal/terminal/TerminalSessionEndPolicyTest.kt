package com.example.arch_terminal.terminal

import org.junit.Assert.assertTrue
import org.junit.Test

class TerminalSessionEndPolicyTest {
    @Test
    fun notificationEndRemovesBackgroundStateAndSchedulesOneDeepRestart() {
        val plan = TerminalSessionEndPolicy.fromNotification()

        assertTrue(plan.removeForegroundNotification)
        assertTrue(plan.terminateHostProcess)
        assertTrue(plan.restartDeepOnNextLaunch)
    }
}
