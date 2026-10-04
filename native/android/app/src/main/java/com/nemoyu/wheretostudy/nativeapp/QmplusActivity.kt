package com.nemoyu.wheretostudy.nativeapp

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.os.ResultReceiver
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.TextView
import java.lang.ref.WeakReference
import java.nio.charset.StandardCharsets
import org.json.JSONArray
import org.json.JSONObject

/** Official, user-operated SSO/MFA in the dedicated :qmplus process. Never a password form or native JS bridge. */
class QmplusActivity : Activity() {
    private var browser: WebView? = null
    private lateinit var status: TextView
    private lateinit var syncButton: TextView
    private val handler = Handler(Looper.getMainLooper())
    private var navigationRevision = 0L
    private var syncStartedAt = 0L
    private var syncing = false
    private var closing = false
    private var generation = -1L
    private var connectionToken: String? = null

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppLocale.wrap(newBase, AppPreferences(newBase).languageCode))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        Palette.configure(this)
        generation = intent.getLongExtra(EXTRA_GENERATION, -1)
        connectionToken = intent.getStringExtra(EXTRA_CONNECTION_TOKEN)
        if (generation < 0) { finish(); return }
        setResult(RESULT_CANCELED, resultIntent())
        runCatching {
            QmplusWebProfile.initialize()
            QmplusWebProfile.attach(this)
            installBrowser()
            if (intent.getBooleanExtra(EXTRA_CLEAR_FIRST, false)) clearSession(thenOpen = true)
            else browser?.loadUrl(startURL())
        }.onFailure {
            setResult(RESULT_CANCELED, resultIntent().putExtra(EXTRA_SYNC_FAILED, true))
            setContentView(TextView(this).apply {
                text = getString(R.string.qmplus_web_unavailable); textSize = 15f
                setThemeTextColor { Palette.muted }; setPadding(dp(20), dp(20), dp(20), dp(20))
            })
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun installBrowser() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setThemeBackgroundColor { Palette.background }
        }
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(8))
            addView(TextView(this@QmplusActivity).apply {
                text = "QMplus"; textSize = 17f; setThemeTextColor { Palette.text }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            syncButton = TextView(this@QmplusActivity).apply {
                text = getString(R.string.qmplus_sync); textSize = 15f; gravity = Gravity.CENTER
                minimumHeight = dp(UiMetrics.controlHeightDp); setPadding(dp(12), 0, dp(12), 0)
                background = themedRoundedBackground(this@QmplusActivity, { Palette.surfaceVariant }, radius = 8)
                setThemeTextColor { Palette.primaryText }; isEnabled = false; isClickable = true
                setOnClickListener { beginSync() }
            }
            addView(syncButton, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        })
        status = TextView(this).apply {
            text = getString(R.string.qmplus_web_login_notice); textSize = 13f
            setThemeTextColor { Palette.muted }; setPadding(dp(16), 0, dp(16), dp(8))
        }
        root.addView(status)
        val weakOwner = WeakReference(this)
        val webView = WebView(this).apply {
            WebView.setWebContentsDebuggingEnabled(false)
            settings.javaScriptEnabled = true; settings.domStorageEnabled = true
            settings.allowFileAccess = false; settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.setSupportMultipleWindows(false); settings.javaScriptCanOpenWindowsAutomatically = false
            settings.cacheMode = WebSettings.LOAD_NO_CACHE
            @Suppress("DEPRECATION")
            settings.saveFormData = false
            if (Build.VERSION.SDK_INT >= 26) importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
            // evaluateJavascript only: no addJavascriptInterface, no message handler,
            // and no application capabilities are exposed to any frame or SSO page.
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                    !QmplusPolicy.allowsHTTPSNavigation(request.url.toString())
                @Suppress("DEPRECATION")
                override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
                    !QmplusPolicy.allowsHTTPSNavigation(url)
                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                    weakOwner.get()?.invalidateSync()
                }
                override fun onPageFinished(view: WebView, url: String?) {
                    weakOwner.get()?.let { owner ->
                        if (owner.closing) return
                        owner.syncButton.isEnabled = QmplusPolicy.isBusinessPage(url.orEmpty()) && !owner.syncing
                        if (!owner.syncing) owner.status.text = owner.getString(R.string.qmplus_web_login_notice)
                    }
                }
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                    handler.cancel()
                    weakOwner.get()?.status?.setText(R.string.qmplus_web_error)
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            }
        }
        browser = webView
        root.addView(webView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
    }

    private fun beginSync() {
        val view = browser ?: return
        if (closing || syncing || !QmplusPolicy.isBusinessPage(view.url.orEmpty())) return
        val script = runCatching { assets.open("qmplus-sync.js").bufferedReader().use { it.readText() } }.getOrNull()
            ?: run { status.setText(R.string.qmplus_web_error); return }
        syncing = true; syncStartedAt = SystemClock.elapsedRealtime(); syncButton.isEnabled = false
        status.setText(R.string.qmplus_syncing)
        val revision = ++navigationRevision
        val key = "__wtsNativeResult$revision"
        val quotedKey = JSONObject.quote(key)
        val weakOwner = WeakReference(this)
        view.evaluateJavascript("if (location.origin === 'https://qmplus.qmul.ac.uk' && " +
            "['/my/','/my/index.php','/course/view.php','/mod/assign/view.php','/mod/quiz/view.php'].includes(location.pathname)) {\n" +
            script + "\nWTSQmSync().then(r => { const s = JSON.stringify(r); " +
            "window[$quotedKey] = r.ok && new TextEncoder().encode(s).byteLength <= ${QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES} ? s : 'error'; " +
            "}).catch(() => { window[$quotedKey] = 'error'; });\n}") {
            weakOwner.get()?.pollSnapshot(revision, key)
        }
    }

    private fun pollSnapshot(revision: Long, key: String) {
        val view = browser ?: return
        if (closing || !syncing || revision != navigationRevision || !QmplusPolicy.isBusinessPage(view.url.orEmpty())) return
        // JS owns a 120s total deadline; allow its bounded final serialization to finish.
        if (SystemClock.elapsedRealtime() - syncStartedAt > 125_000) { failSync(); return }
        val weakOwner = WeakReference(this)
        view.evaluateJavascript("window[${JSONObject.quote(key)}] || null") { encoded ->
            val owner = weakOwner.get() ?: return@evaluateJavascript
            if (owner.closing || !owner.syncing || owner.navigationRevision != revision ||
                !QmplusPolicy.isBusinessPage(owner.browser?.url.orEmpty())) return@evaluateJavascript
            if (encoded == "null") {
                owner.handler.postDelayed({ weakOwner.get()?.pollSnapshot(revision, key) }, 250)
                return@evaluateJavascript
            }
            val raw = encoded.takeIf { it.length <= QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES * 6 + 4 }
                ?.let { runCatching { JSONArray("[$it]").getString(0) }.getOrNull() }
            val bytes = raw?.toByteArray(StandardCharsets.UTF_8)
            if (bytes == null || raw == "error" || bytes.size > QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES) {
                owner.failSync(); return@evaluateJavascript
            }
            owner.closing = true
            owner.setResult(RESULT_OK, owner.resultIntent().putExtra(EXTRA_SNAPSHOT, bytes))
            owner.finish()
        }
    }

    private fun failSync() {
        invalidateSync()
        status.setText(R.string.qmplus_web_error)
        setResult(RESULT_CANCELED, resultIntent().putExtra(EXTRA_SYNC_FAILED, true))
    }

    private fun invalidateSync() {
        cancelRendererFlight()
        navigationRevision++; syncing = false; handler.removeCallbacksAndMessages(null)
        if (::syncButton.isInitialized) syncButton.isEnabled = QmplusPolicy.isBusinessPage(browser?.url.orEmpty()) && !closing
    }

    private fun clearSession(thenOpen: Boolean) {
        invalidateSync()
        browser?.stopLoading(); browser?.clearCache(true); browser?.clearHistory()
        val weakOwner = WeakReference(this)
        CookieManager.getInstance().removeAllCookies {
            CookieManager.getInstance().flush(); WebStorage.getInstance().deleteAllData()
            weakOwner.get()?.takeUnless { it.isFinishing || it.isDestroyed }?.let { owner ->
                if (thenOpen) {
                    owner.setResult(RESULT_CANCELED, owner.resultIntent()
                        .putExtra(EXTRA_COOKIES_CLEARED, true))
                    owner.browser?.loadUrl(owner.startURL())
                }
                else { owner.setResult(RESULT_OK, owner.resultIntent()); owner.finish() }
            }
        }
    }

    override fun onDestroy() {
        closing = true
        invalidateSync()
        browser?.apply {
            stopLoading(); webViewClient = WebViewClient(); webChromeClient = WebChromeClient()
            (parent as? ViewGroup)?.removeView(this); removeAllViews(); destroy()
        }
        browser = null
        QmplusWebProfile.detach(this)
        super.onDestroy()
    }

    companion object {
        internal const val EXTRA_GENERATION = "qmplus_generation"
        internal const val EXTRA_CONNECTION_TOKEN = "qmplus_connection_token"
        internal const val EXTRA_SNAPSHOT = "qmplus_business_snapshot"
        internal const val EXTRA_CLEAR_FIRST = "qmplus_clear_first"
        internal const val EXTRA_SYNC_FAILED = "qmplus_sync_failed"
        internal const val EXTRA_COOKIES_CLEARED = "qmplus_cookies_cleared"
        internal const val EXTRA_START_URL = "qmplus_start_url"
    }

    internal fun closeForLogout() { closing = true; invalidateSync(); browser?.stopLoading(); finish() }
    private fun resultIntent(): Intent = Intent().putExtra(EXTRA_GENERATION, generation)
        .putExtra(EXTRA_CONNECTION_TOKEN, connectionToken)
    private fun startURL(): String = intent.getStringExtra(EXTRA_START_URL)?.takeIf(QmplusPolicy::isBusinessPage)
        ?: QmplusPolicy.START_URL

    private fun cancelRendererFlight() {
        val view = browser ?: return
        if (QmplusPolicy.isBusinessPage(view.url.orEmpty())) view.evaluateJavascript(
            "if (location.origin === 'https://qmplus.qmul.ac.uk' && " +
                "['/my/','/my/index.php','/course/view.php','/mod/assign/view.php','/mod/quiz/view.php'].includes(location.pathname) " +
                "&& typeof WTSQmCancel === 'function') WTSQmCancel();", null)
    }
}

internal object QmplusWebProfile {
    private var initialized = false
    private var activity = WeakReference<QmplusActivity>(null)
    fun attach(owner: QmplusActivity) { activity = WeakReference(owner) }
    fun detach(owner: QmplusActivity) { if (activity.get() === owner) activity.clear() }
    fun closeCurrentActivity() { activity.get()?.closeForLogout() }
    fun initialize() {
        if (!initialized) {
            if (Build.VERSION.SDK_INT >= 28) WebView.setDataDirectorySuffix("qmplus_official_sso")
            // API 24–27: only this private :qmplus process may use the app's
            // default profile. Future app WebViews must not share that profile.
            initialized = true
        }
    }
}

/** No visible Activity and no external browser cookies. Clear completion returns to an app-context owner. */
class QmplusClearService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val generation = intent?.getLongExtra(QmplusActivity.EXTRA_GENERATION, -1) ?: -1
        @Suppress("DEPRECATION")
        val receiver = intent?.getParcelableExtra<ResultReceiver>(EXTRA_RECEIVER)
        runCatching {
            QmplusWebProfile.initialize()
            QmplusWebProfile.closeCurrentActivity()
            CookieManager.getInstance().removeAllCookies {
                CookieManager.getInstance().flush(); WebStorage.getInstance().deleteAllData()
                receiver?.send(RESULT_CLEARED, Bundle().apply { putLong(QmplusActivity.EXTRA_GENERATION, generation) })
                stopSelf(startId)
            }
        }.onFailure {
            receiver?.send(RESULT_FAILED, Bundle().apply { putLong(QmplusActivity.EXTRA_GENERATION, generation) })
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }
    companion object {
        internal const val EXTRA_RECEIVER = "qmplus_clear_receiver"
        internal const val RESULT_CLEARED = 1
        internal const val RESULT_FAILED = 2
    }
}

internal class QmplusClearReceiver(private val repository: QmplusRepository,
    private val attempt: QmplusCookieClearAttempt,
) : ResultReceiver(Handler(Looper.getMainLooper())) {
    override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
        if (resultData?.getLong(QmplusActivity.EXTRA_GENERATION, -1) != attempt.generation) return
        if (resultCode == QmplusClearService.RESULT_CLEARED)
            repository.cookiesCleared(attempt.generation, attempt.token)
        else repository.cookieClearCouldNotStart(attempt.generation, attempt.token)
    }
}
