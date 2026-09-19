package com.example.starflow

import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlaybackSourceTest {
    @Test
    fun requestHeadersPreserveProviderUserAgent() {
        val headers = NativePlaybackSource.buildRequestHeaders(
            """{"User-Agent":"Browser UA","Referer":"https://example.com/"}""",
        )

        assertEquals("Browser UA", headers["User-Agent"])
        assertEquals("https://example.com/", headers["Referer"])
    }

    @Test
    fun requestHeadersUseStarflowWithoutProviderUserAgent() {
        assertEquals(
            "Starflow",
            NativePlaybackSource.buildRequestHeaders(
                """{"Referer":"https://example.com/"}""",
            )["User-Agent"],
        )
        assertEquals(
            "Starflow",
            NativePlaybackSource.buildRequestHeaders("not-json")["User-Agent"],
        )
    }
}
