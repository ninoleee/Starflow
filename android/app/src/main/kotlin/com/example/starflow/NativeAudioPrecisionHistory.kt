package com.example.starflow

import androidx.media3.common.Format
import androidx.media3.common.MimeTypes

/**
 * Main-thread history for one media item, retained across player rebuilds.
 *
 * The caller records only an observed high-precision output disabled for speed/pitch,
 * using the selected SOURCE format, never the decoded PCM sink format. This class
 * does not infer output precision from the codec or the source's PCM encoding.
 */
internal class NativeAudioPrecisionHistory {
    private var downgradedSource: Format? = null

    fun recordSpeedDowngrade(sourceFormat: Format?) {
        downgradedSource = sourceFormat?.takeIf { isAudio(it) }
    }

    /**
     * Pure query; the caller must also require default speed/pitch and a policy that
     * allows high precision. Clear before dispatching a restore rebuild so callbacks
     * cannot repeatedly retry if the decoder continues to produce PCM16.
     */
    fun shouldRestore(sourceFormat: Format?): Boolean {
        val previous = downgradedSource ?: return false
        val current = sourceFormat ?: return false
        if (!isAudio(current)) return false

        val previousId = previous.id?.takeIf { it.isNotBlank() }
        val currentId = current.id?.takeIf { it.isNotBlank() }
        // Equal anonymous formats may describe different tracks; metadata equality
        // is not proof of identity. Only reuse the exact source object without IDs.
        if (previousId == null || currentId == null) return previous === current
        return previousId == currentId && previous.sampleMimeType == current.sampleMimeType
    }

    /**
     * Clear on media changes, compatibility/decoder fallback, or restoration. Do not
     * clear on the speed-downgrade rebuild itself. IDs are only unique within a media
     * item, so its owner must never carry this history into another item.
     */
    fun clear() {
        downgradedSource = null
    }

    private fun isAudio(format: Format): Boolean =
        format.sampleMimeType?.let(MimeTypes::isAudio) == true
}
