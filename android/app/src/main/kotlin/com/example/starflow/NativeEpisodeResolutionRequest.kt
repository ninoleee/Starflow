package com.example.starflow

internal data class NativeEpisodeResolutionRequest(
    val requestId: Long,
    val sourceQueueIndex: Int,
    val sourcePlaybackTargetJson: String,
    val requestedIndex: Int,
    val requestedTargetJson: String,
) {
    fun matchesPlayback(queue: NativeEpisodeQueue?, playbackTargetJson: String): Boolean =
        queue != null &&
            queue.currentIndex == sourceQueueIndex &&
            playbackTargetJson == sourcePlaybackTargetJson &&
            queue.entries.getOrNull(requestedIndex)?.playbackTargetJson == requestedTargetJson
}
