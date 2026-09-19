package com.example.starflow

import java.util.Locale
import org.json.JSONObject

internal object NativeFntvQualityMenu {
    fun title(quality: JSONObject): String {
        val raw = quality.optString("resolution").trim()
        val normalized = raw.uppercase(Locale.ROOT)
        if (normalized in listOf("原画", "原始", "ORIGINAL", "SOURCE")) return "原画"
        if (normalized in listOf("4K", "2160", "2160P")) return "4K"
        val height = normalized.removeSuffix("P").toIntOrNull()
        if (height != null && height > 0) return "${height}P"
        return raw.ifBlank { "画质 ${kotlin.math.abs(quality.optInt("index")) + 1}" }
    }

    fun detail(quality: JSONObject): String {
        val bitrate = quality.optLong("bitrate")
        return title(quality) + if (bitrate <= 0) "" else if (bitrate >= 1_000_000) {
            String.format(Locale.ROOT, " · %.1f Mbps", bitrate / 1_000_000.0)
        } else " · ${kotlin.math.round(bitrate / 1000.0).toLong()} Kbps"
    }

    fun presets(qualities: List<JSONObject>, current: Int): List<JSONObject> {
        val groups = linkedMapOf<String, JSONObject>()
        for (quality in qualities) {
            val title = title(quality)
            if (title !in groups || quality.optInt("index") == current) groups[title] = quality
        }
        return groups.values.toList()
    }
}
