package com.example.starflow

internal enum class PlaybackDecodeMode {
    AUTO,
    HARDWARE_PREFERRED,
    SOFTWARE_PREFERRED;

    companion object {
        fun fromRaw(raw: String): PlaybackDecodeMode {
            return when (raw) {
                "hardwarePreferred" -> HARDWARE_PREFERRED
                "softwarePreferred" -> SOFTWARE_PREFERRED
                else -> AUTO
            }
        }
    }
}
