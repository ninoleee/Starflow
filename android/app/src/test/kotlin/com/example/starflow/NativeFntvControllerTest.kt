package com.example.starflow

import androidx.media3.common.PlaybackParameters
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativeFntvControllerTest {
    private val host = mock(NativeFntvController.Host::class.java, RETURNS_DEEP_STUBS)
    private var json = """{"sourceKind":"fntv","playbackQualities":[{"index":0},{"index":1}],"subtitleStreams":[{"id":"sub","isExternal":true}]}"""
    private var pending: ((Map<String, Any?>) -> Unit)? = null
    private val calls = mutableListOf<String>()
    private val controller = NativeFntvController(host,
        invoke = { method, _, callback -> calls += method; pending = callback },
        resolve = { _, _, callback -> pending = callback; true },
    )

    @Before
    fun setup() {
        `when`(host.target.playbackTargetJson).thenAnswer { json }
        `when`(host.target.decodePlaybackTargetObject()).thenAnswer { JSONObject(json) }
        `when`(host.target.resolverSessionId).thenReturn("session")
    }

    @Test
    fun qualityEntryExplainsMissingOrSingleQualityInsteadOfDisappearing() {
        json = """{"sourceKind":"fntv"}"""
        assertEquals("画质 · 未返回可切换画质", controller.qualitySettingsLabel())
        controller.openQualityPicker()
        verify(host).showToast("飞牛未返回可切换画质，继续使用当前播放地址")
        json = """{"sourceKind":"fntv","playbackQualities":[{"index":2,"resolution":"1080P"}]}"""
        assertEquals("画质 · 1080P（仅一档）", controller.qualitySettingsLabel())
        controller.openQualityPicker()
        verify(host).showToast("飞牛仅返回一个画质，没有其他画质可切换")
        assertTrue(calls.isEmpty())
        assertNull(pending)
    }

    @Test
    fun qualityEntryUsesSelectedServerIndexAndStaysAbsentForOtherSources() {
        json = """{"sourceKind":"fntv","preferredPlaybackQualityIndex":4,"playbackQualities":[{"index":2,"resolution":"1080P"},{"index":4,"resolution":"4K"}]}"""
        assertEquals("画质 · 4K", controller.qualitySettingsLabel())
        json = """{"sourceKind":"emby"}"""
        assertNull(controller.qualitySettingsLabel())
    }

    @Test
    fun audioAndSubtitleEntriesExposeFntvCounts() {
        json = """
            {
              "sourceKind":"fntv",
              "audioStreams":[{"id":"a1"},{"id":"a2"}],
              "subtitleStreams":[
                {"id":"s1","isExternal":false},
                {"id":"s2","isExternal":true},
                {"id":"s3","isExternal":true}
              ]
            }
        """.trimIndent()
        assertEquals("音轨 · 飞牛 2 条", controller.audioSettingsLabel())
        assertEquals("字幕 · 内置 1 / 外挂 2", controller.subtitleSettingsLabel())
        json = """{"sourceKind":"emby"}"""
        assertNull(controller.audioSettingsLabel())
        assertNull(controller.subtitleSettingsLabel())
    }

    @Test
    fun menusAreScopedToFntv() {
        assertEquals(2, controller.qualities().size)
        assertEquals("sub", controller.externalSubtitles().single().optString("id"))
        json = """{"sourceKind":"emby","playbackQualities":[{"index":0}]}"""
        assertTrue(controller.qualities().isEmpty())
        assertTrue(controller.externalSubtitles().isEmpty())
    }

    @Test
    fun qualityReopenPreservesPlaybackStateAndCanRollBackOnce() {
        `when`(host.session.player!!.currentTracks).thenReturn(Tracks.EMPTY)
        `when`(host.session.player!!.trackSelectionParameters).thenReturn(TrackSelectionParameters.DEFAULT_WITHOUT_CONTEXT)
        `when`(host.session.player!!.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        `when`(host.session.player!!.currentPosition).thenReturn(42_000L)
        `when`(host.session.player!!.playWhenReady).thenReturn(false)
        controller.switchQuality(1)
        pending!!(mapOf("ok" to true, "playbackTargetJson" to """{"streamUrl":"https://example.com/video"}"""))
        verify(host.session).pendingResumePositionOverrideMs = 42_000L
        verify(host.session).nextInitializePlayWhenReady = false
        verify(host.session.player!!).playbackParameters = PlaybackParameters(1.5f)
        verify(host.session).initializePlayer()
        assertTrue(controller.recoverQualityFailure())
        verify(host.session, times(2)).initializePlayer()
        assertFalse(controller.recoverQualityFailure())
    }

    @Test
    fun failedQualityResolutionKeepsExistingPlayer() {
        controller.switchQuality(1)
        assertTrue(controller.isSwitching)
        pending!!(mapOf("ok" to false))
        assertFalse(controller.isSwitching)
        verify(host.session, never()).releasePlayer()
        assertFalse(controller.recoverQualityFailure())
    }

    @Test
    fun lateQualityResponseCannotReplaceAnotherEpisode() {
        controller.switchQuality(1)
        controller.invalidateMedia()
        pending!!(mapOf("ok" to true, "playbackTargetJson" to """{"streamUrl":"https://example.com/video"}"""))
        verify(host.session, never()).releasePlayer()
        assertFalse(controller.isSwitching)
    }

    @Test
    fun lateSubtitleResponseIsIgnoredAfterTargetChanges() {
        controller.loadSubtitle(JSONObject("""{"id":"sub"}"""))
        json = """{"sourceKind":"fntv","itemId":"next"}"""
        pending!!(mapOf("ok" to true, "path" to "/tmp/sub.srt", "displayName" to "sub"))
        verify(host.externalSubtitles, never()).loadCachedSubtitleFile(anyString(), anyString())
        assertFalse(controller.isSwitching)
    }

    @Test
    fun failedSubtitleLoadDoesNotRecordSelection() {
        controller.loadSubtitle(JSONObject("""{"id":"sub"}"""))
        pending!!(mapOf("ok" to true, "path" to "/tmp/missing.srt", "displayName" to "sub"))
        verify(host.runtime, never()).persistPlaybackProgress(anyBoolean())
    }

    @Test
    fun closeIsIdempotentAndDisablesFurtherActions() {
        controller.close()
        controller.close()
        controller.switchQuality(1)
        controller.loadSubtitle(JSONObject("""{"id":"sub"}"""))
        assertEquals(listOf("closeNativeFntvSession"), calls)
        assertFalse(controller.isSwitching)
    }
}
