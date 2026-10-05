package com.nemoyu.wheretostudy.nativeapp

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.ColorDrawable
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
import android.webkit.WebResourceError
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

/** Official SSO/MFA in :qmplus. No native JS bridge and no external-browser cookie access. */
class QmplusActivity : Activity() {
    private var browser: WebView? = null
    private lateinit var status: TextView
    private lateinit var reconnectButton: TextView
    private val handler = Handler(Looper.getMainLooper())
    private var navigationRevision = 0L
    private var syncStartedAt = 0L
    private var syncing = false
    private var closing = false
    private var generation = -1L
    private var connectionToken: String? = null
    private var browserRoot: View? = null
    private var authFlow: QmplusAuthFlow? = null
    private val authHandler = Handler(Looper.getMainLooper())
    private var foreground = false
    private var documentFinished = false
    private var authenticatedDocument = false
    private val pageScript by lazy { runCatching { assets.open("qmplus-page.js").bufferedReader().use { it.readText() } }
        .getOrDefault(QmplusLoginPagePolicy.UNKNOWN_PAGE_SCRIPT) }
    private var loginVisible = false
    private var clearingWebSession = false
    private var quietConnection = true
    private var silentRefresh = false
    private lateinit var featureStore: QmplusFeatureStore
    private var featureRecord: QmplusFeatureRecord? = null

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppLocale.wrap(newBase, AppPreferences(newBase).languageCode))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.setBackgroundDrawable(ColorDrawable(android.graphics.Color.TRANSPARENT))
        Palette.configure(this)
        generation = intent.getLongExtra(EXTRA_GENERATION, -1)
        connectionToken = intent.getStringExtra(EXTRA_CONNECTION_TOKEN)
        quietConnection = startURL() == QmplusPolicy.START_URL
        silentRefresh = intent.getBooleanExtra(EXTRA_SILENT_REFRESH, false) && quietConnection
        if (generation < 0) { finish(); return }
        setResult(RESULT_CANCELED, resultIntent())
        if (savedInstanceState != null) {
            // A restored private Activity cannot inherit the old native owner.
            // Reconnect with a new token/revision; keep cookies and saved data.
            closing = true
            setResult(RESULT_CANCELED, resultIntent().putExtra(EXTRA_OWNER_EXPIRED, true))
            finish(); return
        }
        featureStore = QmplusFeatureStore(applicationContext.noBackupFilesDir)
        featureRecord = runCatching { featureStore.status() }.getOrNull()?.takeIf {
            it.enabled && it.revision == intent.getLongExtra(EXTRA_FEATURE_REVISION, -1)
        }
        if (!isFeatureCurrent()) { closing = true; finish(); return }
        watchFeature()
        runCatching {
            QmplusWebProfile.initialize()
            QmplusWebProfile.attach(this)
            installBrowser()
            authFlow?.begin()
            if (intent.getBooleanExtra(EXTRA_CLEAR_FIRST, false)) clearSession(thenOpen = true)
            else browser?.loadUrl(startURL())
        }.onFailure {
            setResult(RESULT_CANCELED, resultIntent().putExtra(EXTRA_SYNC_FAILED, true))
            revealOfficialWindow()
            if (closing) return@onFailure
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
            alpha = 0f
        }
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(8))
            addView(TextView(this@QmplusActivity).apply {
                text = "QMplus"; textSize = 17f; setThemeTextColor { Palette.text }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            reconnectButton = TextView(this@QmplusActivity).apply {
                text = getString(R.string.qmplus_connect); textSize = 15f; gravity = Gravity.CENTER
                setThemeTextColor { Palette.primaryText }; visibility = View.GONE
                minimumHeight = dp(UiMetrics.controlHeightDp); setPadding(dp(12), 0, dp(12), 0)
                setOnClickListener {
                    if (closing || !this@QmplusActivity.foreground || !documentFinished || !isFeatureCurrent()) return@setOnClickListener
                    setResult(RESULT_CANCELED, resultIntent().putExtra(EXTRA_RECONNECT_REQUEST, true))
                    closing = true; authFlow?.close(); invalidateSync(); finish()
                }
            }
            addView(reconnectButton, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
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
            isSaveEnabled = false; isSaveFromParentEnabled = false
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
                    weakOwner.get()?.let { owner ->
                        owner.authenticatedDocument = false; owner.invalidateSync(resumeInterrupted = true); owner.documentFinished = false
                        owner.authFlow?.pageStarted(url.orEmpty())
                    }
                }
                override fun onPageFinished(view: WebView, url: String?) {
                    weakOwner.get()?.let { owner ->
                        if (owner.closing) return
                        owner.documentFinished = true
                        owner.reconnectButton.visibility = View.GONE
                        if (!owner.syncing) owner.status.text = owner.getString(
                            if (owner.quietConnection) R.string.qmplus_web_login_notice else R.string.qmplus_saved_login_manual)
                        owner.inspectFinishedDocument(url.orEmpty())
                    }
                }
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                    handler.cancel()
                    weakOwner.get()?.let { owner -> owner.authFlow?.manualRequired(); owner.status.setText(R.string.qmplus_web_error) }
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (request.isForMainFrame) weakOwner.get()?.authFlow?.manualRequired()
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            }
        }
        browser = webView
        root.addView(webView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        browserRoot = root; setContentView(root)
        val weakBrowser = WeakReference(webView)
        val credentialWorker = QmplusAuthCredentialWorker(QmplusCredentialStore(applicationContext))
        val renderer = object : QmplusAuthRenderer {
            override val currentURL: String? get() = weakBrowser.get()?.url
            override val active: Boolean get() = weakOwner.get()?.let {
                it.foreground && !it.closing && !it.isFinishing && !it.isDestroyed && it.isFeatureCurrent()
            } == true
            override fun evaluate(script: String, completion: (String) -> Unit) {
                val view = weakBrowser.get() ?: return
                if (active) view.evaluateJavascript(script) { completion(it) }
            }
            override fun navigateToOfficialSSO() {
                if (active) weakBrowser.get()?.loadUrl(QmplusLoginPagePolicy.SSO_START_URL)
            }
            override fun navigateToOfficialLogin() {
                if (active) weakBrowser.get()?.loadUrl(QmplusLoginPagePolicy.LOGIN_ENTRY_URL)
            }
            override fun openBusinessPage(value: String) {
                if (active && QmplusPolicy.isBusinessPage(value)) weakBrowser.get()?.loadUrl(value)
            }
        }
        val schedulerHandler = authHandler
        val scheduler = object : QmplusAuthScheduler {
            override fun schedule(delayMillis: Long, action: () -> Unit): () -> Unit {
                val task = Runnable(action)
                schedulerHandler.postDelayed(task, delayMillis)
                return { schedulerHandler.removeCallbacks(task) }
            }
        }
        val explicitManual = intent.getBooleanExtra(EXTRA_MANUAL_CONTINUATION, false)
        val savedOptIn = intent.getBooleanExtra(EXTRA_SAVED_LOGIN_ENABLED, false) && !explicitManual
        val diagnosticsEnabled = BuildConfig.DEBUG && intent.getBooleanExtra(EXTRA_AUTH_DIAGNOSTICS, false)
        val authScript = runCatching {
            assets.open("qmplus-auth.js").bufferedReader().use { it.readText() }
        }.getOrDefault("")
        authFlow = QmplusAuthFlow(renderer, credentialWorker, scheduler,
            savedOptIn,
            intent.getLongExtra(EXTRA_SAVED_LOGIN_REVISION, -1), authScript,
            reveal = { weakOwner.get()?.revealOfficialWindow() },
            verificationRequired = { weakOwner.get()?.revealOfficialWindow(verification = true) },
            verificationFinished = { weakOwner.get()?.hideForSync() },
            authenticated = { weakOwner.get()?.beginSync() },
            reportPhase = { phase ->
                if (diagnosticsEnabled)
                    weakOwner.get()?.status?.contentDescription = "qmplus.auth.$phase"
            }, quietConnection = quietConnection, requestedTarget = startURL(),
            featureEnabled = { weakOwner.get()?.isFeatureCurrent() == true }, pageScript = pageScript,
            manualContinuation = { weakOwner.get()?.deferManualContinuation() },
            pageObserved = { kind -> weakOwner.get()?.let { owner ->
                owner.authenticatedDocument = kind == QmplusPageKind.AUTHENTICATED && QmplusPolicy.isBusinessPage(owner.browser?.url.orEmpty())
                if (owner.authenticatedDocument) owner.persistOfficialWebSession()
                owner.reconnectButton.visibility = if (kind == QmplusPageKind.ERROR) View.VISIBLE else View.GONE
                if (kind == QmplusPageKind.ERROR) owner.status.setText(R.string.qmplus_web_error)
            } })
        if (!quietConnection || explicitManual) revealOfficialWindow()
    }

    private fun inspectFinishedDocument(url: String) {
        if (closing || !foreground || syncing || !documentFinished || browser?.url != url) return
        authFlow?.pageReady(url)
    }

    private fun deferManualContinuation() {
        if (closing || isFinishing || isDestroyed || loginVisible) return
        closing = true
        authFlow?.close(); invalidateSync(); browser?.stopLoading()
        setResult(RESULT_CANCELED, resultIntent().putExtra(EXTRA_CONNECT_REQUIRED, true))
        finish()
    }

    private fun revealOfficialWindow(verification: Boolean = false) {
        if (closing || isFinishing || isDestroyed) return
        if (silentRefresh && !(verification && foreground)) {
            // Background refresh defers unknown/error pages. Only a verified
            // challenge observed while foreground can present the official UI.
            closing = true
            authFlow?.close(); invalidateSync()
            browser?.stopLoading()
            setResult(RESULT_CANCELED, resultIntent().putExtra(EXTRA_CONNECT_REQUIRED, true))
            finish(); return
        }
        loginVisible = true
        window.clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
        browserRoot?.alpha = 1f
        window.setBackgroundDrawable(ColorDrawable(Palette.background))
        if (::status.isInitialized && !syncing) status.text = if (verification)
            uiText("请在官方窗口完成验证码或 MFA，完成后将继续同步。") else getString(R.string.qmplus_saved_login_manual)
    }

    private fun beginSync() {
        val view = browser ?: return
        if (closing || syncing || !foreground || !isFeatureCurrent() || !QmplusPolicy.isBusinessPage(view.url.orEmpty())) return
        val url = view.url
        val revision = navigationRevision
        val weakOwner = WeakReference(this)
        val deadline = Runnable {
            weakOwner.get()?.takeIf { !it.closing && !it.syncing && it.navigationRevision == revision &&
                it.foreground && it.isFeatureCurrent() }?.let { owner ->
                owner.authFlow?.manualRequired(); owner.revealOfficialWindow()
            }
        }
        handler.postDelayed(deadline, 2_000)
        runCatching { view.evaluateJavascript(QmplusLoginPagePolicy.authenticatedPageScript(pageScript)) { authenticated ->
            val owner = weakOwner.get() ?: return@evaluateJavascript
            owner.handler.removeCallbacks(deadline)
            if (owner.closing || owner.syncing || !owner.foreground || !owner.isFeatureCurrent() ||
                owner.navigationRevision != revision || owner.browser?.url != url) return@evaluateJavascript
            if (authenticated == "true") owner.startVerifiedSync()
            else { owner.authFlow?.manualRequired(); owner.revealOfficialWindow() }
        } }.onFailure { handler.removeCallbacks(deadline); authFlow?.manualRequired(); revealOfficialWindow() }
    }

    private fun hideForSync() {
        // A transparent, untouchable Activity retains the live WebView and its
        // resumed owner. No hide()/finish()/focus change that would trigger Pause.
        if (!quietConnection) return
        loginVisible = false
        browserRoot?.alpha = 0f
        window.setBackgroundDrawable(ColorDrawable(android.graphics.Color.TRANSPARENT))
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
    }

    private fun startVerifiedSync() {
        val view = browser ?: return
        if (closing || syncing || !foreground || !isFeatureCurrent() || !QmplusPolicy.isBusinessPage(view.url.orEmpty())) return
        val script = runCatching { assets.open("qmplus-sync.js").bufferedReader().use { it.readText() } }.getOrNull()
            ?: run { authFlow?.manualRequired(); status.setText(R.string.qmplus_web_error); return }
        syncing = true; syncStartedAt = SystemClock.elapsedRealtime()
        hideForSync()
        status.setText(R.string.qmplus_syncing)
        val revision = ++navigationRevision
        val key = "__wtsNativeResult$revision"
        val quotedKey = JSONObject.quote(key)
        val weakOwner = WeakReference(this)
        view.evaluateJavascript("if (location.origin === 'https://qmplus.qmul.ac.uk' && " +
            "['/my/','/my/index.php','/course/view.php','/mod/assign/view.php','/mod/quiz/view.php'].includes(location.pathname)) {\n" +
            script + "\nWTSQmSync().then(r => { const s = JSON.stringify(r); " +
            "window[$quotedKey] = r.ok && new TextEncoder().encode(s).byteLength <= ${QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES} ? s : " +
            "(r.ok === false && r.error_code === 'QM_PAGE_NOT_READY' ? 'QM_PAGE_NOT_READY' : 'error'); " +
            "}).catch(() => { window[$quotedKey] = 'error'; });\n}") {
            weakOwner.get()?.pollSnapshot(revision, key)
        }
    }

    private fun pollSnapshot(revision: Long, key: String) {
        val view = browser ?: return
        if (!isFeatureCurrent()) { closeForFeatureDisabled(); return }
        if (closing || !syncing || revision != navigationRevision || !QmplusPolicy.isBusinessPage(view.url.orEmpty())) return
        // JS owns a 120s total deadline; allow its bounded final serialization to finish.
        if (SystemClock.elapsedRealtime() - syncStartedAt > 125_000) { failSync(); return }
        val weakOwner = WeakReference(this)
        view.evaluateJavascript("window[${JSONObject.quote(key)}] || null") { encoded ->
            val owner = weakOwner.get() ?: return@evaluateJavascript
            if (owner.closing || !owner.isFeatureCurrent() || !owner.syncing || owner.navigationRevision != revision ||
                !QmplusPolicy.isBusinessPage(owner.browser?.url.orEmpty())) return@evaluateJavascript
            if (encoded == "null") {
                owner.handler.postDelayed({ weakOwner.get()?.pollSnapshot(revision, key) }, 250)
                return@evaluateJavascript
            }
            val raw = encoded.takeIf { it.length <= QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES * 6 + 4 }
                ?.let { runCatching { JSONArray("[$it]").getString(0) }.getOrNull() }
            val bytes = raw?.toByteArray(StandardCharsets.UTF_8)
            if (raw == "QM_PAGE_NOT_READY") {
                owner.persistOfficialWebSession()
                owner.closing = true; owner.authFlow?.close(); owner.invalidateSync(); owner.browser?.stopLoading()
                owner.setResult(RESULT_CANCELED, owner.resultIntent().putExtra(EXTRA_PAGE_NOT_READY, true))
                owner.finish(); return@evaluateJavascript
            }
            if (bytes == null || raw == "error" || bytes.size > QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES) {
                owner.failSync(); return@evaluateJavascript
            }
            // WebView owns its isolated cookies. Persist the current official
            // session before this private Activity/process may be released;
            // never export cookie values or turn a disk failure into a logout.
            if (owner.authenticatedDocument) owner.persistOfficialWebSession()
            owner.closing = true
            owner.setResult(RESULT_OK, owner.resultIntent().putExtra(EXTRA_SNAPSHOT, bytes))
            owner.finish()
        }
    }

    private fun failSync() {
        if (silentRefresh) { revealOfficialWindow(); return; }
        invalidateSync()
        authFlow?.manualRequired()
        revealOfficialWindow()
        status.setText(R.string.qmplus_web_error)
        setResult(RESULT_CANCELED, resultIntent().putExtra(EXTRA_SYNC_FAILED, true))
    }

    private fun invalidateSync(resumeInterrupted: Boolean = false) {
        if (resumeInterrupted && syncing && !closing) authFlow?.interruptedSync()
        cancelRendererFlight()
        navigationRevision++; syncing = false; handler.removeCallbacksAndMessages(null)
    }

    private fun clearSession(thenOpen: Boolean) {
        clearingWebSession = true
        invalidateSync()
        browser?.stopLoading(); browser?.clearCache(true); browser?.clearHistory()
        val weakOwner = WeakReference(this)
        CookieManager.getInstance().removeAllCookies {
            CookieManager.getInstance().flush(); WebStorage.getInstance().deleteAllData()
            weakOwner.get()?.takeUnless { it.isFinishing || it.isDestroyed }?.let { owner ->
                if (thenOpen) {
                    owner.clearingWebSession = false
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
        authFlow?.close(); authFlow = null; authHandler.removeCallbacksAndMessages(null)
        invalidateSync()
        browser?.stopLoading()
        persistOfficialWebSession()
        browser?.apply {
            stopLoading(); webViewClient = WebViewClient(); webChromeClient = WebChromeClient()
            (parent as? ViewGroup)?.removeView(this); removeAllViews(); destroy()
        }
        browser = null; browserRoot = null
        QmplusWebProfile.detach(this)
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume(); foreground = true
        if (documentFinished) browser?.url?.let(::inspectFinishedDocument)
    }

    override fun onStop() {
        foreground = false
        authFlow?.suspend(); invalidateSync(resumeInterrupted = true)
        super.onStop()
    }

    override fun onPause() {
        foreground = false
        persistOfficialWebSession()
        authFlow?.suspend(); invalidateSync(resumeInterrupted = true)
        super.onPause()
    }

    companion object {
        internal const val EXTRA_GENERATION = "qmplus_generation"
        internal const val EXTRA_CONNECTION_TOKEN = "qmplus_connection_token"
        internal const val EXTRA_SNAPSHOT = "qmplus_business_snapshot"
        internal const val EXTRA_CLEAR_FIRST = "qmplus_clear_first"
        internal const val EXTRA_SYNC_FAILED = "qmplus_sync_failed"
        internal const val EXTRA_PAGE_NOT_READY = "qmplus_page_not_ready"
        internal const val EXTRA_COOKIES_CLEARED = "qmplus_cookies_cleared"
        internal const val EXTRA_START_URL = "qmplus_start_url"
        // Policy metadata only. A secret is never an Intent/Bundle field.
        internal const val EXTRA_SAVED_LOGIN_ENABLED = "qmplus_saved_login_enabled"
        internal const val EXTRA_SAVED_LOGIN_REVISION = "qmplus_saved_login_revision"
        // DEBUG-only fixed phase codes; never an account, URL, form value, or script result.
        internal const val EXTRA_AUTH_DIAGNOSTICS = "qmplus_auth_diagnostics"
        internal const val EXTRA_FEATURE_REVISION = "qmplus_feature_revision"
        internal const val EXTRA_OWNER_EXPIRED = "qmplus_owner_expired"
        internal const val EXTRA_RECONNECT_REQUEST = "qmplus_reconnect_request"
        internal const val EXTRA_SILENT_REFRESH = "qmplus_silent_refresh"
        internal const val EXTRA_CONNECT_REQUIRED = "qmplus_connect_required"
        internal const val EXTRA_MANUAL_CONTINUATION = "qmplus_manual_continuation"
    }

    internal fun closeForLogout() { clearingWebSession = true; closing = true; authFlow?.close(); invalidateSync(); browser?.stopLoading(); finish() }

    private fun persistOfficialWebSession() {
        if (browser == null || clearingWebSession) return
        // Flush only the engine-owned persistent profile. Never extract cookies
        // or change their expiry; logout/account replacement retain their fence.
        runCatching { CookieManager.getInstance().flush() }
    }
    internal fun closeForFeatureDisabled() {
        // Only retire the owner. Cookie, saved-login, and business-cache removal
        // belong exclusively to the separate explicit logout/clear workflow.
        closing = true; authFlow?.close(); invalidateSync(); browser?.stopLoading(); finish()
    }
    internal fun acceptsFeatureStop(token: String?, revision: Long): Boolean =
        QmplusFeatureOwnerPolicy.acceptsStop(connectionToken, featureRecord?.revision ?: -1, token, revision)
    private fun isFeatureCurrent(): Boolean = ::featureStore.isInitialized && featureRecord?.let {
        QmplusWebProfile.featureOwnerIsCurrent(it.revision) && featureStore.isCurrent(it)
    } == true
    private fun watchFeature() {
        val weakOwner = WeakReference(this)
        val task = object : Runnable {
            override fun run() {
                val owner = weakOwner.get() ?: return
                if (owner.closing || owner.isFinishing || owner.isDestroyed) return
                if (!owner.isFeatureCurrent()) { owner.closeForFeatureDisabled(); return }
                owner.authHandler.postDelayed(this, 500)
            }
        }
        authHandler.postDelayed(task, 500)
    }
    private fun resultIntent(): Intent = Intent().putExtra(EXTRA_GENERATION, generation)
        .putExtra(EXTRA_CONNECTION_TOKEN, connectionToken)
        .putExtra(EXTRA_FEATURE_REVISION, intent.getLongExtra(EXTRA_FEATURE_REVISION, -1))
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
    private var stoppedFeatureRevision = -1L
    fun featureOwnerIsCurrent(revision: Long): Boolean = revision > stoppedFeatureRevision
    fun attach(owner: QmplusActivity) { activity = WeakReference(owner) }
    fun detach(owner: QmplusActivity) { if (activity.get() === owner) activity.clear() }
    fun closeCurrentActivity() { activity.get()?.closeForLogout() }
    fun stopFeatureOwner(token: String?, revision: Long) {
        // Also fence a launch still queued when Off arrives before its Activity
        // exists. This process marker is useful when the durable write failed.
        if (revision >= 0) stoppedFeatureRevision = maxOf(stoppedFeatureRevision, revision)
        activity.get()?.takeIf { it.acceptsFeatureStop(token, revision) }?.closeForFeatureDisabled()
    }
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
        if (intent?.getBooleanExtra(EXTRA_STOP_ONLY, false) == true) {
            // Feature Off must not initialize a Web profile or clear any storage.
            QmplusWebProfile.stopFeatureOwner(intent.getStringExtra(QmplusActivity.EXTRA_CONNECTION_TOKEN),
                intent.getLongExtra(QmplusActivity.EXTRA_FEATURE_REVISION, -1))
            stopSelf(startId)
            return START_NOT_STICKY
        }
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
        internal const val EXTRA_STOP_ONLY = "qmplus_stop_only"
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
