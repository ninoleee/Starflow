package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.content.DialogInterface
import android.view.LayoutInflater
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.widget.Button
import android.widget.SeekBar
import android.widget.TextView
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.ArgumentCaptor
import org.mockito.Mockito.*

class NativePlaybackNumberPickerTest {
    private val activity = mock(Activity::class.java)
    private val inflater = mock(LayoutInflater::class.java)
    private val view = mock(View::class.java)
    private val decrease = mock(Button::class.java)
    private val increase = mock(Button::class.java)
    private val slider = mock(SeekBar::class.java)
    private val label = mock(TextView::class.java)
    private val dialog = mock(AlertDialog::class.java)
    private val window = mock(Window::class.java)
    private val changes = mutableListOf<Double>()

    private fun withPicker(current: Double, range: IntRange, check: () -> Unit) {
        withSteppedPicker(
            current = current,
            min = range.first.toDouble(),
            max = range.last.toDouble(),
            step = 1.0,
            format = { "$it%" },
            check = check,
        )
    }

    private fun withSteppedPicker(
        current: Double,
        min: Double,
        max: Double,
        step: Double,
        format: (Double) -> String,
        check: () -> Unit,
    ) {
        `when`(activity.layoutInflater).thenReturn(inflater)
        `when`(inflater.inflate(R.layout.native_playback_number_picker, null)).thenReturn(view)
        `when`(view.findViewById<Button>(R.id.native_number_decrease)).thenReturn(decrease)
        `when`(view.findViewById<Button>(R.id.native_number_increase)).thenReturn(increase)
        `when`(view.findViewById<SeekBar>(R.id.native_number_slider)).thenReturn(slider)
        `when`(view.findViewById<TextView>(R.id.native_number_value)).thenReturn(label)
        `when`(dialog.window).thenReturn(window)
        mockConstruction(AlertDialog.Builder::class.java, withSettings().defaultAnswer(RETURNS_SELF)) { builder, _ ->
            `when`(builder.create()).thenReturn(dialog)
        }.use {
            NativePlaybackNumberPicker.createStepped(
                activity = activity,
                title = "Value",
                current = current,
                min = min,
                max = max,
                step = step,
                format = format,
            ) {
                changes += it
            }
            check()
        }
    }

    private fun click(button: Button) {
        val listener = ArgumentCaptor.forClass(View.OnClickListener::class.java)
        verify(button).setOnClickListener(listener.capture())
        listener.value.onClick(button)
    }

    @Test
    fun `opening preserves a non preset value without persisting and focuses a one step slider`() {
        withPicker(83.0, 50..100) {
            assertEquals(emptyList<Double>(), changes)
            verify(slider).setProgress(33)
            verify(slider).setKeyProgressIncrement(1)
            verify(label).setText("83.0%")
            val listener = ArgumentCaptor.forClass(DialogInterface.OnShowListener::class.java)
            verify(dialog).setOnShowListener(listener.capture())
            listener.value.onShow(dialog)
            verify(slider).requestFocus()
            verify(window).clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        }
    }

    @Test
    fun `buttons adjust by one and reaching bounds does not save again`() {
        withPicker(99.0, 50..100) {
            click(increase)
            click(increase)
            click(decrease)
            assertEquals(listOf(100.0, 99.0), changes)
            verify(increase).setEnabled(false)
            verify(dialog, never()).dismiss()
        }
    }

    @Test
    fun `slider accepts every integer and ignores programmatic updates and unchanged values`() {
        withPicker(32.0, 20..78) {
            val listener = ArgumentCaptor.forClass(SeekBar.OnSeekBarChangeListener::class.java)
            verify(slider).setOnSeekBarChangeListener(listener.capture())
            listener.value.onProgressChanged(slider, 13, false)
            listener.value.onProgressChanged(slider, 13, true)
            listener.value.onProgressChanged(slider, 13, true)
            listener.value.onProgressChanged(slider, 0, true)
            click(decrease)
            assertEquals(listOf(33.0, 20.0), changes)
            verify(decrease).setEnabled(false)
        }
    }

    @Test
    fun `secondary scale supports one percent changes through 120`() {
        withPicker(119.0, 50..120) {
            verify(slider).setMax(70)
            click(increase)
            click(increase)
            assertEquals(listOf(120.0), changes)
        }
    }

    @Test
    fun `speed supports exact five hundredth steps`() {
        withSteppedPicker(
            current = 1.05,
            min = 0.75,
            max = 2.0,
            step = 0.05,
            format = { NativePlaybackFormatting.formatPlaybackSpeedLabel(it.toFloat()) },
        ) {
            verify(slider).setMax(25)
            verify(slider).setProgress(6)
            verify(label).setText("1.05x")
            click(increase)
            click(decrease)
            assertEquals(listOf(1.1, 1.05), changes)
        }
    }

    @Test
    fun `subtitle delay supports signed hundred millisecond steps across zero`() {
        withSteppedPicker(
            current = -100.0,
            min = -30_000.0,
            max = 30_000.0,
            step = 100.0,
            format = { NativePlaybackFormatting.formatSubtitleDelayLabel(it.toLong()) },
        ) {
            verify(slider).setMax(600)
            verify(slider).setProgress(299)
            verify(label).setText("-0.1s")
            click(increase)
            click(increase)
            assertEquals(listOf(0.0, 100.0), changes)
        }
    }
}
