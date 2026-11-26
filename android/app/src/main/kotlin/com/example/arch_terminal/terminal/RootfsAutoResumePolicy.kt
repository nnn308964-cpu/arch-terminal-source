package com.example.arch_terminal.terminal

/** Decides whether an unfinished RootFS download may safely resume on app launch. */
object RootfsAutoResumePolicy {
    fun shouldResume(
        wasRunning: Boolean,
        rootfsInstalled: Boolean,
        partialBytes: Long,
    ): Boolean = wasRunning && !rootfsInstalled && partialBytes > 0L
}
