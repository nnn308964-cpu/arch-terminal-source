package com.example.arch_terminal.terminal

import android.system.Os
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.GZIPInputStream
import kotlin.math.ceil

/** Extracts the plain GNU tar.gz rootfs format used by the bundled Arch image. */
object TarGzExtractor {
    private const val BLOCK_SIZE = 512

    data class Progress(
        val extractedFiles: Int,
        val totalFiles: Int,
        val filesPerSecond: Long,
        val secondsRemaining: Long?,
        val percent: Int?,
        val currentEntry: String? = null,
        val currentEntryBytes: Long = 0L,
        val currentEntrySize: Long = 0L,
    )

    /** Progress emitted while the compressed archive is scanned to count files. */
    data class CountProgress(
        val scannedCompressedBytes: Long,
        val totalCompressedBytes: Long,
        val percent: Int?,
    )

    /** Archive information collected before extraction without materializing files. */
    data class ScanResult(
        val fileCount: Int,
        val materializedBytes: Long,
    )

    /** Counts regular and hard-linked files before extraction begins. */
    fun countFiles(
        source: InputStream,
        totalCompressedBytes: Long = -1,
        onProgress: (CountProgress) -> Unit = {},
    ): Int = scan(source, totalCompressedBytes, onProgress).fileCount

    /** Counts files and their eventual payload size in the uncompressed tar stream. */
    fun scan(
        source: InputStream,
        totalCompressedBytes: Long = -1,
        onProgress: (CountProgress) -> Unit = {},
    ): ScanResult {
        val counted = CountingInputStream(source, totalCompressedBytes, onProgress)
        return GZIPInputStream(BufferedInputStream(counted, 64 * 1024), 64 * 1024).use(::scanTarEntries)
            .also { counted.publish(force = true) }
    }

    fun extract(
        source: InputStream,
        destination: File,
        totalFiles: Int = 0,
        startEntryIndex: Long = 0L,
        initialExtractedFiles: Int = 0,
        onEntryCompleted: (Long, Int) -> Unit = { _, _ -> },
        onProgress: (Progress) -> Unit = {},
        outputFactory: (File) -> OutputStream = { target -> FileOutputStream(target) },
    ) {
        destination.mkdirs()
        GZIPInputStream(BufferedInputStream(source, 64 * 1024), 64 * 1024).use { gzip ->
            extractTar(gzip, destination, totalFiles, startEntryIndex, initialExtractedFiles, onEntryCompleted, onProgress, outputFactory)
        }
    }

    private fun scanTarEntries(input: InputStream): ScanResult {
        val header = ByteArray(BLOCK_SIZE)
        var entries = 0
        var materializedBytes = 0L
        while (true) {
            readFully(input, header)
            if (header.all { it.toInt() == 0 }) return ScanResult(entries, materializedBytes)
            val type = header[156].toInt().toChar()
            val size = readOctal(header, 124, 12)
            skipExactly(input, size)
            skipPadding(input, size)
            if (isFileEntry(type)) {
                entries++
                // Hard links do not allocate a second payload. Special entries
                // are skipped by extraction and are intentionally not counted.
                if (type != '1') materializedBytes = saturatedAdd(materializedBytes, size)
            }
        }
    }

    private fun extractTar(
        input: InputStream,
        destination: File,
        totalFiles: Int,
        startEntryIndex: Long,
        initialExtractedFiles: Int,
        onEntryCompleted: (Long, Int) -> Unit,
        onProgress: (Progress) -> Unit,
        outputFactory: (File) -> OutputStream,
    ) {
        val header = ByteArray(BLOCK_SIZE)
        var longName: String? = null
        var entryIndex = 0L
        var extractedFiles = initialExtractedFiles
        val startedAt = System.nanoTime()

        fun reportProgress(
            force: Boolean = false,
            currentEntry: String? = null,
            currentEntryBytes: Long = 0L,
            currentEntrySize: Long = 0L,
        ) {
            if (!force && extractedFiles % 24 != 0) return
            val elapsedSeconds = (System.nanoTime() - startedAt) / 1_000_000_000.0
            // Before a meaningful sample interval, file-count speed can jump
            // into billions per second and wreck the narrow Arabic progress
            // card. Wait for one second, then use a stable average.
            val speed = if (elapsedSeconds >= 1.0) (extractedFiles / elapsedSeconds).toLong() else 0L
            val remaining = when {
                totalFiles <= 0 || speed <= 0L -> null
                extractedFiles >= totalFiles -> 0L
                else -> ceil((totalFiles - extractedFiles).toDouble() / speed).toLong()
            }
            val percent = if (totalFiles > 0) {
                ((extractedFiles.toLong() * 100L) / totalFiles).toInt().coerceIn(0, 100)
            } else {
                null
            }
            onProgress(
                Progress(
                    extractedFiles = extractedFiles,
                    totalFiles = totalFiles,
                    filesPerSecond = speed,
                    secondsRemaining = remaining,
                    percent = percent,
                    currentEntry = currentEntry,
                    currentEntryBytes = currentEntryBytes,
                    currentEntrySize = currentEntrySize,
                ),
            )
        }

        reportProgress(force = true)
        while (true) {
            readFully(input, header)
            if (header.all { it.toInt() == 0 }) {
                if (extractedFiles > 0) reportProgress(force = true)
                return
            }

            val currentEntryIndex = entryIndex++
            val type = header[156].toInt().toChar()
            val size = readOctal(header, 124, 12)
            if (currentEntryIndex < startEntryIndex) {
                if (type == 'L') {
                    val bytes = readBytes(input, size)
                    longName = bytes.toString(Charsets.UTF_8).trimEnd('\u0000', '\n')
                    skipPadding(input, size)
                } else {
                    skipExactly(input, size)
                    skipPadding(input, size)
                    longName = null
                }
                continue
            }
            val name = longName ?: readString(header, 0, 100)
            val prefix = readString(header, 345, 155)
            val fullName = if (prefix.isBlank()) name else "$prefix/$name"
            val mode = readOctal(header, 100, 8)
            longName = null

            when (type) {
                'L' -> {
                    val bytes = readBytes(input, size)
                    longName = bytes.toString(Charsets.UTF_8).trimEnd('\u0000', '\n')
                    skipPadding(input, size)
                    continue
                }
                'x', 'g' -> {
                    // PAX metadata is not needed by the official Arch rootfs layout.
                    skipExactly(input, size)
                    skipPadding(input, size)
                    continue
                }
            }

            val target = safeTarget(destination, fullName)
            when (type) {
                '5' -> {
                    target.mkdirs()
                    applyMode(target, mode, directory = true)
                }
                '2' -> {
                    // Tar stores symlink targets in the linkname header field.
                    val linkTarget = readString(header, 157, 100)
                    skipExactly(input, size)
                    skipPadding(input, size)
                    target.parentFile?.mkdirs()
                    if (target.exists() || target.isSymbolicLink()) target.delete()
                    Os.symlink(linkTarget, target.absolutePath)
                }
                '1' -> {
                    // Hard links also use the linkname header field and normally have size 0.
                    val linkTarget = readString(header, 157, 100)
                    skipExactly(input, size)
                    skipPadding(input, size)
                    target.parentFile?.mkdirs()
                    if (target.exists() || target.isSymbolicLink()) target.delete()
                    val resolved = safeTarget(destination, linkTarget)
                    try {
                        Os.link(resolved.absolutePath, target.absolutePath)
                    } catch (_: Throwable) {
                        // A hard link is an optimization, not a runtime requirement. Some
                        // Android kernels/filesystems reject it, so copy the source instead.
                        require(resolved.isFile) { "هدف الرابط الصلب غير موجود: $linkTarget" }
                        resolved.inputStream().use { source ->
                            FileOutputStream(target).use { output -> source.copyTo(output) }
                        }
                        applyMode(target, mode, directory = false)
                    }
                }
                '0', '\u0000', '\n' -> {
                    target.parentFile?.mkdirs()
                    outputFactory(target).use { output ->
                        copyExactly(input, output, size) { copied ->
                            reportProgress(
                                force = true,
                                currentEntry = fullName,
                                currentEntryBytes = copied,
                                currentEntrySize = size,
                            )
                        }
                    }
                    skipPadding(input, size)
                    applyMode(target, mode, directory = false)
                }
                else -> {
                    // Device nodes, FIFOs and other special entries are deliberately skipped.
                    skipExactly(input, size)
                    skipPadding(input, size)
                }
            }
            if (isFileEntry(type)) {
                extractedFiles++
                reportProgress()
                onEntryCompleted(entryIndex, extractedFiles)
            }
        }
    }

    private fun isFileEntry(type: Char): Boolean = type == '0' || type == '\u0000' || type == '\n' || type == '1'

    private fun safeTarget(destination: File, archiveName: String): File {
        val normalized = archiveName.replace('\\', '/').removePrefix("./")
        require(normalized.isNotBlank() && !normalized.startsWith("/")) {
            "Unsafe rootfs entry: $archiveName"
        }
        val candidate = File(destination, normalized)
        val root = destination.canonicalFile
        val canonicalParent = candidate.parentFile?.canonicalFile ?: root
        require(canonicalParent.path == root.path || canonicalParent.path.startsWith(root.path + File.separator)) {
            "Unsafe rootfs entry: $archiveName"
        }
        return candidate
    }

    private fun applyMode(file: File, mode: Long, directory: Boolean) {
        if (directory) file.setExecutable(true, false)
        file.setReadable(true, false)
        file.setWritable(true, true)
        if (!directory) {
            file.setExecutable((mode and 0b001_001_001L) != 0L, false)
        }
    }

    private fun readString(header: ByteArray, offset: Int, length: Int): String {
        var end = offset
        while (end < offset + length && header[end].toInt() != 0) end++
        return header.copyOfRange(offset, end).toString(Charsets.UTF_8).trim()
    }

    private fun readOctal(header: ByteArray, offset: Int, length: Int): Long {
        val value = readString(header, offset, length).trim()
        return value.toLongOrNull(8) ?: 0L
    }

    private fun readBytes(input: InputStream, length: Long): ByteArray {
        require(length <= Int.MAX_VALUE) { "Tar entry is too large: $length" }
        val bytes = ByteArray(length.toInt())
        readFully(input, bytes)
        return bytes
    }

    private fun copyExactly(
        input: InputStream,
        output: OutputStream,
        length: Long,
        onBytesCopied: (Long) -> Unit = {},
    ) {
        var remaining = length
        var copied = 0L
        var nextReportAt = 1L * 1024L * 1024L
        val buffer = ByteArray(64 * 1024)
        while (remaining > 0) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            require(read > 0) { "Unexpected end of rootfs archive" }
            output.write(buffer, 0, read)
            remaining -= read
            copied += read
            if (copied >= nextReportAt || remaining == 0L) {
                onBytesCopied(copied)
                nextReportAt = copied + 1L * 1024L * 1024L
            }
        }
    }

    private fun skipExactly(input: InputStream, length: Long) {
        var remaining = length
        while (remaining > 0) {
            val skipped = input.skip(remaining)
            if (skipped > 0) {
                remaining -= skipped
            } else {
                require(input.read() >= 0) { "Unexpected end of rootfs archive" }
                remaining--
            }
        }
    }

    private fun skipPadding(input: InputStream, size: Long) {
        val padding = (BLOCK_SIZE - (size % BLOCK_SIZE)) % BLOCK_SIZE
        skipExactly(input, padding)
    }

    private fun readFully(input: InputStream, buffer: ByteArray) {
        var offset = 0
        while (offset < buffer.size) {
            val read = input.read(buffer, offset, buffer.size - offset)
            require(read > 0) { "Unexpected end of rootfs archive" }
            offset += read
        }
    }

    private fun saturatedAdd(first: Long, second: Long): Long =
        if (Long.MAX_VALUE - first < second) Long.MAX_VALUE else first + second

    private class CountingInputStream(
        source: InputStream,
        private val totalBytes: Long,
        private val onProgress: (CountProgress) -> Unit,
    ) : FilterInputStream(source) {
        private var scannedBytes = 0L
        private var lastReportedBytes = -1L
        private var lastReportedPercent: Int? = null

        override fun read(): Int = super.read().also { value ->
            if (value >= 0) record(1)
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
            super.read(buffer, offset, length).also { count ->
                if (count > 0) record(count.toLong())
            }

        fun publish(force: Boolean = false) {
            val percent = totalBytes.takeIf { it > 0L }
                ?.let { ((scannedBytes * 100L) / it).toInt().coerceIn(0, 100) }
            val crossedPercent = percent != null && percent != lastReportedPercent
            if (!force && !crossedPercent && scannedBytes - lastReportedBytes < 2L * 1024L * 1024L) return
            lastReportedBytes = scannedBytes
            lastReportedPercent = percent
            onProgress(CountProgress(scannedBytes, totalBytes, percent))
        }

        private fun record(count: Long) {
            scannedBytes += count
            publish()
        }
    }
}

private fun File.isSymbolicLink(): Boolean = try {
    java.nio.file.Files.isSymbolicLink(toPath())
} catch (_: Throwable) {
    false
}
