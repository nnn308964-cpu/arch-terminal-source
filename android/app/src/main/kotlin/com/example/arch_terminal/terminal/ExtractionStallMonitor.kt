package com.example.arch_terminal.terminal

import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Detects an extraction that stops producing file/byte progress. */
class ExtractionStallMonitor(
    private val timeoutMillis: Long = 120_000L,
    private val onStall: () -> Unit = {},
) : AutoCloseable {
    private val lastHeartbeat = AtomicLong(System.nanoTime())
    private val stalled = AtomicBoolean(false)
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private var task: ScheduledFuture<*>? = null

    fun start() {
        task = scheduler.scheduleAtFixedRate({
            if (!stalled.get() && elapsedMillis() >= timeoutMillis && stalled.compareAndSet(false, true)) {
                onStall()
            }
        }, timeoutMillis, minOf(timeoutMillis, 5_000L), TimeUnit.MILLISECONDS)
    }

    fun heartbeat() {
        if (!stalled.get()) lastHeartbeat.set(System.nanoTime())
    }

    fun isStalled(): Boolean = stalled.get()

    private fun elapsedMillis(): Long = (System.nanoTime() - lastHeartbeat.get()) / 1_000_000L

    override fun close() {
        task?.cancel(true)
        scheduler.shutdownNow()
    }
}
