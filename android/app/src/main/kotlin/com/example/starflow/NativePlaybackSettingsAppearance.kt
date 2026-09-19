package com.example.starflow

import android.app.Activity
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan

internal object NativePlaybackSettingsAppearance {
    fun labels(activity: Activity, labels: List<String>): Array<CharSequence> {
        val valueColor = activity.getColor(R.color.native_settings_value)
        return labels.map { label ->
            val separator = label.indexOf(" · ")
            if (separator < 0) {
                label
            } else {
                SpannableString(label).apply {
                    setSpan(
                        ForegroundColorSpan(valueColor),
                        separator,
                        label.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
            }
        }.toTypedArray()
    }
}
