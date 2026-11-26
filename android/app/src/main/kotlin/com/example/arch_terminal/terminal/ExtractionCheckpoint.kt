package com.example.arch_terminal.terminal

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Small atomic checkpoint for resuming a deterministic tar extraction. */
data class ExtractionCheckpoint(
    val archiveLength: Long,
    val totalFiles: Int,
    val completedEntries: Long,
    val completedFiles: Int,
) {
    fun isCompatible(length: Long, files: Int): Boolean = archiveLength == length && totalFiles == files

    fun writeAtomically(file: File) {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, ".${file.name}.tmp")
        temporary.writeText("$archiveLength\n$totalFiles\n$completedEntries\n$completedFiles\n")
        Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    companion object {
        fun read(file: File): ExtractionCheckpoint? {
            if (!file.isFile) return null
            return runCatching {
                val values = file.readLines().map(String::trim)
                if (values.size < 4) return@runCatching null
                ExtractionCheckpoint(values[0].toLong(), values[1].toInt(), values[2].toLong(), values[3].toInt())
            }.getOrNull()
        }
    }
}
