package com.example.starflow

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Element

class NativePlayerControlLayoutTest {
    @Test
    fun `play pause is left aligned in the bottom bar on phone and television`() {
        for (device in listOf("phone", "tv")) {
            val file = File("src/main/res/layout/native_player_control_view_$device.xml")
            val document = DocumentBuilderFactory.newInstance().apply {
                isNamespaceAware = true
            }.newDocumentBuilder().parse(file)
            val buttons = document.getElementsByTagName("ImageButton")
            val playPause = (0 until buttons.length).map { buttons.item(it) as Element }
                .filter { it.getAttributeNS(ANDROID_NS, "id") == "@id/exo_play_pause" }
            assertEquals(device, 1, playPause.size)
            val bottomBar = playPause.single().parentNode as Element
            assertEquals(device, "@id/exo_bottom_bar", bottomBar.getAttributeNS(ANDROID_NS, "id"))
            assertEquals(device, "center_vertical|start", playPause.single().getAttributeNS(ANDROID_NS, "layout_gravity"))
            assertEquals(device, "@drawable/native_player_play_pause_background", playPause.single().getAttributeNS(ANDROID_NS, "background"))
            assertEquals(device, "48dp", playPause.single().getAttributeNS(ANDROID_NS, "layout_height"))
        }
    }

    companion object {
        private const val ANDROID_NS = "http://schemas.android.com/apk/res/android"
    }
}
