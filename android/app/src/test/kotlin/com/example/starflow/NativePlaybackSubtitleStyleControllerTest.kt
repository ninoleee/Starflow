package com.example.starflow

import android.app.Activity
import android.view.accessibility.CaptioningManager
import android.widget.FrameLayout
import androidx.media3.ui.SubtitleView
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
}
