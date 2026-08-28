package com.example.starflow

data class NativeSubtitleStyleConfig(
    val textSizeFraction: Float,
    val bottomPaddingFraction: Float,
)

object NativeSubtitleStylePolicy {
    const val DEFAULT_SCALE = 32.0
    private const val MIN_SCALE = 20.0
    private const val MAX_SCALE = 78.0
    private const val MIN_TEXT_SIZE_FRACTION = 0.035f
    private const val DEFAULT_TEXT_SIZE_FRACTION = 0.0533f
    private const val MAX_TEXT_SIZE_FRACTION = 0.09f
    private const val TV_BOTTOM_PADDING_FRACTION = 0.08f
    private const val PHONE_BOTTOM_PADDING_FRACTION = 0.10f

    fun resolve(rawScale: Double, isTelevision: Boolean): NativeSubtitleStyleConfig {
        val scale = if (rawScale.isFinite()) {
            rawScale.coerceIn(MIN_SCALE, MAX_SCALE)
        } else {
            DEFAULT_SCALE
        }
        val textSizeFraction = if (scale <= DEFAULT_SCALE) {
            interpolate(
                value = scale,
                inputStart = MIN_SCALE,
                inputEnd = DEFAULT_SCALE,
                outputStart = MIN_TEXT_SIZE_FRACTION,
                outputEnd = DEFAULT_TEXT_SIZE_FRACTION,
            )
        } else {
            interpolate(
                value = scale,
                inputStart = DEFAULT_SCALE,
                inputEnd = MAX_SCALE,
                outputStart = DEFAULT_TEXT_SIZE_FRACTION,
                outputEnd = MAX_TEXT_SIZE_FRACTION,
            )
        }
        return NativeSubtitleStyleConfig(
            textSizeFraction = textSizeFraction,
            bottomPaddingFraction = if (isTelevision) {
                TV_BOTTOM_PADDING_FRACTION
            } else {
                PHONE_BOTTOM_PADDING_FRACTION
            },
        )
    }

    private fun interpolate(
        value: Double,
        inputStart: Double,
        inputEnd: Double,
        outputStart: Float,
        outputEnd: Float,
    ): Float {
        val progress = ((value - inputStart) / (inputEnd - inputStart)).toFloat()
        return outputStart + ((outputEnd - outputStart) * progress)
    }
}
