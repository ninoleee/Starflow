package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.os.Build
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.SeekBar
import android.widget.TextView
import kotlin.math.roundToInt

internal object NativePlaybackNumberPicker {
    fun create(
        activity: Activity,
        title: String,
        current: Double,
        range: IntRange,
        format: (Double) -> String,
        onChanged: (Double) -> Unit,
    ): AlertDialog = createStepped(
        activity = activity,
        title = title,
        current = current,
        min = range.first.toDouble(),
        max = range.last.toDouble(),
        step = 1.0,
        format = format,
        onChanged = onChanged,
    )

    fun createStepped(
        activity: Activity,
        title: String,
        current: Double,
        min: Double,
        max: Double,
        step: Double,
        format: (Double) -> String,
        onChanged: (Double) -> Unit,
    ): AlertDialog {
        require(min < max) { "Picker minimum must be lower than maximum" }
        require(step > 0.0 && step.isFinite()) { "Picker step must be positive" }
        val view = activity.layoutInflater.inflate(R.layout.native_playback_number_picker, null)
        val decrease = view.findViewById<Button>(R.id.native_number_decrease)
        val increase = view.findViewById<Button>(R.id.native_number_increase)
        val label = view.findViewById<TextView>(R.id.native_number_value)
        val slider = view.findViewById<SeekBar>(R.id.native_number_slider)
        val maxStepIndex = ((max - min) / step).roundToInt()
        var stepIndex = if (current.isFinite()) {
            ((current.coerceIn(min, max) - min) / step).roundToInt().coerceIn(0, maxStepIndex)
        } else {
            0
        }

        fun valueAt(index: Int): Double = min + (index * step)

        fun render() {
            label.text = format(valueAt(stepIndex))
            slider.progress = stepIndex
            decrease.isEnabled = stepIndex > 0
            increase.isEnabled = stepIndex < maxStepIndex
        }

        fun change(next: Int) {
            val bounded = next.coerceIn(0, maxStepIndex)
            if (bounded == stepIndex) return
            stepIndex = bounded
            render()
            onChanged(valueAt(stepIndex))
        }

        decrease.contentDescription = "减少$title"
        increase.contentDescription = "增加$title"
        slider.contentDescription = title
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            decrease.tooltipText = decrease.contentDescription
            increase.tooltipText = increase.contentDescription
        }
        slider.max = maxStepIndex
        slider.keyProgressIncrement = 1
        render()
        decrease.setOnClickListener { change(stepIndex - 1) }
        increase.setOnClickListener { change(stepIndex + 1) }
        slider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                if (fromUser) change(progress)
            }

            override fun onStartTrackingTouch(seekBar: SeekBar) = Unit
            override fun onStopTrackingTouch(seekBar: SeekBar) = Unit
        })

        return AlertDialog.Builder(activity)
            .setTitle(title)
            .setView(view)
            .setPositiveButton("完成", null)
            .create()
            .apply {
                setOnShowListener {
                    // Keep the lower picture visible while adjusting subtitle placement.
                    window?.setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL)
                    window?.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                    slider.requestFocus()
                }
            }
    }
}
