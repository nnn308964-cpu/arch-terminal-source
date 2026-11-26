package com.example.arch_terminal.terminal

object DeviceFilePreviewPolicy {
    const val KIND_TEXT = "text"
    const val KIND_IMAGE = "image"
    const val MAX_TEXT_BYTES = 256 * 1024L
    const val MAX_IMAGE_BYTES = 4 * 1024 * 1024L
    const val MAX_IMAGE_PIXELS = 4_000_000L

    private val textExtensions = setOf(
        "txt", "md", "markdown", "log", "json", "xml", "yaml", "yml", "csv", "ini", "conf",
        "sh", "bash", "zsh", "py", "js", "ts", "dart", "java", "kt", "kts", "c", "h", "cpp",
        "hpp", "html", "css", "sql", "properties",
    )
    private val imageExtensions = setOf("png", "jpg", "jpeg", "gif", "webp")

    fun isGuestPath(path: String): Boolean =
        path == DeviceStorageAccess.GUEST_PATH ||
            (path.startsWith("${DeviceStorageAccess.GUEST_PATH}/") &&
                !path.contains("\\") &&
                path.split('/').none { it == "." || it == ".." })

    fun kindFor(path: String): String? {
        val extension = path.substringAfterLast('.', "").lowercase()
        return when {
            extension in textExtensions -> KIND_TEXT
            extension in imageExtensions -> KIND_IMAGE
            else -> null
        }
    }

    fun isSizeAllowed(kind: String, sizeBytes: Long): Boolean = when (kind) {
        KIND_TEXT -> sizeBytes in 1..MAX_TEXT_BYTES
        KIND_IMAGE -> sizeBytes in 1..MAX_IMAGE_BYTES
        else -> false
    }

    fun isPixelCountAllowed(width: Int, height: Int): Boolean =
        width > 0 && height > 0 && width.toLong() * height.toLong() <= MAX_IMAGE_PIXELS
}
