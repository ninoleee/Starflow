package com.example.starflow

import android.app.Activity
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.Format
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackFrameRateControllerTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    @Test
    fun disabledByDefaultAndUntouchedRestoreAreNoOps() {
        val f = Fixture(enabled = false)
        f.controller.update(f.player)
        f.controller.restore()
        f.controller.setEnabled(false)
        verifyNoInteractions(f.player, f.display, f.surface, f.activity)
        f.controller.setEnabled(true)
        f.controller.update(f.player)
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
    }

    @Test
    fun api23Through29NeverReadPlayerDisplayOrSurface() {
        for (api in listOf(23, 24, 29)) {
            val f = Fixture(apiLevel = api)
            f.controller.update(f.player)
            f.controller.restore()
            f.controller.setEnabled(false)
            verifyNoInteractions(f.player, f.display, f.surface, f.activity)
        }
    }

    @Test
    fun api30UsesTwoArgumentsAndDeduplicatesRequests() {
        val f = Fixture()
        repeat(3) { f.controller.update(f.player) }
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        verify(f.surface, never()).setFrameRate(anyFloat(), anyInt(), anyInt())
    }

    @Test
    fun api31AndLaterUseOnlySeamlessAndRestoreWithApi30Call() {
        for (api in listOf(31, 35, 36)) {
            val f = Fixture(apiLevel = api)
            f.controller.update(f.player)
            f.controller.restore()
            f.controller.restore()
            verify(f.surface).setFrameRate(
                24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
            )
            verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
            verify(f.surface, never()).setFrameRate(
                anyFloat(), anyInt(), eq(Surface.CHANGE_FRAME_RATE_ALWAYS),
            )
        }
    }

    @Test
    fun disableClearsOnceAndReenableAllowsAnotherRequest() {
        val f = Fixture()
        f.controller.update(f.player)
        f.controller.setEnabled(false)
        f.controller.setEnabled(false)
        f.controller.update(f.player)
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        f.controller.setEnabled(true)
        f.controller.update(f.player)
        verify(f.surface, times(2)).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
    }

    @Test
    fun restoreClearsOnceWithoutDisablingLaterPlayback() {
        val f = Fixture()
        f.controller.update(f.player)
        f.controller.restore()
        f.controller.restore()
        f.controller.update(f.player)
        verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        verify(f.surface, times(2)).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
    }

    @Test
    fun sourceRateIsRequestedWhenDisplaySupportsIntegerMultiples() {
        for (rate in listOf(24f, 48f, 72f, 120f)) {
            val f = Fixture()
            f.modes(rate)
            f.controller.update(f.player)
            assertEquals(rate, requireNotNull(resolve(24f, f.display)), 0.0001f)
            verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        }
    }

    @Test
    fun nonIntegerMultiplesAndFractionalVersusIntegerCadenceDoNotMatch() {
        val f = Fixture()
        f.modes(60f)
        assertNull(resolve(24f, f.display))
        f.controller.update(f.player)
        verifyNoInteractions(f.surface)
        f.modes(24f, 48f, 72f, 120f)
        assertNull(resolve(23.976f, f.display))
        f.modes(60f, 120f)
        assertNull(resolve(29.97f, f.display))
    }

    @Test
    fun fractionalRatesAcceptTheirMultiplesAndSmallReportingRounding() {
        val f = Fixture()
        f.modes(47.952f, 71.928f, 119.88f)
        assertEquals(47.952f, requireNotNull(resolve(23.976f, f.display)), 0.0001f)
        f.modes(59.94f)
        assertEquals(59.94f, requireNotNull(resolve(29.97f, f.display)), 0.0001f)
        f.modes(24.0001f)
        assertEquals(24.0001f, requireNotNull(resolve(24f, f.display)), 0.0001f)
    }

    @Test
    fun resolutionMustMatchCurrentDisplayModeNotVideoDimensions() {
        val f = Fixture()
        val current = mode(60f, 3840, 2160)
        `when`(f.display.mode).thenReturn(current)
        f.modes(24f)
        assertNull(resolve(24f, f.display))
        f.controller.update(f.player)
        verifyNoInteractions(f.surface)
        val compatible = mode(48f, 3840, 2160)
        `when`(f.display.supportedModes).thenReturn(arrayOf(compatible))
        f.controller.update(f.player)
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        verifyNoInteractions(f.activity)
    }

    @Test
    fun nonUnitSpeedClearsHintAndNormalSpeedReappliesIt() {
        val f = Fixture()
        f.controller.update(f.player)
        for (speed in listOf(0.5f, 1.5f, 2f)) {
            `when`(f.player.playbackParameters).thenReturn(PlaybackParameters(speed))
            f.controller.update(f.player)
        }
        verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        `when`(f.player.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
        f.controller.update(f.player)
        verify(f.surface, times(2)).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
    }

    @Test
    fun missingAndInvalidFormatAreNoOpsBeforeQueryingDevice() {
        val f = Fixture()
        f.format(null)
        f.controller.update(f.player)
        for (rate in listOf(-1f, 0f, Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY)) {
            f.format(rate)
            f.controller.update(f.player)
        }
        verifyNoInteractions(f.surface, f.display)
    }

    @Test
    fun unknownOrInvalidDeviceCapabilitiesAreNoOps() {
        val f = Fixture()
        f.currentDisplay = null
        f.controller.update(f.player)
        f.currentDisplay = f.display
        `when`(f.display.isValid).thenReturn(false)
        f.controller.update(f.player)
        `when`(f.display.isValid).thenReturn(true)
        `when`(f.display.mode).thenReturn(null)
        f.controller.update(f.player)
        val zeroSize = mode(60f, 0, 1080)
        `when`(f.display.mode).thenReturn(zeroSize)
        f.controller.update(f.player)
        val invalidRate = mode(Float.NaN)
        `when`(f.display.mode).thenReturn(invalidRate)
        f.controller.update(f.player)
        val current = mode(60f)
        `when`(f.display.mode).thenReturn(current)
        `when`(f.display.supportedModes).thenReturn(null)
        f.controller.update(f.player)
        f.modes()
        f.controller.update(f.player)
        f.modes(-1f, 0f, Float.NaN, Float.POSITIVE_INFINITY)
        f.controller.update(f.player)
        verifyNoInteractions(f.surface, f.activity)
    }

    @Test
    fun missingAndInvalidSurfacesAreNoOpsAndCanRecover() {
        val f = Fixture()
        f.currentSurface = null
        f.controller.update(f.player)
        f.currentSurface = f.surface
        `when`(f.surface.isValid).thenReturn(false)
        f.controller.update(f.player)
        verify(f.surface, never()).setFrameRate(anyFloat(), anyInt())
        `when`(f.surface.isValid).thenReturn(true)
        f.controller.update(f.player)
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
    }

    @Test
    fun changedSourceRateUpdatesHintAndUnknownFormatClearsIt() {
        val f = Fixture()
        f.modes(24f, 30f)
        f.controller.update(f.player)
        f.format(30f)
        f.controller.update(f.player)
        f.format(null)
        f.controller.update(f.player)
        f.controller.update(f.player)
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        verify(f.surface).setFrameRate(30f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
    }

    @Test
    fun unsupportedSourceOrLostCapabilitiesClearsEarlierRequest() {
        for (loseFormat in listOf(true, false)) {
            val f = Fixture()
            f.controller.update(f.player)
            if (loseFormat) f.format(25f) else f.currentDisplay = null
            f.controller.update(f.player)
            f.controller.restore()
            verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        }
    }

    @Test
    fun replacementSurfaceClearsOldHintBeforeSettingNewOne() {
        val f = Fixture()
        val next = mock(Surface::class.java)
        `when`(next.isValid).thenReturn(true)
        f.controller.update(f.player)
        f.currentSurface = next
        f.controller.update(f.player)
        f.controller.restore()
        val order = inOrder(f.surface, next)
        order.verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        order.verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        order.verify(next).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        order.verify(next).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
    }

    @Test
    fun destroyedSurfaceIsNotTouchedDuringRestore() {
        val f = Fixture()
        f.controller.update(f.player)
        `when`(f.surface.isValid).thenReturn(false)
        f.controller.restore()
        f.controller.restore()
        verify(f.surface, never()).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
    }

    @Test
    fun vendorRequestFailureStopsRepeatedAttemptsUntilUserReenables() {
        val f = Fixture()
        doThrow(IllegalStateException("released surface")).doNothing().`when`(f.surface)
            .setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        repeat(3) { f.controller.update(f.player) }
        f.controller.restore()
        f.controller.update(f.player)
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        f.controller.setEnabled(false)
        f.controller.setEnabled(true)
        f.controller.update(f.player)
        verify(f.surface, times(2)).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
    }

    @Test
    fun api31VendorLinkageErrorIsContainedAndCleanedUp() {
        val f = Fixture(apiLevel = 31)
        doThrow(NoSuchMethodError("vendor API mismatch")).`when`(f.surface).setFrameRate(
            24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
            Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
        )
        repeat(2) { f.controller.update(f.player) }
        verify(f.surface).setFrameRate(
            24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
            Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
        )
        verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
    }

    @Test
    fun vendorCapabilityAndSurfaceValidityExceptionsAreContained() {
        val f = Fixture()
        `when`(f.display.supportedModes).thenThrow(IllegalStateException("display disconnected"))
        repeat(2) { f.controller.update(f.player) }
        verify(f.display).supportedModes
        verifyNoInteractions(f.surface)
        val other = Fixture()
        `when`(other.surface.isValid).thenThrow(IllegalArgumentException("invalid surface"))
        repeat(2) { other.controller.update(other.player) }
        other.controller.restore()
        verify(other.surface).isValid
        verify(other.surface, never()).setFrameRate(anyFloat(), anyInt())
    }

    @Test
    fun vendorRestoreFailureDoesNotThrowOrRetryInLoop() {
        val f = Fixture()
        f.controller.update(f.player)
        doThrow(IllegalArgumentException("vendor restore failure")).`when`(f.surface)
            .setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        f.controller.restore()
        f.controller.restore()
        f.controller.update(f.player)
        verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
    }

    @Test
    fun defaultProvidersUseActualPlayerSurfaceAndItsDisplay() {
        val f = Fixture()
        val playerView = mock(PlayerView::class.java)
        val view = mock(SurfaceView::class.java)
        val holder = mock(SurfaceHolder::class.java)
        `when`(f.activity.findViewById<PlayerView>(R.id.native_player_view)).thenReturn(playerView)
        `when`(playerView.videoSurfaceView).thenReturn(view)
        `when`(view.display).thenReturn(f.display)
        `when`(view.holder).thenReturn(holder)
        `when`(holder.surface).thenReturn(f.surface)
        val controller = NativePlaybackFrameRateController(f.activity, apiLevel = 30)
        controller.setEnabled(true)
        controller.update(f.player)
        controller.restore()
        verify(f.surface).setFrameRate(24f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        verify(f.surface).setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        verify(f.activity, never()).window
    }

    @Test
    fun missingPlayerViewAndNonSurfaceViewAreNoOps() {
        val f = Fixture()
        val controller = NativePlaybackFrameRateController(f.activity, apiLevel = 30)
        controller.setEnabled(true)
        controller.update(f.player)
        val playerView = mock(PlayerView::class.java)
        val view = mock(View::class.java)
        `when`(f.activity.findViewById<PlayerView>(R.id.native_player_view)).thenReturn(playerView)
        `when`(playerView.videoSurfaceView).thenReturn(view)
        `when`(view.display).thenReturn(f.display)
        controller.update(f.player)
        verifyNoInteractions(f.surface)
    }

    private class Fixture(apiLevel: Int = 30, enabled: Boolean = true) {
        val activity = mock(Activity::class.java)
        val player = mock(ExoPlayer::class.java)
        val surface = mock(Surface::class.java)
        val display = mock(Display::class.java)
        var currentSurface: Surface? = surface
        var currentDisplay: Display? = display
        val controller = NativePlaybackFrameRateController(
            activity, { currentSurface }, { currentDisplay }, apiLevel,
        )

        init {
            `when`(surface.isValid).thenReturn(true)
            `when`(display.isValid).thenReturn(true)
            `when`(player.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
            val currentMode = mode(60f)
            `when`(display.mode).thenReturn(currentMode)
            modes(24f)
            format(24f)
            if (enabled) controller.setEnabled(true)
        }

        fun modes(vararg rates: Float) {
            val supported = rates.map { mode(it) }.toTypedArray()
            `when`(display.supportedModes).thenReturn(supported)
        }

        fun format(rate: Float?) {
            val format = rate?.let {
                Format.Builder().setFrameRate(it).setWidth(1920).setHeight(1080).build()
            }
            `when`(player.videoFormat).thenReturn(format)
        }
    }

    private companion object {
        fun mode(rate: Float, width: Int = 1920, height: Int = 1080): Display.Mode {
            val mode = mock(Display.Mode::class.java)
            `when`(mode.refreshRate).thenReturn(rate)
            `when`(mode.physicalWidth).thenReturn(width)
            `when`(mode.physicalHeight).thenReturn(height)
            return mode
        }

        fun resolve(rate: Float, display: Display?) =
            NativePlaybackFrameRateController.resolveSupportedFrameRate(rate, display)
    }
}
