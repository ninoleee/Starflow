package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.TextView
import android.widget.Toast
import android.util.Rational
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.R as Media3UiR
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.DefaultTimeBar
import androidx.media3.ui.PlayerView
import androidx.media3.ui.TrackSelectionDialogBuilder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class NativePlaybackActivity : Activity() {
    private lateinit var sharedPreferences: SharedPreferences
    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView
    private var baseMediaItem: MediaItem? = null
    private var playbackTargetJson = "{}"
    private var playbackItemKey = ""
    private var seriesKey = ""
    private var restoredResumePositionMs: Long = 0L
    private var subtitleDelayMs: Long = 0L
    private var externalSubtitleSource: ExternalSubtitleSource? = null
    private var lastSavedPositionMs: Long = -1L
    private var subtitleSearchActive = false
    private var resumePlaybackAfterSubtitleSearch = false
    private var nextInitializePlayWhenReady: Boolean? = null
    private var pendingControllerFocusTarget = ControllerFocusTarget.NONE
    private var exitConfirmationDialog: AlertDialog? = null
    private var playbackSettingsDialog: AlertDialog? = null
    private var trackSelectionDialog: Dialog? = null
    private var progressTimeBar: DefaultTimeBar? = null
    private var tvSeekHoldKeyCode: Int? = null
    private var tvSeekHoldStartedAtMs: Long? = null
    private var tvSeekHoldRepeatCount = 0
    private val playbackSystemSessionManager by lazy {
        PlaybackSystemSessionManager(
            context = applicationContext,
            sessionTag = "starflow_native_playback",
            contentIntentFactory = { buildPlaybackContentIntent() },
        ) { command, positionMs ->
            handlePlaybackSystemCommand(command, positionMs)
        }
    }
    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            syncPlaybackSystemSession()
            updateTelevisionControllerAutoHidePolicy()
            if (isTelevisionDevice &&
                !subtitleSearchActive &&
                !isOverlayDialogVisible()
            ) {
                if (!isPlaying) {
                    showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
                } else if (!playerView.isControllerFullyVisible) {
                    playerView.requestFocus()
                }
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            syncPlaybackSystemSession()
            updatePictureInPictureParams()
            updateProgressMarkers()
            logPlayback(
                "native.playback.state state=${playbackStateLabel(playbackState)} " +
                    "positionMs=${player?.currentPosition ?: -1L}",
            )
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int,
        ) {
            syncPlaybackSystemSession()
        }

        override fun onPlayerError(error: PlaybackException) {
            logPlayback(
                "native.playback.error code=${error.errorCode} " +
                    "name=${error.errorCodeName} message=${error.message ?: ""} " +
                    "url=${summarizeUrl(intent.getStringExtra(EXTRA_URL)?.trim().orEmpty())} " +
                    "container=${decodePlaybackTargetObject().optString("container").trim()}",
                error,
            )
        }
    }
    private val isTelevisionDevice: Boolean by lazy {
        val currentMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        currentMode == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        sharedPreferences = getSharedPreferences(SHARED_PREFERENCES_NAME, MODE_PRIVATE)
        playbackTargetJson = intent.getStringExtra(EXTRA_PLAYBACK_TARGET_JSON)?.trim().orEmpty()
            .ifEmpty { "{}" }
        playbackItemKey = intent.getStringExtra(EXTRA_PLAYBACK_ITEM_KEY)?.trim().orEmpty()
        seriesKey = intent.getStringExtra(EXTRA_SERIES_KEY)?.trim().orEmpty()
        restoreExternalSubtitleSourceFromTarget()

        setContentView(
            if (isTelevisionDevice) {
                R.layout.native_player_view_tv
            } else {
                R.layout.native_player_view_phone
            },
        )
        playerView = findViewById<PlayerView>(R.id.native_player_view).apply {
            useController = true
            setShutterBackgroundColor(Color.BLACK)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setBackgroundColor(Color.BLACK)
            keepScreenOn = true
            setShowSubtitleButton(true)
            setShowFastForwardButton(true)
            setShowRewindButton(true)
            setShowPreviousButton(false)
            setShowNextButton(false)
            setControllerAutoShow(!isTelevisionDevice)
            setControllerHideOnTouch(!isTelevisionDevice)
            setControllerShowTimeoutMs(4_000)
        }
        bindControllerChrome()
        configureRemoteControls()
        findViewById<View>(Media3UiR.id.exo_subtitle)?.setOnClickListener {
            openSubtitleTrackSelectionDialog()
        }
        findViewById<View>(R.id.native_audio_track_button)?.setOnClickListener {
            openAudioTrackSelectionDialog()
        }
        findViewById<View>(R.id.native_external_subtitle)?.setOnClickListener {
            openExternalSubtitlePicker()
            showControllerForRemoteFocus(ControllerFocusTarget.SETTINGS)
        }
        findViewById<View>(R.id.native_subtitle_delay)?.setOnClickListener {
            openSubtitleDelayPicker()
            showControllerForRemoteFocus(ControllerFocusTarget.SETTINGS)
        }
        findViewById<View>(R.id.native_online_subtitle_search)?.setOnClickListener {
            openOnlineSubtitleSearch()
        }
        findViewById<View>(R.id.native_playback_settings)?.setOnClickListener {
            openPlaybackSettingsDialog()
        }
        updateTelevisionControllerAutoHidePolicy()
        updatePictureInPictureParams()
        enterImmersiveMode()
    }

    override fun onStart() {
        super.onStart()
        initializePlayer()
    }

    override fun onResume() {
        super.onResume()
        enterImmersiveMode()
        restoreVideoSurfaceIfNeeded()
        playerView.onResume()
        syncPlaybackSystemSession()
        if (isTelevisionDevice && player?.isPlaying == true && !subtitleSearchActive) {
            playerView.hideController()
            playerView.requestFocus()
        }
        if (!subtitleSearchActive && resumePlaybackAfterSubtitleSearch) {
            player?.playWhenReady = true
            resumePlaybackAfterSubtitleSearch = false
        }
    }

    override fun onPause() {
        if (subtitleSearchActive) {
            hideVideoSurfaceForOverlay()
        }
        persistPlaybackProgress()
        playerView.onPause()
        super.onPause()
    }

    override fun onStop() {
        exitConfirmationDialog?.dismiss()
        exitConfirmationDialog = null
        playbackSettingsDialog?.setOnDismissListener(null)
        playbackSettingsDialog?.dismiss()
        playbackSettingsDialog = null
        trackSelectionDialog?.setOnDismissListener(null)
        trackSelectionDialog?.dismiss()
        trackSelectionDialog = null
        persistPlaybackProgress(force = true)
        if (isFinishing) {
            releasePlayer()
        }
        super.onStop()
    }

    override fun onDestroy() {
        releasePlayer()
        playbackSystemSessionManager.release()
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enterImmersiveMode()
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        enterPictureInPictureIfPossible()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            playerView.hideController()
        } else if (!subtitleSearchActive) {
            if (isTelevisionDevice && player?.isPlaying == true) {
                playerView.hideController()
                playerView.requestFocus()
            } else {
                showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) {
            if (isTelevisionDevice &&
                event.action == KeyEvent.ACTION_UP &&
                isTvSeekKeyCode(event.keyCode)
            ) {
                resetTvSeekHold(keyCode = event.keyCode)
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        when (event.keyCode) {
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_ESCAPE -> {
                resetTvSeekHold()
                if (!subtitleSearchActive && playerView.isControllerFullyVisible) {
                    pendingControllerFocusTarget = ControllerFocusTarget.PLAYER
                    playerView.hideController()
                    playerView.requestFocus()
                    return true
                }
                if (!subtitleSearchActive && isTelevisionDevice) {
                    showExitConfirmation()
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER,
            KeyEvent.KEYCODE_BUTTON_A -> {
                if (isTelevisionDevice && !playerView.isControllerFullyVisible) {
                    if (togglePlayback()) {
                        showControllerForRemoteFocus(ControllerFocusTarget.PLAYER)
                        return true
                    }
                }
            }

            KeyEvent.KEYCODE_DPAD_UP -> {
                if (isTelevisionDevice && !playerView.isControllerFullyVisible) {
                    showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_DOWN -> {
                if (isTelevisionDevice && !playerView.isControllerFullyVisible) {
                    openPlaybackSettingsDialog()
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_LEFT -> {
                if (handleTvHiddenSeek(event, direction = -1)) {
                    return true
                }
            }

            KeyEvent.KEYCODE_DPAD_RIGHT -> {
                if (handleTvHiddenSeek(event, direction = 1)) {
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_REWIND -> {
                if (seekBy(-10_000L)) {
                    resetTvSeekHold()
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                if (seekBy(10_000L)) {
                    resetTvSeekHold()
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_SPACE -> {
                if (togglePlayback()) {
                    showControllerForRemoteFocus(
                        if (isTelevisionDevice) {
                            ControllerFocusTarget.PLAYER
                        } else {
                            ControllerFocusTarget.PRIMARY
                        },
                    )
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_PLAY -> {
                if (setPlayWhenReady(true)) {
                    showControllerForRemoteFocus(
                        if (isTelevisionDevice) {
                            ControllerFocusTarget.PLAYER
                        } else {
                            ControllerFocusTarget.PRIMARY
                        },
                    )
                    return true
                }
            }

            KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                if (setPlayWhenReady(false)) {
                    showControllerForRemoteFocus(
                        if (isTelevisionDevice) {
                            ControllerFocusTarget.PLAYER
                        } else {
                            ControllerFocusTarget.PRIMARY
                        },
                    )
                    return true
                }
            }

            KeyEvent.KEYCODE_MENU,
            KeyEvent.KEYCODE_INFO,
            KeyEvent.KEYCODE_SETTINGS -> {
                openPlaybackSettingsDialog()
                return true
            }

            KeyEvent.KEYCODE_CAPTIONS -> {
                openSubtitleTrackSelectionDialog()
                return true
            }

            KeyEvent.KEYCODE_SEARCH -> {
                openOnlineSubtitleSearch()
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun showExitConfirmation() {
        val existingDialog = exitConfirmationDialog
        if (existingDialog?.isShowing == true) {
            return
        }

        exitConfirmationDialog = AlertDialog.Builder(this)
            .setTitle("退出播放")
            .setMessage("确认退出当前播放吗？")
            .setNegativeButton("继续播放", null)
            .setPositiveButton("退出") { _, _ ->
                finish()
            }
            .create()
            .apply {
                setOnDismissListener {
                    exitConfirmationDialog = null
                    if (!isFinishing) {
                        playerView.post {
                            enterImmersiveMode()
                            playerView.requestFocus()
                        }
                    }
                }
                show()
            }
    }

    private fun bindControllerChrome() {
        progressTimeBar = findViewById(Media3UiR.id.exo_progress)
        findViewById<View>(R.id.native_back)?.setOnClickListener {
            handleNavigationBack()
        }
        val primaryTitle = buildPlaybackPagePrimaryTitle()
        val secondaryTitle = buildPlaybackPageSecondaryTitle()
        findViewById<TextView?>(R.id.native_title)?.text = primaryTitle
        findViewById<TextView?>(R.id.native_title_secondary)?.apply {
            if (secondaryTitle.isBlank()) {
                text = ""
                visibility = View.GONE
            } else {
                text = secondaryTitle
                visibility = View.VISIBLE
            }
        }
        updateProgressMarkers()
    }

    private fun handleNavigationBack() {
        if (isTelevisionDevice) {
            showExitConfirmation()
        } else {
            finish()
        }
    }

    private fun isTvSeekKeyCode(keyCode: Int): Boolean {
        return keyCode == KeyEvent.KEYCODE_DPAD_LEFT ||
            keyCode == KeyEvent.KEYCODE_DPAD_RIGHT
    }

    private fun resetTvSeekHold(keyCode: Int? = null) {
        if (keyCode != null && tvSeekHoldKeyCode != keyCode) {
            return
        }
        tvSeekHoldKeyCode = null
        tvSeekHoldStartedAtMs = null
        tvSeekHoldRepeatCount = 0
    }

    private fun resolveTvSeekStepMs(
        heldForMs: Long,
        repeatCount: Int,
    ): Long {
        if (heldForMs >= 5_000L || repeatCount >= 12) {
            return 120_000L
        }
        if (heldForMs >= 3_000L || repeatCount >= 7) {
            return 60_000L
        }
        if (heldForMs >= 1_500L || repeatCount >= 3) {
            return 30_000L
        }
        return 10_000L
    }

    private fun handleTvHiddenSeek(event: KeyEvent, direction: Int): Boolean {
        if (!isTelevisionDevice || playerView.isControllerFullyVisible) {
            return false
        }
        val keyCode = event.keyCode
        if (!isTvSeekKeyCode(keyCode)) {
            return false
        }
        val nowMs = System.currentTimeMillis()
        if (tvSeekHoldKeyCode != keyCode || tvSeekHoldStartedAtMs == null) {
            tvSeekHoldKeyCode = keyCode
            tvSeekHoldStartedAtMs = nowMs
            tvSeekHoldRepeatCount = 0
        } else if (event.repeatCount > 0) {
            tvSeekHoldRepeatCount = maxOf(tvSeekHoldRepeatCount, event.repeatCount)
        }
        val heldForMs = nowMs - (tvSeekHoldStartedAtMs ?: nowMs)
        val stepMs = resolveTvSeekStepMs(
            heldForMs = heldForMs,
            repeatCount = tvSeekHoldRepeatCount,
        )
        return seekBy(stepMs * direction.toLong())
    }

    private fun buildPlaybackPagePrimaryTitle(): String {
        val targetObject = decodePlaybackTargetObject()
        val title = intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        val itemType = targetObject.optString("itemType").trim().lowercase()
        return when {
            itemType == "episode" && seriesTitle.isNotEmpty() -> seriesTitle
            title.isNotEmpty() -> title
            else -> "Starflow"
        }
    }

    private fun buildPlaybackPageSecondaryTitle(): String {
        val targetObject = decodePlaybackTargetObject()
        val title = intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        val itemType = targetObject.optString("itemType").trim().lowercase()
        val seasonNumber = targetObject.optInt("seasonNumber", 0)
        val episodeNumber = targetObject.optInt("episodeNumber", 0)
        val primaryTitle = buildPlaybackPagePrimaryTitle()
        val parts = mutableListOf<String>()
        if (title.isNotEmpty() && title != primaryTitle) {
            parts += title
        }
        if (itemType == "episode" && seasonNumber > 0 && episodeNumber > 0) {
            parts += "S${seasonNumber.toString().padStart(2, '0')}" +
                "E${episodeNumber.toString().padStart(2, '0')}"
        }
        val subtitle = buildSystemSessionSubtitle()
        if (subtitle.isNotEmpty()) {
            parts += subtitle
        }
        return parts.joinToString(" · ")
    }

    private fun isOverlayDialogVisible(): Boolean {
        return playbackSettingsDialog?.isShowing == true ||
            trackSelectionDialog?.isShowing == true
    }

    private fun updateTelevisionControllerAutoHidePolicy() {
        if (!isTelevisionDevice) {
            return
        }
        val currentPlayer = player
        val shouldAutoHide = currentPlayer?.isPlaying == true
        playerView.setControllerShowTimeoutMs(if (shouldAutoHide) 4_000 else 0)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_EXTERNAL_SUBTITLE) {
            if (resultCode != RESULT_OK) {
                return
            }
            val subtitleUri = data?.data ?: return
            loadExternalSubtitle(subtitleUri, data.flags)
            return
        }
        if (requestCode == REQUEST_CODE_SUBTITLE_SEARCH) {
            handleSubtitleSearchResult(resultCode, data)
        }
    }

    private fun initializePlayer() {
        if (player != null) {
            return
        }

        val url = intent.getStringExtra(EXTRA_URL)?.trim().orEmpty()
        if (url.isEmpty()) {
            finish()
            return
        }
        val title = intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        val headersJson = intent.getStringExtra(EXTRA_HEADERS_JSON)?.trim().orEmpty()
        val targetObject = decodePlaybackTargetObject()
        logPlayback(
            "native.initialize.begin " +
                "url=${summarizeUrl(url)} " +
                "actual=${summarizeUrl(targetObject.optString("actualAddress").trim())} " +
                "source=${targetObject.optString("sourceName").trim()} " +
                "container=${targetObject.optString("container").trim()} " +
                "headers=${summarizeHeaderKeys(headersJson)}",
        )
        val decodeMode = PlaybackDecodeMode.fromRaw(
            intent.getStringExtra(EXTRA_DECODE_MODE)?.trim().orEmpty(),
        )
        val guessedMimeType = guessVideoMimeType(targetObject, url).takeIf { it != "-" }

        restoredResumePositionMs = loadResumePositionMs()

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setUserAgent("Starflow")

        if (headersJson.isNotEmpty()) {
            try {
                val json = JSONObject(headersJson)
                val headers = mutableMapOf<String, String>()
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    headers[key] = json.optString(key)
                }
                dataSourceFactory.setDefaultRequestProperties(headers)
            } catch (error: Throwable) {
                logPlayback("native.initialize.headers-parse-failed", error)
            }
        }

        val renderersFactory = DefaultRenderersFactory(this).apply {
            setEnableDecoderFallback(true)
            when (decodeMode) {
                PlaybackDecodeMode.AUTO -> Unit
                PlaybackDecodeMode.HARDWARE_PREFERRED -> {
                    setMediaCodecSelector(buildMediaCodecSelector(preferSoftware = false))
                }

                PlaybackDecodeMode.SOFTWARE_PREFERRED -> {
                    setMediaCodecSelector(buildMediaCodecSelector(preferSoftware = true))
                }
            }
        }

        val exoPlayer = ExoPlayer.Builder(this)
            .setRenderersFactory(renderersFactory)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .build()
        val initialMediaItemBuilder = MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(title.ifEmpty { null })
                    .build(),
            )
        if (guessedMimeType != null) {
            initialMediaItemBuilder.setMimeType(guessedMimeType)
        }
        val initialMediaItem = initialMediaItemBuilder.build()
        logPlayback(
            "native.initialize.media-item " +
                "resumeMs=$restoredResumePositionMs " +
                "decodeMode=$decodeMode " +
                "mimeGuess=${guessedMimeType ?: "-"}",
        )
        baseMediaItem = initialMediaItem

        exoPlayer.apply {
            playWhenReady = nextInitializePlayWhenReady ?: true
            nextInitializePlayWhenReady = null
            repeatMode = Player.REPEAT_MODE_OFF
            setMediaItem(initialMediaItem)
            if (restoredResumePositionMs > 5_000L) {
                seekTo(restoredResumePositionMs)
            }
            prepare()
        }
        exoPlayer.addListener(playerListener)
        logPlayback("native.initialize.prepare-called playWhenReady=${exoPlayer.playWhenReady}")

        player = exoPlayer
        playerView.player = exoPlayer
        playbackSystemSessionManager.setActive(true)
        if (externalSubtitleSource != null) {
            applyExternalSubtitleConfiguration(showFeedback = false)
        }
        syncPlaybackSystemSession()
        if (isTelevisionDevice && exoPlayer.playWhenReady) {
            playerView.hideController()
            playerView.requestFocus()
        } else {
            showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        }
        if (restoredResumePositionMs > 5_000L) {
            showToast("已从 ${formatClockDuration(restoredResumePositionMs)} 继续播放")
        }
    }

    private fun buildMediaCodecSelector(preferSoftware: Boolean): MediaCodecSelector {
        return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            val allInfos = MediaCodecUtil.getDecoderInfos(
                mimeType,
                requiresSecureDecoder,
                requiresTunnelingDecoder,
            )
            val preferredInfos = allInfos.filter { info -> info.softwareOnly == preferSoftware }
            if (preferredInfos.isNotEmpty()) {
                preferredInfos
            } else {
                allInfos
            }
        }
    }

    private fun releasePlayer() {
        playerView.player = null
        player?.removeListener(playerListener)
        player?.release()
        player = null
        playbackSystemSessionManager.setActive(false)
    }

    private fun syncPlaybackSystemSession() {
        val currentPlayer = player ?: return
        val state = PlaybackSystemSessionState(
            title = buildSystemSessionTitle(),
            subtitle = buildSystemSessionSubtitle(),
            positionMs = currentPlayer.currentPosition.coerceAtLeast(0L),
            durationMs = currentPlayer.duration.takeIf { it > 0L } ?: 0L,
            playing = currentPlayer.isPlaying,
            buffering = currentPlayer.playbackState == Player.STATE_BUFFERING,
            speed = currentPlayer.playbackParameters.speed,
            canSeek = true,
        )
        playbackSystemSessionManager.update(state)
    }

    private fun handlePlaybackSystemCommand(command: String, positionMs: Long?) {
        when (command) {
            "play" -> setPlayWhenReady(true)
            "pause",
            "stop",
            "becomingNoisy",
            "interruptionPause" -> {
                setPlayWhenReady(false)
                persistPlaybackProgress(force = true)
            }
            "toggle" -> togglePlayback()
            "seekForward",
            "next" -> seekBy(10_000L)
            "seekBackward",
            "previous" -> seekBy(-10_000L)
            "seekTo" -> {
                val currentPlayer = player ?: return
                currentPlayer.seekTo((positionMs ?: 0L).coerceAtLeast(0L))
                syncPlaybackSystemSession()
            }
            "interruptionResume" -> setPlayWhenReady(true)
        }
    }

    private fun buildSystemSessionTitle(): String {
        val title = intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        val targetObject = try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
        val seasonNumber = targetObject.optInt("seasonNumber", 0)
        val episodeNumber = targetObject.optInt("episodeNumber", 0)
        if (seasonNumber > 0 && episodeNumber > 0 && title.isNotEmpty()) {
            return "$title · S${seasonNumber.toString().padStart(2, '0')}" +
                "E${episodeNumber.toString().padStart(2, '0')}"
        }
        return if (title.isEmpty()) "Starflow" else title
    }

    private fun buildSystemSessionSubtitle(): String {
        val targetObject = try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
        val itemType = targetObject.optString("itemType").trim().lowercase()
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        if (itemType == "episode" && seriesTitle.isNotEmpty()) {
            return seriesTitle
        }
        val sourceName = targetObject.optString("sourceName").trim()
        val formatParts = buildList {
            val container = targetObject.optString("container").trim()
            val videoCodec = targetObject.optString("videoCodec").trim()
            val audioCodec = targetObject.optString("audioCodec").trim()
            if (sourceName.isNotEmpty()) {
                add(sourceName)
            }
            if (container.isNotEmpty()) {
                add(container.uppercase())
            }
            if (videoCodec.isNotEmpty()) {
                add(videoCodec.uppercase())
            }
            if (audioCodec.isNotEmpty()) {
                add(audioCodec.uppercase())
            }
        }
        return formatParts.joinToString(" · ")
    }

    private fun buildPlaybackContentIntent(): PendingIntent? {
        val activityIntent = Intent(this, NativePlaybackActivity::class.java).apply {
            replaceExtras(intent)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        return PendingIntent.getActivity(this, 0, activityIntent, flags)
    }

    private fun updatePictureInPictureParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        setPictureInPictureParams(
            PictureInPictureParams.Builder()
                .setAspectRatio(buildPictureInPictureAspectRatio())
                .build(),
        )
    }

    private fun enterPictureInPictureIfPossible() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || isTelevisionDevice) {
            return
        }
        val currentPlayer = player ?: return
        if (!currentPlayer.isPlaying || isInPictureInPictureMode) {
            return
        }
        updatePictureInPictureParams()
        enterPictureInPictureMode(
            PictureInPictureParams.Builder()
                .setAspectRatio(buildPictureInPictureAspectRatio())
                .build(),
        )
    }

    private fun buildPictureInPictureAspectRatio(): Rational {
        val currentPlayer = player
        val videoSize = currentPlayer?.videoSize
        val width = videoSize?.width ?: 0
        val height = videoSize?.height ?: 0
        return if (width > 0 && height > 0) {
            Rational(width, height)
        } else {
            Rational(16, 9)
        }
    }

    private fun openExternalSubtitlePicker() {
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/x-subrip",
                        "text/plain",
                        "text/vtt",
                        "text/x-ssa",
                        "application/ssa",
                        "application/ass",
                    ),
                )
            }
            startActivityForResult(intent, REQUEST_CODE_EXTERNAL_SUBTITLE)
        } catch (_: Throwable) {
            showToast("无法打开字幕文件选择器")
        }
    }

    private fun openSubtitleDelayPicker() {
        if (externalSubtitleSource == null) {
            showToast("当前仅支持外挂字幕偏移")
            return
        }
        val labels = SUBTITLE_DELAY_OPTIONS_MS.map { formatSubtitleDelayLabel(it) }.toTypedArray()
        val currentIndex = SUBTITLE_DELAY_OPTIONS_MS.indexOf(subtitleDelayMs).coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle("字幕偏移")
            .setSingleChoiceItems(labels, currentIndex) { dialog, which ->
                subtitleDelayMs = SUBTITLE_DELAY_OPTIONS_MS[which]
                dialog.dismiss()
                applyExternalSubtitleConfiguration()
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun openPlaybackSettingsDialog() {
        if (subtitleSearchActive) {
            return
        }
        if (playbackSettingsDialog?.isShowing == true) {
            return
        }

        val currentPlayer = player
        val actions = mutableListOf<Pair<String, () -> Unit>>()
        actions +=
            "${getString(R.string.native_playback_speed)} · " +
                formatPlaybackSpeedLabel(currentPlayer?.playbackParameters?.speed ?: 1f) to
                { openPlaybackSpeedPicker() }
        actions += getString(R.string.native_audio_track) to { openAudioTrackSelectionDialog() }
        actions += getString(R.string.native_subtitle_track) to { openSubtitleTrackSelectionDialog() }
        actions += getString(R.string.native_online_subtitle_search) to { openOnlineSubtitleSearch() }
        actions += getString(R.string.native_external_subtitle) to { openExternalSubtitlePicker() }
        actions +=
            "${getString(R.string.native_subtitle_delay)} · ${formatSubtitleDelayLabel(subtitleDelayMs)}" to
                { openSubtitleDelayPicker() }

        playbackSettingsDialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.native_playback_settings))
            .setItems(actions.map { it.first }.toTypedArray()) { dialog, which ->
                dialog.dismiss()
                playerView.post { actions[which].second.invoke() }
            }
            .setNegativeButton("关闭", null)
            .create()
            .apply {
                setOnDismissListener {
                    playbackSettingsDialog = null
                    restoreControllerFocusIfNeeded(ControllerFocusTarget.SETTINGS)
                }
                show()
            }
    }

    private fun openPlaybackSpeedPicker() {
        val currentPlayer = player ?: return
        val speeds = PLAYBACK_SPEED_OPTIONS
        val currentSpeed = currentPlayer.playbackParameters.speed
        val currentIndex = speeds
            .withIndex()
            .minByOrNull { (_, value) -> kotlin.math.abs(value - currentSpeed) }
            ?.index ?: 0
        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.native_playback_speed))
            .setSingleChoiceItems(
                speeds.map(::formatPlaybackSpeedLabel).toTypedArray(),
                currentIndex,
            ) { pickerDialog, which ->
                currentPlayer.playbackParameters =
                    currentPlayer.playbackParameters.withSpeed(speeds[which])
                syncPlaybackSystemSession()
                pickerDialog.dismiss()
                restoreControllerFocusIfNeeded(ControllerFocusTarget.SETTINGS)
            }
            .setNegativeButton("取消", null)
            .create()
        showTransientDialog(dialog, ControllerFocusTarget.SETTINGS)
    }

    private fun openAudioTrackSelectionDialog() {
        openTrackSelectionDialog(
            title = getString(R.string.native_audio_track),
            trackType = C.TRACK_TYPE_AUDIO,
            showDisableOption = false,
            emptyMessage = getString(R.string.native_no_audio_tracks),
            focusTarget = ControllerFocusTarget.AUDIO,
        )
    }

    private fun openSubtitleTrackSelectionDialog() {
        openTrackSelectionDialog(
            title = getString(R.string.native_subtitle_track),
            trackType = C.TRACK_TYPE_TEXT,
            showDisableOption = true,
            emptyMessage = getString(R.string.native_no_subtitle_tracks),
            focusTarget = ControllerFocusTarget.SUBTITLE,
        )
    }

    private fun openTrackSelectionDialog(
        title: String,
        trackType: Int,
        showDisableOption: Boolean,
        emptyMessage: String,
        focusTarget: ControllerFocusTarget,
    ) {
        val currentPlayer = player ?: return
        if (!currentPlayer.currentTracks.containsType(trackType)) {
            showToast(emptyMessage)
            restoreControllerFocusIfNeeded(focusTarget)
            return
        }
        val dialog = TrackSelectionDialogBuilder(this, title, currentPlayer, trackType)
            .setShowDisableOption(showDisableOption)
            .build()
        showTransientDialog(dialog, focusTarget)
    }

    private fun showTransientDialog(dialog: Dialog, focusTarget: ControllerFocusTarget) {
        trackSelectionDialog?.dismiss()
        trackSelectionDialog = dialog
        dialog.setOnDismissListener {
            if (trackSelectionDialog === dialog) {
                trackSelectionDialog = null
            }
            restoreControllerFocusIfNeeded(focusTarget)
        }
        dialog.show()
    }

    private fun restoreControllerFocusIfNeeded(target: ControllerFocusTarget) {
        if (isFinishing || subtitleSearchActive) {
            return
        }
        playerView.post {
            enterImmersiveMode()
            showControllerForRemoteFocus(target)
        }
    }

    private fun formatPlaybackSpeedLabel(value: Float): String {
        val normalized = if (value == value.toInt().toFloat()) {
            "${value.toInt()}.0"
        } else {
            String.format(Locale.US, "%.2f", value).trimEnd('0').trimEnd('.')
        }
        return "${normalized}x"
    }

    private fun openOnlineSubtitleSearch() {
        val query = buildSubtitleSearchQuery()
        if (query.isBlank()) {
            showToast("缺少片名信息，暂时无法搜索字幕")
            return
        }

        val currentPlayer = player
        resumePlaybackAfterSubtitleSearch = currentPlayer?.playWhenReady == true
        nextInitializePlayWhenReady = currentPlayer?.playWhenReady
        subtitleSearchActive = true
        currentPlayer?.playWhenReady = false
        hideVideoSurfaceForOverlay()

        try {
            startActivityForResult(
                FlutterActivity.NewEngineIntentBuilder(SubtitleSearchActivity::class.java)
                    .initialRoute(buildSubtitleSearchRoute(query))
                    .backgroundMode(FlutterActivityLaunchConfigs.BackgroundMode.opaque)
                    .build(this),
                REQUEST_CODE_SUBTITLE_SEARCH,
            )
        } catch (_: Throwable) {
            subtitleSearchActive = false
            restoreVideoSurfaceIfNeeded()
            if (resumePlaybackAfterSubtitleSearch) {
                currentPlayer?.playWhenReady = true
                resumePlaybackAfterSubtitleSearch = false
            }
            nextInitializePlayWhenReady = null
            showToast("打开字幕搜索失败")
        }
    }

    private fun buildSubtitleSearchQuery(): String {
        val targetObject = try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        val title = targetObject.optString("title").trim()
        val itemType = targetObject.optString("itemType").trim().lowercase()
        val seasonNumber = targetObject.optInt("seasonNumber", 0)
        val episodeNumber = targetObject.optInt("episodeNumber", 0)
        val year = targetObject.optInt("year", 0)

        val parts = mutableListOf<String>()
        val baseTitle = if (seriesTitle.isNotEmpty()) seriesTitle else title
        if (baseTitle.isNotEmpty()) {
            parts += baseTitle
        }
        if (seasonNumber > 0 && episodeNumber > 0) {
            parts += "S${seasonNumber.toString().padStart(2, '0')}E${episodeNumber.toString().padStart(2, '0')}"
        }
        if (itemType != "episode" && year > 0) {
            parts += year.toString()
        }
        return parts.joinToString(" ").trim()
    }

    private fun buildSubtitleSearchRoute(query: String): String {
        val title = buildSubtitleSearchTitle()
        return Uri.Builder()
            .path("/subtitle-search")
            .appendQueryParameter("q", query)
            .appendQueryParameter("title", title)
            .appendQueryParameter("input", title.ifBlank { query })
            .appendQueryParameter("mode", "downloadAndApply")
            .appendQueryParameter("standalone", "1")
            .build()
            .toString()
    }

    private fun buildSubtitleSearchTitle(): String {
        val targetObject = try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
        val seriesTitle = targetObject.optString("seriesTitle").trim()
        val title = targetObject.optString("title").trim()
        return if (seriesTitle.isNotEmpty()) seriesTitle else title
    }

    private fun handleSubtitleSearchResult(resultCode: Int, data: Intent?) {
        subtitleSearchActive = false
        restoreVideoSurfaceIfNeeded()
        val shouldResumePlayback = resumePlaybackAfterSubtitleSearch
        resumePlaybackAfterSubtitleSearch = false
        if (resultCode != RESULT_OK || data == null) {
            if (shouldResumePlayback) {
                player?.playWhenReady = true
            }
            return
        }

        val subtitleFilePath = data.getStringExtra(SubtitleSearchActivity.RESULT_SUBTITLE_FILE_PATH)
            ?.trim()
            .orEmpty()
        val displayName = data.getStringExtra(SubtitleSearchActivity.RESULT_DISPLAY_NAME)
            ?.trim()
            .orEmpty()
        if (subtitleFilePath.isNotEmpty()) {
            loadCachedSubtitleFile(subtitleFilePath, displayName)
            if (shouldResumePlayback) {
                player?.playWhenReady = true
            }
            return
        }

        val cachedPath = data.getStringExtra(SubtitleSearchActivity.RESULT_CACHED_PATH)
            ?.trim()
            .orEmpty()
        if (cachedPath.isNotEmpty()) {
            showToast("字幕已下载到缓存，但当前结果暂不能直接挂载")
        }
        if (shouldResumePlayback) {
            player?.playWhenReady = true
        }
    }

    private fun hideVideoSurfaceForOverlay() {
        playerView.hideController()
        playerView.visibility = View.INVISIBLE
        playerView.videoSurfaceView?.visibility = View.INVISIBLE
    }

    private fun restoreVideoSurfaceIfNeeded() {
        playerView.visibility = View.VISIBLE
        playerView.videoSurfaceView?.visibility = View.VISIBLE
        if (isTelevisionDevice && player?.playWhenReady == true) {
            playerView.hideController()
            playerView.requestFocus()
        } else {
            showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        }
    }

    private fun loadExternalSubtitle(uri: Uri, intentFlags: Int) {
        val mimeType = resolveSubtitleMimeType(uri)
        if (mimeType == null) {
            showToast("暂不支持该字幕格式")
            return
        }

        val takeFlags = intentFlags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        if (takeFlags != 0) {
            try {
                contentResolver.takePersistableUriPermission(uri, takeFlags)
            } catch (_: SecurityException) {
            } catch (_: Throwable) {
            }
        }

        externalSubtitleSource = ExternalSubtitleSource(
            originalUri = uri,
            mimeType = mimeType,
            displayName = resolveDisplayName(uri),
        )
        applyExternalSubtitleConfiguration()
    }

    private fun restoreExternalSubtitleSourceFromTarget() {
        val targetObject = try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
        val subtitleFilePath = targetObject.optString("externalSubtitleFilePath").trim()
        if (subtitleFilePath.isEmpty()) {
            return
        }
        val displayName = targetObject.optString("externalSubtitleDisplayName").trim()
        prepareCachedSubtitleFile(subtitleFilePath, displayName)
    }

    private fun loadCachedSubtitleFile(filePath: String, displayName: String) {
        if (!prepareCachedSubtitleFile(filePath, displayName)) {
            showToast("缓存字幕文件不存在")
            return
        }
        applyExternalSubtitleConfiguration()
    }

    private fun prepareCachedSubtitleFile(filePath: String, displayName: String): Boolean {
        val file = File(filePath)
        if (!file.exists() || !file.isFile) {
            return false
        }

        val uri = Uri.fromFile(file)
        val mimeType = resolveSubtitleMimeType(uri)
        if (mimeType == null) {
            return false
        }

        externalSubtitleSource = ExternalSubtitleSource(
            originalUri = uri,
            mimeType = mimeType,
            displayName = displayName.ifBlank { file.name },
        )
        return true
    }

    private fun applyExternalSubtitleConfiguration(showFeedback: Boolean = true) {
        val currentPlayer = player ?: return
        val source = externalSubtitleSource ?: return
        val sourceMediaItem = baseMediaItem ?: currentPlayer.currentMediaItem ?: return
        val currentPosition = currentPlayer.currentPosition
        val shouldResumePlayback = currentPlayer.playWhenReady
        val configuration = try {
            buildSubtitleConfiguration(source)
        } catch (_: Throwable) {
            showToast("字幕处理失败，已保留当前播放")
            return
        }

        val updatedMediaItem = sourceMediaItem.buildUpon()
            .setSubtitleConfigurations(listOf(configuration))
            .build()
        currentPlayer.setMediaItem(updatedMediaItem, currentPosition)
        currentPlayer.prepare()
        currentPlayer.playWhenReady = shouldResumePlayback
        if (showFeedback) {
            showToast(
                if (subtitleDelayMs == 0L) {
                    "外挂字幕已加载"
                } else {
                    "外挂字幕已加载，偏移 ${formatSubtitleDelayLabel(subtitleDelayMs)}"
                },
            )
        }
        showControllerForRemoteFocus(ControllerFocusTarget.SETTINGS)
    }

    private fun configureRemoteControls() {
        playerView.isFocusable = true
        playerView.isFocusableInTouchMode = true
        playerView.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        playerView.setOnClickListener {
            showControllerForRemoteFocus(ControllerFocusTarget.PRIMARY)
        }
        playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                if (visibility == View.VISIBLE) {
                    applyPendingControllerFocus()
                    updateProgressMarkers()
                } else if (isTelevisionDevice && !isOverlayDialogVisible()) {
                    playerView.requestFocus()
                }
            },
        )
        configureFocusability(
            intArrayOf(
                R.id.native_back,
                Media3UiR.id.exo_rew,
                Media3UiR.id.exo_play_pause,
                Media3UiR.id.exo_ffwd,
                Media3UiR.id.exo_subtitle,
                R.id.native_audio_track_button,
                R.id.native_subtitle_delay,
                R.id.native_external_subtitle,
                R.id.native_online_subtitle_search,
                R.id.native_playback_settings,
            ),
        )
        configureHorizontalFocusChain(
            intArrayOf(
                Media3UiR.id.exo_rew,
                Media3UiR.id.exo_play_pause,
                Media3UiR.id.exo_ffwd,
            ),
        )
        configureHorizontalFocusChain(
            if (isTelevisionDevice) {
                intArrayOf(
                    Media3UiR.id.exo_subtitle,
                    R.id.native_audio_track_button,
                    R.id.native_playback_settings,
                )
            } else {
                intArrayOf(
                    Media3UiR.id.exo_subtitle,
                    R.id.native_online_subtitle_search,
                    R.id.native_external_subtitle,
                    R.id.native_subtitle_delay,
                    R.id.native_playback_settings,
                )
            },
        )
        configureHorizontalFocusChain(intArrayOf(R.id.native_back))
        if (isTelevisionDevice) {
            configureVerticalFocusLink(R.id.native_back, downId = Media3UiR.id.exo_play_pause)
            configureVerticalFocusLink(
                Media3UiR.id.exo_rew,
                upId = R.id.native_back,
                downId = Media3UiR.id.exo_subtitle,
            )
            configureVerticalFocusLink(
                Media3UiR.id.exo_play_pause,
                upId = R.id.native_back,
                downId = R.id.native_audio_track_button,
            )
            configureVerticalFocusLink(
                Media3UiR.id.exo_ffwd,
                upId = R.id.native_back,
                downId = R.id.native_playback_settings,
            )
            configureVerticalFocusLink(
                Media3UiR.id.exo_subtitle,
                upId = Media3UiR.id.exo_play_pause,
            )
            configureVerticalFocusLink(
                R.id.native_audio_track_button,
                upId = Media3UiR.id.exo_play_pause,
            )
            configureVerticalFocusLink(
                R.id.native_playback_settings,
                upId = Media3UiR.id.exo_ffwd,
            )
            playerView.requestFocus()
        }
    }

    private fun configureFocusability(ids: IntArray) {
        ids.forEach { id ->
            findViewById<View?>(id)?.apply {
                isFocusable = true
                isFocusableInTouchMode = true
            }
        }
    }

    private fun configureHorizontalFocusChain(ids: IntArray) {
        val views = ids
            .map { id -> findViewById<View?>(id) }
            .filterNotNull()
            .filter { view -> view.id != View.NO_ID }
        views.forEachIndexed { index, view ->
            view.nextFocusLeftId =
                views.getOrNull(index - 1)?.id ?: views.lastOrNull()?.id ?: view.id
            view.nextFocusRightId =
                views.getOrNull(index + 1)?.id ?: views.firstOrNull()?.id ?: view.id
        }
    }

    private fun configureVerticalFocusLink(
        viewId: Int,
        upId: Int? = null,
        downId: Int? = null,
    ) {
        val view = findViewById<View?>(viewId) ?: return
        if (upId != null && findViewById<View?>(upId) != null) {
            view.nextFocusUpId = upId
        }
        if (downId != null && findViewById<View?>(downId) != null) {
            view.nextFocusDownId = downId
        }
    }

    private fun updateProgressMarkers() {
        val timeBar = progressTimeBar ?: findViewById<DefaultTimeBar?>(Media3UiR.id.exo_progress)
            ?.also { progressTimeBar = it } ?: return
        val durationMs = player?.duration?.takeIf { it > 0L } ?: 0L
        if (durationMs <= 0L) {
            timeBar.setAdGroupTimesMs(longArrayOf(), booleanArrayOf(), 0)
            return
        }
        val markers = buildPlaybackMarkerPositionsMs(durationMs)
        timeBar.setAdGroupTimesMs(markers, BooleanArray(markers.size), markers.size)
    }

    private fun buildPlaybackMarkerPositionsMs(durationMs: Long): LongArray {
        val markers = linkedSetOf<Long>()
        val skipPreference = loadSeriesSkipPreference()
        if (skipPreference?.optBoolean("enabled", false) == true) {
            addMarkerIfInRange(
                markers,
                skipPreference.optLong("introDurationMs", 0L),
                durationMs,
            )
            val outroDurationMs = skipPreference.optLong("outroDurationMs", 0L)
            if (outroDurationMs > 0L && outroDurationMs < durationMs) {
                addMarkerIfInRange(markers, durationMs - outroDurationMs, durationMs)
            }
        }
        collectChapterMarkers(decodePlaybackTargetObject(), durationMs, markers)
        return markers.sorted().toLongArray()
    }

    private fun loadSeriesSkipPreference(): JSONObject? {
        if (seriesKey.isBlank()) {
            return null
        }
        return loadPlaybackSnapshot()
            .optJSONObject("skipPreferences")
            ?.optJSONObject(seriesKey)
    }

    private fun collectChapterMarkers(
        targetObject: JSONObject,
        durationMs: Long,
        markers: MutableSet<Long>,
    ) {
        listOf(
            "chapterTimesMs",
            "chapterPositionsMs",
            "chapterStartTimesMs",
            "chapterMarkersMs",
        ).forEach { key ->
            appendMarkersFromArray(targetObject.optJSONArray(key), durationMs, markers)
        }
        val chapters = targetObject.optJSONArray("chapters") ?: return
        for (index in 0 until chapters.length()) {
            addMarkerIfInRange(
                markers,
                extractMarkerTimeMs(chapters.opt(index)),
                durationMs,
            )
        }
    }

    private fun appendMarkersFromArray(
        array: org.json.JSONArray?,
        durationMs: Long,
        markers: MutableSet<Long>,
    ) {
        if (array == null) {
            return
        }
        for (index in 0 until array.length()) {
            addMarkerIfInRange(markers, extractMarkerTimeMs(array.opt(index)), durationMs)
        }
    }

    private fun extractMarkerTimeMs(value: Any?): Long {
        return when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            is JSONObject -> {
                listOf(
                    "startPositionMs",
                    "startMs",
                    "positionMs",
                    "timeMs",
                ).forEach { key ->
                    val candidate = value.optLong(key, Long.MIN_VALUE)
                    if (candidate != Long.MIN_VALUE) {
                        return candidate
                    }
                }
                listOf("startSeconds", "positionSeconds", "timeSeconds").forEach { key ->
                    val candidate = value.optLong(key, Long.MIN_VALUE)
                    if (candidate != Long.MIN_VALUE) {
                        return candidate * 1000L
                    }
                }
                0L
            }
            else -> 0L
        }
    }

    private fun addMarkerIfInRange(
        markers: MutableSet<Long>,
        markerTimeMs: Long,
        durationMs: Long,
    ) {
        if (markerTimeMs > 0L && markerTimeMs < durationMs) {
            markers += markerTimeMs
        }
    }

    private fun showControllerForRemoteFocus(target: ControllerFocusTarget) {
        pendingControllerFocusTarget = target
        playerView.showController()
        if (isTelevisionDevice) {
            playerView.post { applyPendingControllerFocus() }
        }
    }

    private fun applyPendingControllerFocus() {
        if (!isTelevisionDevice) {
            pendingControllerFocusTarget = ControllerFocusTarget.NONE
            return
        }
        if (pendingControllerFocusTarget == ControllerFocusTarget.NONE) {
            return
        }
        if (!playerView.isControllerFullyVisible &&
            pendingControllerFocusTarget != ControllerFocusTarget.PLAYER
        ) {
            playerView.post { applyPendingControllerFocus() }
            return
        }

        val handled = when (pendingControllerFocusTarget) {
            ControllerFocusTarget.NONE -> false
            ControllerFocusTarget.PLAYER -> playerView.requestFocus()
            ControllerFocusTarget.PRIMARY -> requestFocusForAny(
                if (isTelevisionDevice) {
                    intArrayOf(
                        Media3UiR.id.exo_play_pause,
                        Media3UiR.id.exo_ffwd,
                        Media3UiR.id.exo_rew,
                        R.id.native_playback_settings,
                        Media3UiR.id.exo_subtitle,
                        R.id.native_back,
                    )
                } else {
                    intArrayOf(
                        Media3UiR.id.exo_play_pause,
                        Media3UiR.id.exo_ffwd,
                        Media3UiR.id.exo_rew,
                        R.id.native_playback_settings,
                    )
                },
            )

            ControllerFocusTarget.SETTINGS -> requestFocusForAny(
                if (isTelevisionDevice) {
                    intArrayOf(
                        R.id.native_playback_settings,
                        R.id.native_audio_track_button,
                        Media3UiR.id.exo_subtitle,
                        Media3UiR.id.exo_play_pause,
                        R.id.native_back,
                    )
                } else {
                    intArrayOf(
                        R.id.native_playback_settings,
                        R.id.native_online_subtitle_search,
                        R.id.native_external_subtitle,
                        Media3UiR.id.exo_subtitle,
                        Media3UiR.id.exo_play_pause,
                    )
                },
            )

            ControllerFocusTarget.AUDIO -> requestFocusForAny(
                if (isTelevisionDevice) {
                    intArrayOf(
                        R.id.native_audio_track_button,
                        R.id.native_playback_settings,
                        Media3UiR.id.exo_subtitle,
                        Media3UiR.id.exo_play_pause,
                    )
                } else {
                    intArrayOf(
                        R.id.native_playback_settings,
                        Media3UiR.id.exo_subtitle,
                        Media3UiR.id.exo_play_pause,
                    )
                },
            )

            ControllerFocusTarget.SUBTITLE -> requestFocusForAny(
                if (isTelevisionDevice) {
                    intArrayOf(
                        Media3UiR.id.exo_subtitle,
                        R.id.native_audio_track_button,
                        R.id.native_playback_settings,
                        Media3UiR.id.exo_play_pause,
                    )
                } else {
                    intArrayOf(
                        Media3UiR.id.exo_subtitle,
                        R.id.native_online_subtitle_search,
                        R.id.native_external_subtitle,
                        R.id.native_subtitle_delay,
                        R.id.native_playback_settings,
                    )
                },
            )
        }
        if (!handled) {
            playerView.requestFocus()
        }
        pendingControllerFocusTarget = ControllerFocusTarget.NONE
    }

    private fun requestFocusForAny(ids: IntArray): Boolean {
        ids.forEach { id ->
            val view = findViewById<View?>(id) ?: return@forEach
            if (!view.isShown || !view.isEnabled || !view.isFocusable) {
                return@forEach
            }
            if (view.requestFocus()) {
                return true
            }
        }
        return false
    }

    private fun seekBy(deltaMs: Long): Boolean {
        val currentPlayer = player ?: return false
        val durationMs = currentPlayer.duration.takeIf { it > 0L } ?: 0L
        val currentPositionMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        val nextPositionMs = if (durationMs > 0L) {
            (currentPositionMs + deltaMs).coerceIn(0L, durationMs)
        } else {
            (currentPositionMs + deltaMs).coerceAtLeast(0L)
        }
        if (nextPositionMs == currentPositionMs) {
            return false
        }
        currentPlayer.seekTo(nextPositionMs)
        showControllerForRemoteFocus(ControllerFocusTarget.PLAYER)
        return true
    }

    private fun togglePlayback(): Boolean {
        val currentPlayer = player ?: return false
        return setPlayWhenReady(!currentPlayer.playWhenReady)
    }

    private fun setPlayWhenReady(playWhenReady: Boolean): Boolean {
        val currentPlayer = player ?: return false
        currentPlayer.playWhenReady = playWhenReady
        return true
    }

    private fun buildSubtitleConfiguration(source: ExternalSubtitleSource): MediaItem.SubtitleConfiguration {
        val effectiveUri = if (subtitleDelayMs == 0L) {
            source.originalUri
        } else {
            buildShiftedSubtitleFile(source, subtitleDelayMs)
        }
        return MediaItem.SubtitleConfiguration.Builder(effectiveUri)
            .setMimeType(source.mimeType)
            .setLanguage(C.LANGUAGE_UNDETERMINED)
            .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
            .setLabel(
                if (subtitleDelayMs == 0L) {
                    source.displayName
                } else {
                    "${source.displayName} (${formatSubtitleDelayLabel(subtitleDelayMs)})"
                },
            )
            .setId("external:${source.originalUri}:$subtitleDelayMs")
            .build()
    }

    private fun buildShiftedSubtitleFile(source: ExternalSubtitleSource, delayMs: Long): Uri {
        val subtitleDirectory = File(cacheDir, "native_subtitles").apply { mkdirs() }
        val extension = resolveSubtitleExtension(source)
        val outputFile = File(
            subtitleDirectory,
            "shifted_${source.displayName.hashCode()}_${delayMs}.$extension",
        )
        val originalContent = openSubtitleInputStream(source.originalUri)
            ?.bufferedReader(StandardCharsets.UTF_8)
            ?.use { it.readText() }
            ?: throw IllegalStateException("字幕文件读取失败")
        val shiftedContent = shiftSubtitleContent(
            content = originalContent,
            mimeType = source.mimeType,
            delayMs = delayMs,
        )
        outputFile.writeText(shiftedContent, StandardCharsets.UTF_8)
        return Uri.fromFile(outputFile)
    }

    private fun openSubtitleInputStream(uri: Uri) = when (uri.scheme?.lowercase()) {
        "file" -> {
            val path = uri.path?.trim().orEmpty()
            if (path.isEmpty()) {
                null
            } else {
                File(path).inputStream()
            }
        }

        else -> contentResolver.openInputStream(uri)
    }

    private fun shiftSubtitleContent(content: String, mimeType: String, delayMs: Long): String {
        return when (mimeType) {
            MimeTypes.APPLICATION_SUBRIP -> shiftSubRip(content, delayMs)
            MimeTypes.TEXT_VTT -> shiftWebVtt(content, delayMs)
            MimeTypes.TEXT_SSA -> shiftAssSsa(content, delayMs)
            else -> content
        }
    }

    private fun shiftSubRip(content: String, delayMs: Long): String {
        val regex =
            Regex("(\\d{2}:\\d{2}:\\d{2},\\d{3})\\s-->\\s(\\d{2}:\\d{2}:\\d{2},\\d{3})")
        return regex.replace(content) { match ->
            val startMs = parseSubRipTimestamp(match.groupValues[1])
            val endMs = parseSubRipTimestamp(match.groupValues[2])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${formatSubRipTimestamp(shiftedStart)} --> ${formatSubRipTimestamp(shiftedEnd)}"
        }
    }

    private fun shiftWebVtt(content: String, delayMs: Long): String {
        val regex =
            Regex(
                "((?:\\d{2}:)?\\d{2}:\\d{2}\\.\\d{3})\\s-->\\s((?:\\d{2}:)?\\d{2}:\\d{2}\\.\\d{3})(.*)",
            )
        return regex.replace(content) { match ->
            val startMs = parseWebVttTimestamp(match.groupValues[1])
            val endMs = parseWebVttTimestamp(match.groupValues[2])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${formatWebVttTimestamp(shiftedStart)} --> ${formatWebVttTimestamp(shiftedEnd)}${match.groupValues[3]}"
        }
    }

    private fun shiftAssSsa(content: String, delayMs: Long): String {
        val regex = Regex("^(Dialogue:\\s*[^,]*,)([^,]+),([^,]+)(,.*)$", RegexOption.MULTILINE)
        return regex.replace(content) { match ->
            val startMs = parseAssTimestamp(match.groupValues[2])
            val endMs = parseAssTimestamp(match.groupValues[3])
            val shiftedStart = shiftTimestamp(startMs, delayMs)
            val shiftedEnd = shiftTimestamp(endMs, delayMs, minimum = shiftedStart)
            "${match.groupValues[1]}${formatAssTimestamp(shiftedStart)},${formatAssTimestamp(shiftedEnd)}${match.groupValues[4]}"
        }
    }

    private fun shiftTimestamp(originalMs: Long, delayMs: Long, minimum: Long = 0L): Long {
        return (originalMs + delayMs).coerceAtLeast(minimum.coerceAtLeast(0L))
    }

    private fun resolveSubtitleMimeType(uri: Uri): String? {
        val fromResolver = contentResolver.getType(uri)?.let { candidate ->
            when (candidate.lowercase()) {
                "application/x-subrip" -> MimeTypes.APPLICATION_SUBRIP
                "text/vtt" -> MimeTypes.TEXT_VTT
                "text/x-ssa",
                "application/ssa",
                "application/ass",
                "text/x-ass" -> MimeTypes.TEXT_SSA
                else -> null
            }
        }
        if (fromResolver != null) {
            return fromResolver
        }

        val name = resolveDisplayName(uri).lowercase()
        return when {
            name.endsWith(".srt") -> MimeTypes.APPLICATION_SUBRIP
            name.endsWith(".vtt") -> MimeTypes.TEXT_VTT
            name.endsWith(".ass") || name.endsWith(".ssa") -> MimeTypes.TEXT_SSA
            else -> null
        }
    }

    private fun resolveSubtitleExtension(source: ExternalSubtitleSource): String {
        return when (source.mimeType) {
            MimeTypes.APPLICATION_SUBRIP -> "srt"
            MimeTypes.TEXT_VTT -> "vtt"
            MimeTypes.TEXT_SSA -> "ass"
            else -> "srt"
        }
    }

    private fun resolveDisplayName(uri: Uri): String {
        if (uri.scheme?.lowercase() == "file") {
            val fileName = uri.path?.let { path -> File(path).name }.orEmpty()
            if (fileName.isNotBlank()) {
                return fileName
            }
        }
        var result = uri.lastPathSegment ?: "外挂字幕"
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && cursor.moveToFirst()) {
                        result = cursor.getString(index) ?: result
                    }
                }
        } catch (_: Throwable) {
        }
        return result
    }

    private fun loadResumePositionMs(): Long {
        val entry = loadPlaybackEntry(playbackItemKey) ?: return 0L
        val positionMs = entry.optLong("positionMs", 0L)
        val durationMs = entry.optLong("durationMs", 0L)
        val progress = entry.optDouble("progress", 0.0)
        val completed = entry.optBoolean("completed", false)
        if (completed || positionMs < 5_000L) {
            return 0L
        }
        if (durationMs > 0L && durationMs - positionMs <= 12_000L) {
            return 0L
        }
        if (progress >= 0.985) {
            return 0L
        }
        return positionMs
    }

    private fun persistPlaybackProgress(force: Boolean = false) {
        val currentPlayer = player ?: return
        val resolvedDuration = currentPlayer.duration.takeIf { it > 0L } ?: 0L
        val resolvedPosition = currentPlayer.currentPosition.coerceAtLeast(0L)
        if (!force && kotlin.math.abs(resolvedPosition - lastSavedPositionMs) < 4_000L) {
            return
        }
        lastSavedPositionMs = resolvedPosition
        savePlaybackEntry(
            targetJson = playbackTargetJson,
            itemKey = playbackItemKey,
            seriesKey = seriesKey,
            positionMs = resolvedPosition,
            durationMs = resolvedDuration,
        )
    }

    private fun loadPlaybackEntry(itemKey: String): JSONObject? {
        if (itemKey.isBlank()) {
            return null
        }
        val snapshot = loadPlaybackSnapshot()
        val items = snapshot.optJSONObject("items") ?: return null
        return items.optJSONObject(itemKey)
    }

    private fun loadPlaybackSnapshot(): JSONObject {
        val raw = sharedPreferences.getString(PLAYBACK_MEMORY_STORAGE_KEY, null)
        if (raw.isNullOrBlank()) {
            return JSONObject()
        }
        return try {
            JSONObject(raw)
        } catch (_: Throwable) {
            JSONObject()
        }
    }

    private fun savePlaybackEntry(
        targetJson: String,
        itemKey: String,
        seriesKey: String,
        positionMs: Long,
        durationMs: Long,
    ) {
        if (itemKey.isBlank()) {
            return
        }

        val clampedDuration = durationMs.coerceAtLeast(0L)
        val safePosition = if (clampedDuration > 0L) {
            positionMs.coerceIn(0L, clampedDuration)
        } else {
            positionMs.coerceAtLeast(0L)
        }
        val progress = if (clampedDuration <= 0L) {
            0.0
        } else {
            (safePosition.toDouble() / clampedDuration.toDouble()).coerceIn(0.0, 1.0)
        }
        val completed = isCompleted(
            positionMs = safePosition,
            durationMs = clampedDuration,
            progress = progress,
        )

        val snapshot = loadPlaybackSnapshot()
        val items = snapshot.optJSONObject("items") ?: JSONObject()
        val series = snapshot.optJSONObject("series") ?: JSONObject()
        val skipPreferences = snapshot.optJSONObject("skipPreferences") ?: JSONObject()
        val targetObject = try {
            JSONObject(targetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
        val seriesTitle = targetObject.optString("seriesTitle").ifBlank {
            if (targetObject.optString("itemType").trim().lowercase() == "series") {
                targetObject.optString("title")
            } else {
                ""
            }
        }

        val entry = JSONObject().apply {
            put("key", itemKey)
            put("target", targetObject)
            put("updatedAt", isoNow())
            put("seriesKey", seriesKey)
            put("seriesTitle", seriesTitle)
            put("positionMs", safePosition)
            put("durationMs", clampedDuration)
            put("progress", progress)
            put("completed", completed)
        }

        items.put(itemKey, entry)
        pruneRecentItems(items)
        if (seriesKey.isNotBlank()) {
            series.put(seriesKey, entry)
        }

        val nextSnapshot = JSONObject().apply {
            put("items", items)
            put("series", series)
            put("skipPreferences", skipPreferences)
        }
        sharedPreferences.edit()
            .putString(PLAYBACK_MEMORY_STORAGE_KEY, nextSnapshot.toString())
            .apply()
    }

    private fun pruneRecentItems(items: JSONObject) {
        val keyedEntries = mutableListOf<Pair<String, JSONObject>>()
        val keys = items.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = items.optJSONObject(key) ?: continue
            keyedEntries.add(key to value)
        }
        if (keyedEntries.size <= RECENT_ENTRY_LIMIT) {
            return
        }
        keyedEntries.sortByDescending { (_, value) -> value.optString("updatedAt") }
        keyedEntries.drop(RECENT_ENTRY_LIMIT).forEach { (key, _) ->
            items.remove(key)
        }
    }

    private fun isCompleted(positionMs: Long, durationMs: Long, progress: Double): Boolean {
        if (durationMs <= 0L) {
            return progress >= 0.995
        }
        val remaining = durationMs - positionMs
        return progress >= 0.985 || remaining <= 8_000L
    }

    private fun parseSubRipTimestamp(value: String): Long {
        val parts = value.split(":", ",")
        if (parts.size != 4) {
            return 0L
        }
        val hours = parts[0].toLongOrNull() ?: 0L
        val minutes = parts[1].toLongOrNull() ?: 0L
        val seconds = parts[2].toLongOrNull() ?: 0L
        val millis = parts[3].toLongOrNull() ?: 0L
        return (((hours * 60 + minutes) * 60) + seconds) * 1_000L + millis
    }

    private fun formatSubRipTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val millis = valueMs % 1_000L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return String.format(Locale.US, "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private fun parseWebVttTimestamp(value: String): Long {
        val parts = value.split(":", ".")
        return when (parts.size) {
            4 -> {
                val hours = parts[0].toLongOrNull() ?: 0L
                val minutes = parts[1].toLongOrNull() ?: 0L
                val seconds = parts[2].toLongOrNull() ?: 0L
                val millis = parts[3].toLongOrNull() ?: 0L
                (((hours * 60 + minutes) * 60) + seconds) * 1_000L + millis
            }

            3 -> {
                val minutes = parts[0].toLongOrNull() ?: 0L
                val seconds = parts[1].toLongOrNull() ?: 0L
                val millis = parts[2].toLongOrNull() ?: 0L
                ((minutes * 60) + seconds) * 1_000L + millis
            }

            else -> 0L
        }
    }

    private fun formatWebVttTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val millis = valueMs % 1_000L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return if (hours > 0L) {
            String.format(Locale.US, "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
        } else {
            String.format(Locale.US, "%02d:%02d.%03d", minutes, seconds, millis)
        }
    }

    private fun parseAssTimestamp(value: String): Long {
        val parts = value.trim().split(":", ".")
        if (parts.size != 4) {
            return 0L
        }
        val hours = parts[0].toLongOrNull() ?: 0L
        val minutes = parts[1].toLongOrNull() ?: 0L
        val seconds = parts[2].toLongOrNull() ?: 0L
        val centiseconds = parts[3].toLongOrNull() ?: 0L
        return (((hours * 60 + minutes) * 60) + seconds) * 1_000L + centiseconds * 10L
    }

    private fun formatAssTimestamp(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val centiseconds = (valueMs % 1_000L) / 10L
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return String.format(Locale.US, "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }

    private fun isoNow(): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        return formatter.format(Date())
    }

    private fun formatClockDuration(valueMs: Long): String {
        val totalSeconds = valueMs / 1_000L
        val hours = totalSeconds / 3_600L
        val minutes = (totalSeconds % 3_600L) / 60L
        val seconds = totalSeconds % 60L
        return if (hours > 0L) {
            String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%d:%02d", minutes, seconds)
        }
    }

    private fun formatSubtitleDelayLabel(valueMs: Long): String {
        if (valueMs == 0L) {
            return "0s"
        }
        val seconds = valueMs / 1_000.0
        val formatted = if (seconds == seconds.toLong().toDouble()) {
            seconds.toLong().toString()
        } else {
            String.format(Locale.US, "%.1f", seconds).trimEnd('0').trimEnd('.')
        }
        return if (valueMs > 0L) "+${formatted}s" else "${formatted}s"
    }

    private fun showToast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    private fun logPlayback(message: String, error: Throwable? = null) {
        // Logging intentionally disabled for production playback runs.
    }

    private fun decodePlaybackTargetObject(): JSONObject {
        return try {
            JSONObject(playbackTargetJson)
        } catch (_: Throwable) {
            JSONObject()
        }
    }

    private fun summarizeHeaderKeys(headersJson: String): String {
        if (headersJson.isBlank()) {
            return "-"
        }
        return try {
            val json = JSONObject(headersJson)
            val keys = mutableListOf<String>()
            val iterator = json.keys()
            while (iterator.hasNext()) {
                keys += iterator.next()
            }
            if (keys.isEmpty()) "-" else keys.joinToString("|")
        } catch (_: Throwable) {
            "invalid-json"
        }
    }

    private fun summarizeUrl(raw: String): String {
        if (raw.isBlank()) {
            return "-"
        }
        return try {
            val uri = Uri.parse(raw)
            val path = uri.path?.takeIf { it.isNotBlank() } ?: "/"
            "${uri.scheme}://${uri.host ?: ""}$path"
        } catch (_: Throwable) {
            raw
        }
    }

    private fun guessVideoMimeType(targetObject: JSONObject, url: String): String {
        val container = targetObject.optString("container").trim().lowercase(Locale.US)
        return when {
            container == "mp4" || container == "m4v" -> MimeTypes.VIDEO_MP4
            container == "webm" -> MimeTypes.VIDEO_WEBM
            container == "mkv" -> MimeTypes.VIDEO_MATROSKA
            container == "ts" || container == "m2ts" -> MimeTypes.VIDEO_MP2T
            container == "mpg" || container == "mpeg" -> MimeTypes.VIDEO_MPEG
            url.lowercase(Locale.US).endsWith(".mp4") ||
                url.lowercase(Locale.US).endsWith(".m4v") -> MimeTypes.VIDEO_MP4
            url.lowercase(Locale.US).endsWith(".webm") -> MimeTypes.VIDEO_WEBM
            url.lowercase(Locale.US).endsWith(".mkv") -> MimeTypes.VIDEO_MATROSKA
            url.lowercase(Locale.US).endsWith(".ts") ||
                url.lowercase(Locale.US).endsWith(".m2ts") -> MimeTypes.VIDEO_MP2T
            url.lowercase(Locale.US).endsWith(".mpg") ||
                url.lowercase(Locale.US).endsWith(".mpeg") -> MimeTypes.VIDEO_MPEG
            else -> "-"
        }
    }

    private fun playbackStateLabel(playbackState: Int): String {
        return when (playbackState) {
            Player.STATE_IDLE -> "IDLE"
            Player.STATE_BUFFERING -> "BUFFERING"
            Player.STATE_READY -> "READY"
            Player.STATE_ENDED -> "ENDED"
            else -> playbackState.toString()
        }
    }

    private fun enterImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.hide(
                android.view.WindowInsets.Type.statusBars() or
                    android.view.WindowInsets.Type.navigationBars(),
            )
            window.insetsController?.systemBarsBehavior =
                android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            return
        }

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    }

    companion object {
        private const val REQUEST_CODE_EXTERNAL_SUBTITLE = 1001
        private const val REQUEST_CODE_SUBTITLE_SEARCH = 1002
        private const val SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
        private const val PLAYBACK_MEMORY_STORAGE_KEY = "flutter.starflow.playback.memory.v1"
        private const val RECENT_ENTRY_LIMIT = 20
        private val SUBTITLE_DELAY_OPTIONS_MS =
            listOf(-5_000L, -2_000L, -1_000L, -500L, 0L, 500L, 1_000L, 2_000L, 5_000L)
        private val PLAYBACK_SPEED_OPTIONS =
            listOf(0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f)

        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_HEADERS_JSON = "headersJson"
        const val EXTRA_DECODE_MODE = "decodeMode"
        const val EXTRA_PLAYBACK_TARGET_JSON = "playbackTargetJson"
        const val EXTRA_PLAYBACK_ITEM_KEY = "playbackItemKey"
        const val EXTRA_SERIES_KEY = "seriesKey"
    }
}

private enum class ControllerFocusTarget {
    NONE,
    PLAYER,
    PRIMARY,
    SETTINGS,
    AUDIO,
    SUBTITLE,
}

private data class ExternalSubtitleSource(
    val originalUri: Uri,
    val mimeType: String,
    val displayName: String,
)

private enum class PlaybackDecodeMode {
    AUTO,
    HARDWARE_PREFERRED,
    SOFTWARE_PREFERRED;

    companion object {
        fun fromRaw(raw: String): PlaybackDecodeMode {
            return when (raw) {
                "hardwarePreferred" -> HARDWARE_PREFERRED
                "softwarePreferred" -> SOFTWARE_PREFERRED
                else -> AUTO
            }
        }
    }
}
