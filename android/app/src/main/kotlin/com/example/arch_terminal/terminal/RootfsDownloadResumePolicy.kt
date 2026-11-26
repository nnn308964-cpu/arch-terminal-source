package com.example.arch_terminal.terminal

/** Pure HTTP resume rules, kept separate so interrupted RootFS downloads are testable. */
object RootfsDownloadResumePolicy {
    data class ResponsePlan(
        val append: Boolean,
        val initialBytes: Long,
        val totalBytes: Long,
    )

    fun responsePlan(
        existingPartialBytes: Long,
        responseCode: Int,
        responseContentLength: Long,
        contentRange: String?,
    ): ResponsePlan {
        require(responseCode in 200..299) { "Unexpected HTTP $responseCode" }
        val resumeAccepted = existingPartialBytes > 0L && responseCode == 206
        if (!resumeAccepted) {
            return ResponsePlan(
                append = false,
                initialBytes = 0L,
                totalBytes = responseContentLength.takeIf { it > 0L } ?: -1L,
            )
        }
        val total = contentRange
            ?.substringAfterLast('/', "")
            ?.toLongOrNull()
            ?.takeIf { it > 0L }
            ?: responseContentLength.takeIf { it > 0L }?.plus(existingPartialBytes)
            ?: -1L
        return ResponsePlan(append = true, initialBytes = existingPartialBytes, totalBytes = total)
    }
}
