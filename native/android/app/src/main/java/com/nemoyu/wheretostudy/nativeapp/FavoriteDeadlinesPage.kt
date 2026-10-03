package com.nemoyu.wheretostudy.nativeapp

import android.content.res.ColorStateList
import android.graphics.Typeface
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

internal class FavoriteDeadlinesPage(
    private val activity: MainActivity,
    private val preferences: AppPreferences,
    private val availableWidthDp: Int,
) {
    private lateinit var scroll: ScrollView
    private lateinit var list: LinearLayout
    private lateinit var loadMore: TextView
    private val rows = linkedMapOf<String, Pair<PublicDeadlineItem, View>>()
    private var visibleLimit = PAGE_SIZE
    private var pendingAppend: Runnable? = null
    private var pendingScrollRestore: Runnable? = null
    private var ownerRevision = 0
    private var restoringScroll = false

    fun build(): ScrollView = ScrollView(activity).apply {
        scroll = this
        id = R.id.favorite_deadlines_page
        isFillViewport = true
        clipToPadding = false
        scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
        setThemeBackgroundColor { Palette.background }
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) { ownerRevision++ }
            override fun onViewDetachedFromWindow(view: View) {
                ownerRevision++
                pendingAppend?.let(scroll::removeCallbacks)
                pendingScrollRestore?.let(scroll::removeCallbacks)
                pendingAppend = null
                pendingScrollRestore = null
                restoringScroll = false
            }
        })
        setOnScrollChangeListener { _, _, scrollY, _, _ ->
            val range = ((getChildAt(0)?.height ?: 0) + paddingBottom - height).coerceAtLeast(0)
            if (!restoringScroll && range > 0 && range - scrollY <= activity.dp(48)) requestNextPage()
        }
        addView(verticalPage(activity).apply {
            if (availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP) {
                setPadding(
                    activity.dp(20),
                    activity.dp(16),
                    activity.dp(20),
                    activity.dp(28),
                )
            }
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(TextView(activity).apply {
                    id = R.id.favorite_deadlines_back
                    text = "‹"
                    textSize = 28f
                    gravity = Gravity.CENTER
                    includeFontPadding = false
                    setThemeTextColor { Palette.primaryText }
                    contentDescription = activity.uiText("返回设置")
                    isClickable = true
                    isFocusable = true
                    background = themedRoundedBackground(
                        activity, { Palette.surfaceVariant },
                        radius = UiMetrics.controlRadiusDp)
                    setOnClickListener {
                        activity.performControlHaptic(it)
                        activity.closeFavoriteManagement()
                    }
                }, LinearLayout.LayoutParams(activity.dp(42), activity.dp(42)).apply {
                    marginEnd = activity.dp(12)
                })
                addView(pageTitle(
                    activity,
                    "收藏管理",
                    "收藏快照在来源关闭、失效或删除后仍会保留",
                    titleSizeSp = if (availableWidthDp < 600) 26f else 34f,
                ), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            })
            list = surface(activity, showsBorder = false).apply {
                id = R.id.favorite_deadlines_list
            }
            addView(list)
            loadMore = fixedTab(activity, activity.uiText("加载更多")) {
                activity.performControlHaptic(loadMore)
                requestNextPage()
            }.apply {
                id = R.id.favorite_deadlines_load_more
                contentDescription = activity.uiText("加载更多")
                setSelectedStyle(activity, selected = false)
                setThemeTextColor { Palette.primaryText }
                setPadding(activity.dp(12), activity.dp(8), activity.dp(12), activity.dp(8))
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = activity.dp(8) }
            }
            addView(loadMore)
            refresh()
        })
    }

    fun refresh() {
        if (!::list.isInitialized) return
        val favorites = preferences.favoriteDeadlines
        val visible = favorites.take(visibleLimit)
        val wanted = visible.mapTo(mutableSetOf()) { it.favoriteID }
        val scrollY = scroll.scrollY
        pendingScrollRestore?.let(scroll::removeCallbacks)
        pendingScrollRestore = null
        restoringScroll = scroll.isLaidOut
        var changed = false
        rows.entries.filter { it.key !in wanted }.toList().forEach { (key, row) ->
            list.removeView(row.second)
            rows.remove(key)
            changed = true
        }
        list.findViewById<View?>(R.id.favorite_deadlines_empty)?.let { empty ->
            if (favorites.isNotEmpty()) { list.removeView(empty); changed = true }
        }
        visible.forEachIndexed { index, item ->
            val existing = rows[item.favoriteID]
            val row = if (existing != null && existing.first == item) existing.second else {
                existing?.second?.let(list::removeView)
                favoriteRow(item).also {
                    UiText.localizeTree(it)
                    rows[item.favoriteID] = item to it
                }
            }
            if (list.indexOfChild(row) != index) {
                (row.parent as? ViewGroup)?.removeView(row)
                list.addView(row, index)
                changed = true
            }
        }
        if (favorites.isEmpty() && list.childCount == 0) {
            list.addView(TextView(activity).apply {
                id = R.id.favorite_deadlines_empty
                text = activity.uiText("暂无收藏日程")
                textSize = 14f
                gravity = Gravity.CENTER
                setThemeTextColor { Palette.muted }
                setPadding(0, activity.dp(28), 0, activity.dp(28))
            })
            changed = true
        }
        loadMore.visibility = if (visible.size < favorites.size) View.VISIBLE else View.GONE
        loadMore.isEnabled = pendingAppend == null
        if (changed && scroll.isLaidOut) {
            val revision = ownerRevision
            val restore = object : Runnable {
                override fun run() {
                    if (pendingScrollRestore !== this) return
                    pendingScrollRestore = null
                    if (scroll.isAttachedToWindow && revision == ownerRevision) scroll.scrollTo(0, scrollY)
                    restoringScroll = false
                }
            }
            pendingScrollRestore = restore
            scroll.post(restore)
        } else restoringScroll = false
        activity.favoriteDeadlinesDidChange()
    }

    private fun requestNextPage() {
        if (!scroll.isAttachedToWindow || pendingAppend != null ||
            visibleLimit >= preferences.favoriteDeadlines.size
        ) return
        val revision = ownerRevision
        val append = object : Runnable {
            override fun run() {
                if (pendingAppend !== this) return
                pendingAppend = null
                if (!scroll.isAttachedToWindow || revision != ownerRevision) return
                visibleLimit = (visibleLimit + PAGE_SIZE).coerceAtMost(maxOf(PAGE_SIZE, preferences.favoriteDeadlines.size))
                refresh()
            }
        }
        pendingAppend = append
        loadMore.isEnabled = false
        scroll.postOnAnimation(append)
    }

    private fun favoriteRow(item: PublicDeadlineItem): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = themedRoundedBackground(activity, { Palette.background }, { Palette.border }, radius = 8)
            setPadding(activity.dp(12), activity.dp(10), activity.dp(6), activity.dp(10))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = activity.dp(8) }
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(activity).apply {
                    text = item.name
                    UiText.preserveRawText(this)
                    textSize = 14f
                    setThemeTextColor { Palette.text }
                    setTypeface(typeface, Typeface.BOLD)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                })
                addView(TextView(activity).apply {
                    text = buildList {
                        add(item.deadline.replace('T', ' ').take(16))
                        add(item.sourceName ?: activity.uiText(item.source.title))
                        item.organizer?.let(::add)
                    }.joinToString(" · ")
                    UiText.preserveRawText(this)
                    textSize = 11f
                    setThemeTextColor { Palette.muted }
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(0, activity.dp(3), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(ImageView(activity).apply {
                setImageResource(R.drawable.ic_star_filled)
                bindTheme("imageTintList") { imageTintList = ColorStateList.valueOf(Palette.accent) }
                scaleType = ImageView.ScaleType.CENTER
                isClickable = true
                isFocusable = true
                contentDescription = activity.uiText("取消收藏")
                tag = item.favoriteID
                setTag(R.id.favorite_deadline_item_key, item.favoriteID)
                background = themedRoundedBackground(activity, { Palette.surfaceVariant }, radius = 8)
                setOnClickListener {
                    activity.performControlHaptic(it)
                    runCatching { preferences.setFavorite(item, favorite = false) }
                        .onSuccess { refresh() }
                        .onFailure { error ->
                            Toast.makeText(activity, activity.uiText(error.message ?: "无法保存收藏日程。"),
                                Toast.LENGTH_LONG).show()
                        }
                }
            }, LinearLayout.LayoutParams(activity.dp(40), activity.dp(40)).apply {
                marginStart = activity.dp(8)
            })
        }

    private companion object { const val PAGE_SIZE = 20 }
}
