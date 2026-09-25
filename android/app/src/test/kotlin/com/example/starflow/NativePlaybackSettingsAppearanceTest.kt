package com.example.starflow

import android.app.Activity
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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

    @Test
    fun `every native playback alert explicitly shares the neutral theme`() {
        val sources = File("src/main/kotlin/com/example/starflow").listFiles()!!
            .filter { it.name.startsWith("Native") && it.extension == "kt" }
        val builders = Regex("AlertDialog\\.Builder\\(([^)]*)\\)")
        var count = 0
        for (source in sources) {
            for (builder in builders.findAll(source.readText())) {
                count++
                assertTrue(source.name, builder.groupValues[1].endsWith(
                    ", R.style.NativePlaybackSettingsDialogTheme",
                ))
            }
        }
        assertTrue("Expected native playback dialogs", count > 0)
    }

    @Test
    fun `episode panel shares palette while playback surfaces stay black and translucent`() {
        val picker = File("src/main/kotlin/com/example/starflow/NativePlaybackEpisodePicker.kt").readText()
        for (color in listOf("background", "title", "value")) {
            assertTrue(picker.contains("activity.getColor(R.color.native_settings_$color)"))
        }
        assertTrue(picker.contains("decorView.elevation = 0f"))
        for (device in listOf("phone", "tv")) {
            val surface = parse("layout/native_player_view_$device.xml").documentElement
            assertEquals("@android:color/black", surface.getAttributeNS(ANDROID_NS, "background"))
        }
        val colors = parse("values/native_player_colors.xml").getElementsByTagName("color")
        val values = (0 until colors.length).associate {
            val color = colors.item(it) as Element
            color.getAttribute("name") to color.textContent
        }
        assertEquals("#CC18181B", values["native_settings_background"])
        assertEquals("#4D000000", values["native_player_overlay_scrim"])
    }

    private fun parse(path: String) = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
    }.newDocumentBuilder().parse(File("src/main/res/$path"))

    @Test
    fun `episode tools live above the list without a footer`() {
        val picker = File("src/main/kotlin/com/example/starflow/NativePlaybackEpisodePicker.kt").readText()
        assertTrue(picker.contains("if (!television) header.addView(tool(R.drawable.native_player_back_24, \"返回\") { dismiss() })"))
        assertTrue(!picker.contains("locateButton"))
        assertTrue(!picker.contains("定位当前集"))
        assertTrue(picker.contains("addView(rangeButton, LinearLayout.LayoutParams(dp(112), ViewGroup.LayoutParams.MATCH_PARENT))"))
        assertTrue(picker.contains("rangeButton.visibility = if (queue.entries.size > PAGE_SIZE) View.VISIBLE else View.GONE"))
        assertTrue(!picker.contains("footer"))
        assertTrue(!picker.contains("\"上一段\""))
        assertTrue(!picker.contains("\"下一段\""))
        assertTrue(picker.contains("next in queue.entries.indices && next != index -> move(next)"))
        assertTrue(picker.contains("KeyEvent.KEYCODE_DPAD_UP -> { gridButton.requestFocus(); true }"))
        assertTrue(picker.contains("this === gridButton && rangeButton.isShown && rangeButton.isEnabled"))
    }

    @Test
    fun `episode states use Flutter accent while focus stays white`() {
        val sources = File("src/main/kotlin/com/example/starflow")
        val picker = File(sources, "NativePlaybackEpisodePicker.kt").readText()
        val main = File(sources, "MainActivity.kt").readText()
        val launcher = File("../../lib/features/playback/data/native_playback_launcher_io.dart").readText()
        assertTrue(launcher.contains("'episodeAccentColor':"))
        assertTrue(launcher.contains("_ref.read(appSettingsProvider).appAccent.primary.toARGB32()"))
        assertTrue(main.contains("call.argument<Number>(\"episodeAccentColor\")?.toInt()"))
        assertTrue(main.contains("NativePlaybackActivity.EXTRA_EPISODE_ACCENT_COLOR,"))
        assertTrue(launcher.contains("'uiTextScale':"))
        assertTrue(main.contains("call.argument<Number>(\"uiTextScale\")"))
        assertTrue(main.contains("NativePlaybackActivity.EXTRA_UI_TEXT_SCALE,"))
        assertTrue(picker.contains("activity.intent.getIntExtra("))
        assertTrue(picker.contains("NativePlaybackActivity.EXTRA_EPISODE_ACCENT_COLOR, 0xFF2DD4BF.toInt()"))
        assertTrue(picker.contains("(accent and 0x00FFFFFF) or (23 shl 24)"))
        assertTrue(picker.contains("progressTintList = ColorStateList.valueOf(accent)"))
        assertTrue(picker.contains("imageTintList = ColorStateList.valueOf(if (playing) accent else muted)"))
        assertTrue(picker.contains("setTextColor(if (playing) accent else muted)"))
        assertTrue(picker.contains("if (focus) setStroke(dp(2), Color.WHITE)"))
    }

    companion object {
        private const val ANDROID_NS = "http://schemas.android.com/apk/res/android"
    }
}
