package com.example.starflow

import android.app.Activity
import android.graphics.Bitmap
import android.view.accessibility.CaptioningManager
import android.widget.FrameLayout
import androidx.media3.ui.SubtitleView
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class NativePlaybackSubtitleStyleControllerTest {
    private val host = mock(NativePlaybackSubtitleStyleController.Host::class.java, RETURNS_DEEP_STUBS)
    private val controller = NativePlaybackSubtitleStyleController(host)
    private val captioning = mock(CaptioningManager::class.java)

    @Before
    fun setup() {
        `when`(host.activity.getSystemService(Activity.CAPTIONING_SERVICE)).thenReturn(captioning)
        `when`(captioning.isEnabled).thenReturn(true)
    }

    @Test
    fun `subtitle view moves out of the aspect ratio frame and is not added twice`() {
        val subtitleView = host.playerView.subtitleView!!
        val overlay = host.playerView.overlayFrameLayout!!
        val contentFrame = mock(FrameLayout::class.java)
        `when`(subtitleView.parent).thenReturn(contentFrame)
        mockConstruction(FrameLayout.LayoutParams::class.java).use { params ->
            controller.primarySubtitlePosition = 100.0
            controller.applySubtitleStyle()
            verify(contentFrame).removeView(subtitleView)
            verify(overlay).addView(subtitleView, 0, params.constructed().single())
            verify(subtitleView).setBottomPaddingFraction(0f)
            verify(subtitleView).setViewType(SubtitleView.VIEW_TYPE_CANVAS)
            verify(subtitleView).setUserDefaultStyle()
            verify(subtitleView).setUserDefaultTextSize()

            `when`(subtitleView.parent).thenReturn(overlay)
            controller.applySubtitleStyle()
            verify(overlay, times(1)).addView(subtitleView, 0, params.constructed().single())
        }
    }

    @Test
    fun `single and dual modes both allow zero bottom padding with system captions enabled`() {
        val subtitleView = host.playerView.subtitleView!!
        val overlay = host.playerView.overlayFrameLayout!!
        `when`(subtitleView.parent).thenReturn(overlay)
        controller.primarySubtitlePosition = 100.0
        for (dual in listOf(false, true)) {
            `when`(host.subtitles.dualSubtitleController.isEnabled).thenReturn(dual)
            controller.applySubtitleStyle()
            verify(subtitleView).setApplyEmbeddedStyles(dual)
            verify(subtitleView).setApplyEmbeddedFontSizes(dual)
        }
        verify(subtitleView, times(2)).setBottomPaddingFraction(0f)
        verify(subtitleView, times(2)).setUserDefaultTextSize()
    }

    @Test
    fun `bitmap subtitles return to video frame and text returns to full window`() {
        val subtitleView = host.playerView.subtitleView!!
        val overlay = host.playerView.overlayFrameLayout!!
        val contentFrame = mock(FrameLayout::class.java)
        val bitmapGroup = CueGroup(listOf(
            Cue.Builder().setBitmap(mock(Bitmap::class.java))
                .setPosition(0.25f).setLine(0.8f, Cue.LINE_TYPE_FRACTION)
                .setSize(0.5f).setBitmapHeight(0.1f).build(),
        ), 1L)
        val textGroup = CueGroup(listOf(Cue.Builder().setText("Subtitle").build()), 2L)
        `when`(subtitleView.parent).thenReturn(contentFrame)
        mockConstruction(FrameLayout.LayoutParams::class.java).use { params ->
            controller.applySubtitleStyle()
            `when`(subtitleView.parent).thenReturn(overlay)
            controller.onCues(bitmapGroup)
            verify(overlay).removeView(subtitleView)
            verify(contentFrame).addView(subtitleView, params.constructed()[1])
            `when`(subtitleView.parent).thenReturn(contentFrame)
            controller.onCues(CueGroup.EMPTY_TIME_ZERO)
            controller.onCues(bitmapGroup)
            controller.applySubtitleStyle()
            // Changing style and clear cues must not put a bitmap back in window coordinates.
            verify(contentFrame, times(1)).removeView(subtitleView)
            controller.onCues(textGroup)
            verify(contentFrame, times(2)).removeView(subtitleView)
            verify(overlay).addView(subtitleView, 0, params.constructed()[2])
        }
    }

    @Test
    fun `bitmap arriving before style initialization stays in original video frame`() {
        val subtitleView = host.playerView.subtitleView!!
        val contentFrame = mock(FrameLayout::class.java)
        `when`(subtitleView.parent).thenReturn(contentFrame)
        controller.onCues(CueGroup(listOf(
            Cue.Builder().setBitmap(mock(Bitmap::class.java)).build(),
        ), 1L))
        controller.applySubtitleStyle()
        verify(contentFrame, never()).removeView(subtitleView)
        verify(host.playerView.overlayFrameLayout!!, never())
            .addView(eq(subtitleView), anyInt(), any(android.view.ViewGroup.LayoutParams::class.java))
    }
}
