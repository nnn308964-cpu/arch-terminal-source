package com.example.arch_terminal.terminal

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExtractionStallMonitorTest {
    @Test
    fun `reports a stall after the configured timeout`() {
        val signal = CountDownLatch(1)
        val monitor = ExtractionStallMonitor(timeoutMillis = 40L) { signal.countDown() }
        try {
            monitor.start()
            assertTrue(signal.await(1, TimeUnit.SECONDS))
            assertTrue(monitor.isStalled())
        } finally {
            monitor.close()
        }
    }

    @Test
    fun `heartbeat prevents a stall while extraction is progressing`() {
        val stalls = AtomicInteger(0)
        val monitor = ExtractionStallMonitor(timeoutMillis = 120L) { stalls.incrementAndGet() }
        try {
            monitor.start()
            repeat(5) {
                Thread.sleep(25L)
                monitor.heartbeat()
            }
            assertFalse(monitor.isStalled())
            assertTrue(stalls.get() == 0)
        } finally {
            monitor.close()
        }
    }
}
