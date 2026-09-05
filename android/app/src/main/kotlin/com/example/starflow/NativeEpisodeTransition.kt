package com.example.starflow

internal data class NativeEpisodePreparationKey(
    val queue: NativeEpisodeQueue,
    val index: Int,
    val sourceTargetJson: String,
    val resolverSessionId: String,
    val sourceUrl: String,
    val sourceHeaders: String,
    val sourceMimeType: String,
)

internal class NativeEpisodeTransition(private val now: () -> Long) {
    enum class State {
        IDLE,
        RESOLVING,
        SWITCHING,
        WAITING_FOR_FIRST_FRAME,
        FAILED,
    }

    data class Request(
        val id: Long,
        val key: NativeEpisodePreparationKey,
        val startedAtMs: Long,
        val background: Boolean,
    )

    data class Destination(
        val entry: NativeEpisodeQueueEntry,
        val reason: String,
        val prepared: Boolean,
    )

    sealed interface Decision {
        data class Resolve(val request: Request) : Decision

        data class Ready(val destination: Destination) : Decision

        data object Wait : Decision
    }

    private data class Prepared(
        val key: NativeEpisodePreparationKey,
        val entry: NativeEpisodeQueueEntry,
        val atMs: Long,
    )

    var state = State.IDLE
        private set

    var pending: Request? = null
        private set

    var reason: String? = null
        private set

    private var prepared: Prepared? = null
    private var prefetchAttempt: NativeEpisodePreparationKey? = null
    private var automaticAttempt: NativeEpisodePreparationKey? = null
    private var sequence = 0L

    val isSwitching: Boolean
        get() = state == State.SWITCHING || state == State.WAITING_FOR_FIRST_FRAME

    fun prefetch(key: NativeEpisodePreparationKey): Request? {
        if (state != State.IDLE || pending != null || prefetchAttempt == key) return null
        prefetchAttempt = key
        return newRequest(key, background = true)
    }

    fun begin(key: NativeEpisodePreparationKey, reason: String): Decision {
        if (isSwitching) return Decision.Wait
        if (isAutomatic(reason) && this.reason?.let { !isAutomatic(it) } == true)
            return Decision.Wait
        if (isAutomatic(reason) && automaticAttempt == key) return Decision.Wait
        if (this.reason != null && pending?.key == key) return Decision.Wait
        if (isAutomatic(reason)) automaticAttempt = key
        this.reason = reason
        state = State.RESOLVING
        val cached = prepared
        prepared = null
        if (cached?.key == key && now() - cached.atMs in 0 until PREPARED_TTL_MS) {
            pending = null
            state = State.SWITCHING
            return Decision.Ready(Destination(cached.entry, reason, prepared = true))
        }
        if (pending?.key == key && now() - pending!!.startedAtMs < RESOLUTION_TIMEOUT_MS)
            return Decision.Wait
        return Decision.Resolve(newRequest(key))
    }

    fun resolve(request: Request, entry: NativeEpisodeQueueEntry): Destination? {
        if (pending != request) return null
        pending = null
        val requestedReason = reason
        if (requestedReason == null) {
            prepared = Prepared(request.key, entry, now())
            return null
        }
        state = State.SWITCHING
        return Destination(entry, requestedReason, prepared = request.background)
    }

    fun fail(request: Request): String? {
        if (pending != request) return null
        pending = null
        val failedReason = reason
        reason = null
        if (failedReason != null) state = State.FAILED
        return failedReason
    }

    fun expiredRequest(): Request? =
        pending?.takeIf { now() - it.startedAtMs >= RESOLUTION_TIMEOUT_MS }

    fun awaitFirstFrame() {
        state = State.WAITING_FOR_FIRST_FRAME
        pending = null
        prepared = null
    }

    fun onFirstFrame() {
        if (state == State.WAITING_FOR_FIRST_FRAME) {
            state = State.IDLE
            reason = null
        }
    }

    fun onPlaybackFailed() {
        state = State.FAILED
        reason = null
        pending = null
        prepared = null
    }

    fun cancelAutomaticAdvance() {
        if (isSwitching) return
        automaticAttempt = null
        if (reason?.let(::isAutomatic) == true) {
            reason = null
            state = State.IDLE
        }
    }

    fun reset() {
        sequence += 1L
        state = State.IDLE
        pending = null
        prepared = null
        reason = null
        prefetchAttempt = null
        automaticAttempt = null
    }

    private fun newRequest(key: NativeEpisodePreparationKey, background: Boolean = false): Request =
        Request(++sequence, key, now(), background).also { pending = it }

    companion object {
        const val PREPARED_TTL_MS = 60_000L
        const val RESOLUTION_TIMEOUT_MS = 30_000L

        fun isAutomatic(reason: String): Boolean = reason == "outro" || reason == "ended"
    }
}
