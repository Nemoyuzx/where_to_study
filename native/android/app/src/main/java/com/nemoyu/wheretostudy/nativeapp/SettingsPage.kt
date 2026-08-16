package com.nemoyu.wheretostudy.nativeapp

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
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
    fun build(): ScrollView = ScrollView(activity).apply {
        isFillViewport = true
        clipToPadding = false
        setBackgroundColor(Palette.background)
        addView(verticalPage(activity).apply {
            if (isCompact) {
                setPadding(activity.dp(16), activity.dp(14), activity.dp(16), activity.dp(88))
                if (!usesBottomNavigation) {
                    setPadding(activity.dp(16), activity.dp(14), activity.dp(16), activity.dp(28))
                }
            }
            addView(pageTitle(
                activity,
                "设置",
                if (isCompact) null else "个人账户与本地偏好",
            ))
            if (availableWidthDp >= 760) {
                addView(LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.TOP
                    addView(accountSurface(), LinearLayout.LayoutParams(
                        0,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        1f,
                    ).apply { marginEnd = activity.dp(8) })
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(notificationSurface())
                        addView(spacer(activity, UiMetrics.sectionSpacingDp))
                        addView(localDataSurface())
                    }, LinearLayout.LayoutParams(
                        0,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        1f,
                    ).apply { marginStart = activity.dp(8) })
                })
            } else {
                addView(accountSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(notificationSurface())
                addView(spacer(activity, UiMetrics.sectionSpacingDp))
                addView(localDataSurface())
            }
            addView(spacer(activity, UiMetrics.sectionSpacingDp))
            addView(aboutSurface())
        })
    }

    private fun accountSurface(): LinearLayout = surface(activity).apply {
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
        val termID = field("学期编号", preferences.termID, false)
        val termStartDate = field("第一周周一（YYYY-MM-DD）", preferences.termStartDate, false)
        fun updatePasswordStatus() {
            val preservesSavedPassword = hasPersistedPassword &&
                persistedAccount == account.text.toString().trim()
            passwordStatus.text = if (preservesSavedPassword) {
                "密码已安全保存，留空保持不变"
            } else if (hasPersistedPassword && account.text.toString().trim().isNotEmpty()) {
                "更换账号时请输入新密码"
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
        addView(spacer(activity, compactGap))
        addView(termID)
        addView(spacer(activity, compactGap))
        addView(termStartDate)
        addView(spacer(activity, if (isCompact) 10 else 16))
        addView(TextView(activity).apply {
            text = "默认校区"
            textSize = 13f
            setTextColor(Palette.muted)
            setPadding(0, 0, 0, activity.dp(if (isCompact) 5 else 7))
        })
        val campusLabels = AppMetadata.campuses.map(CampusMetadata::name)
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
        val campus = Spinner(activity).apply {
            adapter = campusAdapter
            setSelection(AppMetadata.campuses.indexOfFirst { it.id == preferences.campusID }.coerceAtLeast(0))
            background = roundedBackground(
                activity,
                Palette.surface,
                Palette.border,
                radius = UiMetrics.controlRadiusDp,
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
                val resolvedTermStartDate = SettingsInputLogic.resolveTermStartDate(
                    termStartDate.text.toString(),
                )
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
                        preferences.termID = termID.text.toString().trim()
                            .ifEmpty { AppMetadata.defaultTermID }
                        preferences.termStartDate = resolvedTermStartDate
                    }
                }
                if (accountChanged) {
                    credentialTransactionStarted = true
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
                radius = UiMetrics.controlRadiusDp,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
                saveSettings().onSuccess { credentials ->
                    applySavedCredentials(credentials)
                    Toast.makeText(activity, "设置已保存", Toast.LENGTH_SHORT).show()
                }.onFailure { error ->
                    Toast.makeText(
                        activity,
                        error.message ?: "无法安全保存账户信息",
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
                radius = UiMetrics.controlRadiusDp,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
                val button = it as TextView
                val saveResult = saveSettings()
                if (saveResult.isFailure) {
                    Toast.makeText(
                        activity,
                        saveResult.exceptionOrNull()?.message ?: "无法安全保存账户信息",
                        Toast.LENGTH_LONG,
                    ).show()
                    return@setOnClickListener
                }
                applySavedCredentials(saveResult.getOrThrow())
                button.text = "正在获取…"
                button.isEnabled = false
                scheduleRepository.refresh { result ->
                    button.text = "获取/刷新个人课表"
                    button.isEnabled = true
                    result.onSuccess { schedule ->
                        activity.reconcileDailyCourseNotifications()
                        Toast.makeText(
                            activity,
                            "个人课表已更新，共 ${schedule.courses.size} 门课程",
                            Toast.LENGTH_LONG,
                        ).show()
                        activity.refreshCurrentPage()
                    }.onFailure { error ->
                        Toast.makeText(
                            activity,
                            error.message ?: "个人课表获取失败",
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

    private fun notificationSurface(): LinearLayout = surface(activity).apply {
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
                    Toast.makeText(activity, message, Toast.LENGTH_SHORT).show()
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

    private fun localDataSurface(): LinearLayout = surface(activity).apply {
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
                radius = UiMetrics.controlRadiusDp,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
                AlertDialog.Builder(activity)
                    .setTitle("清除全部本地数据？")
                    .setMessage("将删除保存的账号、密码、个人课表、空教室缓存和设置。此操作无法撤销。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("确认清除") { _, _ ->
                        val result = activity.clearAllLocalData()
                        val message = if (result.isComplete) {
                            "本地数据已清除"
                        } else {
                            "已清除其余本地数据；未能清除：${result.failedItems.joinToString("、")}"
                        }
                        Toast.makeText(
                            activity,
                            message,
                            if (result.isComplete) Toast.LENGTH_SHORT else Toast.LENGTH_LONG,
                        ).show()
                    }
                    .show()
            }
        })
    }

    private fun aboutSurface(): LinearLayout = surface(activity).apply {
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
                radius = UiMetrics.controlRadiusDp,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener {
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
            radius = UiMetrics.controlRadiusDp,
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
                radius = UiMetrics.controlRadiusDp,
            )
            isClickable = true
            isFocusable = true
            minHeight = activity.dp(UiMetrics.controlHeightDp)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(UiMetrics.controlHeightDp),
            )
            setOnClickListener { onClick() }
        }

    private fun LinearLayout.applyCompactSurfacePadding() {
        if (!isCompact) return
        val padding = activity.dp(14)
        setPadding(padding, padding, padding, padding)
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
                text = "隐私声明"
                textSize = 24f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(activity).apply {
                text = "生效日期：2026 年 8 月 9 日"
                textSize = 13f
                setTextColor(Palette.muted)
                setPadding(0, activity.dp(4), 0, activity.dp(14))
            })
            addView(privacyParagraph(
                "Where To Study 是用于查看北邮个人课表和空教室的独立非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。",
            ))
            addView(privacySection(
                "账户与教务请求",
                "你输入的学号和密码保存在操作系统的受保护凭据存储中。应用在你手动获取课表或空教室时，会通过 HTTPS 将凭据发送到北邮教务服务 jwglweixin.bupt.edu.cn。保存有效凭据后，应用还可能在启动，或系统允许的每日 07:00 左右后台任务中自动刷新当天空教室。项目维护者无法读取这些凭据。",
            ))
            addView(privacySection(
                "本地数据",
                "个人课表、空教室结果、校区和学期等设置会缓存在你的设备上，以减少重复请求。你可以在设置中使用“清除本地数据”删除应用保存的凭据、课表、空教室缓存、节假日缓存和提醒任务。",
            ))
            addView(privacySection(
                "节假日数据",
                "应用在启动、切换日历年份或缓存需要更新时，可能通过 unpkg 自动获取 holiday-calendar 数据集中的中国法定节假日和调休信息。请求只包含 CN 地区和年份，不包含你的凭据、课表或空教室数据。",
            ))
            addView(privacySection(
                "系统日历与课程提醒",
                "只有在你主动操作并授予系统权限后，应用才会向系统日历写入课程或在本地安排课程摘要通知。应用只管理带有 Where To Study 标记的日历事件，相关数据不会上传给项目维护者。",
            ))
            addView(privacySection(
                "不收集的数据",
                "本项目不运营应用后端，不包含广告、分析或行为跟踪 SDK，也不收集位置、联系人、广告标识符或使用行为。北邮教务服务和节假日数据的 CDN 可能依据各自政策处理 IP 地址、请求时间等普通网络元数据。",
            ))
            addView(privacySection(
                "保留与删除",
                "凭据和缓存会保留在你的设备上，直到被替换、在设置中清除或随应用卸载移除。清除本地数据不会删除北邮教务服务持有的记录。",
            ))
            addView(privacySection(
                "安全与联系",
                "隐私问题可以在 GitHub 提交不含敏感信息的讨论或 Issue。请勿在公开内容中提供账号、密码、令牌、个人课表或其他敏感数据。",
            ))
            addView(TextView(activity).apply {
                id = R.id.privacy_github_link
                text = "在 GitHub 查看项目与完整声明 ↗"
                textSize = 15f
                gravity = Gravity.CENTER
                setTextColor(Palette.primaryText)
                setTypeface(typeface, Typeface.BOLD)
                background = roundedBackground(
                    activity,
                    Palette.surface,
                    Palette.border,
                    radius = UiMetrics.controlRadiusDp,
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
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)))
                }
            })
        }
        val scroll = ScrollView(activity).apply {
            isFillViewport = true
            setBackgroundColor(Palette.surface)
            addView(content)
        }
        AlertDialog.Builder(activity)
            .setView(scroll)
            .setNegativeButton("关闭", null)
            .show()
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

    private companion object {
        const val PROJECT_URL = "https://github.com/Nemoyuzx/where_to_study"
        const val PRIVACY_URL = "https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md"
    }

    private val isCompact: Boolean
        get() = availableWidthDp < AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP

    private val compactGap: Int
        get() = if (isCompact) 7 else 10
}
