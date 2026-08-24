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

internal class FavoriteDeadlinesPage(
    private val activity: MainActivity,
    private val preferences: AppPreferences,
    private val availableWidthDp: Int,
    private val usesBottomNavigation: Boolean,
) {
    fun build(): ScrollView = ScrollView(activity).apply {
        isFillViewport = true
        clipToPadding = false
        scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
        setBackgroundColor(Palette.background)
        addView(verticalPage(activity).apply {
            id = R.id.favorite_deadlines_page
            if (availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP) {
                setPadding(
                    activity.dp(20),
                    activity.dp(16),
                    activity.dp(20),
                    activity.dp(if (usesBottomNavigation) 88 else 28),
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
                    setTextColor(Palette.primaryText)
                    contentDescription = activity.uiText("返回设置")
                    isClickable = true
                    isFocusable = true
                    background = roundedBackground(
                        activity,
                        Palette.surfaceVariant,
                        radius = UiMetrics.controlRadiusDp,
                    )
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
            val favorites = preferences.favoriteDeadlines
            addView(surface(activity, showsBorder = false).apply {
                id = R.id.favorite_deadlines_list
                if (favorites.isEmpty()) {
                    addView(TextView(activity).apply {
                        id = R.id.favorite_deadlines_empty
                        text = "暂无收藏日程"
                        textSize = 14f
                        gravity = Gravity.CENTER
                        setTextColor(Palette.muted)
                        setPadding(0, activity.dp(28), 0, activity.dp(28))
                    })
                } else {
                    favorites.forEach { item -> addView(favoriteRow(item)) }
                }
            })
        })
    }

    private fun favoriteRow(item: PublicDeadlineItem): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = roundedBackground(activity, Palette.background, Palette.border, radius = 8)
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
                    setTextColor(Palette.text)
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
                    setTextColor(Palette.muted)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(0, activity.dp(3), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(ImageView(activity).apply {
                setImageResource(R.drawable.ic_star_filled)
                imageTintList = ColorStateList.valueOf(Palette.accent)
                scaleType = ImageView.ScaleType.CENTER
                isClickable = true
                isFocusable = true
                contentDescription = activity.uiText("取消收藏")
                tag = item.favoriteID
                setTag(R.id.favorite_deadline_item_key, item.favoriteID)
                background = roundedBackground(activity, Palette.surfaceVariant, radius = 8)
                setOnClickListener {
                    activity.performControlHaptic(it)
                    preferences.setFavorite(item, favorite = false)
                    activity.refreshCurrentPage()
                }
            }, LinearLayout.LayoutParams(activity.dp(40), activity.dp(40)).apply {
                marginStart = activity.dp(8)
            })
        }
}
