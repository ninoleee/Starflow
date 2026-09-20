package com.example.starflow

import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito.mock

class LiveTvNetworkSpeedTest {
    @Test fun aggregatesParallelMediaReadsAndDropsIdleSpeed() {
        var now = 0L
        val speed = LiveTvNetworkSpeed { now }
        val source = mock(DataSource::class.java)
        val spec = mock(DataSpec::class.java)
        assertEquals(0L, speed.bytesPerSecond)
        speed.onBytesTransferred(source, spec, true, 1024)
        speed.onBytesTransferred(source, spec, true, 3072)
        speed.onBytesTransferred(source, spec, false, 9000)
        speed.onBytesTransferred(source, spec, true, -1)
        speed.sample()
        now = 2000
        speed.sample()
        assertEquals(2048L, speed.bytesPerSecond)
        now = 3000
        speed.sample()
        assertEquals(0L, speed.bytesPerSecond)
    }
}
