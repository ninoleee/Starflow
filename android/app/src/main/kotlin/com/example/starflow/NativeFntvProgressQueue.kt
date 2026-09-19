package com.example.starflow

/** Serial delivery with one latest pending snapshot per media, including final saves. */
internal class NativeFntvProgressQueue(
    private val send: (Map<String, Any?>, () -> Unit) -> Unit,
) {
    private val pending = linkedMapOf<String, Map<String, Any?>>()
    private var sending = false
    private var onDrained: (() -> Unit)? = null

    fun enqueue(key: String, snapshot: Map<String, Any?>) {
        pending[key] = snapshot
        drain()
    }

    fun finish(callback: () -> Unit) {
        onDrained = callback
        drain()
    }

    private fun drain() {
        if (sending) return
        val first = pending.entries.firstOrNull()
        if (first == null) {
            val callback = onDrained
            onDrained = null
            callback?.invoke()
            return
        }
        val snapshot = first.value
        pending.remove(first.key)
        sending = true
        send(snapshot) {
            sending = false
            drain()
        }
    }
}
