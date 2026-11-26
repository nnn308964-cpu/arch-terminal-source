package com.example.arch_terminal

import android.content.Context
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * App-private startup evidence with no Flutter, dependency injection, or
 * third-party dependency. A prior run is preserved for inspection after the
 * next launch, including when the failure happened before Flutter rendered.
 */
internal object StartupDiagnostics {
    private const val CURRENT_FILE = "startup_diagnostics.log"
    private const val PREVIOUS_FILE = "startup_diagnostics_previous.log"
    private const val MAX_BYTES = 256 * 1024
    private val lock = Any()
    private var directory: File? = null

    fun initialize(context: Context) = initializeIn(context.filesDir)

    internal fun initializeIn(filesDirectory: File) {
        synchronized(lock) {
            filesDirectory.mkdirs()
            val current = File(filesDirectory, CURRENT_FILE)
            val previous = File(filesDirectory, PREVIOUS_FILE)
            if (current.isFile) {
                previous.delete()
                current.renameTo(previous)
            }
            if (!current.exists()) current.createNewFile()
            directory = filesDirectory
            writeLocked("STARTUP_SESSION_BEGIN")
        }
    }

    fun begin(step: String) = write("${step}_BEGIN")

    fun ok(step: String) = write("${step}_OK")

    fun failed(step: String, error: Throwable) {
        val trace = StringWriter().also { writer ->
            error.printStackTrace(PrintWriter(writer))
        }.toString()
        write("${step}_FAILED")
        write("exception_class: ${error.javaClass.name}")
        write("exception_message: ${error.message.orEmpty().take(4096)}")
        write("stack_trace:\n${trace.take(24 * 1024)}")
    }

    fun report(context: Context): String = reportIn(context.filesDir)

    internal fun reportIn(filesDirectory: File): String {
        synchronized(lock) {
            val root = directory ?: filesDirectory
            return buildString {
                append("== Current startup log ==\n")
                append(read(File(root, CURRENT_FILE)))
                append("\n\n== Previous startup log ==\n")
                append(read(File(root, PREVIOUS_FILE)))
            }.takeLast(MAX_BYTES)
        }
    }

    private fun read(file: File): String = if (file.isFile) file.readText() else "No log recorded."

    private fun write(text: String) {
        synchronized(lock) { writeLocked(text) }
    }

    private fun writeLocked(text: String) {
        val root = directory ?: return
        try {
            val current = File(root, CURRENT_FILE)
            current.parentFile?.mkdirs()
            current.appendText("[${System.currentTimeMillis()}] $text\n")
            if (current.length() > MAX_BYTES) {
                val bytes = current.readBytes()
                current.writeBytes(bytes.copyOfRange((bytes.size - MAX_BYTES).coerceAtLeast(0), bytes.size))
            }
        } catch (_: Throwable) {
            // Diagnostics are intentionally the end of the dependency chain.
        }
    }
}
