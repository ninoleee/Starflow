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
import android.view.ViewTreeObserver
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
    private val preferences = activity.getSharedPreferences("FlutterSharedPreferences", 0)
    private var grid = preferences.getString("flutter.episode_picker_layout", "list") == "grid"
    private var page = original.currentIndex.coerceAtLeast(0) / PAGE_SIZE
    private var focusedIndex = original.currentIndex.coerceAtLeast(0)
    private var requestId = 0
    private var seasons = emptyList<Map<*, *>>()
    private var loading = false
    private var initialPositionPending = true
    private var positionListener: ViewTreeObserver.OnPreDrawListener? = null
    private var locateButton: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private val root = LinearLayout(activity)
    private val subtitle = TextView(activity)
    private val seasonButton = Button(activity)
    private val scroll = ScrollView(activity)
    private val rows = LinearLayout(activity)
    private val footer = LinearLayout(activity)
    private val status = Button(activity)
    private val information = FrameLayout(activity)
    private val seasonRow = FrameLayout(activity)
    private lateinit var listButton: ImageButton
    private lateinit var gridButton: ImageButton
    private val television = (activity.getSystemService(Activity.UI_MODE_SERVICE) as android.app.UiModeManager)
        .currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION
    private val accent = activity.getColor(R.color.native_settings_title)
    private val cells = mutableMapOf<Int, View>()
    private var popup: AlertDialog? = null
    private val target = JSONObject(original.currentEntry()?.playbackTargetJson ?: "{}")
    private val currentKey = original.currentEntry()?.playbackItemKey
    private val muted = activity.getColor(R.color.native_settings_value)
    private val text = activity.getColor(R.color.native_settings_title)

    init {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(dp(20), dp(12), dp(20), dp(8))
        root.background = GradientDrawable().apply {
            setColor(activity.getColor(R.color.native_settings_background)); setStroke(dp(1), Color.argb(31, 255, 255, 255))
        }
        val header = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(label(target.optString("seriesTitle").ifBlank { "选择剧集" }, 22f).apply {
            maxLines = 2; ellipsize = TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        listButton = tool(R.drawable.episode_list, "列表") { setGrid(false) }
        gridButton = tool(R.drawable.episode_grid, "网格") { setGrid(true) }
        header.addView(listButton)
        header.addView(gridButton)
        root.addView(header)
        subtitle.setTextColor(muted); subtitle.textSize = if (television) 13f else 12f
        subtitle.maxLines = 1; subtitle.ellipsize = TextUtils.TruncateAt.END
        seasonButton.contentDescription = "选择季"
        styleButton(seasonButton)
        seasonButton.textSize = if (television) 16f else 14f
        seasonButton.gravity = Gravity.START or Gravity.CENTER_VERTICAL
        seasonButton.setPadding(0, 0, dp(8), 0)
        seasonButton.maxLines = 1; seasonButton.ellipsize = TextUtils.TruncateAt.END
        seasonButton.setOnClickListener { chooseSeason() }
        seasonRow.addView(seasonButton, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(seasonRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(36)))
        styleButton(status); status.textSize = if (television) 13f else 12f; status.visibility = View.INVISIBLE
        status.maxLines = 1; status.ellipsize = TextUtils.TruncateAt.END
        status.gravity = Gravity.START or Gravity.CENTER_VERTICAL; status.setPadding(0, 0, 0, 0)
        status.setTextColor(muted)
        root.addView(information.apply {
            addView(subtitle, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            subtitle.gravity = Gravity.CENTER_VERTICAL
            addView(status, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(28)))
        rows.orientation = LinearLayout.VERTICAL
        scroll.isFillViewport = false
        scroll.addView(rows)
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        footer.gravity = Gravity.CENTER_VERTICAL
        root.addView(View(activity).apply { setBackgroundColor(Color.argb(31, 255, 255, 255)) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)).apply { topMargin = dp(6); bottomMargin = dp(6) })
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
        render()
        positionBeforeDraw()
        setOnShowListener { loadSeasons() }
    }

    private fun setGrid(value: Boolean) {
        if (loading) return
        grid = value
        preferences.edit().putString("flutter.episode_picker_layout", if (grid) "grid" else "list").apply()
        render(); positionBeforeDraw()
    }

    private fun positionBeforeDraw() {
        positionListener?.let { root.viewTreeObserver.removeOnPreDrawListener(it) }
        initialPositionPending = true
        val listener = object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                root.viewTreeObserver.removeOnPreDrawListener(this)
                positionListener = null
                cells[focusedIndex]?.let { cell ->
                    cell.requestFocus()
                    center(cell, animate = false)
                }
                initialPositionPending = false
                updateInformation()
                return true
            }
        }
        positionListener = listener
        root.viewTreeObserver.addOnPreDrawListener(listener)
        root.invalidate()
    }

    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
    private fun label(value: String, size: Float) = TextView(activity).apply {
        this.text = value; textSize = size; setTextColor(this@NativePlaybackEpisodePicker.text)
    }
    private fun background(playing: Boolean = false): StateListDrawable {
        fun shape(focus: Boolean, selected: Boolean = false) = GradientDrawable().apply {
            cornerRadius = dp(6).toFloat()
            setColor(if (selected) Color.argb(41, 250, 250, 250) else if (playing) Color.argb(23, 45, 212, 191) else Color.TRANSPARENT)
            if (focus) setStroke(dp(2), Color.WHITE)
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused, android.R.attr.state_selected), shape(true, true))
            addState(intArrayOf(android.R.attr.state_focused), shape(true))
            addState(intArrayOf(android.R.attr.state_selected), shape(false, true))
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
        setPadding(dp(11), dp(11), dp(11), dp(11)); scaleType = ImageView.ScaleType.FIT_CENTER
        setOnClickListener { action() }
        setOnKeyListener { _, key, event ->
            if (event.action == KeyEvent.ACTION_DOWN && !loading &&
                ((this === listButton && key == KeyEvent.KEYCODE_DPAD_DOWN) ||
                 (this === locateButton && key == KeyEvent.KEYCODE_DPAD_UP))) {
                focus(focusedIndex); true
            } else false
        }
    }
    private fun number(index: Int): Int = JSONObject(queue.entries[index].playbackTargetJson).optInt("episodeNumber", index + 1)
    private fun currentSeasonNumber() = JSONObject(queue.entries.first().playbackTargetJson).optInt("seasonNumber", 0)

    private fun updateInformation() {
        val statusParent = if (grid) information else seasonRow
        if (status.parent !== statusParent) {
            (status.parent as? ViewGroup)?.removeView(status)
            statusParent.addView(status, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
        information.visibility = if (grid) View.VISIBLE else View.GONE
        seasonButton.visibility = if (!grid && status.visibility == View.VISIBLE) View.INVISIBLE else View.VISIBLE
        subtitle.visibility = if (status.visibility == View.VISIBLE) View.INVISIBLE else View.VISIBLE
        if (!grid) return
        val index = focusedIndex.coerceIn(queue.entries.indices)
        val entry = queue.entries[index]
        val history = memory.loadPlaybackEntry(entry.playbackItemKey)
        val state = when {
            entry.playbackItemKey == currentKey -> "正在播放"
            history?.optBoolean("completed") == true -> "已看完"
            (history?.optLong("positionMs") ?: 0) > 0 -> "已看 ${(history?.optLong("positionMs") ?: 0) / 60000} 分钟"
            else -> ""
        }
        subtitle.text = entry.title().ifBlank { "第 ${number(index)} 集" } + if (state.isBlank()) "" else " · $state"
    }

    private fun render() {
        initialPositionPending = true
        rows.removeAllViews(); cells.clear(); footer.removeAllViews()
        val season = currentSeasonNumber()
        seasonButton.text = "${if (season == 0) "特别篇" else "第 $season 季"} · 共 ${queue.entries.size} 集"
        seasonButton.isEnabled = !loading && seasons.size > 1
        seasonButton.setCompoundDrawablesWithIntrinsicBounds(0, 0, if (seasons.size > 1) R.drawable.episode_expand else 0, 0)
        listButton.isSelected = !grid; gridButton.isSelected = grid
        updateInformation()
        run {
            val start = page * PAGE_SIZE
            val end = minOf(start + PAGE_SIZE, queue.entries.size)
            var row: LinearLayout? = null
            for (index in start until end) {
                if (!grid || (index - start) % 4 == 0) {
                    row = LinearLayout(activity)
                    rows.addView(row, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(72)))
                }
                val cell = cell(index)
                cells[index] = cell
                row!!.addView(cell, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f).apply { setMargins(dp(4), dp(4), dp(4), dp(4)) })
            }
            if (grid && (end - start) % 4 != 0) repeat(4 - (end - start) % 4) {
                row?.addView(View(activity), LinearLayout.LayoutParams(0, 1, 1f))
            }
        }
        footer.addView(tool(R.drawable.episode_chevron_left, "上一段") { move((page - 1) * PAGE_SIZE) }.apply { isEnabled = !loading && page > 0; alpha = if (isEnabled) 1f else .3f })
        val range = Button(activity).apply {
            styleButton(this); textSize = 13f
            setTextColor(muted)
            val start = page * PAGE_SIZE
            text = "${number(start)}–${number(minOf(start + PAGE_SIZE, queue.entries.size) - 1)} 集"
            isEnabled = !loading && queue.entries.size > PAGE_SIZE
            setOnClickListener { chooseRange() }
        }
        footer.addView(range, LinearLayout.LayoutParams(0, dp(44), 1f))
        footer.addView(tool(R.drawable.episode_chevron_right, "下一段") { move((page + 1) * PAGE_SIZE) }.apply { isEnabled = !loading && (page + 1) * PAGE_SIZE < queue.entries.size; alpha = if (isEnabled) 1f else .3f })
        locateButton = tool(R.drawable.episode_locate, "定位当前集") {
            requestId++; loading = false; status.visibility = View.INVISIBLE; queue = original
            page = original.currentIndex.coerceAtLeast(0) / PAGE_SIZE
            focusedIndex = original.currentIndex.coerceAtLeast(0)
            render(); positionBeforeDraw()
        }
        footer.addView(locateButton)
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
            setPadding(dp(if (grid) 8 else 12), dp(4), dp(if (grid) 8 else 12), dp(4)); styleButton(this, playing)
        }
        val title = entry.title().ifBlank { "第 ${number(index)} 集" }
        content.contentDescription = "第 ${number(index)} 集，$title，$statusText"
        val line = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; orientation = if (grid) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL }
        line.addView(label(number(index).toString().padStart(2, '0'), if (grid) 22f else 20f).apply {
            maxLines = 1; ellipsize = TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(if (grid) ViewGroup.LayoutParams.WRAP_CONTENT else dp(46), ViewGroup.LayoutParams.WRAP_CONTENT))
        val details = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        if (!grid) details.addView(label(title, if (television) 16f else 15f).apply { includeFontPadding = false; maxLines = 2; ellipsize = TextUtils.TruncateAt.END })
        if (!grid && statusText.isNotBlank()) details.addView(label(statusText, if (television) 13f else 12f).apply { includeFontPadding = false; setTextColor(if (playing) accent else muted); maxLines = 1; ellipsize = TextUtils.TruncateAt.END })
        line.addView(details, if (grid) LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT) else LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (!grid && (playing || watched)) line.addView(ImageView(activity).apply {
            setImageResource(if (playing) R.drawable.episode_play else R.drawable.episode_check)
            imageTintList = ColorStateList.valueOf(if (playing) accent else muted)
        }, LinearLayout.LayoutParams(dp(18), dp(18)))
        if (grid) {
            line.gravity = Gravity.CENTER
            content.addView(FrameLayout(activity).apply {
                addView(line, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                if (playing || watched) addView(ImageView(activity).apply {
                    setImageResource(if (playing) R.drawable.episode_play else R.drawable.episode_check)
                    imageTintList = ColorStateList.valueOf(if (playing) accent else muted)
                }, FrameLayout.LayoutParams(dp(14), dp(14), Gravity.TOP or Gravity.END))
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        } else content.addView(line, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        if (progress > 0 && !watched) content.addView(ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000; this.progress = (progress * 1000).toInt(); progressTintList = ColorStateList.valueOf(Color.rgb(45, 212, 191))
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2)))
        content.setOnClickListener { if (!loading) select(queue, index) }
        content.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus && !initialPositionPending) {
                focusedIndex = index
                updateInformation()
                center(content)
            }
        }
        content.setOnKeyListener { _, key, event ->
            if (loading) return@setOnKeyListener true
            val delta = when (key) {
                KeyEvent.KEYCODE_DPAD_DOWN -> if (grid) 4 else 1
                KeyEvent.KEYCODE_DPAD_UP -> if (grid) -4 else -1
                KeyEvent.KEYCODE_DPAD_LEFT -> if (grid) -1 else 0
                KeyEvent.KEYCODE_DPAD_RIGHT -> if (grid) 1 else 0
                else -> 0
            }
            if (event.action != KeyEvent.ACTION_DOWN || delta == 0) false
            else {
                val next = episodePickerNeighbor(index, queue.entries.size, grid, delta)
                when {
                    next < 0 -> listButton.requestFocus()
                    next >= queue.entries.size -> locateButton?.requestFocus()
                    else -> move(next)
                }
                true
            }
        }
        return content
    }

    private fun center(view: View, animate: Boolean = true) {
        val row = view.parent as? View ?: return
        val offset = (row.top - (scroll.height - row.height) / 2).coerceAtLeast(0)
        if (animate) scroll.smoothScrollTo(0, offset) else scroll.scrollTo(0, offset)
    }
    private fun focus(index: Int) { if (isShowing) cells[index]?.requestFocus() }
    private fun move(index: Int) {
        if (loading || index !in queue.entries.indices) return
        focusedIndex = index
        val nextPage = index / PAGE_SIZE
        if (nextPage != page || cells[index] == null) {
            page = nextPage; render(); positionBeforeDraw()
        } else focus(index)
    }
    private fun showOptions(title: String, labels: Array<String>, current: Int, action: (Int) -> Unit) {
        popup?.dismiss()
        popup = AlertDialog.Builder(activity, R.style.NativePlaybackSettingsDialogTheme).setTitle(title).setSingleChoiceItems(labels, current) { dialog, index -> dialog.dismiss(); action(index) }.setNegativeButton("关闭", null).create().also {
            it.window?.setWindowAnimations(0)
            it.show()
        }
    }
    private fun chooseRange() {
        if (loading) return
        val labels = (0 until (queue.entries.size + PAGE_SIZE - 1) / PAGE_SIZE).map { page ->
            "${number(page * PAGE_SIZE)}–${number(minOf((page + 1) * PAGE_SIZE, queue.entries.size) - 1)} 集"
        }.toTypedArray()
        showOptions("选择集数范围", labels, page) {
            focusedIndex = it * PAGE_SIZE; page = it
            render(); positionBeforeDraw()
        }
    }
    private fun chooseSeason() {
        if (loading) return
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
                seasonButton.isEnabled = !loading && seasons.size > 1
                seasonButton.setCompoundDrawablesWithIntrinsicBounds(0, 0, if (seasons.size > 1) R.drawable.episode_expand else 0, 0)
                status.visibility = View.INVISIBLE
            } else {
                status.visibility = View.VISIBLE; status.text = "季列表加载失败 · 重试"
                status.setOnClickListener { loadSeasons() }
            }
            updateInformation()
        }
    }
    private fun loadSeason(id: String) {
        loading = true
        status.visibility = View.VISIBLE; status.text = "正在加载剧集"; status.isEnabled = false
        seasonButton.requestFocus()
        updateInformation()
        listButton.requestFocus()
        request(id) { result ->
            val loaded = if (result["ok"] == true) NativeEpisodeQueue.fromJsonString(result["queueJson"]?.toString().orEmpty()) else null
            loading = false; status.isEnabled = true
            if (loaded == null) {
                status.text = "本季加载失败 · 重试"; status.setOnClickListener { loadSeason(id) }; status.requestFocus()
            } else {
                queue = if (JSONObject(loaded.entries.first().playbackTargetJson).optInt("seasonNumber") == target.optInt("seasonNumber")) original else loaded
                focusedIndex = queue.currentIndex.coerceAtLeast(0)
                page = focusedIndex / PAGE_SIZE; status.visibility = View.INVISIBLE
                render(); positionBeforeDraw()
            }
            updateInformation()
        }
    }
    override fun dismiss() {
        positionListener?.let { root.viewTreeObserver.removeOnPreDrawListener(it) }
        positionListener = null
        requestId++; handler.removeCallbacksAndMessages(null); popup?.dismiss(); popup = null; super.dismiss()
    }
    companion object { const val PAGE_SIZE = 30 }
}
