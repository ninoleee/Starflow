package com.example.starflow

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Element

class NativePlayerControlLayoutTest {
    @Test
    fun `top and bottom controls rely on the shared scrim on phone and television`() {
        for (device in listOf("phone", "tv")) {
            val file = File("src/main/res/layout/native_player_control_view_$device.xml")
            val document = DocumentBuilderFactory.newInstance().apply {
                isNamespaceAware = true
            }.newDocumentBuilder().parse(file)
            val labels = document.getElementsByTagName("TextView")
            val speed = (0 until labels.length).map { labels.item(it) as Element }
                .single { it.getAttributeNS(ANDROID_NS, "id") == "@+id/native_network_speed" }
            assertEquals(device, "", speed.getAttributeNS(ANDROID_NS, "background"))
            val topBar = speed.parentNode as Element
            assertEquals(device, "@id/exo_top_controls", topBar.getAttributeNS(ANDROID_NS, "id"))
            assertEquals(device, "", topBar.getAttributeNS(ANDROID_NS, "background"))
            val bottomBar = elementWithId(document, "@id/exo_bottom_bar")
            assertEquals(device, "", bottomBar.getAttributeNS(ANDROID_NS, "background"))
            val scrim = elementWithId(document, "@id/exo_controls_background")
            assertEquals(device, "@color/native_player_overlay_scrim", scrim.getAttributeNS(ANDROID_NS, "background"))
        }
    }

    @Test
    fun `play pause highlights stay circular without borders`() {
        val file = File("src/main/res/drawable/native_player_play_pause_background.xml")
        val document = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
        }.newDocumentBuilder().parse(file)
        assertEquals(0, document.getElementsByTagName("stroke").length)
        val shapes = document.getElementsByTagName("shape")
        assertEquals(3, shapes.length)
        for (index in 0 until shapes.length) {
            val shape = shapes.item(index) as Element
            assertEquals("oval", shape.getAttributeNS(ANDROID_NS, "shape"))
            assertEquals(1, shape.getElementsByTagName("solid").length)
        }
    }

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
            if (device == "tv") {
                assertEquals("false", playPause.single().getAttributeNS(ANDROID_NS, "focusable"))
                assertEquals("false", playPause.single().getAttributeNS(ANDROID_NS, "focusableInTouchMode"))
            }
        }
    }

    companion object {
        private const val ANDROID_NS = "http://schemas.android.com/apk/res/android"

        private fun elementWithId(document: org.w3c.dom.Document, id: String): Element {
            val views = document.getElementsByTagName("*")
            return (0 until views.length).map { views.item(it) as Element }
                .single { it.getAttributeNS(ANDROID_NS, "id") == id }
        }
    }
}
