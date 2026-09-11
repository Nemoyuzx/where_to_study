package com.nemoyu.wheretostudy.nativeapp

import android.graphics.Typeface
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/** Presets use a compact grid when space allows; larger fonts keep a single column. */
internal class ColorThemeSettingsView(
    private val activity: MainActivity,
    private val isCompact: Boolean = activity.resources.configuration.screenWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP,
    private val availableWidthDp: Int = activity.resources.configuration.screenWidthDp,
) : LinearLayout(activity) {
    private val store = ColorThemePreferences(activity)
    private var saved = store.load()
    private val choices = mutableMapOf<String, TextView>()
    private var previewColors = ColorThemeLogic.palette(saved, isDark)
    private val fields = mutableListOf<EditText>()
    private val isDark get() = resources.configuration.uiMode and
        android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES
    private fun label(zh: String, en: String) = if (AppLocale.isEnglish(activity)) en else zh

    init {
        id = R.id.settings_color_theme_section
        orientation = VERTICAL
        background = themedRoundedBackground(activity, { Palette.surface },
            radius = if (isCompact) UiMetrics.phoneSurfaceRadiusDp else UiMetrics.surfaceRadiusDp)
        setPadding(activity.dp(16), activity.dp(16), activity.dp(16), activity.dp(16))
        addView(sectionTitle(activity, label("颜色主题", "Color Theme"), R.drawable.ic_settings_palette))
        addView(TextView(activity).apply {
            text = label("主色会同时调整页面、卡片和控件的底色。浅色与深色外观仍跟随系统。", "The primary color also shapes page, card and control backgrounds. Light and dark appearance still follows your system.")
            textSize = 13f
            setThemeTextColor { Palette.muted }
        })
        addView(spacer(activity, 12))
        val presetContentWidthDp = availableWidthDp - 2 * (UiMetrics.pagePaddingDp + UiMetrics.surfacePaddingDp)
        val presetColumns = if (isCompact && presetContentWidthDp >= 298 &&
            resources.configuration.fontScale <= 1.2f) 2 else 1
        var presetLine: LinearLayout? = null
        ColorThemeLogic.presets.forEachIndexed { index, preset ->
            if (index % presetColumns == 0) {
                presetLine = LinearLayout(activity).apply {
                    orientation = HORIZONTAL
                }
                addView(presetLine, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                    topMargin = activity.dp(if (index == 0) 0 else 8)
                })
            }
            val row = LinearLayout(activity).apply {
                orientation = if (isCompact) VERTICAL else HORIZONTAL
                gravity = if (isCompact) Gravity.START else Gravity.CENTER_VERTICAL
                minimumHeight = activity.dp(48)
                if (isCompact) setPadding(activity.dp(12), activity.dp(10), activity.dp(12), activity.dp(10))
                isClickable = true
                isFocusable = true
                tag = "color_theme_${preset.id}"
                contentDescription = label(preset.nameZh, preset.nameEn)
                background = themedRoundedBackground(activity, {
                    if (saved.preset == preset.id) Palette.selectionSurface
                    else if (isCompact) Palette.background else Palette.surface
                }, radius = if (isCompact) UiMetrics.phoneControlRadiusDp else UiMetrics.controlRadiusDp)
                val title = TextView(activity).apply {
                    textSize = 15f
                    includeFontPadding = false
                    if (isCompact) setPadding(0, activity.dp(9), 0, 0)
                    else setPadding(activity.dp(8), activity.dp(10), activity.dp(8), activity.dp(10))
                    setThemeTextColor {
                        if (saved.preset != preset.id) Palette.text
                        else if (saved.preset == "default") Palette.primaryText
                        else ColorThemeLogic.readableText(Palette.primaryText, Palette.selectionSurface)
                    }
                }
                choices[preset.id] = title
                val swatches = LinearLayout(activity).apply {
                    orientation = HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                listOf(preset.seeds.primary, preset.seeds.accent, preset.seeds.selectedDate).forEach { seed ->
                    swatches.addView(View(activity).apply {
                        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
                        background = roundedBackground(activity, ColorThemeLogic.color(seed), radius = 99)
                    }, LayoutParams(activity.dp(if (isCompact) 17 else 14), activity.dp(if (isCompact) 17 else 14)).apply {
                        marginEnd = activity.dp(7)
                    })
                }
                if (isCompact) {
                    addView(swatches)
                    addView(title, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
                } else {
                    addView(title, LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                    addView(swatches)
                }
                setOnClickListener {
                    activity.performControlHaptic(it)
                    commit(saved.copy(preset = preset.id))
                }
            }
            presetLine!!.addView(row, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
                if (index % presetColumns > 0) marginStart = activity.dp(8)
            })
        }
        if (ColorThemeLogic.presets.size % presetColumns != 0) {
            presetLine?.addView(View(activity), LayoutParams(0, 0, 1f).apply { marginStart = activity.dp(8) })
        }
        addView(spacer(activity, 16))
        addView(TextView(activity).apply {
            text = label("自定义 RGB 颜色", "Custom RGB Colors")
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
            setThemeTextColor { Palette.text }
        })
        addField(label("主色", "Primary"), saved.custom.primary, R.id.settings_color_theme_primary)
        addField(label("强调色", "Accent"), saved.custom.accent, R.id.settings_color_theme_accent)
        addField(label("选中日期", "Selected Date"), saved.custom.selectedDate, R.id.settings_color_theme_selected_date)
        addView(TextView(activity).apply {
            text = label("输入 6 位十六进制颜色，可带 #。文字对比度会自动调整。", "Enter 6 hexadecimal digits, optionally starting with #. Text contrast adjusts automatically.")
            textSize = 12f
            setThemeTextColor { Palette.muted }
            setPadding(0, activity.dp(6), 0, activity.dp(12))
        })
        addView(LinearLayout(activity).apply {
            id = R.id.settings_color_theme_preview
            orientation = VERTICAL
            setPadding(activity.dp(14), activity.dp(14), activity.dp(14), activity.dp(14))
            background = themedRoundedBackground(activity, { previewColors.background },
                { if (isCompact) android.graphics.Color.TRANSPARENT else previewColors.border }, radius = 12)
            addView(TextView(activity).apply {
                text = label("配色预览", "Theme Preview")
                textSize = 12f
                setThemeTextColor { previewColors.muted }
                setPadding(0, 0, 0, activity.dp(10))
            })
            addView(LinearLayout(activity).apply {
                id = R.id.settings_color_theme_preview_card
                orientation = VERTICAL
                setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
                background = themedRoundedBackground(activity, { previewColors.surface },
                    { if (isCompact) android.graphics.Color.TRANSPARENT else previewColors.border }, radius = 10)
                addView(TextView(activity).apply {
                    text = label("今天的日程", "Today's Schedule")
                    textSize = 16f
                    setTypeface(typeface, Typeface.BOLD)
                    setThemeTextColor { previewColors.text }
                    setPadding(0, 0, 0, activity.dp(8))
                })
                addView(previewLabel(label("18 日 · 示例课程", "18 · Sample Course"), { previewColors.elevated }, { previewColors.text }).apply {
                    id = R.id.settings_color_theme_preview_elevated
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    background = themedRoundedBackground(activity, { previewColors.elevated },
                        { if (isCompact) android.graphics.Color.TRANSPARENT else previewColors.border })
                    setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_nav_calendar, 0, 0, 0)
                    compoundDrawablePadding = activity.dp(6)
                    bindTheme("iconTint") { compoundDrawableTintList = android.content.res.ColorStateList.valueOf(previewColors.primaryText) }
                })
                addView(previewLabel(label("强调信息", "Highlighted Note"), {
                    ColorThemeLogic.mix(previewColors.accent, previewColors.surface, 0.88)
                }, {
                    ColorThemeLogic.readableText(previewColors.accent,
                        ColorThemeLogic.mix(previewColors.accent, previewColors.surface, 0.88))
                }))
                addView(previewLabel(label("已选日期 · 18", "Selected Date · 18"), { previewColors.selectedDate }, { previewColors.onPrimary }))
                addView(previewLabel(label("查看课表", "View Schedule"), { previewColors.primaryFill }, { previewColors.onPrimary }).apply {
                    id = R.id.settings_color_theme_preview_control
                })
            })
        })
        addView(action(label("应用自定义颜色", "Apply Custom Colors"), R.id.settings_color_theme_apply, primary = true) {
            val custom = editedSeeds() ?: return@action
            if (commit(ColorThemeSelection("custom", custom))) {
                fields.zip(listOf(custom.primary, custom.accent, custom.selectedDate)).forEach { (field, value) ->
                    field.setText(value)
                }
            }
        })
        addView(action(label("恢复默认", "Restore Default"), R.id.settings_color_theme_restore) {
            commit(saved.copy(preset = "default"))
        })
        val watcher = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                val seeds = editedSeeds() ?: return
                previewColors = ColorThemeLogic.palette(ColorThemeSelection("custom", seeds), isDark)
                findViewById<View>(R.id.settings_color_theme_preview).refreshColorTheme()
            }
        }
        fields.forEach { it.addTextChangedListener(watcher) }
        bindTheme("selection") {
            saved = store.load()
            previewColors = ColorThemeLogic.palette(saved, isDark)
            updateChoiceLabels()
        }
    }

    private fun addField(title: String, value: String, viewId: Int) {
        addView(TextView(activity).apply {
            text = title
            labelFor = viewId
            textSize = 13f
            setThemeTextColor { Palette.muted }
            setPadding(0, activity.dp(12), 0, activity.dp(4))
        })
        val field = EditText(activity).apply {
            id = viewId
            contentDescription = title
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            setSingleLine(true)
            setText(value)
            textSize = 15f
            typeface = Typeface.MONOSPACE
            minHeight = activity.dp(48)
            setPadding(activity.dp(12), activity.dp(10), activity.dp(12), activity.dp(10))
            setThemeTextColor { Palette.text }
            background = themedRoundedBackground(activity, {
                if (Palette.selection.preset == "default") Palette.background else Palette.surfaceVariant
            }, { if (isCompact) android.graphics.Color.TRANSPARENT else Palette.border },
                radius = if (isCompact) UiMetrics.phoneControlRadiusDp else UiMetrics.controlRadiusDp)
        }
        fields += field
        addView(field, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    private fun editedSeeds(): ThemeSeeds? {
        var valid = true
        fields.forEach { field ->
            val error = ColorThemeLogic.normalize(field.text.toString()) == null
            field.error = if (error) label("请输入 6 位 RGB，例如 #166B5D", "Enter 6 RGB digits, e.g. #166B5D") else null
            if (error) valid = false
        }
        return if (valid) ThemeSeeds(fields[0].text.toString(), fields[1].text.toString(), fields[2].text.toString()).normalized() else null
    }

    private fun previewLabel(title: String, fill: () -> Int, textColor: () -> Int): TextView = TextView(activity).apply {
        text = title
        textSize = 14f
        gravity = Gravity.CENTER
        setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
        setThemeTextColor(textColor)
        background = themedRoundedBackground(activity, fill)
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { bottomMargin = activity.dp(6) }
    }

    private fun action(title: String, viewId: Int, primary: Boolean = false, onClick: () -> Unit): TextView = TextView(activity).apply {
        id = viewId
        text = title
        textSize = 15f
        setTypeface(typeface, Typeface.BOLD)
        gravity = Gravity.CENTER
        minimumHeight = activity.dp(48)
        setPadding(activity.dp(8), activity.dp(10), activity.dp(8), activity.dp(10))
        isClickable = true
        isFocusable = true
        setThemeTextColor { if (isCompact && primary) Palette.onPrimary else Palette.primaryText }
        background = themedRoundedBackground(activity, {
            if (!isCompact) Palette.surface else if (primary) Palette.primaryFill else Palette.selectionSurface
        }, { if (isCompact) android.graphics.Color.TRANSPARENT else Palette.primary },
            radius = if (isCompact) UiMetrics.phoneControlRadiusDp else UiMetrics.controlRadiusDp)
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = activity.dp(10) }
        setOnClickListener { activity.performControlHaptic(it); onClick() }
    }

    private fun commit(selection: ColorThemeSelection): Boolean {
        if (!activity.applyColorTheme(selection)) {
            Toast.makeText(activity, label("颜色主题保存失败，请重试。", "Could not save the color theme. Please try again."), Toast.LENGTH_SHORT).show()
            return false
        }
        saved = store.load()
        previewColors = ColorThemeLogic.palette(saved, isDark)
        updateChoiceLabels()
        refreshColorTheme()
        return true
    }

    private fun updateChoiceLabels() {
        ColorThemeLogic.presets.forEach { preset ->
            choices[preset.id]?.apply {
                text = (if (saved.preset == preset.id) "✓ " else "") + label(preset.nameZh, preset.nameEn)
                isSelected = saved.preset == preset.id
                setTypeface(typeface, if (isSelected) Typeface.BOLD else Typeface.NORMAL)
                (parent as View).isSelected = isSelected
            }
        }
        findViewById<TextView>(R.id.settings_color_theme_apply)?.apply {
            text = (if (saved.preset == "custom") "✓ " else "") + label("应用自定义颜色", "Apply Custom Colors")
            isSelected = saved.preset == "custom"
        }
    }
}
