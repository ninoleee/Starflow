package com.example.starflow

import android.view.KeyEvent
import android.view.View
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.R as Media3UiR
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackRemoteControllerTest {
    private val host = mock(NativePlaybackRemoteController.Host::class.java, RETURNS_DEEP_STUBS)
    private var time = 100_000L
    private val controller = NativePlaybackRemoteController(host) { time }
    private val button = mock(View::class.java)
    private val queue = mutableListOf<Pair<Long, Runnable>>()
    private val seekPositions = mutableListOf<Long>()
    private var position = 1_000_000L

    @Before
    fun setup() {
        `when`(host.isTelevisionDevice).thenReturn(true)
        `when`(host.session.togglePlayback()).thenReturn(true)
        `when`(host.session.setPlayWhenReady(anyBoolean())).thenReturn(true)
        val activity = host.activity
        doReturn(button).`when`(activity).findViewById<View>(Media3UiR.id.exo_play_pause)
        `when`(button.isShown).thenReturn(true)
        `when`(button.isEnabled).thenReturn(true)
        `when`(activity.hasWindowFocus()).thenReturn(true)
        val playerView = host.playerView
        `when`(playerView.isAttachedToWindow).thenReturn(true)
        doAnswer { call ->
            queue += (time + call.getArgument<Long>(1)) to call.getArgument<Runnable>(0)
            true
        }.`when`(playerView).postDelayed(any(Runnable::class.java), anyLong())
        doAnswer { call ->
            queue.removeAll { it.second === call.getArgument<Runnable>(0) }
            true
        }.`when`(playerView).removeCallbacks(any(Runnable::class.java))
        val player = host.session.player!!
        `when`(player.playbackState).thenReturn(Player.STATE_READY)
        `when`(player.duration).thenReturn(10_000_000L)
        `when`(player.currentPosition).thenAnswer { position }
        `when`(host.session.seekTo(anyLong())).thenAnswer { call ->
            position = call.getArgument(0)
            seekPositions += position
            true
        }
    }

    @Test
    fun visibleControllerDownOpensEpisodePickerWithoutAMenuKey() {
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        `when`(host.episodes.openEpisodeSelectionDialog()).thenReturn(true)
        assertTrue(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN))
        assertTrue(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN, repeat = 1))
        verify(host.episodes).openEpisodeSelectionDialog()
        verify(host.settings, never()).openPlaybackSettingsDialog()
        verify(host.session, never()).togglePlayback()
    }

    @Test
    fun visibleControllerDownFallsBackToSettingsWithoutEpisodes() {
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        `when`(host.episodes.openEpisodeSelectionDialog()).thenReturn(false)
        assertTrue(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN))
        verify(host.settings).openPlaybackSettingsDialog()
    }

    @Test
    fun hiddenControllerDownKeepsEpisodePickerWithSettingsFallback() {
        `when`(host.playerView.isControllerFullyVisible).thenReturn(false)
        `when`(host.episodes.openEpisodeSelectionDialog()).thenReturn(true)
        assertTrue(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN))
        verify(host.episodes).openEpisodeSelectionDialog()
        verify(host.settings, never()).openPlaybackSettingsDialog()
        `when`(host.episodes.openEpisodeSelectionDialog()).thenReturn(false)
        assertTrue(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN, downTime = 200L))
        verify(host.settings).openPlaybackSettingsDialog()
    }

    @Test
    fun downInDialogsSubtitleSearchAndPhoneIsNotIntercepted() {
        `when`(host.settings.isOverlayDialogVisible()).thenReturn(true)
        assertFalse(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN))
        `when`(host.settings.isOverlayDialogVisible()).thenReturn(false)
        `when`(host.externalSubtitles.subtitleSearchActive).thenReturn(true)
        assertFalse(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN))
        `when`(host.externalSubtitles.subtitleSearchActive).thenReturn(false)
        `when`(host.isTelevisionDevice).thenReturn(false)
        assertFalse(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN))
        verify(host.settings, never()).openPlaybackSettingsDialog()
        verify(host.episodes, never()).openEpisodeSelectionDialog()
    }

    @Test
    fun upThenDownReachesSettingsWithoutPausingPlayback() {
        assertTrue(send(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.ACTION_DOWN))
        verify(host.controllerView).showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        assertTrue(send(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_DOWN, downTime = 200L))
        verify(host.settings).openPlaybackSettingsDialog()
        verify(host.session, never()).togglePlayback()
    }

    @Test
    fun hiddenControllerConfirmConsumesRepeatsAndReleaseAfterFocusChanges() {
        for (key in confirmKeys) {
            clearInvocations(host.session, button)
            `when`(host.playerView.isControllerFullyVisible).thenReturn(false)
            `when`(button.hasFocus()).thenReturn(false)
            `when`(host.controllerView.progressTimeBar!!.hasFocus()).thenReturn(false)
            assertTrue(send(key, KeyEvent.ACTION_DOWN))
            `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
            `when`(host.controllerView.progressTimeBar!!.hasFocus()).thenReturn(true)
            assertTrue(send(key, KeyEvent.ACTION_DOWN, repeat = 1))
            assertTrue(send(key, KeyEvent.ACTION_DOWN, repeat = 8))
            assertTrue(send(key, KeyEvent.ACTION_UP))
            verify(host.session).togglePlayback()
            verify(button, never()).performClick()
            assertTrue(send(key, KeyEvent.ACTION_DOWN, downTime = 200L))
            assertTrue(send(key, KeyEvent.ACTION_UP, downTime = 200L))
            verify(host.session, times(2)).togglePlayback()
            verify(button, never()).performClick()
        }
    }

    @Test
    fun focusedProgressTogglesOnceAndKeepsFocus() {
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        `when`(host.controllerView.progressTimeBar!!.hasFocus()).thenReturn(true)
        assertTrue(send(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.ACTION_DOWN))
        assertTrue(send(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.ACTION_DOWN, repeat = 2))
        assertTrue(send(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.ACTION_UP))
        verify(host.session).togglePlayback()
        verify(host.playerView).showController()
        verify(host.controllerView, never()).showControllerForRemoteFocus(anyTarget())
    }

    @Test
    fun mediaKeysActOncePerPress() {
        for (key in intArrayOf(
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE,
        )) {
            clearInvocations(host.session)
            assertTrue(send(key, KeyEvent.ACTION_DOWN))
            assertTrue(send(key, KeyEvent.ACTION_DOWN, repeat = 1))
            assertTrue(send(key, KeyEvent.ACTION_UP))
            when (key) {
                KeyEvent.KEYCODE_MEDIA_PLAY -> verify(host.session).setPlayWhenReady(true)
                KeyEvent.KEYCODE_MEDIA_PAUSE -> verify(host.session).setPlayWhenReady(false)
                else -> verify(host.session).togglePlayback()
            }
        }
    }

    @Test
    fun overlaysAndPhoneConfirmAreNotIntercepted() {
        `when`(host.settings.isOverlayDialogVisible()).thenReturn(true)
        assertFalse(send(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.ACTION_DOWN))
        assertFalse(send(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.ACTION_DOWN))
        `when`(host.settings.isOverlayDialogVisible()).thenReturn(false)
        `when`(host.externalSubtitles.subtitleSearchActive).thenReturn(true)
        assertFalse(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN))
        `when`(host.externalSubtitles.subtitleSearchActive).thenReturn(false)
        `when`(host.isTelevisionDevice).thenReturn(false)
        assertFalse(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN))
        verify(host.session, never()).togglePlayback()
    }

    @Test
    fun ownedReleaseIsConsumedEvenWhenAnOverlayAppears() {
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN))
        `when`(host.settings.isOverlayDialogVisible()).thenReturn(true)
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN, repeat = 1))
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_UP))
        assertFalse(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN, downTime = 200L))
        verify(host.session).togglePlayback()
    }

    @Test
    fun resetAndLostReleaseDoNotBlockTheNextPressOrReplayHeldKeys() {
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN))
        controller.resetInputState()
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN, repeat = 1))
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN, downTime = 200L))
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_UP, downTime = 200L))
        verify(host.session, times(2)).togglePlayback()
    }

    @Test
    fun visibleControllerConfirmDoesNotDependOnThePlayButton() {
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        `when`(button.hasFocus()).thenReturn(false)
        `when`(host.playerView.hasFocus()).thenReturn(true)
        `when`(button.isEnabled).thenReturn(false)
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_DOWN))
        assertTrue(send(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_UP))
        verify(button, never()).performClick()
        verify(host.session).togglePlayback()
    }

    @Test
    fun shortDirectionalPressSeeksImmediatelyAndReleaseDoesNotRepeat() {
        assertTrue(send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN))
        assertEquals(listOf(1_010_000L), seekPositions)
        assertTrue(send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_UP))
        assertTrue(queue.isEmpty())
        assertTrue(send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN, downTime = 200L))
        assertTrue(send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_UP, downTime = 200L))
        assertEquals(listOf(1_010_000L, 1_000_000L), seekPositions)
    }

    @Test
    fun repeatBurstKeepsOneCallbackAndCommitsTheAccumulatedTarget() {
        send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN)
        repeat(4) {
            advance(50L)
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, repeat = it + 1)
            assertEquals(1, queue.size)
            assertEquals(1, seekPositions.size)
        }
        advance(49L)
        assertEquals(1, seekPositions.size)
        advance(1L)
        assertEquals(listOf(1_010_000L, 1_090_000L), seekPositions)
        assertTrue(queue.isEmpty())
        send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_UP)
        assertEquals(2, seekPositions.size)
    }

    @Test
    fun sustainedHighRateHoldIsBoundedToFourRepeatCommitsPerSecond() {
        send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN)
        repeat(100) {
            advance(10L)
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, repeat = it + 1)
            assertTrue(queue.size <= 1)
        }
        assertEquals(5, seekPositions.size)
        send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_UP)
        assertEquals(6, seekPositions.size)
        assertTrue(queue.isEmpty())
    }

    @Test
    fun repeatedSeekAtStartKeepsControllerVisibleWithoutExtraPlayerWork() {
        position = 0L
        `when`(host.session.seekTo(0L)).thenReturn(false)
        clearInvocations(host.session, host.controllerView)
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN)
        repeat(10) {
            advance(10L)
            send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN, repeat = it + 1)
        }
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_UP)
        verify(host.session, times(2)).seekTo(0L)
        verify(host.controllerView, times(2)).showControllerForRemoteFocus(ControllerFocusTarget.PLAYER)
        assertTrue(queue.isEmpty())
    }

    @Test
    fun releaseFlushesTheLatestTargetAndLateCallbacksCannotSeekAgain() {
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN)
        advance(50L)
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN, repeat = 1)
        val stale = queue.single().second
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_UP)
        assertEquals(listOf(990_000L, 980_000L), seekPositions)
        assertTrue(queue.isEmpty())
        stale.run()
        assertEquals(2, seekPositions.size)
    }

    @Test
    fun changingDirectionUsesPendingTargetAndResetsAcceleration() {
        send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN)
        advance(50L)
        send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, repeat = 12)
        val stale = queue.single().second
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN, downTime = 200L)
        assertEquals(listOf(1_010_000L, 1_120_000L), seekPositions)
        assertTrue(queue.isEmpty())
        assertFalse(send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_UP))
        stale.run()
        advance(50L)
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN, repeat = 1, downTime = 200L)
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_UP, downTime = 200L)
        assertEquals(1_110_000L, seekPositions.last())
    }

    @Test
    fun cancelledReleaseAndResetDiscardPendingSeekAndStrayRepeats() {
        for (cancelled in listOf(false, true)) {
            controller.resetInputState()
            seekPositions.clear()
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN)
            advance(50L)
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, repeat = 1)
            val stale = queue.single().second
            if (cancelled) send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_UP, cancelled = true)
            else controller.resetInputState()
            stale.run()
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, repeat = 2)
            assertTrue(queue.isEmpty())
            assertEquals(1, seekPositions.size)
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, downTime = 200L)
            assertEquals(2, seekPositions.size)
        }
    }

    @Test
    fun pendingSeekIsRejectedAfterFocusLossOverlayDetachOrPlayerReplacement() {
        val player = host.session.player!!
        for (state in listOf("focus", "overlay", "subtitle", "detach", "destroyed", "player", "ended")) {
            controller.resetInputState()
            `when`(host.session.player).thenReturn(player)
            `when`(player.playbackState).thenReturn(Player.STATE_READY)
            `when`(host.activity.hasWindowFocus()).thenReturn(true)
            `when`(host.activity.isDestroyed).thenReturn(false)
            `when`(host.playerView.isAttachedToWindow).thenReturn(true)
            `when`(host.settings.isOverlayDialogVisible()).thenReturn(false)
            `when`(host.externalSubtitles.subtitleSearchActive).thenReturn(false)
            seekPositions.clear()
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN)
            advance(50L)
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, repeat = 1)
            when (state) {
                "focus" -> `when`(host.activity.hasWindowFocus()).thenReturn(false)
                "overlay" -> `when`(host.settings.isOverlayDialogVisible()).thenReturn(true)
                "subtitle" -> `when`(host.externalSubtitles.subtitleSearchActive).thenReturn(true)
                "detach" -> `when`(host.playerView.isAttachedToWindow).thenReturn(false)
                "destroyed" -> `when`(host.activity.isDestroyed).thenReturn(true)
                "player" -> `when`(host.session.player).thenReturn(mock(ExoPlayer::class.java))
                "ended" -> `when`(player.playbackState).thenReturn(Player.STATE_ENDED)
            }
            advance(250L)
            assertEquals(state, 1, seekPositions.size)
            assertTrue(state, queue.isEmpty())
        }
    }

    @Test
    fun bufferingStillCoalescesAndBoundsAreClampedBeforeRelease() {
        position = 15_000L
        `when`(host.session.player!!.playbackState).thenReturn(Player.STATE_BUFFERING)
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN)
        advance(50L)
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN, repeat = 12)
        assertEquals(listOf(5_000L), seekPositions)
        send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_UP)
        assertEquals(listOf(5_000L, 0L), seekPositions)
        position = 9_995_000L
        send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, downTime = 200L)
        assertEquals(10_000_000L, seekPositions.last())
    }

    @Test
    fun unrelatedKeysCancelPendingSeekBeforeHidingOrOpeningChrome() {
        for (key in intArrayOf(KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_DPAD_CENTER)) {
            controller.resetInputState()
            seekPositions.clear()
            `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN)
            advance(50L)
            send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN, repeat = 1)
            val stale = queue.single().second
            send(key, KeyEvent.ACTION_DOWN)
            stale.run()
            assertTrue(queue.isEmpty())
            assertEquals(1, seekPositions.size)
        }
    }

    @Test
    fun directionalKeysInOverlaysAndOnPhoneAreNotOwned() {
        `when`(host.settings.isOverlayDialogVisible()).thenReturn(true)
        assertFalse(send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_DOWN))
        assertFalse(send(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_UP))
        `when`(host.settings.isOverlayDialogVisible()).thenReturn(false)
        `when`(host.isTelevisionDevice).thenReturn(false)
        assertFalse(send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_DOWN))
        assertFalse(send(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_UP))
        assertTrue(seekPositions.isEmpty())
    }

    private fun advance(ms: Long) {
        time += ms
        while (queue.any { it.first <= time }) {
            val task = queue.first { it.first <= time }
            queue.remove(task)
            task.second.run()
        }
    }

    private fun send(
        key: Int,
        action: Int,
        repeat: Int = 0,
        downTime: Long = 100L,
        cancelled: Boolean = false,
    ): Boolean {
        val event = mock(KeyEvent::class.java)
        `when`(event.keyCode).thenReturn(key)
        `when`(event.action).thenReturn(action)
        `when`(event.repeatCount).thenReturn(repeat)
        `when`(event.downTime).thenReturn(downTime)
        `when`(event.isCanceled).thenReturn(cancelled)
        return controller.dispatchKeyEvent(event)
    }

    private fun anyTarget(): ControllerFocusTarget {
        any(ControllerFocusTarget::class.java)
        return ControllerFocusTarget.NONE
    }

    private val confirmKeys = intArrayOf(
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BUTTON_A,
    )
}
