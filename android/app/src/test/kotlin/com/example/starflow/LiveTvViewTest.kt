package com.example.starflow

import android.content.Context
import android.graphics.Matrix
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import android.widget.FrameLayout
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class LiveTvViewTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    private class Fixture(
        val view: PlatformView,
        val channel: MethodChannel,
        val calls: MethodChannel.MethodCallHandler,
        val players: MutableList<ExoPlayer>,
        val listeners: MutableList<Player.Listener>,
        val lifecycle: Lifecycle,
        val speeds: List<LiveTvNetworkSpeed>,
        val polls: MutableList<Runnable>,
    ) {
        fun call(method: String, args: Map<String, Any> = emptyMap()): MethodChannel.Result {
            val result = mock(MethodChannel.Result::class.java)
            calls.onMethodCall(MethodCall(method, args), result)
            return result
        }

        fun open(generation: Long, volume: Float = 1f) {
            verify(call("open", mapOf("url" to "https://example.test/live", "generation" to generation,
                "volume" to volume))).success(null)
        }
    }

    private fun withView(test: (Fixture) -> Unit) {
        val resources = mutableListOf<AutoCloseable>()
        try {
            resources.add(mockStatic(androidx.media3.common.util.Util::class.java) { call ->
                if (call.method.name == "isRunningOnEmulator") false else call.callRealMethod()
            })
            val looper = mockStatic(Looper::class.java).also(resources::add)
            looper.`when`<Looper> { Looper.getMainLooper() }.thenReturn(mock(Looper::class.java))
            val uri = mockStatic(Uri::class.java).also(resources::add)
            uri.`when`<Uri> { Uri.parse(anyString()) }.thenReturn(mock(Uri::class.java))
            val polls = mutableListOf<Runnable>()
            resources.add(mockConstruction(Handler::class.java) { handler, _ ->
                doAnswer { polls.add(it.getArgument(0)); true }.`when`(handler).postDelayed(any(), anyLong())
            })
            val speeds = mockConstruction(LiveTvNetworkSpeed::class.java).also(resources::add)
            resources.add(mockConstruction(FrameLayout::class.java))
            resources.add(mockConstruction(TextureView::class.java))
            resources.add(mockConstruction(Matrix::class.java))
            resources.add(mockConstruction(DefaultMediaSourceFactory::class.java))
            resources.add(mockConstruction(DefaultLoadControl.Builder::class.java,
                withSettings().defaultAnswer(RETURNS_SELF)) { builder, _ ->
                val control = mock(DefaultLoadControl::class.java)
                `when`(builder.build()).thenReturn(control)
            })
            val players = mutableListOf<ExoPlayer>()
            val listeners = mutableListOf<Player.Listener>()
            resources.add(mockConstruction(ExoPlayer.Builder::class.java,
                withSettings().defaultAnswer(RETURNS_SELF)) { builder, _ ->
                val player = mock(ExoPlayer::class.java)
                players.add(player)
                `when`(builder.build()).thenReturn(player)
                doAnswer { listeners.add(it.getArgument(0)); null }.`when`(player).addListener(any())
            })
            var calls: MethodChannel.MethodCallHandler? = null
            val channels = mockConstruction(MethodChannel::class.java) { channel, _ ->
                doAnswer { calls = it.getArgument(0); null }.`when`(channel).setMethodCallHandler(any())
            }.also(resources::add)
            val lifecycle = mock(Lifecycle::class.java)
            `when`(lifecycle.currentState).thenReturn(Lifecycle.State.STARTED)
            val view = LiveTvViewFactory(mock(BinaryMessenger::class.java), lifecycle)
                .create(mock(Context::class.java), 1, null)
            clearInvocations(channels.constructed().single())
            var failure: Throwable? = null
            try {
                test(Fixture(view, channels.constructed().single(), calls!!, players, listeners, lifecycle,
                    speeds.constructed(), polls))
            } catch (error: Throwable) {
                failure = error
                throw error
            } finally {
                try { view.dispose() } catch (cleanupError: Throwable) {
                    val original = failure
                    if (original == null) throw cleanupError
                    original.addSuppressed(cleanupError)
                }
            }
        } finally { resources.asReversed().forEach { it.close() } }
    }

    @Test fun networkSpeedIsScopedToTheActiveGeneration() = withView { f ->
        verify(f.call("networkSpeed", mapOf("generation" to 1L))).success(null)
        f.open(1)
        verify(f.call("networkSpeed", mapOf("generation" to 1L))).success(0L)
        val oldPoll = f.polls.last()
        oldPoll.run()
        verify(f.speeds.single()).sample()
        `when`(f.speeds.single().bytesPerSecond).thenReturn(2048L)
        verify(f.call("networkSpeed", mapOf("generation" to 1L))).success(2048L)
        f.open(2)
        oldPoll.run()
        verify(f.speeds.first(), times(1)).sample()
        verify(f.call("networkSpeed", mapOf("generation" to 1L))).success(null)
        verify(f.call("networkSpeed", mapOf("generation" to 2L))).success(0L)
        f.call("stop")
        verify(f.call("networkSpeed", mapOf("generation" to 2L))).success(null)
    }

    @Test fun playerErrorsBridgeOnlySafeDetailsAndRejectLateNativeSessions() = withView { f ->
        f.open(1)
        val old = f.listeners.single()
        f.open(2)
        clearInvocations(f.channel)
        val error = PlaybackException("https://private.test/password",
            LiveTvHttpTransport.HttpStatusException(403, mapOf("Set-Cookie" to listOf("secret"))),
            PlaybackException.ERROR_CODE_IO_UNSPECIFIED)
        old.onPlayerError(error)
        verifyNoInteractions(f.channel)
        f.listeners.last().onPlayerError(error)
        f.listeners.last().onPlayerError(error)
        verify(f.channel).invokeMethod("state", mapOf(
            "generation" to 2L, "state" to "error",
            "error" to mapOf("errorCategory" to "http", "nativeErrorCode" to 2000, "httpStatus" to 403)))
        verifyNoMoreInteractions(f.channel)
    }

    @Test fun synchronousFallbackFailureReturnsSafeStructuredDetails() = withView { f ->
        f.open(1)
        val current = f.players.single()
        doThrow(IllegalStateException("https://private.test/password")).`when`(current).prepare()
        // Exercise fallback preparation on the already allocated player.
        val unsupported = androidx.media3.exoplayer.source.UnrecognizedInputFormatException(
            "private", mock(Uri::class.java), emptyList())
        f.listeners.single().onPlayerError(PlaybackException("private", unsupported,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED))
        verify(f.channel).invokeMethod("state", mapOf(
            "generation" to 1L, "state" to "error", "error" to mapOf("errorCategory" to "unknown")))
    }

    @Test fun cancelOpenReleasesCurrentGenerationAndRejectsLateCallbacks() = withView { f ->
        f.open(1L shl 40)
        verify(f.call("cancelOpen", mapOf("generation" to (1L shl 40)))).success(null)
        verify(f.players.single()).release()
        clearInvocations(f.channel)
        f.listeners.single().onPlaybackStateChanged(Player.STATE_READY)
        f.listeners.single().onPlayWhenReadyChanged(false, Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS)
        f.listeners.single().onRenderedFirstFrame()
        verifyNoInteractions(f.channel)
        f.call("cancelOpen", mapOf("generation" to (1L shl 40)))
        f.call("stop")
        verify(f.players.single(), times(1)).release()
    }

    @Test fun staleCancellationCannotReleaseReplacementAndMuteSurvivesOpen() = withView { f ->
        f.open(7, 0f)
        f.open(8, 0f)
        verify(f.players[0]).release()
        f.call("cancelOpen", mapOf("generation" to 7L))
        verify(f.players[1], never()).release()
        verify(f.players[1]).volume = 0f
        f.listeners[1].onPlaybackStateChanged(Player.STATE_READY)
        verify(f.channel).invokeMethod("state", mapOf("generation" to 8L, "state" to "ready"))
    }

    @Test fun audioFocusSuppressionLossAndRecoveryAreNotStreamFailures() = withView { f ->
        f.open(1)
        val current = f.players.single()
        val listener = f.listeners.single()
        verify(current).setAudioAttributes(any(), eq(true))
        verify(current).setHandleAudioBecomingNoisy(true)
        `when`(current.playWhenReady).thenReturn(true)
        listener.onPlaybackSuppressionReasonChanged(Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS)
        verify(f.channel).invokeMethod("state", mapOf("generation" to 1L, "state" to "suppressed:1"))
        listener.onPlaybackSuppressionReasonChanged(Player.PLAYBACK_SUPPRESSION_REASON_NONE)
        verify(f.channel).invokeMethod("state", mapOf("generation" to 1L, "state" to "resumed"))
        listener.onPlayWhenReadyChanged(false, Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS)
        verify(f.channel).invokeMethod("state", mapOf("generation" to 1L, "state" to "paused:2"))
        listener.onPlayWhenReadyChanged(false, Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY)
        verify(f.channel).invokeMethod("state", mapOf("generation" to 1L, "state" to "paused:3"))
        verify(current, never()).release()
        verifyNoMoreInteractions(f.channel)
    }

    @Test fun backgroundAndDisposeReleaseOnceAndInactiveOpenCannotAllocatePlayer() = withView { f ->
        f.open(1)
        val observer = org.mockito.ArgumentCaptor.forClass(LifecycleEventObserver::class.java)
        verify(f.lifecycle).addObserver(observer.capture() ?: LifecycleEventObserver { _, _ -> })
        `when`(f.lifecycle.currentState).thenReturn(Lifecycle.State.CREATED)
        observer.value.onStateChanged(mock(androidx.lifecycle.LifecycleOwner::class.java), Lifecycle.Event.ON_STOP)
        verify(f.players.single()).release()
        verify(f.call("open", mapOf("url" to "https://example.test/live", "generation" to 2L)))
            .error(eq("inactive"), anyString(), isNull())
        assertEquals(1, f.players.size)
        f.view.dispose()
        f.view.dispose()
        verify(f.players.single(), times(1)).release()
        verify(f.lifecycle, times(1)).removeObserver(observer.value)
    }
}
