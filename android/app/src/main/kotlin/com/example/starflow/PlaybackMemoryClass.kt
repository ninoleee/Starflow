package com.example.starflow

import android.app.ActivityManager
import android.content.Context
import android.content.pm.ApplicationInfo

internal object PlaybackMemoryClass {
    fun read(context: Context): Int {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val flags = context.applicationInfo.flags
        val normalMb = manager.memoryClass
        val largeMb = manager.largeMemoryClass
        val maxHeapBytes = Runtime.getRuntime().maxMemory()
        NativeAppLogger.log(
            level = "info",
            category = "playback.memory-class",
            message = "Resolved Android playback heap allowance",
            fields = diagnosticFields(flags, normalMb, largeMb, maxHeapBytes),
        )
        return resolve(maxHeapBytes)
    }

    internal fun diagnosticFields(
        flags: Int, normalMb: Int, largeMb: Int, maxHeapBytes: Long,
    ): Map<String, Any> = mapOf(
        "largeHeapRequested" to (flags and ApplicationInfo.FLAG_LARGE_HEAP != 0),
        "normalMemoryClassMb" to normalMb,
        "largeMemoryClassMb" to largeMb,
        "runtimeMaxHeapBytes" to maxHeapBytes,
        "runtimeMaxHeapMiB" to (maxHeapBytes / (1024 * 1024)),
        "effectiveMemoryClassMb" to resolve(maxHeapBytes),
    )

    // Reported classes and the request flag are diagnostic only; use the running VM's limit.
    fun resolve(maxHeapBytes: Long): Int =
        (maxHeapBytes / (1024 * 1024)).coerceIn(1, Int.MAX_VALUE.toLong()).toInt()
}
