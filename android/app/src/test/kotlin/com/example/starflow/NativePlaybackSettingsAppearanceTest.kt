package com.example.starflow

import android.app.Activity
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito.*
import org.w3c.dom.Element

class NativePlaybackSettingsAppearanceTest {
    @Test
    fun `only status suffix is muted without changing labels or order`() {
        val activity = mock(Activity::class.java)
        val color = 0xFFBDBDBD.toInt()
        `when`(activity.getColor(R.color.native_settings_value)).thenReturn(color)
        val title = "Speed"
        val status = "Speed · 1.0x · Default"
        mockConstruction(ForegroundColorSpan::class.java) { _, context ->
            assertEquals(listOf(color), context.arguments())
        }.use { spans ->
            mockConstruction(SpannableString::class.java) { _, context ->
                assertEquals(listOf(status), context.arguments())
            }.use { strings ->
                val labels = NativePlaybackSettingsAppearance.labels(activity, listOf(title, status))
                assertEquals(2, labels.size)
                assertEquals(title, labels[0])
                assertEquals(strings.constructed().single(), labels[1])
                verify(strings.constructed().single()).setSpan(
                    spans.constructed().single(), title.length, status.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
                verify(activity, times(1)).getColor(R.color.native_settings_value)
            }
        }
    }

    @Test
    fun `dialog theme uses a flat neutral palette with subtle dividers`() {
        val styles = parse("values/styles.xml").getElementsByTagName("style")
        fun items(name: String): Map<String, String> {
            val style = (0 until styles.length).map { styles.item(it) as Element }
                .single { it.getAttribute("name") == name }
            val items = style.getElementsByTagName("item")
            return (0 until items.length).associate {
                val item = items.item(it) as Element
                item.getAttribute("name") to item.textContent
            }
        }
        val theme = items("NativePlaybackSettingsDialogTheme")
        assertEquals("@color/native_settings_title", theme["android:textColorPrimary"])
        assertEquals("@color/native_settings_value", theme["android:textColorSecondary"])
        assertEquals("@drawable/native_settings_background", theme["android:windowBackground"])
        assertEquals("0dp", theme["android:windowElevation"])
        assertEquals("@drawable/native_settings_divider", theme["android:listDividerAlertDialog"])
        val divider = parse("drawable/native_settings_divider.xml")
        val size = divider.getElementsByTagName("size").item(0) as Element
        assertEquals("1dp", size.getAttributeNS(ANDROID_NS, "height"))
        val background = parse("drawable/native_settings_background.xml")
        assertEquals(0, background.getElementsByTagName("stroke").length)
        assertEquals(0, background.getElementsByTagName("gradient").length)
        val solid = background.getElementsByTagName("solid").item(0) as Element
        assertEquals("@color/native_settings_background", solid.getAttributeNS(ANDROID_NS, "color"))
    }

    @Test
    fun `numeric value uses the same muted color without changing slider dimensions`() {
        val layout = parse("layout/native_playback_number_picker.xml")
        val value = layout.getElementsByTagName("TextView").item(0) as Element
        assertEquals("@color/native_settings_value", value.getAttributeNS(ANDROID_NS, "textColor"))
        val slider = layout.getElementsByTagName("SeekBar").item(0) as Element
        assertEquals("48dp", slider.getAttributeNS(ANDROID_NS, "layout_height"))
        assertEquals("true", slider.getAttributeNS(ANDROID_NS, "focusable"))
    }

    private fun parse(path: String) = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
    }.newDocumentBuilder().parse(File("src/main/res/$path"))

    companion object {
        private const val ANDROID_NS = "http://schemas.android.com/apk/res/android"
    }
}
