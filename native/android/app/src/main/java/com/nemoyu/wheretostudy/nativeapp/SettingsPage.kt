package com.nemoyu.wheretostudy.nativeapp

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast

class SettingsPage(
    private val activity: MainActivity,
    private val credentialStore: SecureCredentialStore,
    private val preferences: AppPreferences,
    private val scheduleRepository: ScheduleRepository,
    private val classroomRepository: ClassroomRepository,
    private val availableWidthDp: Int,
    private val usesBottomNavigation: Boolean,
) {
    private val toastHandler = Handler(Looper.getMainLooper())
    private var transientToast: Toast? = null

    private fun showSavedToast() {
        transientToast?.cancel()
        val toast = Toast.makeText(activity, activity.uiText("设置已保存"), Toast.LENGTH_SHORT)
        transientToast = toast
        toast.show()
        toastHandler.postDelayed({
            if (transientToast === toast) {
                toast.cancel()
                transientToast = null
            }
        }, 1_800L)
    }

    fun build(): ScrollView = ScrollView(activity).apply {
        isFillViewport = true
        clipToPadding = false
        scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
        setBackgroundColor(Palette.background)
        addView(verticalPage(activity).apply {
            if (isCompact) {
                setPadding(activity.dp(20), activity.dp(16), activity.dp(20), activity.dp(88))
                if (!usesBottomNavigation) {
                    setPadding(activity.dp(20), activity.dp(16), activity.dp(20), activity.dp(28))
                }
            }
            addView(if (isCompact) compactSettingsTitle() else pageTitle(activity, "设置"))
            addView(referenceNotice())
            addView(spacer(activity, UiMetrics.sectionSpacingDp))
            if (availableWidthDp >= 760) {
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.TOP
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(accountSurface())
                        addView(spacer(activity, UiMetrics.sectionSpacingDp))
                        addView(semesterSurface())
                    }, LinearLayout.LayoutParams(
                        0,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        1f,
                    ).apply { marginEnd = activity.dp(8) })
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(notificationSurface())
                        addView(spacer(activity, UiMetrics.sectionSpacingDp))
                        addView(informationSurface())
                        addView(spacer(activity, UiMetrics.sectionSpacingDp))
                        addView(widgetSurface())
                        addView(spacer(activity, UiMetrics.sectionSpacingDp))
                        addView(languageSurface())
                        addView(spacer(activity, UiMetrics.sectionSpacingDp))
                        addView(aboutSurface())
                        addView(spacer(activity, UiMetrics.sectionSpacingDp))
                        addView(localDataSurface())
                    }, LinearLayout.LayoutParams(
                        0,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        2f,
                    ).apply { marginStart = activity.dp(8) })
                })
            } else {
                addView(accountSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(semesterSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(notificationSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(informationSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(widgetSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(languageSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(aboutSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(localDataSurface())
            }
        })
    }

    private fun languageSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        id = R.id.settings_language_section
        applyCompactSurfacePadding()
        addView(sectionTitle(activity, "应用设置"))
        addView(TextView(activity).apply {
            text = "语言"
            textSize = 13f
            setTextColor(Palette.muted)
            setPadding(0, 0, 0, activity.dp(6))
        })
        val languages = AppLanguage.entries
        val current = languages.indexOfFirst { it.code == preferences.languageCode }
            .coerceAtLeast(0)
        addView(Spinner(activity).apply {
            id = R.id.settings_language_selector
            adapter = ArrayAdapter(
                activity,
                android.R.layout.simple_spinner_item,
                languages.map { AppLocale.displayName(activity, it) },
            ).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
            setSelection(current, false)
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            setPadding(activity.dp(12), 0, activity.dp(12), 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                override fun onItemSelected(
                    parent: android.widget.AdapterView<*>?,
                    view: View?,
                    position: Int,
                    id: Long,
                ) {
                    val selectedLanguage = languages[position]
                    if (selectedLanguage.code != preferences.languageCode) {
                        activity.performControlHaptic(view)
                        activity.updateAppLanguage(selectedLanguage)
                    }
                }

                override fun onNothingSelected(parent: android.widget.AdapterView<*>?) = Unit
            }
        })
        addView(TextView(activity).apply {
            text = "更改语言后将立即重新加载界面。"
            textSize = 12f
            setTextColor(Palette.muted)
            setPadding(0, activity.dp(7), 0, 0)
        })
    }

    private fun accountSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        applyCompactSurfacePadding()
        val savedIdentity = credentialStore.load()?.let { it.account to it.password.isNotEmpty() }
        var persistedAccount = savedIdentity?.first.orEmpty()
        var hasPersistedPassword = savedIdentity?.second == true
        addView(sectionTitle(activity, "个人账户"))
        val account = field("教务账号", persistedAccount, false)
        val password = field("密码", "", true)
        val passwordStatus = TextView(activity).apply {
            textSize = 12f
            setTextColor(Palette.muted)
            setPadding(activity.dp(2), activity.dp(7), activity.dp(2), 0)
        }
        fun updatePasswordStatus() {
            val preservesSavedPassword = hasPersistedPassword &&
                persistedAccount == account.text.toString().trim()
            passwordStatus.text = if (preservesSavedPassword) {
                activity.uiText("密码已安全保存，留空保持不变")
            } else if (hasPersistedPassword && account.text.toString().trim().isNotEmpty()) {
                activity.uiText("更换账号时请输入新密码")
            } else {
                ""
            }
            passwordStatus.visibility = if (passwordStatus.text.isEmpty()) View.GONE else View.VISIBLE
        }
        account.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(value: CharSequence?, start: Int, count: Int, after: Int) = Unit

            override fun onTextChanged(value: CharSequence?, start: Int, before: Int, count: Int) {
                updatePasswordStatus()
            }

            override fun afterTextChanged(value: Editable?) = Unit
        })
        updatePasswordStatus()
        addView(account)
        addView(spacer(activity, compactGap))
        addView(password)
        addView(passwordStatus)
        addView(spacer(activity, if (isCompact) 10 else 16))
        addView(TextView(activity).apply {
            text = "默认校区"
            textSize = 13f
            setTextColor(Palette.muted)
            setPadding(0, 0, 0, activity.dp(if (isCompact) 5 else 7))
        })
        val campusLabels = AppMetadata.campuses.map { activity.uiText(it.name) }
        val campusAdapter = object : ArrayAdapter<String>(
            activity,
            android.R.layout.simple_spinner_item,
            campusLabels,
        ) {
            init {
                setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            }

            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
                super.getView(position, convertView, parent).also(::styleSpinnerText)

            override fun getDropDownView(position: Int, convertView: View?, parent: ViewGroup): View =
                super.getDropDownView(position, convertView, parent).also { view ->
                    styleSpinnerText(view)
                    view.setBackgroundColor(Palette.surface)
                }

            private fun styleSpinnerText(view: View) {
                (view as? TextView)?.apply {
                    setTextColor(Palette.text)
                    setPadding(activity.dp(12), 0, activity.dp(12), 0)
                }
            }
        }
        val campus = object : Spinner(activity) {
            override fun performClick(): Boolean {
                activity.performControlHaptic(this)
                return super.performClick()
            }
        }.apply {
            adapter = campusAdapter
            setSelection(AppMetadata.campuses.indexOfFirst { it.id == preferences.campusID }.coerceAtLeast(0))
            background = roundedBackground(
                activity,
                Palette.surface,
                Palette.border,
                radius = 6,
            )
            setPadding(activity.dp(12), 0, activity.dp(12), 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
        }
        addView(campus)
        addView(spacer(activity, if (isCompact) 12 else 18))
        fun saveSettings(): Result<Credentials> {
            var credentialTransactionStarted = false
            val result = runCatching {
                val savedCredentials = credentialStore.load()
                val credentials = CredentialUpdateLogic.resolve(
                    saved = savedCredentials,
                    requestedAccount = account.text.toString(),
                    enteredPassword = password.text.toString(),
                )
                val accountChanged = CredentialUpdateLogic.changesAccount(
                    savedCredentials,
                    credentials,
                )
                val persist: () -> Credentials = {
                    credentials.also {
                        credentialStore.save(credentials)
                        preferences.campusID = AppMetadata.campuses[campus.selectedItemPosition].id
                    }
                }
                if (accountChanged) {
                    credentialTransactionStarted = true
                    activity.clearCalendarAssignmentData()
                    check(DailyClassroomRefreshScheduler.cancel(activity)) {
                        "无法可靠撤销旧账号的空教室后台刷新，设置未保存。"
                    }
                    check(activity.clearDailyCourseNotificationsForAccountChange()) {
                        "无法可靠撤销旧账号的课程提醒，设置未保存。"
                    }
                    LocalDataCoordinator.clear {
                        scheduleRepository.clearLocalDataCoordinated()
                        classroomRepository.clearLocalDataCoordinated()
                        persist()
                    }
                } else {
                    credentialTransactionStarted = true
                    val generation = LocalDataCoordinator.snapshot()
                    LocalDataCoordinator.withCurrent(generation, persist)
                }
                check(DailyClassroomRefreshScheduler.ensureScheduled(activity)) {
                    "无法更新空教室后台刷新任务。"
                }
                credentials
            }
            if (result.isFailure && credentialTransactionStarted &&
                !DailyClassroomRefreshScheduler.cancel(activity)
            ) {
                return Result.failure(
                    IllegalStateException(
                        "账号设置失败，且无法可靠撤销空教室后台刷新。",
                        result.exceptionOrNull(),
                    ),
                )
            }
            return result
        }
        fun applySavedCredentials(credentials: Credentials) {
            persistedAccount = credentials.account
            hasPersistedPassword = credentials.password.isNotEmpty()
            password.text.clear()
            updatePasswordStatus()
        }

        addView(TextView(activity).apply {
            text = "保存设置"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Palette.onPrimary)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(
                activity,
                Palette.primaryFill,
                radius = 6,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
                activity.performControlHaptic(it)
                saveSettings().onSuccess { credentials ->
                    applySavedCredentials(credentials)
                    showSavedToast()
                }.onFailure { error ->
                    Toast.makeText(
                        activity,
                        activity.uiText(error.message ?: "无法安全保存账户信息"),
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        })
        addView(spacer(activity, compactGap))
        addView(TextView(activity).apply {
            text = "获取/刷新个人课表"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Palette.primaryText)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(
                activity,
                Palette.surface,
                Palette.primary,
                radius = 6,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
                activity.performControlHaptic(it)
                val button = it as TextView
                val saveResult = saveSettings()
                if (saveResult.isFailure) {
                    Toast.makeText(
                        activity,
                        activity.uiText(
                            saveResult.exceptionOrNull()?.message ?: "无法安全保存账户信息",
                        ),
                        Toast.LENGTH_LONG,
                    ).show()
                    return@setOnClickListener
                }
                applySavedCredentials(saveResult.getOrThrow())
                button.text = activity.uiText("正在获取…")
                button.isEnabled = false
                scheduleRepository.refresh { result ->
                    button.text = activity.uiText("获取/刷新个人课表")
                    button.isEnabled = true
                    result.onSuccess { schedule ->
                        activity.reconcileDailyCourseNotifications()
                        Toast.makeText(
                            activity,
                            activity.uiText("个人课表已更新，共 ${schedule.courses.size} 门课程"),
                            Toast.LENGTH_LONG,
                        ).show()
                        activity.refreshCurrentPage()
                    }.onFailure { error ->
                        Toast.makeText(
                            activity,
                            activity.uiText(error.message ?: "个人课表获取失败"),
                            Toast.LENGTH_LONG,
                        ).show()
                    }
                }
            }
        })
        addView(TextView(activity).apply {
            text = activity.getString(R.string.credential_security_note)
            textSize = 12f
            setTextColor(Palette.muted)
            setPadding(0, activity.dp(if (isCompact) 8 else 12), 0, 0)
        })
    }

    private fun semesterSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        applyCompactSurfacePadding()
        addView(sectionTitle(activity, "学期设置"))
        val termID = field("学期编号", preferences.termID, false)
        val termStartDate = field("第一周周一（YYYY-MM-DD）", preferences.termStartDate, false)
        val autoDetect = Switch(activity).apply {
            text = "自动检测当前学期"
            textSize = 15f
            setTextColor(Palette.text)
            isChecked = preferences.automaticTermDetectionEnabled
            minHeight = activity.dp(UiMetrics.controlHeightDp)
            setPadding(0, 0, 0, 0)
        }
        fun updateManualFields() {
            val enabled = !autoDetect.isChecked
            termID.isEnabled = enabled
            termStartDate.isEnabled = enabled
            termID.alpha = if (enabled) 1f else 0.62f
            termStartDate.alpha = if (enabled) 1f else 0.62f
        }
        addView(autoDetect)
        addView(spacer(activity, compactGap))
        addView(termID)
        addView(spacer(activity, compactGap))
        addView(termStartDate)
        addView(TextView(activity).apply {
            text = if (autoDetect.isChecked) {
                "获取/刷新课表后会自动应用教务返回的学期与开学日期。"
            } else {
                "关闭自动检测后，将使用手动填写的学期信息。"
            }
            textSize = 12f
            setTextColor(Palette.muted)
            setPadding(0, activity.dp(8), 0, activity.dp(if (isCompact) 8 else 12))
            autoDetect.setOnCheckedChangeListener { button, checked ->
                activity.performControlHaptic(button)
                updateManualFields()
                text = activity.uiText(if (checked) {
                    "获取/刷新课表后会自动应用教务返回的学期与开学日期。"
                } else {
                    "关闭自动检测后，将使用手动填写的学期信息。"
                })
            }
        })
        updateManualFields()
        addView(settingsActionButton("保存学期设置", primary = false) {
            runCatching {
                val resolvedStartDate = SettingsInputLogic.resolveTermStartDate(
                    termStartDate.text.toString(),
                )
                preferences.automaticTermDetectionEnabled = autoDetect.isChecked
                preferences.termID = termID.text.toString().trim()
                    .ifEmpty { AppMetadata.defaultTermID }
                preferences.termStartDate = resolvedStartDate
            }.onSuccess {
                showSavedToast()
            }.onFailure { error ->
                Toast.makeText(
                    activity,
                    activity.uiText(error.message ?: "无法保存学期设置"),
                    Toast.LENGTH_LONG,
                ).show()
            }
        })
    }

    private fun notificationSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        applyCompactSurfacePadding()
        addView(sectionTitle(activity, "课程提醒"))
        addView(Switch(activity).apply {
            text = activity.getString(R.string.daily_course_notification_toggle)
            textSize = 15f
            setTextColor(Palette.text)
            isChecked = preferences.dailyCourseNotificationsEnabled
            minHeight = activity.dp(UiMetrics.controlHeightDp)
            setPadding(0, 0, 0, 0)
            setOnClickListener {
                activity.performControlHaptic(it)
                val requested = isChecked
                isEnabled = false
                activity.setDailyCourseNotificationsEnabled(requested) { enabled ->
                    isChecked = enabled
                    isEnabled = true
                    val message = when {
                        enabled -> "每日课程摘要已开启"
                        requested -> "通知权限未开启，无法启用课程摘要"
                        else -> "每日课程摘要已关闭"
                    }
                    Toast.makeText(activity, activity.uiText(message), Toast.LENGTH_SHORT).show()
                }
            }
        })
        addView(TextView(activity).apply {
            text = activity.getString(R.string.daily_course_notification_description)
            textSize = 12f
            setTextColor(Palette.muted)
            setPadding(0, activity.dp(4), 0, 0)
        })
    }

    private fun widgetSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        applyCompactSurfacePadding()
        addView(sectionTitle(activity, "桌面小组件"))

        val previewContent = TodayCourseWidgetLogic.previewContent()
        val preview = LayoutInflater.from(activity).inflate(
            R.layout.widget_today_course,
            this,
            false,
        ).apply {
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(205),
            )
        }
        var previewCapacity = 3
        fun updatePreview() {
            TodayCourseWidgetPreviewBinder.bind(
                root = preview,
                content = previewContent,
                showsLocation = preferences.widgetShowsLocation,
                showsTeacher = preferences.widgetShowsTeacher,
                rowLimit = minOf(previewCapacity, preferences.widgetCourseLimit),
            )
            UiText.localizeTree(preview)
            val height = when (previewCapacity) {
                1 -> 122
                3 -> 205
                else -> 328
            }
            preview.layoutParams = (preview.layoutParams as LinearLayout.LayoutParams).apply {
                this.height = activity.dp(height)
                topMargin = activity.dp(8)
            }
            preview.requestLayout()
        }

        addView(Switch(activity).apply {
            text = "显示课程地点"
            textSize = 15f
            setTextColor(Palette.text)
            isChecked = preferences.widgetShowsLocation
            minHeight = activity.dp(UiMetrics.controlHeightDp)
            setPadding(0, 0, 0, 0)
            setOnCheckedChangeListener { button, checked ->
                activity.performControlHaptic(button)
                preferences.widgetShowsLocation = checked
                TodayCourseWidgetProvider.refresh(activity)
                updatePreview()
            }
        })
        addView(Switch(activity).apply {
            text = "显示任课教师"
            textSize = 15f
            setTextColor(Palette.text)
            isChecked = preferences.widgetShowsTeacher
            minHeight = activity.dp(UiMetrics.controlHeightDp)
            setPadding(0, 0, 0, 0)
            setOnCheckedChangeListener { button, checked ->
                activity.performControlHaptic(button)
                preferences.widgetShowsTeacher = checked
                TodayCourseWidgetProvider.refresh(activity)
                updatePreview()
            }
        })
        addView(TextView(activity).apply {
            text = "最多显示课程"
            textSize = 13f
            setTextColor(Palette.muted)
            setPadding(0, activity.dp(8), 0, activity.dp(5))
        })
        val labels = (1..6).map { activity.uiText("$it 门") }
        addView(Spinner(activity).apply {
            adapter = ArrayAdapter(
                activity,
                android.R.layout.simple_spinner_item,
                labels,
            ).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
            setSelection(preferences.widgetCourseLimit - 1)
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            setPadding(activity.dp(12), 0, activity.dp(12), 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                override fun onItemSelected(
                    parent: android.widget.AdapterView<*>?,
                    view: View?,
                    position: Int,
                    id: Long,
                ) {
                    val limit = position + 1
                    if (limit != preferences.widgetCourseLimit) {
                        activity.performControlHaptic(view)
                        preferences.widgetCourseLimit = limit
                        TodayCourseWidgetProvider.refresh(activity)
                        updatePreview()
                    }
                }

                override fun onNothingSelected(parent: android.widget.AdapterView<*>?) = Unit
            }
        })

        addView(View(activity).apply {
            setBackgroundColor(Palette.border)
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, activity.dp(1)).apply {
            topMargin = activity.dp(14)
            bottomMargin = activity.dp(12)
        })
        addView(TextView(activity).apply {
            text = "样式预览 · 示例内容"
            textSize = 14f
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
        })
        val previewLabels = listOf("紧凑", "标准", "展开").map(activity::uiText)
        val previewCapacities = listOf(1, 3, 6)
        addView(Spinner(activity).apply {
            adapter = ArrayAdapter(
                activity,
                android.R.layout.simple_spinner_item,
                previewLabels,
            ).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
            setSelection(1)
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            setPadding(activity.dp(12), 0, activity.dp(12), 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            ).apply { topMargin = activity.dp(7) }
            onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                override fun onItemSelected(
                    parent: android.widget.AdapterView<*>?,
                    view: View?,
                    position: Int,
                    id: Long,
                ) {
                    val capacity = previewCapacities[position]
                    if (capacity != previewCapacity) {
                        activity.performControlHaptic(view)
                        previewCapacity = capacity
                        updatePreview()
                    }
                }

                override fun onNothingSelected(parent: android.widget.AdapterView<*>?) = Unit
            }
        })
        updatePreview()
        addView(preview)
        addView(TextView(activity).apply {
            text = "小组件会显示日期、教学周、当前或下一节状态、节次、地点与教师；展开样式最多展示 6 门课程。预览使用虚构示例，不会写入课表。"
            textSize = 12f
            setTextColor(Palette.muted)
            setPadding(0, activity.dp(8), 0, 0)
        })
    }

    private fun informationSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        applyCompactSurfacePadding()
        addView(sectionTitle(activity, "日期详情与生活信息"))
        addView(featureSwitch("校区天气", preferences.weatherEnabled) {
            preferences.weatherEnabled = it
        })
        addView(featureSwitch("黄历与宜忌", preferences.almanacEnabled) {
            preferences.almanacEnabled = it
        })
        addView(View(activity).apply { setBackgroundColor(Palette.border) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, activity.dp(1)).apply {
                topMargin = activity.dp(8)
                bottomMargin = activity.dp(8)
            })
        addView(deadlineLegendRow(
            label = "课程作业 DDL",
            rowID = R.id.settings_assignment_deadline_legend_row,
            dotID = R.id.settings_assignment_deadline_legend_dot,
            color = Palette.assignment,
        ))
        addView(featureSwitchLegendRow(
            label = "学科竞赛 DDL",
            checked = preferences.competitionDeadlinesEnabled,
            switchID = R.id.settings_competition_deadlines_switch,
            dotID = R.id.settings_competition_deadlines_dot,
            color = Palette.publicDeadline,
        ) {
            preferences.competitionDeadlinesEnabled = it
            if (it) activity.prewarmPublicDeadlinesIfEnabled()
        })
        addView(featureSwitchLegendRow(
            label = "校内竞赛通知",
            checked = preferences.schoolContestNoticesEnabled,
            switchID = R.id.settings_school_contest_notices_switch,
            dotID = R.id.settings_school_contest_notices_dot,
            color = Palette.schoolNotice,
        ) {
            preferences.schoolContestNoticesEnabled = it
            if (it) activity.prewarmPublicDeadlinesIfEnabled()
        })
        addView(featureSwitchLegendRow(
            label = "夏令营 DDL",
            checked = preferences.summerCampDeadlinesEnabled,
            switchID = R.id.settings_summer_camp_deadlines_switch,
            dotID = R.id.settings_summer_camp_deadlines_dot,
            color = Palette.publicDeadline,
        ) {
            preferences.summerCampDeadlinesEnabled = it
            if (it) activity.prewarmPublicDeadlinesIfEnabled()
        })
        addView(featureSwitchLegendRow(
            label = "黑客松 DDL",
            checked = preferences.hackathonDeadlinesEnabled,
            switchID = R.id.settings_hackathon_deadlines_switch,
            dotID = R.id.settings_hackathon_deadlines_dot,
            color = Palette.publicDeadline,
        ) {
            preferences.hackathonDeadlinesEnabled = it
            if (it) activity.prewarmPublicDeadlinesIfEnabled()
        })
        addView(TextView(activity).apply {
            text = "天气、黄历和 DDL 来自第三方公开服务；校内竞赛通知由脚本从学校内部网站公开通知页提取整理，各卡片底部会标明具体来源。"
            textSize = 12f
            setTextColor(Palette.muted)
            setPadding(0, activity.dp(6), 0, 0)
        })
    }

    private fun referenceNotice(): TextView = TextView(activity).apply {
        text = "显示数据仅供参考，请以实际情况为准。\n" +
            "Displayed data is for reference only; please rely on the actual official information."
        textSize = 13f
        setTextColor(Palette.muted)
        background = roundedBackground(activity, Palette.surfaceVariant, radius = 9)
        setPadding(activity.dp(12), activity.dp(10), activity.dp(12), activity.dp(10))
        contentDescription = text
    }

    private fun featureSwitch(
        label: String,
        checked: Boolean,
        save: (Boolean) -> Unit,
    ): Switch = Switch(activity).apply {
        text = label
        textSize = 15f
        setTextColor(Palette.text)
        isChecked = checked
        minHeight = activity.dp(UiMetrics.controlHeightDp)
        setPadding(0, 0, 0, 0)
        setOnCheckedChangeListener { button, enabled ->
            activity.performControlHaptic(button)
            save(enabled)
        }
    }

    private fun deadlineLegendRow(
        label: String,
        rowID: Int,
        dotID: Int,
        color: Int,
    ): LinearLayout = LinearLayout(activity).apply {
        id = rowID
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        isClickable = false
        isFocusable = false
        minimumHeight = activity.dp(UiMetrics.controlHeightDp)
        addView(deadlineLegendLabel(label, dotID, color), LinearLayout.LayoutParams(
            0,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            1f,
        ))
    }

    private fun featureSwitchLegendRow(
        label: String,
        checked: Boolean,
        switchID: Int,
        dotID: Int,
        color: Int,
        save: (Boolean) -> Unit,
    ): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(deadlineLegendLabel(label, dotID, color), LinearLayout.LayoutParams(
            0,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            1f,
        ))
        addView(featureSwitch(label, checked, save).apply {
            id = switchID
            text = ""
            contentDescription = activity.uiText(label)
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
    }

    private fun deadlineLegendLabel(label: String, dotID: Int, color: Int): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(activity).apply {
                text = label
                textSize = 15f
                setTextColor(Palette.text)
                includeFontPadding = false
            })
            addView(deadlineLegendDot(label, dotID, color))
        }

    private fun deadlineLegendDot(label: String, dotID: Int, color: Int): View =
        View(activity).apply {
            id = dotID
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
            }
            contentDescription = "$label 图例颜色"
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            layoutParams = LinearLayout.LayoutParams(activity.dp(10), activity.dp(10)).apply {
                marginStart = activity.dp(8)
            }
        }

    private fun settingsActionButton(
        label: String,
        primary: Boolean,
        onClick: () -> Unit,
    ): TextView = TextView(activity).apply {
        text = label
        textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(if (primary) Palette.onPrimary else Palette.primaryText)
        setTypeface(typeface, Typeface.BOLD)
        background = roundedBackground(
            activity,
            if (primary) Palette.primaryFill else Palette.surface,
            if (primary) Palette.primaryFill else Palette.primary,
            radius = 6,
        )
        isClickable = true
        isFocusable = true
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(UiMetrics.controlHeightDp),
        )
        setOnClickListener {
            activity.performControlHaptic(it)
            onClick()
        }
    }

    private fun localDataSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        id = R.id.settings_local_data_section
        applyCompactSurfacePadding()
        addView(sectionTitle(activity, "本地数据"))
        addView(TextView(activity).apply {
            text = "个人课表、空教室缓存、节假日缓存、账号与偏好均只保存在本机。"
            textSize = 12f
            setTextColor(Palette.muted)
            setLineSpacing(0f, 1.1f)
            setPadding(0, 0, 0, activity.dp(if (isCompact) 8 else 12))
        })
        addView(TextView(activity).apply {
            text = "清除本地数据"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Palette.danger)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(
                activity,
                Palette.dangerSurface,
                Palette.dangerBorder,
                radius = 6,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
                activity.performControlHaptic(it)
                AlertDialog.Builder(activity)
                    .setTitle("清除全部本地数据？")
                    .setMessage("将删除保存的账号、密码、个人课表、空教室缓存和设置。此操作无法撤销。")
                    .setNegativeButton("取消") { _, _ -> activity.performControlHaptic() }
                    .setPositiveButton("确认清除") { _, _ ->
                        activity.performControlHaptic()
                        val result = activity.clearAllLocalData()
                        val message = if (result.isComplete) {
                            "本地数据已清除"
                        } else {
                            "已清除其余本地数据；未能清除：${result.failedItems.joinToString("、")}"
                        }
                        Toast.makeText(
                            activity,
                            activity.uiText(message),
                            if (result.isComplete) Toast.LENGTH_SHORT else Toast.LENGTH_LONG,
                        ).show()
                    }
                    .showLocalized()
            }
        })
    }

    private fun aboutSurface(): LinearLayout = surface(activity, showsBorder = false).apply {
        applyCompactSurfacePadding()
        id = R.id.settings_about_section
        addView(sectionTitle(activity, "关于本应用"))
        addView(TextView(activity).apply {
            text = "Where To Study  ${BuildConfig.VERSION_NAME}\n北邮课表与空教室查询的独立非官方客户端，不由北京邮电大学运营。"
            textSize = 13f
            setTextColor(Palette.muted)
            setLineSpacing(0f, 1.12f)
            setPadding(0, 0, 0, activity.dp(if (isCompact) 8 else 12))
        })
        addView(settingsLinkButton("GitHub 项目主页") {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PROJECT_URL)))
        }.apply { id = R.id.settings_github_link })
        addView(spacer(activity, compactGap))
        addView(TextView(activity).apply {
            id = R.id.privacy_policy_button
            text = "隐私说明"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Palette.primaryText)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(
                activity,
                Palette.surface,
                Palette.border,
                radius = 6,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
                activity.performControlHaptic(it)
                showPrivacyPolicy()
            }
        })
    }

    private fun field(hintText: String, value: String, secure: Boolean): EditText = EditText(activity).apply {
        hint = hintText
        setText(value)
        textSize = 15f
        setTextColor(Palette.text)
        setHintTextColor(Palette.muted)
        isSingleLine = true
        inputType = if (secure) {
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        } else {
            InputType.TYPE_CLASS_TEXT
        }
        if (secure && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            setAutofillHints(null)
        }
        background = roundedBackground(
            activity,
            Palette.surface,
            Palette.border,
            radius = 6,
        )
        setPadding(activity.dp(13), 0, activity.dp(13), 0)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(UiMetrics.controlHeightDp),
        )
    }

    private fun settingsLinkButton(label: String, onClick: () -> Unit): TextView =
        TextView(activity).apply {
            text = label
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Palette.primaryText)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(
                activity,
                Palette.surface,
                Palette.border,
                radius = 6,
            )
            isClickable = true
            isFocusable = true
            minHeight = activity.dp(UiMetrics.controlHeightDp)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
                activity.performControlHaptic(it)
                onClick()
            }
        }

    private fun compactSettingsTitle(): LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, 0, 0, activity.dp(12))
        addView(TextView(activity).apply {
            text = activity.getString(R.string.planner_eyebrow)
            textSize = 11f
            setTextColor(Palette.muted)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
        })
        addView(TextView(activity).apply {
            text = "设置"
            textSize = 28f
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
            setPadding(0, activity.dp(3), 0, 0)
        })
    }

    private fun LinearLayout.applyCompactSurfacePadding() {
        // Keep the shared 16dp surface inset on every width, matching SwiftUI Surface.
    }

    private fun showPrivacyPolicy() {
        val content = LinearLayout(activity).apply {
            id = R.id.privacy_policy_content
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Palette.surface)
            setPadding(
                activity.dp(20),
                activity.dp(18),
                activity.dp(20),
                activity.dp(18),
            )
            addView(TextView(activity).apply {
                text = "隐私声明 / Privacy Policy"
                textSize = 24f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(activity).apply {
                text = "生效日期 / Effective date: 2026-08-23"
                textSize = 13f
                setTextColor(Palette.muted)
                setPadding(0, activity.dp(4), 0, activity.dp(14))
            })
            addView(privacyParagraph(
                "Where To Study 是用于查看北京邮电大学个人课表、空教室及相关学习信息的独立非官方客户端，不由学校运营，也不代表学校官方立场。\n\n" +
                    "Where To Study is an independent, unofficial client for BUPT schedules, empty classrooms, and related study information. It is not operated by or affiliated with BUPT.",
            ))
            privacySections().forEach { (title, body) ->
                addView(privacySection(title, body))
            }
            addView(TextView(activity).apply {
                id = R.id.privacy_github_link
                text = "在 GitHub 查看完整声明 / Full policy on GitHub ↗"
                textSize = 15f
                gravity = Gravity.CENTER
                setTextColor(Palette.primaryText)
                setTypeface(typeface, Typeface.BOLD)
                background = roundedBackground(
                    activity,
                    Palette.surface,
                    Palette.border,
                    radius = 6,
                )
                isClickable = true
                isFocusable = true
                contentDescription = "在 GitHub 查看完整隐私声明"
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    activity.dp(UiMetrics.controlHeightDp),
                ).apply {
                    topMargin = activity.dp(18)
                }
                setOnClickListener {
                    activity.performControlHaptic(it)
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)))
                }
            })
        }
        val scroll = ScrollView(activity).apply {
            isFillViewport = true
            scrollBarStyle = View.SCROLLBARS_INSIDE_OVERLAY
            setBackgroundColor(Palette.surface)
            addView(content)
        }
        AlertDialog.Builder(activity)
            .setView(scroll)
            .setNegativeButton("关闭") { _, _ -> activity.performControlHaptic() }
            .showLocalized()
    }

    private fun privacySection(title: String, body: String): LinearLayout =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, activity.dp(16), 0, 0)
            addView(TextView(activity).apply {
                text = title
                textSize = 16f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(privacyParagraph(body).apply {
                setPadding(0, activity.dp(6), 0, 0)
            })
        }

    private fun privacyParagraph(body: String): TextView = TextView(activity).apply {
        text = body
        textSize = 14f
        setTextColor(Palette.muted)
        setLineSpacing(0f, 1.15f)
    }

    private fun privacySections(): List<Pair<String, String>> = listOf(
        "账户与教务请求 / Account and academic requests" to
            ("学号和密码保存在操作系统的受保护凭据存储中，仅在你请求课表、空教室或作业时按对应用途通过 HTTPS 使用。维护者无法读取凭据，设置接口也不会返回密码。\n\n" +
                "Credentials stay in protected OS storage and are used over HTTPS only for requested schedules, classrooms, or assignments. The maintainer cannot read credentials, and settings APIs never return a password."),
        "本地数据 / Local data" to
            ("课表、空教室、校区、学期和开关缓存在设备上；受支持系统的课程小组件只读取本地课表快照。“清除本地数据”会移除凭据、缓存、偏好和应用管理的提醒。\n\n" +
                "Schedules, classroom results, campus, term, and preferences are cached locally. Course widgets on supported systems read only a local snapshot. Clear local data removes credentials, caches, preferences, and app-managed reminders."),
        "节假日数据 / Holiday data" to
            ("应用可能通过 unpkg 获取固定版本 holiday-calendar 数据；Android 在已有权限时也可能读取系统节假日日历。请求仅含 CN 与年份。iOS 只依据权威休息日数据显示“休”。\n\n" +
                "The app may retrieve pinned holiday-calendar data through unpkg; Android may read the OS holiday calendar when permitted. Requests contain only CN and year. iOS marks rest days only from authoritative rest-day data."),
        "天气、黄历与公开活动 / Weather, almanac, and public events" to
            ("UAPI 按校区行政区提供天气与基础黄历，不读取 GPS；Timeless 可补充宜忌。Contest DDL 提供竞赛、夏令营和黑客松；校内竞赛通知由服务器脚本从学校内部网站公开通知页提取整理。各类别有独立开关。固定 HTTP API 仅接收无凭据 GET，拒绝重定向且不含个人数据。所有显示数据仅供参考。\n\n" +
                "UAPI provides district-level weather and base almanac data without GPS; Timeless may add advice. Contest DDL provides public events. School notices are extracted by a server-side script from public pages on the university’s internal website. Each category has its own switch. Fixed HTTP APIs receive credential-free GET requests with no personal data and reject redirects. Displayed data is for reference only."),
        "云课堂作业 / UCloud assignments" to
            ("密码仅通过 HTTPS 提交给 auth.bupt.edu.cn，一次性票据换取内存令牌后从 apiucloud.bupt.edu.cn 读取作业。应用不读取浏览器 Cookie，不向 UCloud API 发送密码，也不把票据、Cookie、令牌或作业写入磁盘；结果最多在内存复用 10 分钟。\n\n" +
                "The password is submitted only to auth.bupt.edu.cn over HTTPS. An in-memory token is used with apiucloud.bupt.edu.cn. No browser cookie, ticket, token, or assignment is persisted, and results are reused in memory for at most ten minutes."),
        "系统日历、通知与小组件 / Calendar, notifications, and widgets" to
            ("日历写入和本地课程通知需要你的操作与权限；应用只管理带 Where To Study 标记的事件。课程小组件只在支持的平台提供，相关数据不上传。\n\n" +
                "Calendar writes and local course notifications require your action and permission, and only marked events are managed. Widgets exist only on supported platforms. This data is not uploaded."),
        "不收集的数据与第三方元数据 / Data not collected and third-party metadata" to
            ("项目不运营应用后端，不含广告、分析或跟踪 SDK，也不收集 GPS、联系人、广告标识符、诊断或使用行为。第三方可能按各自政策处理 IP 和请求时间。\n\n" +
                "The project operates no app backend and collects no GPS, contacts, advertising identifiers, diagnostics, or usage behavior. Third parties may process ordinary IP and request-time metadata."),
        "保留与删除 / Retention and deletion" to
            ("凭据与缓存保留在设备上，直到被替换、清除或随卸载移除；清除本地数据不会删除学校或第三方持有的记录。\n\n" +
                "Credentials and caches stay on your device until replaced, cleared, or removed with the app. Clearing local data does not delete third-party records."),
        "安全与联系 / Security and contact" to
            ("请按 SECURITY.md 报告安全问题；隐私问题可在 GitHub 提交不含敏感信息的 Issue。请勿公开账号、密码、令牌或个人课表。\n\n" +
                "Follow SECURITY.md for security reports. Open only non-sensitive privacy issues on GitHub, and never publish credentials, tokens, or personal schedules."),
    )

    private companion object {
        const val PROJECT_URL = "https://github.com/Nemoyuzx/where_to_study"
        const val PRIVACY_URL = "https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md"
    }

    private val isCompact: Boolean
        get() = availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP

    private val compactGap: Int
        get() = if (isCompact) 7 else 10
}
