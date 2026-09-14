package com.example.starflow

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.SystemClock
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.*

class PlaybackSystemSessionManagerTest {
    private val mocks = mutableListOf<AutoCloseable>()

    private fun <T : AutoCloseable> track(mock: T): T = mock.also { mocks += it }

    @After
    fun closeMocks() {
        mocks.asReversed().forEach { it.close() }
    }

    @Test
    fun positionUpdatesKeepPublishingTransportWithoutRebuildingChrome() {
        val context = mock(Context::class.java, RETURNS_DEEP_STUBS)
        val notifications = mock(NotificationManager::class.java)
        val audio = mock(AudioManager::class.java)
        `when`(context.getSystemService(Context.NOTIFICATION_SERVICE)).thenReturn(notifications)
        `when`(context.getSystemService(Context.AUDIO_SERVICE)).thenReturn(audio)
        val state = PlaybackSystemSessionState(title = "Episode", subtitle = "Series", durationMs = 100_000L)
        val bitmap = mock(Bitmap::class.java)
        var iconDecodes = 0
        val fluent = withSettings().defaultAnswer(RETURNS_SELF)
        val sessions = track(mockConstruction(MediaSession::class.java))
        track(mockConstruction(AudioAttributes.Builder::class.java, fluent) { builder, _ ->
            `when`(builder.build()).thenReturn(mock(AudioAttributes::class.java))
        })
        val playbackBuilders = track(mockConstruction(PlaybackState.Builder::class.java, fluent) { builder, _ ->
            `when`(builder.build()).thenReturn(mock(PlaybackState::class.java))
        })
        val metadataBuilders = track(mockConstruction(MediaMetadata.Builder::class.java, fluent) { builder, _ ->
            `when`(builder.build()).thenReturn(mock(MediaMetadata::class.java))
        })
        val notificationBuilders = track(mockConstruction(Notification.Builder::class.java, fluent) { builder, _ ->
            `when`(builder.build()).thenReturn(mock(Notification::class.java))
        })
        track(mockConstruction(Notification.Action.Builder::class.java, fluent) { builder, _ ->
            `when`(builder.build()).thenReturn(mock(Notification.Action::class.java))
        })
        track(mockConstruction(Notification.MediaStyle::class.java, fluent))
        track(mockConstruction(Intent::class.java))
        track(mockConstruction(BitmapFactory.Options::class.java))
        track(mockStatic(SystemClock::class.java))
        track(mockStatic(Icon::class.java))
        val intents = track(mockStatic(PendingIntent::class.java))
        intents.`when`<PendingIntent> { PendingIntent.getBroadcast(any(), anyInt(), any(), anyInt()) }
            .thenReturn(mock(PendingIntent::class.java))
        val images = track(mockStatic(BitmapFactory::class.java))
        images.`when`<Bitmap> {
            BitmapFactory.decodeResource(any(), eq(R.drawable.icon_preview_sharp), any())
        }.thenAnswer { call ->
            iconDecodes++
            assertEquals(4, call.getArgument<BitmapFactory.Options>(2).inSampleSize)
            bitmap
        }
        val manager = PlaybackSystemSessionManager(context, "test-session", { null }, { _, _ -> })
        manager.update(state)
        assertTrue(metadataBuilders.constructed().isEmpty())
        manager.setActive(true)
        repeat(100) { manager.update(state.copy(positionMs = it * 1_000L)) }
        assertEquals(100, playbackBuilders.constructed().size)
        assertEquals(1, metadataBuilders.constructed().size)
        assertEquals(1, notificationBuilders.constructed().size)
        assertEquals(1, iconDecodes)
        verify(metadataBuilders.constructed().single())
            .putBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON, bitmap)

        manager.update(state.copy(title = "Next"))
        assertEquals(2, metadataBuilders.constructed().size)
        assertEquals(2, notificationBuilders.constructed().size)
        assertEquals(1, iconDecodes)
        manager.setActive(false)
        manager.setActive(true)
        manager.update(state.copy(title = "Next"))
        assertEquals(3, metadataBuilders.constructed().size)
        assertEquals(3, notificationBuilders.constructed().size)
        assertEquals(1, iconDecodes)
        manager.release()
        verify(sessions.constructed().single()).release()
    }
}
