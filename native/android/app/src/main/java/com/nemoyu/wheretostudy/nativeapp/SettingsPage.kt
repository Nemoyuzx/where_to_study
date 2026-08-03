package com.nemoyu.wheretostudy.nativeapp

import android.graphics.Color
import android.graphics.Typeface
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast

class SettingsPage(
    private val activity: MainActivity,
    private val credentialStore: SecureCredentialStore,
    private val preferences: AppPreferences,
    private val scheduleRepository: ScheduleRepository,
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
        val saved = credentialStore.load()
        addView(sectionTitle(activity, "个人账户"))
        val account = field("教务账号", saved?.account.orEmpty(), false)
        val password = field("密码", saved?.password.orEmpty(), true)
        val termID = field("学期编号", preferences.termID, false)
        val termStartDate = field("第一周周一（YYYY-MM-DD）", preferences.termStartDate, false)
        addView(account)
        addView(spacer(activity, 10))
        addView(password)
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
        fun saveSettings(): Result<Unit> = runCatching {
            credentialStore.save(
                Credentials(
                    account = account.text.toString().trim(),
                    password = password.text.toString(),
                ),
            )
            preferences.campusID = AppMetadata.campuses[campus.selectedItemPosition].id
            preferences.termID = termID.text.toString().trim().ifEmpty { AppMetadata.defaultTermID }
            preferences.termStartDate = termStartDate.text.toString().trim()
                .ifEmpty { AppMetadata.defaultTermStartDate }
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
                saveSettings().onSuccess {
                    Toast.makeText(activity, "设置已保存", Toast.LENGTH_SHORT).show()
                }.onFailure {
                    Toast.makeText(activity, "无法安全保存账户信息", Toast.LENGTH_LONG).show()
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
                saveSettings().onFailure {
                    Toast.makeText(activity, "无法安全保存账户信息", Toast.LENGTH_LONG).show()
                    return@setOnClickListener
                }
                button.text = "正在获取…"
                button.isEnabled = false
                scheduleRepository.refresh { result ->
                    button.text = "获取/刷新个人课表"
                    button.isEnabled = true
                    result.onSuccess { schedule ->
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
        background = roundedBackground(activity, Palette.surface, Palette.border, radius = 6)
        setPadding(activity.dp(13), 0, activity.dp(13), 0)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            activity.dp(50),
        )
    }
}
