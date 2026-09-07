package com.example.starflow

import android.view.View
import android.widget.TextView
import androidx.media3.ui.DefaultTimeBar
import androidx.media3.ui.PlayerView
import androidx.media3.ui.R as Media3UiR
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackControllerViewTest {
    private val host = mock(NativePlaybackControllerView.Host::class.java, RETURNS_DEEP_STUBS)
    private val button = mock(View::class.java)
    private val progress = mock(DefaultTimeBar::class.java)
    private var time = 100L
    private val queue = mutableListOf<Runnable>()
    private val controller = NativePlaybackControllerView(host) { time }

    @Before
    fun setup() {
        `when`(host.isTelevisionDevice).thenReturn(true)
        val playerView = host.playerView
        `when`(playerView.isAttachedToWindow).thenReturn(true)
        `when`(playerView.requestFocus()).thenReturn(true)
        doAnswer { call ->
            queue += call.getArgument<Runnable>(0)
            true
        }.`when`(playerView).postDelayed(any(Runnable::class.java), anyLong())
        doAnswer { call ->
            queue += call.getArgument<Runnable>(0)
            true
        }.`when`(playerView).post(any(Runnable::class.java))
        doAnswer { call ->
            val callback = call.getArgument<Runnable>(0)
            queue.removeAll { it === callback }
            true
        }.`when`(playerView).removeCallbacks(any(Runnable::class.java))
        val activity = host.activity
        doReturn(button).`when`(activity).findViewById<View>(Media3UiR.id.exo_play_pause)
        doReturn(progress).`when`(activity).findViewById<DefaultTimeBar>(Media3UiR.id.exo_progress)
        doReturn(mock(TextView::class.java))
            .`when`(activity).findViewById<TextView>(R.id.native_network_speed)
        `when`(button.isShown).thenReturn(true)
        `when`(button.isEnabled).thenReturn(true)
        `when`(button.isFocusable).thenReturn(true)
        `when`(button.requestFocus()).thenReturn(true)
        `when`(progress.isShown).thenReturn(true)
        `when`(progress.isEnabled).thenReturn(true)
        `when`(progress.isFocusable).thenReturn(true)
        `when`(progress.requestFocus()).thenReturn(true)
    }

    @Test
    fun animationWaitUsesOneCallbackAndStopsAfterOneSecond() {
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        repeat(20) {
            assertEquals(1, queue.size)
            time += 50L
            queue.removeAt(0).run()
        }
        assertTrue(queue.isEmpty())
        assertEquals(ControllerFocusTarget.NONE, controller.pendingControllerFocusTarget)
        verify(button, never()).requestFocus()
    }

    @Test
    fun visibilityCallbacksDoNotDuplicateWaitsAndReadyControllerFocusesOnce() {
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        repeat(5) { controller.applyPendingControllerFocus() }
        assertEquals(1, queue.size)
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        controller.applyPendingControllerFocus()
        assertTrue(queue.isEmpty())
        controller.applyPendingControllerFocus()
        verify(progress).requestFocus()
        verify(button, never()).requestFocus()
    }

    @Test
    fun newRequestReplacesTheOldTarget() {
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PLAYER)
        assertTrue(queue.isEmpty())
        verify(host.playerView).requestFocus()
        verify(button, never()).requestFocus()
    }

    @Test
    fun hidingCancelsPendingWaitsAndLateCallbacksCannotFocus() {
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        val stale = queue.single()
        controller.hideController()
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        stale.run()
        assertTrue(queue.isEmpty())
        verify(host.playerView).hideController()
        verify(button, never()).requestFocus()
    }

    @Test
    fun pausedPageCancelsRestoreAndRejectsNewRequestsUntilResume() {
        controller.restoreControllerFocusIfNeeded(ControllerFocusTarget.PRIMARY)
        val stale = queue.single()
        controller.setFocusRequestsAllowed(false)
        stale.run()
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        controller.restoreControllerFocusIfNeeded(ControllerFocusTarget.PRIMARY)
        assertTrue(queue.isEmpty())
        verify(host.playerView, never()).showController()
        controller.setFocusRequestsAllowed(true)
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        verify(progress).requestFocus()
        verify(button, never()).requestFocus()
    }

    @Test
    fun destroyedDetachedAndOverlayStatesCancelWaits() {
        for (state in listOf("destroyed", "detached", "overlay", "subtitle")) {
            `when`(host.activity.isDestroyed).thenReturn(false)
            `when`(host.playerView.isAttachedToWindow).thenReturn(true)
            `when`(host.settings.isOverlayDialogVisible()).thenReturn(false)
            `when`(host.externalSubtitles.subtitleSearchActive).thenReturn(false)
            controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
            when (state) {
                "destroyed" -> `when`(host.activity.isDestroyed).thenReturn(true)
                "detached" -> `when`(host.playerView.isAttachedToWindow).thenReturn(false)
                "overlay" -> `when`(host.settings.isOverlayDialogVisible()).thenReturn(true)
                "subtitle" -> `when`(host.externalSubtitles.subtitleSearchActive).thenReturn(true)
            }
            queue.removeAt(0).run()
            assertTrue(state, queue.isEmpty())
            assertEquals(state, ControllerFocusTarget.NONE, controller.pendingControllerFocusTarget)
        }
        verify(button, never()).requestFocus()
    }

    @Test
    fun automaticControllerHideCancelsPendingFocus() {
        val playerView = host.playerView
        var listener: PlayerView.ControllerVisibilityListener? = null
        doAnswer { call ->
            listener = call.getArgument(0)
            null
        }.`when`(playerView).setControllerVisibilityListener(
            any(PlayerView.ControllerVisibilityListener::class.java),
        )
        controller.configureRemoteControls()
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        listener!!.onVisibilityChanged(View.GONE)
        assertTrue(queue.isEmpty())
        assertEquals(ControllerFocusTarget.NONE, controller.pendingControllerFocusTarget)
    }

    @Test
    fun remoteSetupDisablesPlayButtonFocusWithoutDisablingClick() {
        controller.configureRemoteControls()
        verify(button).isFocusable = false
        verify(button).isFocusableInTouchMode = false
        verify(button, never()).isEnabled = false
        verify(button, never()).isClickable = false
        verify(progress).isFocusable = true
    }

    @Test
    fun disabledProgressFallsBackToPlayerWithoutFocusingPlayButton() {
        `when`(host.playerView.isControllerFullyVisible).thenReturn(true)
        `when`(progress.isEnabled).thenReturn(false)
        controller.showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        verify(host.playerView).requestFocus()
        verify(button, never()).requestFocus()
        verify(progress, never()).requestFocus()
        assertTrue(queue.isEmpty())
    }
}
