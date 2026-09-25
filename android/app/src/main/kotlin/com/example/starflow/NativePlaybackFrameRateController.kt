package com.example.starflow

import android.app.Activity
import android.os.Build
import android.view.Display
import android.view.Surface
import android.view.SurfaceView
import androidx.annotation.MainThread
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlin.math.abs
import kotlin.math.round

// Session owns Media3's frame-rate strategy and calls this controller on the main thread.
@MainThread
internal class NativePlaybackFrameRateController(
    private val activity: Activity,
    private val surfaceProvider: (() -> Surface?)? = null,
    private val displayProvider: (() -> Display?)? = null,
    private val apiLevel: Int = Build.VERSION.SDK_INT,
) {
    private var enabled = false
    private var requestedSurface: Surface? = null
    private var requestedSourceFrameRate: Float? = null
    private var requestFailed = false

    fun setEnabled(enabled: Boolean) {
        if (this.enabled == enabled) return
        this.enabled = enabled
        if (!enabled) {
            restore()
        } else {
            requestFailed = false
        }
    }

    fun update(player: ExoPlayer) {
        if (!enabled || apiLevel < Build.VERSION_CODES.R || requestFailed) return

        try {
            if (player.playbackParameters.speed != 1f) return clearRequest()
            val frameRate = player.videoFormat?.frameRate ?: return clearRequest()
            if (!frameRate.isFinite() || frameRate <= 0f) return clearRequest()
            val display = if (displayProvider != null) displayProvider() else findDisplay()
            if (resolveSupportedFrameRate(frameRate, display) == null) return clearRequest()
            val surface = (if (surfaceProvider != null) surfaceProvider() else findSurface())
                ?: return clearRequest()
            if (!surface.isValid) return clearRequest()

            if (surface !== requestedSurface) clearRequest()
            if (requestFailed) return
            if (surface === requestedSurface && requestedSourceFrameRate == frameRate) return

            // Retain the target so even a partially applied vendor hint can be cleared.
            requestedSurface = surface
            if (apiLevel >= Build.VERSION_CODES.S) {
                surface.setFrameRate(
                    frameRate,
                    Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                    Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
                )
            } else {
                surface.setFrameRate(
                    frameRate,
                    Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                )
            }
            requestedSourceFrameRate = frameRate
        } catch (_: RuntimeException) {
            requestFailed = true
            clearRequest()
        } catch (_: LinkageError) {
            requestFailed = true
            clearRequest()
        }
    }

    fun restore() {
        clearRequest()
    }

    private fun clearRequest() {
        val surface = requestedSurface
        requestedSurface = null
        requestedSourceFrameRate = null
        if (apiLevel >= Build.VERSION_CODES.R && surface != null) {
            try {
                if (surface.isValid) {
                    surface.setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
                }
            } catch (_: RuntimeException) {
                requestFailed = true
            } catch (_: LinkageError) {
                requestFailed = true
            }
        }
    }

    private fun findSurface(): Surface? {
        val playerView = activity.findViewById<PlayerView?>(R.id.native_player_view) ?: return null
        return (playerView.videoSurfaceView as? SurfaceView)?.holder?.surface
    }

    private fun findDisplay(): Display? =
        activity.findViewById<PlayerView?>(R.id.native_player_view)?.videoSurfaceView?.display

    internal companion object {
        private const val MATCH_TOLERANCE_HZ = 0.01

        fun resolveSupportedFrameRate(frameRate: Float, display: Display?): Float? {
            if (!frameRate.isFinite() || frameRate <= 0f || display == null || !display.isValid) {
                return null
            }
            val current = display.mode ?: return null
            if (current.physicalWidth <= 0 || current.physicalHeight <= 0 ||
                !current.refreshRate.isFinite() || current.refreshRate <= 0f
            ) return null
            return display.supportedModes
                ?.filter { mode ->
                    val refreshRate = mode.refreshRate
                    if (mode.physicalWidth != current.physicalWidth ||
                        mode.physicalHeight != current.physicalHeight ||
                        !refreshRate.isFinite() || refreshRate <= 0f
                    ) {
                        false
                    } else {
                        val multiple = round(refreshRate.toDouble() / frameRate)
                        val tolerance = minOf(MATCH_TOLERANCE_HZ, frameRate * 0.0005)
                        multiple >= 1 && abs(refreshRate / multiple - frameRate) <= tolerance
                    }
                }
                ?.minByOrNull { it.refreshRate }
                ?.refreshRate
        }
    }
}
