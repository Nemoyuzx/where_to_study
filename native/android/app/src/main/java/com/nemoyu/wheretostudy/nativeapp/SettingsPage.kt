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
) {
    fun build(): ScrollView = ScrollView(activity).apply {
        isFillViewport = true
        setBackgroundColor(Palette.background)
        addView(verticalPage(activity).apply {
            addView(pageTitle(activity, "设置", "个人账户与本地偏好"))
            addView(accountSurface())
        })
    }

    private fun accountSurface(): LinearLayout = surface(activity).apply {
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
        addView(spacer(activity, 10))
        addView(password)
        addView(passwordStatus)
        addView(spacer(activity, 10))
        addView(termID)
        addView(spacer(activity, 10))
        addView(termStartDate)
        addView(spacer(activity, 16))
        addView(TextView(activity).apply {
            text = "默认校区"
            textSize = 13f
            setTextColor(Palette.muted)
            setPadding(0, 0, 0, activity.dp(7))
        })
        val campus = Spinner(activity).apply {
            adapter = ArrayAdapter(
                activity,
                android.R.layout.simple_spinner_dropdown_item,
                AppMetadata.campuses.map(CampusMetadata::name),
            )
            setSelection(AppMetadata.campuses.indexOfFirst { it.id == preferences.campusID }.coerceAtLeast(0))
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            setPadding(activity.dp(12), 0, activity.dp(12), 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(50),
            )
        }
        addView(campus)
        addView(spacer(activity, 18))
        fun saveSettings(): Result<Credentials> = runCatching {
            val savedCredentials = credentialStore.load()
            val credentials = CredentialUpdateLogic.resolve(
                saved = savedCredentials,
                requestedAccount = account.text.toString(),
                enteredPassword = password.text.toString(),
            )
            val persist: () -> Credentials = {
                credentials.also {
                    credentialStore.save(credentials)
                    preferences.campusID = AppMetadata.campuses[campus.selectedItemPosition].id
                    preferences.termID = termID.text.toString().trim()
                        .ifEmpty { AppMetadata.defaultTermID }
                    preferences.termStartDate = termStartDate.text.toString().trim()
                        .ifEmpty { AppMetadata.defaultTermStartDate }
                }
            }
            if (CredentialUpdateLogic.changesAccount(savedCredentials, credentials)) {
                check(activity.clearDailyCourseNotificationsForAccountChange()) {
                    "无法可靠撤销旧账号的课程提醒，设置未保存。"
                }
                LocalDataCoordinator.clear {
                    scheduleRepository.clearLocalDataCoordinated()
                    classroomRepository.clearLocalDataCoordinated()
                    persist()
                }
            } else {
                val generation = LocalDataCoordinator.snapshot()
                LocalDataCoordinator.withCurrent(generation, persist)
            }
        }
        fun applySavedCredentials(credentials: Credentials) {
            persistedAccount = credentials.account
            hasPersistedPassword = credentials.password.isNotEmpty()
            password.text.clear()
            updatePasswordStatus()
        }

        addView(TextView(activity).apply {
            text = "保存设置"
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(activity, Palette.primary, radius = 6)
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(48),
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
        addView(spacer(activity, 10))
        addView(TextView(activity).apply {
            text = "获取/刷新个人课表"
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Palette.primaryDark)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(activity, Palette.surface, Palette.primary, radius = 6)
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(48),
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
            setPadding(0, activity.dp(12), 0, 0)
        })
        addView(spacer(activity, 20))
        addView(sectionTitle(activity, "课程提醒"))
        addView(Switch(activity).apply {
            text = activity.getString(R.string.daily_course_notification_toggle)
            textSize = 15f
            setTextColor(Palette.text)
            isChecked = preferences.dailyCourseNotificationsEnabled
            minHeight = activity.dp(48)
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
        addView(spacer(activity, 18))
        addView(TextView(activity).apply {
            text = "隐私说明"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Palette.primaryDark)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(46),
            )
            setOnClickListener {
                activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)))
            }
        })
        addView(spacer(activity, 10))
        addView(TextView(activity).apply {
            text = "清除本地数据"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(138, 45, 28))
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBackground(
                activity,
                Color.rgb(255, 242, 237),
                Color.rgb(230, 183, 170),
                radius = 6,
            )
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                activity.dp(46),
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
        background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
        setPadding(activity.dp(13), 0, activity.dp(13), 0)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(50),
        )
    }

    private companion object {
        const val PRIVACY_URL = "https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md"
    }
}
