package com.nemoyu.wheretostudy.nativeapp

import android.app.AlertDialog
import android.os.Build
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean

/** This explicit settings dialog is not a login client or an academic password field. */
internal object QmplusSavedLoginDialog {
    fun show(activity: MainActivity, source: View) {
        if (!source.isAttachedToWindow || activity.isFinishing || activity.isDestroyed) return
        val fields = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL; setPadding(activity.dp(20), activity.dp(8), activity.dp(20), activity.dp(8))
        }
        val selection = activity.getSharedPreferences("qmplus_settings_ui", android.content.Context.MODE_PRIVATE)
        val savedLogin = activity.qmplusState().savedLoginStatus.enabled
        fields.addView(TextView(activity).apply {
            text = activity.uiText(if (savedLogin) "已在本机安全保存 QMplus 登录资料。" else "尚未保存 QMplus 登录资料。")
            textSize = 13f; setThemeTextColor { Palette.muted }
        })
        if (savedLogin) fields.addView(TextView(activity).apply {
            text = activity.uiText("已保存的密码不会回显。仅更新登录资料时需要重新填写。")
            textSize = 12f; setThemeTextColor { Palette.muted }
        })
        fields.addView(TextView(activity).apply {
            text = activity.uiText("已保存的账号和密码用于自动完成官方登录；只有验证码或 MFA 需要您操作。未知页面会暂停，可手动继续。"); textSize = 12f
            setThemeTextColor { Palette.muted }
        })
        fields.addView(TextView(activity).apply {
            text = activity.uiText("保存选项首次默认开启；只有点击“保存”后，登录资料才会存入本机安全存储。")
            textSize = 12f; setThemeTextColor { Palette.muted }
        })
        fields.addView(TextView(activity).apply {
            text = activity.uiText("关闭“启用 QMplus”只暂停连接和同步，保留登录资料、会话及课程缓存。关闭自动填写、删除登录资料或退出并清除数据，请使用对应操作。"); textSize = 12f
            setThemeTextColor { Palette.muted }
        })
        val optIn = Switch(activity).apply {
            id = R.id.qmplus_saved_login_opt_in
            contentDescription = activity.getString(R.string.qmplus_saved_login_opt_in)
            isChecked = selection.getBoolean("save_login_selected", true)
            minimumHeight = activity.dp(UiMetrics.controlHeightDp)
        }
        fields.addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = android.view.Gravity.CENTER_VERTICAL
            addView(TextView(activity).apply {
                text = activity.getString(R.string.qmplus_saved_login_opt_in)
                textSize = 15f; setThemeTextColor { Palette.text }
                setPadding(0, 0, activity.dp(12), 0)
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(optIn, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        fun input(resource: Int, viewID: Int, password: Boolean): EditText = EditText(activity).apply {
            id = viewID; hint = activity.getString(resource); textSize = 15f; isSingleLine = true
            isSaveEnabled = false; isSaveFromParentEnabled = false
            inputType = InputType.TYPE_CLASS_TEXT or if (password) InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
            textDirection = View.TEXT_DIRECTION_LTR; layoutDirection = View.LAYOUT_DIRECTION_LTR
            if (Build.VERSION.SDK_INT >= 26) {
                importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS; setAutofillHints(null)
            }
            setThemeTextColor { Palette.text }; bindTheme("hint") { setHintTextColor(Palette.muted) }
            background = themedRoundedBackground(activity, { Palette.surfaceVariant }, { Palette.border }, radius = 6)
            setPadding(activity.dp(13), 0, activity.dp(13), 0)
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, activity.dp(UiMetrics.controlHeightDp))
            UiText.preserveRawText(this)
        }
        val account = input(R.string.qmplus_saved_login_account, R.id.qmplus_saved_login_account, false)
        val password = input(R.string.qmplus_saved_login_password, R.id.qmplus_saved_login_password, true)
        fields.addView(account); fields.addView(spacer(activity, 8)); fields.addView(password)
        val dialog = AlertDialog.Builder(activity).setTitle(R.string.qmplus_saved_login_title).setView(fields)
            .setNegativeButton(android.R.string.cancel, null)
            .setNeutralButton(R.string.qmplus_saved_login_remove, null)
            .setPositiveButton(R.string.qmplus_saved_login_save, null).create()
        val active = AtomicBoolean(true)
        val weakActivity = WeakReference(activity); val weakSource = WeakReference(source); val weakDialog = WeakReference(dialog)
        val sourceListener = object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) = Unit
            override fun onViewDetachedFromWindow(view: View) { active.set(false); weakDialog.get()?.dismiss() }
        }
        source.addOnAttachStateChangeListener(sourceListener)
        dialog.setOnDismissListener {
            active.set(false); source.removeOnAttachStateChangeListener(sourceListener)
            account.text.clear(); password.text.clear()
        }
        dialog.show()
        dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val save = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
        val remove = dialog.getButton(AlertDialog.BUTTON_NEUTRAL)
        remove.isEnabled = activity.qmplusState().savedLoginStatus.enabled
        remove.setOnClickListener { activity.disconnectQmplus(); dialog.dismiss() }
        save.isEnabled = optIn.isChecked
        optIn.setOnCheckedChangeListener { _, enabled ->
            selection.edit().putBoolean("save_login_selected", enabled).apply()
            save.isEnabled = enabled
        }
        save.setOnClickListener {
            if (!active.get() || !optIn.isChecked) return@setOnClickListener
            val entered = CharArray(password.text.length) { password.text[it] }
            if (!QmplusCredentialLimits.valid(account.text.toString(), entered)) {
                entered.fill('\u0000')
                Toast.makeText(activity, activity.getString(R.string.qmplus_saved_login_invalid), Toast.LENGTH_LONG).show()
                return@setOnClickListener
            }
            save.isEnabled = false; remove.isEnabled = false; optIn.isEnabled = false
            account.isEnabled = false; password.isEnabled = false
            activity.saveQmplusLogin(account.text.toString(), entered) { result ->
                val current = weakActivity.get() ?: return@saveQmplusLogin
                val currentDialog = weakDialog.get() ?: return@saveQmplusLogin
                if (!active.get() || weakSource.get()?.isAttachedToWindow != true || current.isFinishing || current.isDestroyed) return@saveQmplusLogin
                if (result.isSuccess) currentDialog.dismiss()
                else {
                    currentDialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = true
                    currentDialog.getButton(AlertDialog.BUTTON_NEUTRAL).isEnabled = current.qmplusState().savedLoginStatus.enabled
                    currentDialog.findViewById<Switch>(R.id.qmplus_saved_login_opt_in)?.isEnabled = true
                    currentDialog.findViewById<EditText>(R.id.qmplus_saved_login_account)?.isEnabled = true
                    currentDialog.findViewById<EditText>(R.id.qmplus_saved_login_password)?.isEnabled = true
                    Toast.makeText(current, current.getString(R.string.qmplus_saved_login_failed), Toast.LENGTH_LONG).show()
                }
            }
            entered.fill('\u0000'); password.text.clear()
        }
    }
}
