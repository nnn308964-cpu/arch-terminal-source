package com.example.arch_terminal.terminal

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootfsAutoResumePolicyTest {
    @Test
    fun `resumes a running setup with saved partial bytes after app relaunch`() {
        assertTrue(
            RootfsAutoResumePolicy.shouldResume(
                wasRunning = true,
                rootfsInstalled = false,
                partialBytes = 4_096L,
            ),
        )
    }

    @Test
    fun `does not restart a completed setup or a setup without resumable bytes`() {
        assertFalse(RootfsAutoResumePolicy.shouldResume(true, true, 4_096L))
        assertFalse(RootfsAutoResumePolicy.shouldResume(true, false, 0L))
        assertFalse(RootfsAutoResumePolicy.shouldResume(false, false, 4_096L))
    }
}
