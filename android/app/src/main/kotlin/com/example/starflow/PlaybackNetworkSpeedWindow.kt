package com.example.starflow

import kotlin.math.roundToLong

internal class PlaybackNetworkSpeedWindow {
    private val samples = java.util.ArrayDeque<Long>()

    fun add(speed: Long?): Long? {
        if (speed == null || speed <= 0L) {
            samples.clear()
            return if (speed == 0L) 0L else null
        }
        samples.addLast(speed)
        if (samples.size > 3) samples.removeFirst()
        return samples.map { it.toDouble() }.average().roundToLong()
    }
}
