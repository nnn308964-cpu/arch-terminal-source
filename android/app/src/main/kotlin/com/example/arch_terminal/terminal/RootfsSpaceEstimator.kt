package com.example.arch_terminal.terminal

/** Estimates only additional private-app storage needed for atomic extraction. */
object RootfsSpaceEstimator {
    const val METADATA_MARGIN_BYTES = 64L * 1024L * 1024L

    /**
     * The downloaded archive is already allocated before this check runs,
     * whether in app storage or shared storage. The atomic staging tree is
     * renamed in place, so the additional requirement is its materialized
     * payload plus a filesystem-metadata safety margin—not the archive again.
     */
    fun requiredAdditionalBytes(materializedPayloadBytes: Long): Long =
        saturatedAdd(materializedPayloadBytes.coerceAtLeast(0L), METADATA_MARGIN_BYTES)

    fun hasCapacity(availableBytes: Long, materializedPayloadBytes: Long): Boolean =
        availableBytes >= requiredAdditionalBytes(materializedPayloadBytes)

    private fun saturatedAdd(first: Long, second: Long): Long =
        if (Long.MAX_VALUE - first < second) Long.MAX_VALUE else first + second
}
