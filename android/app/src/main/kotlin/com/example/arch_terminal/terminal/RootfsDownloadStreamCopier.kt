package com.example.arch_terminal.terminal

import java.io.InputStream
import java.io.OutputStream

/** Copies a network response to a partial archive while checking cancellation before each read. */
internal object RootfsDownloadStreamCopier {
    fun copy(
        input: InputStream,
        output: OutputStream,
        checkCancellation: () -> Unit,
        onBytesWritten: (Int) -> Unit = {},
    ) {
        val buffer = ByteArray(64 * 1024)
        while (true) {
            checkCancellation()
            val count = input.read(buffer)
            if (count < 0) return
            output.write(buffer, 0, count)
            onBytesWritten(count)
        }
    }
}
