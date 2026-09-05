package com.example.starflow

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.view.KeyEvent

class NativePlaybackActivity : Activity() {
    private val playback by lazy { NativePlaybackCoordinator(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        playback.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        playback.onNewIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        playback.onStart()
    }

    override fun onResume() {
        super.onResume()
        playback.onResume()
    }

    override fun onPause() {
        playback.onPause()
        super.onPause()
    }

    override fun onStop() {
        playback.onStop()
        super.onStop()
    }

    override fun onDestroy() {
        playback.onDestroy()
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        playback.onWindowFocusChanged(hasFocus)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        playback.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(inPip, config)
        playback.onPictureInPictureModeChanged(inPip, config)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        playback.onActivityResult(requestCode, resultCode, data)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        playback.remote.dispatchKeyEvent(event) || super.dispatchKeyEvent(event)

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_HEADERS_JSON = "headersJson"
        const val EXTRA_DECODE_MODE = "decodeMode"
        const val EXTRA_AUDIO_OUTPUT_MODE = "audioOutputMode"
        const val EXTRA_SUBTITLE_SCALE = "subtitleScale"
        const val EXTRA_PRIMARY_SUBTITLE_POSITION = "primarySubtitlePosition"
        const val EXTRA_SECONDARY_SUBTITLE_POSITION = "secondarySubtitlePosition"
        const val EXTRA_SECONDARY_SUBTITLE_SCALE = "secondarySubtitleScale"
        const val EXTRA_MEDIA_MIME_TYPE = "mediaMimeType"
        const val EXTRA_RESOLVER_SESSION_ID = "resolverSessionId"
        const val EXTRA_SUBTITLE_PREFERENCE = "subtitlePreference"
        const val EXTRA_DEFAULT_SUBTITLE = "defaultSubtitle"
        const val EXTRA_DUAL_SUBTITLE_PRIMARY_LANGUAGE = "dualSubtitlePrimaryLanguage"
        const val EXTRA_DUAL_SUBTITLE_SECONDARY_LANGUAGE = "dualSubtitleSecondaryLanguage"
        const val EXTRA_PLAYBACK_TARGET_JSON = "playbackTargetJson"
        const val EXTRA_PLAYBACK_ITEM_KEY = "playbackItemKey"
        const val EXTRA_SERIES_KEY = "seriesKey"
        const val EXTRA_EPISODE_QUEUE_JSON = "episodeQueueJson"
        const val EXTRA_LAUNCH_REQUEST_ID = "launchRequestId"
        const val EXTRA_LAUNCH_RESULT_RECEIVER = "launchResultReceiver"
        const val RESULT_DATA_REQUEST_ID = "requestId"
        const val RESULT_DATA_MESSAGE = "message"
        const val RESULT_PLAYBACK_READY = 1
        const val RESULT_PLAYBACK_CANCELLED = 2
        const val RESULT_PLAYBACK_FAILED = 0
    }
}
