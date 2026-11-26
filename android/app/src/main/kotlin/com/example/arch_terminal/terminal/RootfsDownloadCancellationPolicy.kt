package com.example.arch_terminal.terminal

/** Keeps download-stop decisions deterministic and independently testable. */
object RootfsDownloadCancellationPolicy {
    fun shouldCancel(userRequested: Boolean, workerInterrupted: Boolean): Boolean =
        userRequested || workerInterrupted
}
