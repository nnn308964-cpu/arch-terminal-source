package com.example.arch_terminal.terminal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootfsDownloadResumePolicyTest {
    @Test
    fun `appends partial archive only when the server accepts a byte range`() {
        val plan = RootfsDownloadResumePolicy.responsePlan(
            existingPartialBytes = 12_000L,
            responseCode = 206,
            responseContentLength = 8_000L,
            contentRange = "bytes 12000-19999/20000",
        )

        assertTrue(plan.append)
        assertEquals(12_000L, plan.initialBytes)
        assertEquals(20_000L, plan.totalBytes)
    }

    @Test
    fun `restarts safely when a server ignores a range request`() {
        val plan = RootfsDownloadResumePolicy.responsePlan(
            existingPartialBytes = 12_000L,
            responseCode = 200,
            responseContentLength = 20_000L,
            contentRange = null,
        )

        assertFalse(plan.append)
        assertEquals(0L, plan.initialBytes)
        assertEquals(20_000L, plan.totalBytes)
    }

    @Test
    fun `uses a fallback total when the range response omits content range`() {
        val plan = RootfsDownloadResumePolicy.responsePlan(
            existingPartialBytes = 12_000L,
            responseCode = 206,
            responseContentLength = 8_000L,
            contentRange = null,
        )

        assertTrue(plan.append)
        assertEquals(20_000L, plan.totalBytes)
    }
}
