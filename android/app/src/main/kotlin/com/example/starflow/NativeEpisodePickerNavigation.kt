package com.example.starflow

// Returns the same index at horizontal boundaries, and out-of-range indices for toolbar exits.
internal fun episodePickerNeighbor(index: Int, count: Int, grid: Boolean, delta: Int): Int {
    if (!grid) return index + delta
    val start = index / 30 * 30
    val end = minOf(start + 30, count)
    val column = (index - start) % 4
    if ((delta == -1 && column == 0) ||
        (delta == 1 && (column == 3 || index == end - 1))) return index
    val next = index + delta
    if (delta == 4 && next >= end) {
        return if (end < count) minOf(end + column, count - 1)
        else if ((index - start) / 4 < (end - start - 1) / 4) end - 1
        else count
    }
    if (delta == -4 && next < start && start > 0) return start - 2 + minOf(column, 1)
    return next
}
