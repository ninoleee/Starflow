package com.example.starflow

import android.app.AlertDialog
import android.content.DialogInterface
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.ui.DefaultTrackNameProvider
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackTrackControllerTest {
    @get:org.junit.Rule internal val android = AudioAndroidStubs()

    @Test fun offInternalGlobalAndDualMenuChoicesAllInvalidateOlderSubtitleWork() {
        for (choice in listOf(0, 1, 2, 3)) {
            val host = mock(NativePlaybackTrackController.Host::class.java, RETURNS_DEEP_STUBS)
            `when`(host.activity.getString(anyInt())).thenReturn("Tracks")
            val controller = NativePlaybackTrackController(host)
            val format = Format.Builder().setId("internal").setLanguage("en")
                .setSampleMimeType(MimeTypes.TEXT_VTT).build()
            val player = host.session.player!!
            `when`(player.currentTracks).thenReturn(Tracks(listOf(Tracks.Group(TrackGroup(format), false,
                intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(true)))))
            `when`(player.trackSelectionParameters).thenReturn(TrackSelectionParameters.Builder().build())
            val dialog = mock(AlertDialog::class.java)
            var click: DialogInterface.OnClickListener? = null
            mockConstruction(DefaultTrackNameProvider::class.java) { provider, _ ->
                `when`(provider.getTrackName(any(Format::class.java))).thenReturn("English")
            }.use {
                mockConstruction(AlertDialog.Builder::class.java, withSettings().defaultAnswer(RETURNS_SELF)) { builder, _ ->
                    `when`(builder.create()).thenReturn(dialog)
                    doAnswer { call ->
                        click = call.getArgument(2)
                        builder
                    }.`when`(builder).setSingleChoiceItems(any(Array<CharSequence>::class.java), anyInt(), any())
                }.use {
                    controller.openSubtitleTrackSelectionDialog()
                    controller.pendingExternalSubtitleSelection = true
                    click!!.onClick(dialog, choice)
                    assertEquals(1L, controller.subtitleSelectionRevision)
                    assertFalse(controller.pendingExternalSubtitleSelection)
                    verify(host.fntv).cancelSubtitleLoad()
                    verify(host.externalSubtitles).invalidatePendingSelection()
                    verify(host.externalSubtitles).externalSubtitleSource = null
                    if (choice == 0) assertEquals(NativeSubtitleSessionMode.OFF, controller.subtitleSessionPreference?.mode)
                    if (choice == 3) assertEquals(NativeSubtitleSessionMode.SINGLE, controller.subtitleSessionPreference?.mode)
                }
            }
        }
    }
}
