package com.example.starflow

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.*
import org.json.JSONObject

internal class NativePlaybackEpisodePicker(
    private val activity: Activity,
    private val original: NativeEpisodeQueue,
    private val memory: NativePlaybackMemoryStore,
    private val browse: (String?, (Map<String, Any?>) -> Unit) -> Boolean,
    private val select: (NativeEpisodeQueue, Int) -> Unit,
) : Dialog(activity) {
    private var queue = original
    private var grid = false
    private var page = original.currentIndex.coerceAtLeast(0) / PAGE_SIZE
    private var focusedIndex = original.currentIndex.coerceAtLeast(0)
    private var requestId = 0
    private var seasons = emptyList<Map<*, *>>()
    private var loading = false
    private val handler = Handler(Looper.getMainLooper())
    private val root = LinearLayout(activity)
    private val subtitle = TextView(activity)
    private val seasonButton = Button(activity)
    private val scroll = ScrollView(activity)
    private val rows = LinearLayout(activity)
    private val footer = LinearLayout(activity)
    private val status = Button(activity)
    private val cells = mutableMapOf<Int, View>()
    private var popup: AlertDialog? = null
    private val target = JSONObject(original.currentEntry()?.playbackTargetJson ?: "{}")
    private val currentKey = original.currentEntry()?.playbackItemKey
    private val muted = activity.getColor(R.color.native_settings_value)
    private val text = activity.getColor(R.color.native_settings_title)

    init {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(20), dp(16), dp(20), dp(12))
        root.setBackgroundColor(activity.getColor(R.color.native_settings_background))
        val header = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(label(target.optString("seriesTitle").ifBlank { "选择剧集" }, 22f).apply {
            maxLines = 2; ellipsize = TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(tool(android.R.drawable.ic_menu_close_clear_cancel, "关闭") { dismiss() })
        root.addView(header)
        val tools = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
        subtitle.setTextColor(muted); subtitle.textSize = 13f
        tools.addView(subtitle, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        seasonButton.text = "季"
        seasonButton.contentDescription = "选择季"
        seasonButton.visibility = View.GONE
        styleButton(seasonButton)
        seasonButton.setOnClickListener { chooseSeason() }
        tools.addView(seasonButton, LinearLayout.LayoutParams(dp(44), dp(44)))
        tools.addView(tool(android.R.drawable.ic_menu_sort_by_size, "列表") { grid = false; render(); focus(focusedIndex) })
        tools.addView(tool(android.R.drawable.ic_menu_agenda, "网格") { grid = true; render(); focus(focusedIndex) })
        root.addView(tools)
        styleButton(status); status.textSize = 13f; status.visibility = View.GONE
        root.addView(status)
        rows.orientation = LinearLayout.VERTICAL
        scroll.isFillViewport = false
        scroll.addView(rows)
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        footer.gravity = Gravity.CENTER_VERTICAL
        root.addView(footer)
        setContentView(root)
        window?.apply {
            decorView.elevation = 0f
            setWindowAnimations(0)
            setBackgroundDrawableResource(android.R.color.transparent)
            setGravity(Gravity.END or Gravity.CENTER_VERTICAL)
            val width = activity.resources.displayMetrics.widthPixels
            setLayout(if (width < dp(600)) width else (width * .30).toInt().coerceIn(dp(320), dp(600)), ViewGroup.LayoutParams.MATCH_PARENT)
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setDimAmount(.18f)
        }
        setOnShowListener {
            render(); focus(focusedIndex); loadSeasons()
        }
    }

    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
    private fun label(value: String, size: Float) = TextView(activity).apply {
        this.text = value; textSize = size; setTextColor(this@NativePlaybackEpisodePicker.text)
    }
    private fun background(playing: Boolean = false): StateListDrawable {
        fun shape(focus: Boolean) = GradientDrawable().apply {
            cornerRadius = dp(6).toFloat()
            setColor(if (playing) Color.rgb(48, 48, 51) else Color.TRANSPARENT)
            if (focus) setStroke(dp(2), Color.WHITE)
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), shape(true))
            addState(intArrayOf(), shape(false))
        }
    }
    private fun styleButton(view: View, playing: Boolean = false) {
        view.isFocusable = true; view.background = background(playing)
        if (view is TextView) { view.setTextColor(text); view.isAllCaps = false }
    }
    private fun tool(icon: Int, description: String, action: () -> Unit) = ImageButton(activity).apply {
        setImageResource(icon); imageTintList = ColorStateList.valueOf(text)
        contentDescription = description; styleButton(this)
        layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
        setOnClickListener { action() }
    }
    private fun number(index: Int): Int = JSONObject(queue.entries[index].playbackTargetJson).optInt("episodeNumber", index + 1)
    private fun currentSeasonNumber() = JSONObject(queue.entries.first().playbackTargetJson).optInt("seasonNumber", 0)

    private fun render() {
        rows.removeAllViews(); cells.clear(); footer.removeAllViews()
        val season = currentSeasonNumber()
        subtitle.text = "${if (season == 0) "特别篇" else "第 $season 季"} · 共 ${queue.entries.size} 集"
        if (!loading) {
            val start = page * PAGE_SIZE
            val end = minOf(start + PAGE_SIZE, queue.entries.size)
            var row: LinearLayout? = null
            for (index in start until end) {
                if (!grid || (index - start) % 4 == 0) {
                    row = LinearLayout(activity)
                    rows.addView(row, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(if (grid) 86 else 80)))
                }
                val cell = cell(index)
                cells[index] = cell
                row!!.addView(cell, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply { setMargins(dp(4), dp(4), dp(4), dp(4)) })
            }
            if (grid && (end - start) % 4 != 0) repeat(4 - (end - start) % 4) {
                row?.addView(View(activity), LinearLayout.LayoutParams(0, 1, 1f))
            }
        }
        footer.addView(tool(android.R.drawable.ic_media_previous, "上一段") { move((page - 1) * PAGE_SIZE) }.apply { isEnabled = !loading && page > 0; alpha = if (isEnabled) 1f else .3f })
        val range = Button(activity).apply {
            styleButton(this); textSize = 13f
            val start = page * PAGE_SIZE
            text = "${number(start)}–${number(minOf(start + PAGE_SIZE, queue.entries.size) - 1)} 集"
            isEnabled = !loading && queue.entries.size > PAGE_SIZE
            setOnClickListener { chooseRange() }
        }
        footer.addView(range, LinearLayout.LayoutParams(0, dp(44), 1f))
        footer.addView(tool(android.R.drawable.ic_media_next, "下一段") { move((page + 1) * PAGE_SIZE) }.apply { isEnabled = !loading && (page + 1) * PAGE_SIZE < queue.entries.size; alpha = if (isEnabled) 1f else .3f })
        footer.addView(tool(android.R.drawable.ic_menu_mylocation, "定位当前集") {
            requestId++; loading = false; status.visibility = View.GONE; queue = original
            page = original.currentIndex.coerceAtLeast(0) / PAGE_SIZE
            render(); move(original.currentIndex)
        })
    }

    private fun cell(index: Int): View {
        val entry = queue.entries[index]
        val playing = entry.playbackItemKey == currentKey
        val history = memory.loadPlaybackEntry(entry.playbackItemKey)
        val watched = history?.optBoolean("completed") == true
        val progress = history?.optDouble("progress", 0.0)?.coerceIn(0.0, 1.0) ?: 0.0
        val statusText = when {
            playing -> "正在播放"
            watched -> "已看完"
            (history?.optLong("positionMs") ?: 0L) > 0 -> "已看 ${(history?.optLong("positionMs") ?: 0L) / 60000} 分钟"
            else -> ""
        }
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(6), dp(12), dp(6)); styleButton(this, playing)
        }
        val title = entry.title().ifBlank { "第 ${number(index)} 集" }
        content.contentDescription = "第 ${number(index)} 集，$title，$statusText"
        val line = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; orientation = if (grid) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL }
        line.addView(label(number(index).toString().padStart(2, '0'), if (grid) 22f else 20f), LinearLayout.LayoutParams(if (grid) ViewGroup.LayoutParams.WRAP_CONTENT else dp(46), ViewGroup.LayoutParams.WRAP_CONTENT))
        val details = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        if (!grid) details.addView(label(title, 15f).apply { maxLines = 2; ellipsize = TextUtils.TruncateAt.END })
        if (statusText.isNotBlank()) details.addView(label(statusText, 12f).apply { setTextColor(muted); maxLines = 1; ellipsize = TextUtils.TruncateAt.END })
        line.addView(details, if (grid) LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT) else LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (!grid && (playing || watched)) line.addView(ImageView(activity).apply {
            setImageResource(if (playing) android.R.drawable.ic_media_play else android.R.drawable.checkbox_on_background)
            imageTintList = ColorStateList.valueOf(text)
        }, LinearLayout.LayoutParams(dp(18), dp(18)))
        content.addView(line, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        if (progress > 0 && !watched) content.addView(ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000; this.progress = (progress * 1000).toInt(); progressTintList = ColorStateList.valueOf(Color.rgb(45, 212, 191))
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2)))
        content.setOnClickListener { select(queue, index) }
        content.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) { focusedIndex = index; scroll.post { center(content) } }
        }
        content.setOnKeyListener { _, key, event ->
            val delta = when (key) {
                KeyEvent.KEYCODE_DPAD_DOWN -> if (grid) 4 else 1
                KeyEvent.KEYCODE_DPAD_UP -> if (grid) -4 else -1
                KeyEvent.KEYCODE_DPAD_LEFT -> if (grid) -1 else 0
                KeyEvent.KEYCODE_DPAD_RIGHT -> if (grid) 1 else 0
                else -> 0
            }
            if (event.action != KeyEvent.ACTION_DOWN || delta == 0 || index + delta !in queue.entries.indices) false
            else { move(index + delta); true }
        }
        return content
    }

    private fun center(view: View) {
        val row = view.parent as? View ?: return
        scroll.smoothScrollTo(0, (row.top - (scroll.height - row.height) / 2).coerceAtLeast(0))
    }
    private fun focus(index: Int) { root.post { if (isShowing) { cells[index]?.requestFocus(); cells[index]?.let(::center) } } }
    private fun move(index: Int) {
        if (index !in queue.entries.indices) return
        focusedIndex = index
        val nextPage = index / PAGE_SIZE
        if (nextPage != page || cells[index] == null) { page = nextPage; render() }
        focus(index)
    }
    private fun showOptions(title: String, labels: Array<String>, current: Int, action: (Int) -> Unit) {
        popup?.dismiss()
        popup = AlertDialog.Builder(activity, R.style.NativePlaybackSettingsDialogTheme).setTitle(title).setSingleChoiceItems(labels, current) { dialog, index -> dialog.dismiss(); action(index) }.setNegativeButton("关闭", null).create().also {
            it.window?.setWindowAnimations(0)
            it.show()
        }
    }
    private fun chooseRange() {
        val labels = (0 until (queue.entries.size + PAGE_SIZE - 1) / PAGE_SIZE).map { page ->
            "${number(page * PAGE_SIZE)}–${number(minOf((page + 1) * PAGE_SIZE, queue.entries.size) - 1)} 集"
        }.toTypedArray()
        showOptions("选择集数范围", labels, page) { move(it * PAGE_SIZE) }
    }
    private fun chooseSeason() {
        showOptions("选择季", seasons.map { it["title"].toString() }.toTypedArray(), seasons.indexOfFirst { (it["number"] as? Number)?.toInt() == currentSeasonNumber() }) { index ->
            loadSeason(seasons[index]["id"].toString())
        }
    }
    private fun request(id: String?, complete: (Map<String, Any?>) -> Unit) {
        val token = ++requestId
        val timeout = Runnable {
            if (isShowing && token == requestId) { requestId++; complete(mapOf("ok" to false)) }
        }
        handler.postDelayed(timeout, 30000)
        if (!browse(id) { result -> activity.runOnUiThread {
            if (isShowing && token == requestId) { handler.removeCallbacks(timeout); complete(result) }
        } }) {
            handler.removeCallbacks(timeout); complete(mapOf("ok" to false))
        }
    }
    private fun loadSeasons() {
        request(null) { result ->
            if (result["ok"] == true) {
                seasons = (result["seasons"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
                seasonButton.visibility = if (seasons.size > 1) View.VISIBLE else View.GONE
                status.visibility = View.GONE
            } else {
                status.visibility = View.VISIBLE; status.text = "季列表加载失败 · 重试"
                status.setOnClickListener { loadSeasons() }
            }
        }
    }
    private fun loadSeason(id: String) {
        loading = true
        status.visibility = View.VISIBLE; status.text = "正在加载剧集"; status.isEnabled = false
        render(); seasonButton.requestFocus()
        request(id) { result ->
            val loaded = if (result["ok"] == true) NativeEpisodeQueue.fromJsonString(result["queueJson"]?.toString().orEmpty()) else null
            loading = false; status.isEnabled = true
            if (loaded == null) {
                status.text = "本季加载失败 · 重试"; status.setOnClickListener { loadSeason(id) }; status.requestFocus()
            } else {
                queue = if (JSONObject(loaded.entries.first().playbackTargetJson).optInt("seasonNumber") == target.optInt("seasonNumber")) original else loaded
                page = 0; status.visibility = View.GONE; render(); move(queue.currentIndex.coerceAtLeast(0))
            }
        }
    }
    override fun dismiss() { requestId++; handler.removeCallbacksAndMessages(null); popup?.dismiss(); popup = null; super.dismiss() }
    companion object { const val PAGE_SIZE = 30 }
}
