package com.example.starflow

import android.view.KeyEvent
import android.view.View
import androidx.media3.ui.R as Media3UiR
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackRemoteControllerTest {
    private val host = mock(NativePlaybackRemoteController.Host::class.java, RETURNS_DEEP_STUBS)
    private val controller = NativePlaybackRemoteController(host)
    private val button = mock(View::class.java)

    @Before
    fun setup() {
        `when`(host.isTelevisionDevice).thenReturn(true)
        `when`(host.session.togglePlayback()).thenReturn(true)
        `when`(host.session.setPlayWhenReady(anyBoolean())).thenReturn(true)
        val activity = host.activity
        doReturn(button).`when`(activity).findViewById<View>(Media3UiR.id.exo_play_pause)
        `when`(button.isShown).thenReturn(true)
        `when`(button.isEnabled).thenReturn(true)
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

    private fun send(key: Int, action: Int, repeat: Int = 0, downTime: Long = 100L): Boolean {
        val event = mock(KeyEvent::class.java)
        `when`(event.keyCode).thenReturn(key)
        `when`(event.action).thenReturn(action)
        `when`(event.repeatCount).thenReturn(repeat)
        `when`(event.downTime).thenReturn(downTime)
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
