package com.example.starflow

import android.app.Activity
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Tracks
import androidx.media3.decoder.ffmpeg.FfmpegLibrary
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.audio.AudioSink
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_MEDIA_MIME_TYPE
import com.example.starflow.NativePlaybackActivity.Companion.EXTRA_URL

internal class NativePlaybackRecoveryController(
    private val host: Host,
    private val supportsSoftwareAudio: (String) -> Boolean = FfmpegLibrary::supportsFormat,
) {
    interface Host {
        val diagnostics: NativePlaybackDiagnostics
        val session: NativePlaybackSession
        val runtime: NativePlaybackRuntimeController
        val systemSession: NativePlaybackSystemController
        val activity: Activity
        val launch: NativePlaybackLaunchController

        fun showToast(message: String)
    }

    private var transcodedVideoFallbackAttempted = false
    private var audioFallbackAttempted = false
    private var pcmFallbackAttempted = false
    private val automaticRecoveryBudget = PlaybackRecoveryBudget()
    private var recoveryItemKey = ""

    var smartStrmHlsFallbackAttempted = false

    fun resetForNewMedia() {
        automaticRecoveryBudget.reset()
        recoveryItemKey = ""
        transcodedVideoFallbackAttempted = false
        audioFallbackAttempted = false
        pcmFallbackAttempted = false
        smartStrmHlsFallbackAttempted = false
        host.session.resetAudioRecovery()
    }

    fun retryAudioWithSoftwareDecoder(error: PlaybackException): Boolean {
        val rendererError = error as? ExoPlaybackException ?: return false
        if (rendererError.type != ExoPlaybackException.TYPE_RENDERER) return false
        val outputError = error.errorCode in setOf(
                PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED,
                PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED,
            )
        if (!outputError && error.errorCode !in setOf(
                PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
                PlaybackException.ERROR_CODE_DECODING_FAILED,
            )) return false
        val format = rendererError.rendererFormat
        val rendererName = rendererError.rendererName?.substringAfterLast('.')
        val isFfmpeg = rendererName == "FfmpegAudioRenderer"
        val knownAudioRenderer = isFfmpeg || rendererName == "MediaCodecAudioRenderer"
        val exceptionFormat = when (val cause = rendererError.rendererException) {
            is AudioSink.ConfigurationException -> cause.format
            is AudioSink.InitializationException -> cause.format
            is AudioSink.WriteException -> cause.format
            else -> null
        }
        if (rendererName?.endsWith("VideoRenderer") == true ||
            (format != null && !MimeTypes.isAudio(format.sampleMimeType))) return false
        if (format == null && (!outputError || !knownAudioRenderer ||
                exceptionFormat == null || !MimeTypes.isAudio(exceptionFormat.sampleMimeType))) return false

        // Sink formats may be decoded PCM with DRM metadata removed. Only current source
        // tracks (not the cached sink state) can fill that gap for platform decoders.
        val currentPlayer = host.session.player
        val sourceFormats = buildList<Format> {
            currentPlayer?.audioFormat?.takeIf { MimeTypes.isAudio(it.sampleMimeType) }?.let(::add)
            currentPlayer?.currentTracks?.groups?.forEach { group ->
                if (group.type == C.TRACK_TYPE_AUDIO) {
                    for (index in 0 until group.length) {
                        if (group.isTrackSelected(index)) add(group.getTrackFormat(index))
                    }
                }
            }
            format?.takeIf { it.sampleMimeType != MimeTypes.AUDIO_RAW || exceptionFormat == null }
                ?.let(::add)
        }
        if (listOfNotNull(format, exceptionFormat).any(::hasDrm) || sourceFormats.any(::hasDrm)) return false
        // FFmpeg rejects DRM at supportsFormat. All other renderers need positive source evidence.
        if (sourceFormats.isEmpty() && !isFfmpeg) return false
        val state = host.session.audioOutputState.snapshot
        val sinkFormat = exceptionFormat ?: state.sinkInput ?:
            format?.takeIf { it.sampleMimeType == MimeTypes.AUDIO_RAW }
        val highResolution = sinkFormat?.sampleMimeType == MimeTypes.AUDIO_RAW &&
            sinkFormat.pcmEncoding in setOf(C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT)
        val passthrough = sinkFormat?.sampleMimeType?.let {
            MimeTypes.isAudio(it) && it != MimeTypes.AUDIO_RAW
        } == true
        if (outputError && !pcmFallbackAttempted && !host.session.pcm16Fallback &&
            (passthrough || (host.session.highPrecisionPcmEnabled &&
                (highResolution || (sinkFormat == null && state.outputEncoding == C.ENCODING_PCM_FLOAT))))) {
            pcmFallbackAttempted = true
            host.session.preserveAudioSession()
            host.session.pcm16Fallback = true
            host.diagnostics.playbackPerformanceTracker.onRecovery()
            NativeAppLogger.warning("playback.audio", "Audio fallback output=pcm16 " +
                "reason=${if (passthrough) "passthrough-output" else "high-precision-output"} " +
                "sinkMime=${sinkFormat?.sampleMimeType ?: "unknown"} " +
                "input=${NativePlaybackAudioPolicy.encodingLabel(sinkFormat?.pcmEncoding)} " +
                "output=${NativePlaybackAudioPolicy.encodingLabel(state.outputEncoding)} " +
                "code=${error.errorCode} attempt=1 decoderPolicy=unchanged")
            host.session.rebuildPlayer()
            return true
        }
        // A sink failure does not establish a decoder failure. Do not spend its budget here.
        if (outputError) return false
        val mime = format?.sampleMimeType ?: return false
        if (rendererError.rendererName?.contains("ffmpeg", ignoreCase = true) == true ||
            audioFallbackAttempted || host.session.audioFallbackMime != null ||
            error.errorCode !in setOf(PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
                PlaybackException.ERROR_CODE_DECODING_FAILED) ||
            !supportsSoftwareAudio(mime)) return false
        audioFallbackAttempted = true
        host.session.preserveAudioSession()
        host.session.audioFallbackMime = mime
        host.diagnostics.playbackPerformanceTracker.onRecovery()
        NativeAppLogger.warning("playback.audio", "Audio fallback decoder=ffmpeg mime=$mime code=${error.errorCode} attempt=1")
        host.session.rebuildPlayer()
        return true
    }

    private fun hasDrm(format: Format): Boolean =
        format.cryptoType != C.CRYPTO_TYPE_NONE || format.drmInitData != null

    fun fallbackToTranscodedVideoIfNeeded(tracks: Tracks) {
        if (transcodedVideoFallbackAttempted) {
            return
        }
        val videoGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_VIDEO }
        if (
            videoGroups.isEmpty() ||
                videoGroups.any { group ->
                    (0 until group.length).any { trackIndex -> group.isTrackSupported(trackIndex) }
                }
        ) {
            return
        }

        transcodedVideoFallbackAttempted = true
        host.diagnostics.playbackPerformanceTracker.onRecovery()
        val currentPlayer = host.session.player ?: return
        val fallbackUrl =
            NativePlaybackSource.buildTranscodedVideoFallbackUrl(
                host.activity.intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
            )
        if (fallbackUrl == null) {
            NativePlaybackFormatting.logPlayback("native.video.unsupported-no-transcode-fallback")
            return
        }

        host.session.pendingResumePositionOverrideMs =
            currentPlayer.currentPosition.coerceAtLeast(0L)
        host.session.nextInitializePlayWhenReady = currentPlayer.playWhenReady
        host.activity.intent.putExtra(EXTRA_URL, fallbackUrl)
        NativePlaybackFormatting.logPlayback(
            "native.video.unsupported-fallback " +
                "resumeMs=${host.session.pendingResumePositionOverrideMs}"
        )
        host.session.rebuildPlayer()
        host.showToast("视频编码需要转码，正在重新连接")
    }

    fun retrySmartStrmAsHlsIfNeeded(error: PlaybackException): Boolean {
        val url = host.activity.intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        if (
            !NativePlaybackHlsFallbackPolicy.shouldRetryAsHls(
                errorCode = error.errorCode,
                url = url,
                alreadyAttempted = smartStrmHlsFallbackAttempted,
            )
        ) {
            return false
        }

        smartStrmHlsFallbackAttempted = true
        host.diagnostics.playbackPerformanceTracker.onRecovery()
        host.session.pendingResumePositionOverrideMs =
            host.session.player?.currentPosition?.coerceAtLeast(0L) ?: 0L
        host.session.nextInitializePlayWhenReady = host.session.player?.playWhenReady ?: true
        host.activity.intent.putExtra(EXTRA_MEDIA_MIME_TYPE, MimeTypes.APPLICATION_M3U8)
        NativePlaybackFormatting.logPlayback(
            "native.playback.smartstrm-hls-fallback " +
                "resumeMs=${host.session.pendingResumePositionOverrideMs} " +
                "url=${NativePlaybackSource.summarizeUrl(url)}"
        )
        host.session.rebuildPlayer()
        return true
    }

    fun recoverPlaybackStall(positionMs: Long): Boolean {
        val currentPlayer = host.session.player ?: return true
        val nowMs = System.currentTimeMillis()
        val recovery =
            host.runtime.playbackWatchdogPolicy.recovery(
                host.diagnostics::isCurrentBandwidthInsufficient
            )
        if (recovery == NativePlaybackWatchdogPolicy.Recovery.NONE) {
            return true
        }
        if (recovery == NativePlaybackWatchdogPolicy.Recovery.WAIT_FOR_BANDWIDTH) {
            if (!host.diagnostics.bandwidthWarningShown) {
                host.diagnostics.bandwidthWarningShown = true
                host.showToast("当前网速低于片源码率，继续等待缓冲")
            }
            return true
        }
        host.diagnostics.playbackPerformanceTracker.onRecovery()

        if (recovery == NativePlaybackWatchdogPolicy.Recovery.SOFT) {
            host.systemSession.playbackSystemSessionManager.prepareForPlayback()
            currentPlayer.seekTo(positionMs.coerceAtLeast(0L))
            currentPlayer.prepare()
            currentPlayer.playWhenReady = true
            host.runtime.playbackWatchdogPolicy.onSoftRecoveryCompleted(nowMs)
            return true
        }

        val itemKey = host.activity.intent.getStringExtra(
            NativePlaybackActivity.EXTRA_PLAYBACK_ITEM_KEY
        ).orEmpty()
        if (itemKey != recoveryItemKey) {
            recoveryItemKey = itemKey
            automaticRecoveryBudget.reset()
        }
        val allowed = automaticRecoveryBudget.take()
        NativeAppLogger.info(
            "playback.reliability",
            "Playback recovery decision engine=exo policyVersion=${PlaybackPolicyValues.version} " +
                "phase=${if (allowed) "recovering" else "failed"} " +
                "action=${if (allowed) "restart" else "stop"} reason=stall " +
                "attempt=${automaticRecoveryBudget.attempts} positionMs=$positionMs",
        )
        if (!allowed) {
            host.launch.handlePlaybackFailure("自动恢复次数已用完，请检查网络后重试播放。")
            return false
        }
        restartPlayerAfterPlaybackStall(positionMs)
        return false
    }

    private fun restartPlayerAfterPlaybackStall(positionMs: Long) {
        host.session.pendingResumePositionOverrideMs = positionMs.coerceAtLeast(0L)
        host.session.nextInitializePlayWhenReady = true
        host.session.rebuildPlayer()
        host.systemSession.syncPlaybackSystemSession()
    }
}
