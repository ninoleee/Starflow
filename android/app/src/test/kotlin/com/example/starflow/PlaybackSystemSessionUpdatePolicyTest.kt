package com.example.starflow

import org.junit.Assert.*
import org.junit.Test

class PlaybackSystemSessionUpdatePolicyTest {
    private val initial = PlaybackSystemSessionState(
        title = "Episode", subtitle = "Series", durationMs = 100_000L,
        playing = true, hasEpisodeQueue = true, hasNext = true,
    )

    @Test
    fun firstPublicationAndReactivationPublishAllChrome() {
        assertTrue(PlaybackSystemSessionUpdatePolicy.metadataChanged(null, initial))
        assertTrue(PlaybackSystemSessionUpdatePolicy.notificationChanged(null, initial))
        assertFalse(PlaybackSystemSessionUpdatePolicy.metadataChanged(initial, initial))
        assertFalse(PlaybackSystemSessionUpdatePolicy.notificationChanged(initial, initial))
    }

    @Test
    fun positionAndBufferSamplesDoNotRebuildMetadataOrNotification() {
        for (next in listOf(
            initial.copy(positionMs = 20_000L),
            initial.copy(buffering = true),
            initial.copy(speed = 2f),
        )) {
            assertFalse(PlaybackSystemSessionUpdatePolicy.metadataChanged(initial, next))
            assertFalse(PlaybackSystemSessionUpdatePolicy.notificationChanged(initial, next))
        }
    }

    @Test
    fun titleSubtitleAndDurationChangesPublishBoth() {
        for (next in listOf(
            initial.copy(title = "Next"), initial.copy(subtitle = "Other"),
            initial.copy(durationMs = 200_000L),
        )) {
            assertTrue(PlaybackSystemSessionUpdatePolicy.metadataChanged(initial, next))
            assertTrue(PlaybackSystemSessionUpdatePolicy.notificationChanged(initial, next))
        }
    }

    @Test
    fun transportChangesRefreshButtonsWithoutRebuildingMetadata() {
        for (next in listOf(
            initial.copy(playing = false), initial.copy(canSeek = false),
            initial.copy(hasEpisodeQueue = false), initial.copy(hasPrevious = true),
            initial.copy(hasNext = false),
        )) {
            assertFalse(PlaybackSystemSessionUpdatePolicy.metadataChanged(initial, next))
            assertTrue(PlaybackSystemSessionUpdatePolicy.notificationChanged(initial, next))
        }
    }
}
