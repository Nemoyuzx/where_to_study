package com.nemoyu.wheretostudy.nativeapp

import android.os.Build
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import java.lang.ref.WeakReference

/** Inline counterpart of the iOS credential editor. Secrets never enter retained UI drafts. */
internal class QmplusCredentialSettingsEditor(private val activity: MainActivity) {
    private val repository = activity.qmplusState()
    private val selection = activity.getSharedPreferences("qmplus_settings_ui", android.content.Context.MODE_PRIVATE)
    private val root = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private var restoring = false
    private var status: String? = null
    private val optIn = Switch(activity).apply {
        id = R.id.qmplus_saved_login_opt_in
        isChecked = selection.getBoolean("save_login_selected", true)
        minimumHeight = activity.dp(UiMetrics.controlHeightDp)
        contentDescription = activity.uiText("允许官方登录页自动填写")
    }
    private val account = input("QMplus 微软账号", R.id.qmplus_saved_login_account, false)
    private val password = input("QMplus 微软密码", R.id.qmplus_saved_login_password, true)
    private val saved = detail("已在本机安全保存 QMplus 登录资料。")
    private val identityWarning = detail("保存新的登录信息会清除现有 QMplus 会话与快照，避免复用其他身份。")
    private val resultText = detail("")
    private val fields = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val save = action("安全保存 QMplus 登录资料") { save() }.apply { id = R.id.settings_qmplus_saved_login }
    private val remove = action("删除已保存的 QMplus 登录资料") { disable() }

    init {
        root.addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            addView(TextView(activity).apply {
                text = activity.uiText("允许官方登录页自动填写")
                textSize = 15f; setThemeTextColor { Palette.text }; setLineSpacing(0f, 1.1f)
                setPadding(0, 0, activity.dp(12), 0)
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(optIn)
        })
        append(root, detail("保存后会在本机安全存储中保留独立 QMplus 登录资料。首次默认开启自动填写，也可在保存前关闭。"))
        append(root, saved)
        fields.addView(account, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        append(fields, password)
        append(fields, identityWarning)
        append(fields, save); append(fields, remove)
        append(root, fields); append(root, resultText)
        val watcher = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { update() }
            override fun afterTextChanged(s: Editable?) = Unit
        }
        account.addTextChangedListener(watcher); password.addTextChangedListener(watcher)
        optIn.setOnCheckedChangeListener { _, enabled ->
            if (!restoring) {
                selection.edit().putBoolean("save_login_selected", enabled).apply()
                if (!enabled) disable() else update()
            }
        }
        root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) { update() }
            override fun onViewDetachedFromWindow(view: View) { password.text.clear() }
        })
        update()
    }

    fun view(): View = root

    fun update() {
        val busy = repository.isLoading || repository.isSavingLogin || repository.isClearingSession || repository.connection != null
        optIn.isEnabled = !repository.isLoading && !repository.isSavingLogin && !repository.isClearingSession
        fields.visibility = if (optIn.isChecked) View.VISIBLE else View.GONE
        saved.visibility = if (repository.savedLoginStatus.enabled) View.VISIBLE else View.GONE
        identityWarning.visibility = if (account.text.toString().trim().isNotEmpty() || password.text.isNotEmpty()) View.VISIBLE else View.GONE
        account.isEnabled = !busy; password.isEnabled = !busy
        save.isEnabled = !busy && optIn.isChecked && account.text.toString().trim().isNotEmpty() && password.text.isNotEmpty()
        remove.isEnabled = !repository.isLoading && !repository.isSavingLogin && !repository.isClearingSession
        val showResult = !status.isNullOrEmpty() &&
            !(repository.savedLoginStatus.enabled && status == "已保存 QMplus 登录信息并授权官方网页自动填写")
        resultText.text = if (showResult) status?.let(activity::uiText).orEmpty() else ""
        resultText.visibility = if (showResult) View.VISIBLE else View.GONE
    }

    private fun save() {
        if (!root.isAttachedToWindow || !optIn.isChecked) return
        val secret = CharArray(password.text.length) { password.text[it] }
        if (!QmplusCredentialLimits.valid(account.text.toString(), secret)) {
            secret.fill('\u0000'); status = activity.getString(R.string.qmplus_saved_login_invalid); update(); return
        }
        val weakEditor = WeakReference(this)
        activity.saveQmplusLogin(account.text.toString(), secret) { result ->
            weakEditor.get()?.takeIf { it.root.isAttachedToWindow }?.let { editor ->
                editor.status = if (result.isSuccess) "已保存 QMplus 登录信息并授权官方网页自动填写"
                    else editor.activity.getString(R.string.qmplus_saved_login_failed)
                editor.update()
            }
        }
        secret.fill('\u0000'); password.text.clear(); update()
    }

    private fun disable() {
        restoring = true; optIn.isChecked = false; restoring = false
        selection.edit().putBoolean("save_login_selected", false).apply()
        account.text.clear(); password.text.clear()
        val weakEditor = WeakReference(this)
        activity.disableQmplusSavedLogin { result ->
            weakEditor.get()?.takeIf { it.root.isAttachedToWindow }?.let { editor ->
                editor.status = if (result.isSuccess) "已关闭 QMplus 自动填写并删除保存的登录信息"
                    else "QMplus 自动填写已关闭，但保存的登录信息删除失败，请重试。"
                editor.update()
            }
        }
        update()
    }

    private fun detail(value: String): TextView = TextView(activity).apply {
        text = activity.uiText(value); textSize = 12f; setThemeTextColor { Palette.muted }; setLineSpacing(0f, 1.1f)
    }

    private fun action(value: String, perform: () -> Unit): TextView = TextView(activity).apply {
        text = activity.uiText(value); textSize = 14f; gravity = Gravity.CENTER
        minimumHeight = activity.dp(UiMetrics.controlHeightDp)
        setThemeTextColor { Palette.primaryText }
        background = themedRoundedBackground(activity, { Palette.surfaceVariant }, { Palette.border }, radius = 8)
        setPadding(activity.dp(12), activity.dp(4), activity.dp(12), activity.dp(4))
        isClickable = true; isFocusable = true
        setOnClickListener { if (isEnabled && root.isAttachedToWindow) { activity.performControlHaptic(it); perform() } }
    }

    private fun input(label: String, viewID: Int, secure: Boolean): EditText = EditText(activity).apply {
        id = viewID; hint = activity.uiText(label); textSize = 15f; isSingleLine = true
        isSaveEnabled = false; isSaveFromParentEnabled = false
        inputType = InputType.TYPE_CLASS_TEXT or if (secure) InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
        textDirection = View.TEXT_DIRECTION_LTR; layoutDirection = View.LAYOUT_DIRECTION_LTR
        if (Build.VERSION.SDK_INT >= 26) { importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS; setAutofillHints(null) }
        setThemeTextColor { Palette.text }; bindTheme("hint") { setHintTextColor(Palette.muted) }
        background = themedRoundedBackground(activity, { Palette.surfaceVariant }, { Palette.border }, radius = 6)
        setPadding(activity.dp(13), 0, activity.dp(13), 0)
        minimumHeight = activity.dp(UiMetrics.controlHeightDp)
        UiText.preserveRawText(this)
    }

    private fun append(container: LinearLayout, view: View) {
        container.addView(view, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            .apply { topMargin = activity.dp(10) })
    }
}
