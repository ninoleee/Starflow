package com.example.starflow

internal class NativePlayerTvSeekPolicy(private val now: () -> Long = System::currentTimeMillis) {
    private var keyCode: Int? = null
    private var startedAtMs: Long? = null
    private var repeatCount = 0

    fun reset(releasedKeyCode: Int? = null) {
        if (releasedKeyCode != null && keyCode != releasedKeyCode) return
        keyCode = null
        startedAtMs = null
        repeatCount = 0
    }

    fun stepMs(pressedKeyCode: Int, eventRepeatCount: Int): Long {
        val timeMs = now()
        if (keyCode != pressedKeyCode || startedAtMs == null) {
            keyCode = pressedKeyCode
            startedAtMs = timeMs
            repeatCount = 0
        } else if (eventRepeatCount > 0) {
            repeatCount = maxOf(repeatCount, eventRepeatCount)
        }
        val heldForMs = timeMs - (startedAtMs ?: timeMs)
        return when {
            heldForMs >= 5_000L || repeatCount >= 12 -> 120_000L
            heldForMs >= 3_000L || repeatCount >= 7 -> 60_000L
            heldForMs >= 1_500L || repeatCount >= 3 -> 30_000L
            else -> 10_000L
        }
    }
}
