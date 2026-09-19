package com.example.starflow

import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.text.CueGroup
import androidx.media3.exoplayer.ForwardingRenderer
import androidx.media3.exoplayer.FormatHolder
import androidx.media3.decoder.DecoderInputBuffer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RendererConfiguration
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.SampleStream
import androidx.media3.exoplayer.text.TextOutput
import androidx.media3.exoplayer.text.TextRenderer

/** One pending UI delivery per renderer, including empty (clear) cue groups. */
internal class NativeSubtitleOutput(
    private val output: TextOutput,
    private val post: (Runnable) -> Unit,
) : TextOutput {
    private var pending: CueGroup? = null
    private var scheduled = false
    private var batching = false
    private var closed = false
    @Volatile
    var revision: Long = 0L
        private set

    @Synchronized
    override fun onCues(cueGroup: CueGroup) {
        if (closed) return
        revision++
        pending = cueGroup
        schedule()
    }

    @Synchronized
    fun beginBatch() { batching = true }

    @Synchronized
    fun endBatch(publish: Boolean = true) {
        batching = !publish
        schedule()
    }

    @Synchronized
    fun invalidate() { pending = null }

    @Synchronized
    fun close() {
        closed = true
        pending = null
    }

    private fun schedule() {
        if (batching || scheduled || closed || pending == null) return
        scheduled = true
        post(Runnable { deliver() })
    }

    @Synchronized
    private fun deliver() {
        scheduled = false
        if (closed || batching) return
        val current = pending ?: return
        pending = null
        // Serialize delivery with invalidate so a pre-seek update cannot escape afterward.
        output.onCues(current)
    }
}

/** Keep Media3's cue resolver/clock, but drain overdue bitmap samples in bounded batches. */
internal class NativeSubtitleRenderer(
    private val delegate: Renderer,
    private val output: NativeSubtitleOutput,
) : ForwardingRenderer(delegate) {
    private var catchUpPgs = false
    private var originalStream: SampleStream? = null
    private var gatedStream: BitmapSubtitleSampleStream? = null
    private var positionUs = 0L
    private var catchUpBatches = 0L
    private var lastCatchUpLogNs = 0L

    override fun enable(
        configuration: RendererConfiguration, formats: Array<Format>, stream: SampleStream,
        positionUs: Long, joining: Boolean, mayRenderStartOfStream: Boolean,
        startPositionUs: Long, offsetUs: Long, mediaPeriodId: MediaSource.MediaPeriodId,
    ) {
        configure(formats)
        this.positionUs = positionUs
        super.enable(configuration, formats, wrap(stream, offsetUs), positionUs, joining,
            mayRenderStartOfStream, startPositionUs, offsetUs, mediaPeriodId)
    }

    override fun replaceStream(formats: Array<Format>, stream: SampleStream,
        startPositionUs: Long, offsetUs: Long, mediaPeriodId: MediaSource.MediaPeriodId) {
        configure(formats)
        super.replaceStream(formats, wrap(stream, offsetUs), startPositionUs, offsetUs, mediaPeriodId)
    }

    // ExoPlayer compares stream identity to the MediaPeriod stream, not our internal gate.
    override fun getStream(): SampleStream? = originalStream

    private fun wrap(stream: SampleStream, offsetUs: Long): SampleStream {
        originalStream = stream
        gatedStream = if (catchUpPgs) BitmapSubtitleSampleStream(stream, offsetUs) else null
        gatedStream?.positionUs = positionUs
        return gatedStream ?: stream
    }

    private fun configure(formats: Array<Format>) {
        output.invalidate()
        catchUpPgs = formats.all {
            it.sampleMimeType == MimeTypes.APPLICATION_MEDIA3_CUES &&
                NativeBitmapSubtitlePolicy.isBitmap(it.codecs)
        } && formats.isNotEmpty()
    }

    override fun render(positionUs: Long, elapsedRealtimeUs: Long) {
        this.positionUs = positionUs
        gatedStream?.positionUs = positionUs
        output.beginBatch()
        var publish = true
        try {
            repeat(if (catchUpPgs) MAX_PGS_READS_PER_RENDER else 1) {
                val before = delegate.readingPositionUs
                val revision = output.revision
                delegate.render(positionUs, elapsedRealtimeUs)
                val after = delegate.readingPositionUs
                if (delegate.isEnded || after == C.TIME_END_OF_SOURCE ||
                    after > positionUs || (after <= before && revision == output.revision)) return
            }
            // Still catching up: do not flash the obsolete last cue of this batch.
            if (catchUpPgs) {
                publish = false
                catchUpBatches++
                val now = System.nanoTime()
                if (lastCatchUpLogNs == 0L || now - lastCatchUpLogNs >= 5_000_000_000L) {
                    lastCatchUpLogNs = now
                    NativeAppLogger.log("info", "subtitle.catch-up", "Bitmap catch-up batch exhausted",
                        fields = mapOf("batches" to catchUpBatches, "positionUs" to positionUs))
                }
            }
        } finally {
            output.endBatch(publish)
        }
    }

    override fun resetPosition(positionUs: Long, sampleStreamIsResetToKeyFrame: Boolean) {
        this.positionUs = positionUs
        gatedStream?.reset(positionUs)
        output.invalidate()
        super.resetPosition(positionUs, sampleStreamIsResetToKeyFrame)
        output.endBatch()
    }

    override fun disable() {
        output.invalidate()
        // TextRenderer.onDisabled does not clear its cue resolver. Its public position reset does.
        if (catchUpPgs) super.resetPosition(positionUs, false)
        super.disable()
        originalStream = null
        gatedStream = null
        output.endBatch()
    }

    override fun release() {
        output.close()
        super.release()
    }

    companion object {
        internal const val MAX_PGS_READS_PER_RENDER = 32

        fun create(output: TextOutput, looper: Looper): NativeSubtitleRenderer {
            val handler = Handler(looper)
            val mailbox = NativeSubtitleOutput(output) { handler.post(it) }
            return NativeSubtitleRenderer(TextRenderer(mailbox, null), mailbox)
        }
    }
}

/** At most one future sample enters the resolver. Clock/render calls must never be gated. */
internal class BitmapSubtitleSampleStream(
    private val source: SampleStream,
    private val offsetUs: Long,
) : SampleStream by source {
    var positionUs = 0L
    private var lastReadUs = Long.MIN_VALUE

    fun reset(positionUs: Long) {
        this.positionUs = positionUs
        lastReadUs = Long.MIN_VALUE
    }

    override fun readData(holder: FormatHolder, buffer: DecoderInputBuffer, flags: Int): Int {
        if (lastReadUs > positionUs) return C.RESULT_NOTHING_READ
        val result = source.readData(holder, buffer, flags)
        if (result == C.RESULT_BUFFER_READ && !buffer.isEndOfStream &&
            flags and SampleStream.FLAG_PEEK == 0) {
            lastReadUs = buffer.timeUs + offsetUs
        }
        return result
    }
}
