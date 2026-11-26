package com.example.arch_terminal.terminal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootfsSpaceEstimatorTest {
    @Test
    fun `requires only additional staging payload and metadata not an already saved archive`() {
        val payload = 1_788_038_132L
        val required = RootfsSpaceEstimator.requiredAdditionalBytes(payload)

        assertEquals(payload + RootfsSpaceEstimator.METADATA_MARGIN_BYTES, required)
        assertTrue(RootfsSpaceEstimator.hasCapacity(required, payload))
        assertFalse(RootfsSpaceEstimator.hasCapacity(required - 1, payload))
    }
}
