package com.example.starflow

import androidx.media3.common.PlaybackParameters
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativeFntvControllerTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()
    private val host = mock(NativeFntvController.Host::class.java, RETURNS_DEEP_STUBS)
    private var json = """{"sourceKind":"fntv","playbackQualities":[{"index":0},{"index":1}],"subtitleStreams":[{"id":"sub","isExternal":true}]}"""
    private var pending: ((Map<String, Any?>) -> Unit)? = null
    private val calls = mutableListOf<String>()
    private val callArgs = mutableListOf<Map<String, Any?>>()
    private var requestJson = ""
    private val controller = NativeFntvController(host,
        invoke = { method, args, callback -> calls += method; callArgs += args; pending = callback },
        resolve = { _, request, callback -> requestJson = request; pending = callback; true },
    )

    @Before
    fun setup() {
        `when`(host.target.playbackTargetJson).thenAnswer { json }
        `when`(host.target.decodePlaybackTargetObject()).thenAnswer { JSONObject(json) }
        `when`(host.target.resolverSessionId).thenReturn("session")
        `when`(host.session.player!!.currentTracks).thenReturn(Tracks.EMPTY)
        `when`(host.session.player!!.trackSelectionParameters).thenReturn(TrackSelectionParameters.DEFAULT_WITHOUT_CONTEXT)
    }

    @Test
    fun versionsAvailableForIndexedMoviesAndServerEpisodesOnly() {
        for (kind in listOf("nas", "quark", "emby", "fntv")) {
            json = """{"sourceKind":"$kind","sourceId":"source","itemId":"file","itemType":"movie"}"""
            assertTrue(controller.supportsPlaybackVersions())
        }
        json = """{"sourceKind":"nas","sourceId":"source","itemId":"show","itemType":"series"}"""
        assertFalse(controller.supportsPlaybackVersions())
    }

    @Test
    fun versionReopenPreservesPositionSpeedPauseAndUpdatesIdentityAndQueue() {
        json = """{"sourceKind":"nas","sourceId":"source","itemId":"a","itemType":"episode","streamUrl":"https://nas/a.mkv"}"""
        val original = json
        val next = """{"sourceKind":"nas","sourceId":"source","itemId":"b","itemType":"episode","streamUrl":"https://nas/b.mkv","headers":{"Authorization":"test"}}"""
        `when`(host.target.playbackItemKey).thenReturn("old-key")
        `when`(host.target.seriesKey).thenReturn("series")
        `when`(host.episodes.episodeQueue).thenReturn(NativeEpisodeQueue(listOf(
            NativeEpisodeQueueEntry(original, "old-key", "series"),
            NativeEpisodeQueueEntry("{}", "next-episode", "series"),
        )))
        `when`(host.session.player!!.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        `when`(host.session.player!!.currentPosition).thenReturn(42_000L)
        `when`(host.session.player!!.playWhenReady).thenReturn(false)
        val nativeTarget = host.target
        doAnswer { json = it.arguments[0] as String; null }.`when`(nativeTarget).playbackTargetJson = anyString()
        controller.switchVersion(JSONObject(next))
        assertEquals("https://nas/b.mkv", JSONObject(requestJson).getString("streamUrl"))
        assertEquals("test", JSONObject(requestJson).getJSONObject("headers").getString("Authorization"))
        pending!!(mapOf("ok" to true, "playbackTargetJson" to next, "playbackItemKey" to "new-key", "seriesKey" to "series"))
        verify(host.target).playbackItemKey = "new-key"
        verify(host.session).pendingResumePositionOverrideMs = 42_000L
        verify(host.session).nextInitializePlayWhenReady = false
        verify(host.session).stagePlaybackParameters(PlaybackParameters(1.5f))
        val queueCaptor = org.mockito.ArgumentCaptor.forClass(NativeEpisodeQueue::class.java)
        verify(host.episodes).episodeQueue = queueCaptor.capture()
        assertEquals(next, queueCaptor.value.currentEntry()!!.playbackTargetJson)
        assertEquals("next-episode", queueCaptor.value.entries[1].playbackItemKey)
        assertTrue(controller.recoverQualityFailure())
        assertEquals(original, json)
        verify(host.target).playbackItemKey = "old-key"
        assertFalse(controller.recoverQualityFailure())
    }

    @Test
    fun versionLoadDeduplicatesRequestsAndRejectsStaleResponse() {
        json = """{"sourceKind":"nas","sourceId":"source","itemId":"a","itemType":"movie"}"""
        controller.openVersionPicker()
        controller.openVersionPicker()
        assertEquals(listOf("browseNativePlaybackVersions"), calls)
        controller.invalidateMedia()
        pending!!(mapOf("ok" to false))
        verify(host, never()).showToast("版本加载失败，请重试")
        verify(host.session, never()).releasePlayer()
    }

    @Test
    fun initialAudioPreferenceAppliedOnceWithoutOverwritingManualSelection() {
        json = """{"sourceKind":"fntv","preferredAudioStreamId":"b","audioStreams":[{"id":"a","index":0},{"id":"b","index":1}]}"""
        val player = host.session.player!!
        val group = TrackGroup(
            Format.Builder().setId("a").setSampleMimeType(MimeTypes.AUDIO_AAC).build(),
            Format.Builder().setId("b").setSampleMimeType(MimeTypes.AUDIO_AC3).build(),
        )
        val tracks = Tracks(listOf(Tracks.Group(group, false,
            intArrayOf(C.FORMAT_HANDLED, C.FORMAT_HANDLED), booleanArrayOf(true, false))))
        `when`(player.currentTracks).thenReturn(tracks)
        controller.onTracksReady()
        controller.onTracksReady()
        val captor = org.mockito.ArgumentCaptor.forClass(TrackSelectionParameters::class.java)
        verify(player, times(1)).trackSelectionParameters = captor.capture()
        assertEquals(listOf(1), captor.value.overrides.values.single().trackIndices)

        controller.invalidateMedia()
        val manual = TrackSelectionParameters.Builder().addOverride(TrackSelectionOverride(group, 0)).build()
        `when`(player.trackSelectionParameters).thenReturn(manual)
        controller.onTracksReady()
        verify(player, times(1)).trackSelectionParameters = any(TrackSelectionParameters::class.java)
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
    fun unsupportedAudioDoesNotShiftReportedGuidOrQualitySelection() {
        json = """{"sourceKind":"fntv","preferredAudioStreamId":"a","audioStreams":[{"id":"a","index":0},{"id":"b","index":1}],"playbackQualities":[{"index":-1,"serverTranscode":true}]}"""
        val group = TrackGroup(
            Format.Builder().setId("a").setSampleMimeType(MimeTypes.AUDIO_AC3).build(),
            Format.Builder().setId("b").setSampleMimeType(MimeTypes.AUDIO_AAC).build(),
        )
        `when`(host.session.player!!.currentTracks).thenReturn(Tracks(listOf(Tracks.Group(group, false,
            intArrayOf(C.FORMAT_UNSUPPORTED_TYPE, C.FORMAT_HANDLED), booleanArrayOf(false, true)))))
        assertEquals(listOf("a"), controller.unavailableAudioStreams().map { it.optString("id") })
        controller.switchQuality(-1)
        assertEquals("b", JSONObject(requestJson).getString("preferredAudioStreamId"))
    }

    @Test
    fun serverAudioFallbackRequiresValidStreamAndTranscodeProfile() {
        json = """{"sourceKind":"fntv","audioStreams":[{"id":"a"},{"id":"b"}],"playbackQualities":[{"index":0},{"index":-1,"serverTranscode":true}]}"""
        controller.switchServerAudio("missing", -1)
        controller.switchServerAudio("b", 0)
        assertNull(pending)
        controller.switchServerAudio("b", -1)
        val request = JSONObject(requestJson)
        assertEquals("b", request.getString("preferredAudioStreamId"))
        assertEquals(-1, request.getInt("preferredPlaybackQualityIndex"))
        assertTrue(request.getBoolean("fntvTrackSelectionExplicit"))
    }

    @Test
    fun missingAudioIdentityDoesNotGuessFirstServerStream() {
        json = """{"sourceKind":"fntv","preferredAudioStreamId":"b","audioStreams":[{"id":"a","index":0},{"id":"b","index":1}],"playbackQualities":[{"index":-1,"serverTranscode":true}]}"""
        val group = TrackGroup(Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build())
        `when`(host.session.player!!.currentTracks).thenReturn(Tracks(listOf(Tracks.Group(group, false,
            intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true)))))
        controller.switchQuality(-1)
        assertEquals("b", JSONObject(requestJson).getString("preferredAudioStreamId"))
    }

    @Test
    fun subtitleSnapshotKeepsUnsupportedTrackPositions() {
        json = """{"sourceKind":"fntv","subtitleStreams":[{"id":"s1","index":0},{"id":"s2","index":1}],"playbackQualities":[{"index":-1,"serverTranscode":true}]}"""
        val group = TrackGroup(
            Format.Builder().setId("s1").setSampleMimeType(MimeTypes.APPLICATION_PGS).build(),
            Format.Builder().setId("s2").setSampleMimeType(MimeTypes.TEXT_VTT).build(),
        )
        `when`(host.session.player!!.currentTracks).thenReturn(Tracks(listOf(Tracks.Group(group, false,
            intArrayOf(C.FORMAT_UNSUPPORTED_TYPE, C.FORMAT_HANDLED), booleanArrayOf(false, true)))))
        controller.switchQuality(-1)
        assertEquals("s2", JSONObject(requestJson).getString("preferredSubtitleStreamId"))
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
        verify(host.session).stagePlaybackParameters(PlaybackParameters(1.5f))
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
    fun transcodeRequestCarriesPositionAndUsesDistinctServerIndex() {
        json = """{"sourceKind":"fntv","fntvSessionLink":"old","preferredAudioStreamId":"en","playbackQualities":[{"index":0},{"index":-1,"serverTranscode":true}]}"""
        `when`(host.session.player!!.currentPosition).thenReturn(42_000L)
        controller.switchQuality(-1)
        val request = JSONObject(requestJson)
        assertEquals(-1, request.getInt("preferredPlaybackQualityIndex"))
        assertEquals(42_000L, request.getLong("fntvStartPositionMs"))
        assertEquals("en", request.getString("preferredAudioStreamId"))
        assertEquals("", request.getString("fntvSessionLink"))
        assertTrue(request.getBoolean("fntvTrackSelectionExplicit"))
        assertTrue(calls.isEmpty())
    }

    @Test
    fun lateTranscodeAllocationIsReleasedWithoutReplacingPlayer() {
        controller.switchQuality(1)
        val reply = pending!!
        controller.invalidateMedia()
        reply(mapOf("ok" to true, "playbackTargetJson" to
            """{"sourceKind":"fntv","fntvSessionLink":"late","streamUrl":"https://nas/hls.m3u8"}"""))
        assertEquals(listOf("releaseNativeFntvPlayback"), calls)
        assertEquals("late", JSONObject(callArgs.single()["playbackTargetJson"].toString()).getString("fntvSessionLink"))
        verify(host.session, never()).releasePlayer()
    }

    @Test
    fun successfulTranscodeSwitchReleasesOnlyOldSessionAfterReady() {
        json = """{"sourceKind":"fntv","fntvSessionLink":"old","playbackQualities":[{"index":0},{"index":-1,"serverTranscode":true}]}"""
        `when`(host.session.player!!.playbackParameters).thenReturn(PlaybackParameters(1.5f))
        val nativeTarget = host.target
        doAnswer { json = it.arguments[0] as String; null }.`when`(nativeTarget).playbackTargetJson = anyString()
        controller.switchQuality(-1)
        pending!!(mapOf("ok" to true, "playbackTargetJson" to
            """{"sourceKind":"fntv","fntvSessionLink":"new","streamUrl":"https://nas/new.m3u8"}"""))
        assertTrue(calls.isEmpty())
        controller.onReady()
        assertEquals(listOf("releaseNativeFntvPlayback"), calls)
        assertEquals("old", JSONObject(callArgs.single()["playbackTargetJson"].toString()).getString("fntvSessionLink"))
        assertFalse(controller.recoverQualityFailure())
    }

    @Test
    fun failedTranscodeSwitchReleasesNewSessionAndRestoresOldOne() {
        json = """{"sourceKind":"fntv","fntvSessionLink":"old","streamUrl":"https://nas/old.m3u8","playbackQualities":[{"index":0},{"index":-1}]}"""
        `when`(host.session.player!!.playbackParameters).thenReturn(PlaybackParameters(1f))
        val nativeTarget = host.target
        doAnswer { json = it.arguments[0] as String; null }.`when`(nativeTarget).playbackTargetJson = anyString()
        controller.switchQuality(-1)
        pending!!(mapOf("ok" to true, "playbackTargetJson" to
            """{"sourceKind":"fntv","fntvSessionLink":"new","streamUrl":"https://nas/new.m3u8"}"""))
        assertTrue(controller.recoverQualityFailure())
        assertEquals("old", JSONObject(json).getString("fntvSessionLink"))
        assertEquals("new", JSONObject(callArgs.single()["playbackTargetJson"].toString()).getString("fntvSessionLink"))
        controller.onReady()
        assertEquals(listOf("releaseNativeFntvPlayback"), calls)
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
    fun lateServerResolutionCannotReplaceNewerLocalSubtitleIntent() {
        controller.switchQuality(1)
        `when`(host.subtitles.subtitleSelectionRevision).thenReturn(1L)
        pending!!(mapOf("ok" to true, "playbackTargetJson" to
            """{"sourceKind":"fntv","fntvSessionLink":"late","streamUrl":"https://nas/hls.m3u8"}"""))
        verify(host.session, never()).releasePlayer()
        assertEquals(listOf("releaseNativeFntvPlayback"), calls)
        assertFalse(controller.isSwitching)
    }

    @Test
    fun lateSubtitleResponseIsIgnoredAfterTargetChanges() {
        controller.loadSubtitle(JSONObject("""{"id":"sub"}"""))
        json = """{"sourceKind":"fntv","itemId":"next"}"""
        pending!!(mapOf("ok" to true, "path" to "/tmp/sub.srt", "displayName" to "sub"))
        verify(host.externalSubtitles, never()).loadCachedSubtitleFile(anyString(), anyString(), isNull(), isNull())
        verify(host.externalSubtitles).discardFntvDownload("/tmp/sub.srt")
        assertFalse(controller.isSwitching)
    }

    @Test
    fun newerSubtitleIntentRejectsLateDownloadWithoutBlockingOtherSelections() {
        val trackHost = mock(NativePlaybackTrackController.Host::class.java, RETURNS_DEEP_STUBS)
        val subtitles = NativePlaybackTrackController(trackHost)
        `when`(host.subtitles).thenReturn(subtitles)
        `when`(trackHost.fntv).thenReturn(controller)
        controller.loadSubtitle(JSONObject("""{"id":"sub"}"""))
        val reply = pending!!
        assertFalse(controller.isSwitching)
        subtitles.beginSubtitleSelection()
        subtitles.subtitleSessionPreference = NativeSubtitleSessionPreference(NativeSubtitleSessionMode.OFF)
        reply(mapOf("ok" to true, "path" to "/tmp/sub.srt"))
        verify(host.externalSubtitles, never()).loadCachedSubtitleFile(anyString(), anyString(), any(), any())
        verify(host.externalSubtitles).discardFntvDownload("/tmp/sub.srt")
        assertEquals(NativeSubtitleSessionMode.OFF, subtitles.subtitleSessionPreference?.mode)
        verify(host.runtime, never()).persistPlaybackProgress(anyBoolean())
    }

    @Test
    fun newerDownloadWinsAndUsesItsOriginalRevisionThroughMount() {
        val trackHost = mock(NativePlaybackTrackController.Host::class.java, RETURNS_DEEP_STUBS)
        val subtitles = NativePlaybackTrackController(trackHost)
        `when`(host.subtitles).thenReturn(subtitles)
        `when`(trackHost.fntv).thenReturn(controller)
        controller.loadSubtitle(JSONObject("""{"id":"old"}"""))
        val oldReply = pending!!
        controller.loadSubtitle(JSONObject("""{"id":"new"}"""))
        val newReply = pending!!
        newReply(mapOf("ok" to true, "path" to "/tmp/new.srt", "displayName" to "new"))
        oldReply(mapOf("ok" to true, "path" to "/tmp/old.srt"))
        verify(host.externalSubtitles).loadCachedSubtitleFile(
            eq("/tmp/new.srt") ?: "", eq("new") ?: "", any(), eq(2L))
        verify(host.externalSubtitles).discardFntvDownload("/tmp/old.srt")
        assertEquals(2L, subtitles.subtitleSelectionRevision)
    }

    @Test
    fun explicitOffPreventsReadyFromRestartingAutomaticServerSubtitleDownload() {
        json = """{"sourceKind":"fntv","fntvSessionLink":"active","preferredSubtitleStreamId":"sub","subtitleStreams":[{"id":"sub","isExternal":true}]}"""
        controller.cancelSubtitleLoad()
        controller.onReady()
        assertTrue(calls.isEmpty())
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
