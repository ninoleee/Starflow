package com.example.starflow

internal object PlaybackSystemSessionUpdatePolicy {
    fun metadataChanged(previous: PlaybackSystemSessionState?, next: PlaybackSystemSessionState): Boolean =
        previous == null || previous.title != next.title || previous.subtitle != next.subtitle ||
            previous.durationMs != next.durationMs

    fun notificationChanged(previous: PlaybackSystemSessionState?, next: PlaybackSystemSessionState): Boolean =
        previous == null || metadataChanged(previous, next) || previous.playing != next.playing ||
            previous.canSeek != next.canSeek || previous.hasEpisodeQueue != next.hasEpisodeQueue ||
            previous.hasPrevious != next.hasPrevious || previous.hasNext != next.hasNext
}
