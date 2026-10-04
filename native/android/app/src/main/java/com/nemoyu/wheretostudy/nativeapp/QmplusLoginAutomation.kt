package com.nemoyu.wheretostudy.nativeapp

import java.net.URI
import java.lang.ref.WeakReference
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Only callback identities and fixed stages; never credentials, cookies, or URLs in a DTO. */
internal class QmplusLoginAutomationGate {
    var document = 0L
        private set
    private var active = true
    private var attemptedSync = false
    private var attemptedUsername = false
    private var attemptedPassword = false
    private var attemptedAccount = false
    private var requiresManualInteraction = false
    private var installedDocument: Long? = null
    private var submittedUsernameDocument: Long? = null
    private var selectedAccountDocument: Long? = null
    private var claimedAccountDocument: Long? = null
    private var attemptedSSO = false

    fun beginDocument(): Long {
        document++; installedDocument = null; submittedUsernameDocument = null; selectedAccountDocument = null; claimedAccountDocument = null
        return document
    }
    fun accepts(expectedDocument: Long): Boolean = active && expectedDocument == document
    fun claimAutomaticSync(expectedDocument: Long, authenticated: Boolean): Boolean {
        if (!authenticated || !accepts(expectedDocument) || attemptedSync) return false
        attemptedSync = true; return true
    }
    // Only a cancelled in-flight sync may be resumed. This does not grant a
    // second username/password attempt or retry a completed/failed sync.
    fun interruptedSync() { if (active) attemptedSync = false }
    fun installed(expectedDocument: Long, result: String): Boolean {
        if (!accepts(expectedDocument) || requiresManualInteraction || result != "AUTH_INSTALLED") return false
        installedDocument = expectedDocument; return true
    }
    fun claimSSO(expectedDocument: Long, savedOptIn: Boolean): Boolean {
        if (!savedOptIn || !accepts(expectedDocument) || requiresManualInteraction || attemptedSSO) return false
        attemptedSSO = true; return true
    }
    fun claimFill(expectedDocument: Long, stage: String, savedOptIn: Boolean, accountMatch: Boolean = false): Boolean {
        if (!savedOptIn || !accepts(expectedDocument) || requiresManualInteraction || installedDocument != expectedDocument) return false
        return when (stage) {
            "account" -> if (attemptedAccount || attemptedUsername || attemptedPassword || !accountMatch) false
                else { attemptedAccount = true; claimedAccountDocument = expectedDocument; true }
            "username" -> if (attemptedUsername || attemptedPassword) false else { attemptedUsername = true; true }
            "password" -> if (attemptedPassword || !accountMatch || !identityAcknowledged(expectedDocument)) false
                else { attemptedPassword = true; true }
            else -> false
        }
    }
    fun submitted(expectedDocument: Long, stage: String, result: String): Boolean {
        if (!accepts(expectedDocument) || requiresManualInteraction) return false
        if (stage == "account" && attemptedAccount && claimedAccountDocument == expectedDocument && result == "ACCOUNT_SELECTED") {
            selectedAccountDocument = expectedDocument; return true
        }
        if (stage == "username" && attemptedUsername && result == "USERNAME_SUBMITTED") {
            submittedUsernameDocument = expectedDocument; return true
        }
        return stage == "password" && attemptedPassword && result == "PASSWORD_SUBMITTED"
    }
    fun usernameSubmitted(expectedDocument: Long): Boolean = accepts(expectedDocument) && submittedUsernameDocument == expectedDocument
    fun accountSelected(expectedDocument: Long): Boolean = accepts(expectedDocument) && selectedAccountDocument == expectedDocument
    fun identityAcknowledged(expectedDocument: Long): Boolean = usernameSubmitted(expectedDocument) || accountSelected(expectedDocument)
    fun passwordAttempted(): Boolean = attemptedPassword
    fun hasAttemptedCredentialSubmission(): Boolean = attemptedAccount || attemptedUsername || attemptedPassword
    fun manualInteractionRequired() { requiresManualInteraction = true }
    fun close() { active = false; document++ }
}

internal object QmplusLoginPagePolicy {
    // This tenant was observed on the official QMplus SAML redirect. Other
    // tenants/origins/paths remain visible and user-operated, not guessed.
    private const val QM_TENANT = "569df091-b013-40e3-86ee-bd9cb9e25814"
    const val SSO_START_URL = "https://qmplus.qmul.ac.uk/auth/saml2/login.php"
    fun isSSOEntry(value: String): Boolean = trustedURI(value)?.let {
        it.host.equals("qmplus.qmul.ac.uk", true) && (it.rawPath == "/login/index.php" ||
            (it.rawPath == "/" && it.rawQuery == "redirect=0"))
    } == true
    fun isSSOTransit(value: String): Boolean = trustedURI(value)?.let {
        it.host.equals("qmplus.qmul.ac.uk", true) && it.rawPath == "/auth/saml2/login.php"
    } == true
    private fun trustedURI(value: String): URI? = runCatching { URI(value) }.getOrNull()?.takeIf {
        it.scheme.equals("https", true) && it.rawUserInfo == null && it.port in listOf(-1, 443) && it.rawFragment == null
    }
    fun isMicrosoftPage(value: String): Boolean = trustedURI(value)?.let {
        it.host.equals("login.microsoftonline.com", true) && it.rawPath in setOf("/$QM_TENANT/saml2", "/$QM_TENANT/login")
    } == true
    fun canInspectAuthenticationPage(value: String): Boolean = runCatching { URI(value) }.getOrNull()?.let {
        it.scheme.equals("https", true) && it.rawUserInfo == null && it.port in listOf(-1, 443) &&
            it.rawFragment == null && when {
                it.host.equals("qmplus.qmul.ac.uk", true) -> isSSOEntry(value)
                it.host.equals("login.microsoftonline.com", true) -> it.rawPath in setOf("/$QM_TENANT/saml2", "/$QM_TENANT/login")
                else -> false
            }
    } == true

    val authenticatedPageScript = """
        (() => {
            if (window.top !== window || location.origin !== 'https://qmplus.qmul.ac.uk') return false;
            if (!['/my/', '/my/index.php', '/course/view.php', '/mod/assign/view.php', '/mod/quiz/view.php'].includes(location.pathname)) return false;
            const body = document.body;
            return !!body && !body.classList.contains('notloggedin') && !body.classList.contains('guestuser')
                && document.querySelectorAll('.usermenu .userbutton').length === 1;
        })()
    """.trimIndent()
}

internal interface QmplusAuthRenderer {
    val currentURL: String?
    val active: Boolean
    fun evaluate(script: String, completion: (String) -> Unit)
    fun navigateToOfficialSSO()
    fun openBusinessPage(value: String)
}
internal interface QmplusAuthCredentials {
    fun authorized(revision: Long, completion: (Boolean) -> Unit)
    fun account(revision: Long, completion: (String?) -> Unit)
    /** Password ownership ends when this synchronous callback returns. */
    fun password(revision: Long, completion: (QmplusSavedLogin?) -> Unit)
    fun close()
}
internal interface QmplusAuthScheduler {
    fun schedule(delayMillis: Long, action: () -> Unit): () -> Unit
}

internal data class QmplusAuthObservation(val stage: String, val document: String, val accountMatch: Boolean, val reason: String)

internal object QmplusAuthResultCodec {
    private val reasons = setOf("READY", "AUTHENTICATED", "LOADING", "INVALID_NONCE", "STALE_DOCUMENT", "UNTRUSTED_CONTEXT",
        "UNSUPPORTED_PAGE", "ACCOUNT_CHOOSER", "ACCOUNT_HINT_REQUIRED", "FORM_UNTRUSTED", "INTERFERENCE", "KNOWN_FORM_ABSENT", "ACCOUNT_MISMATCH",
        "USERNAME_NOT_SUBMITTED", "ALREADY_ATTEMPTED")
    fun code(encoded: String): String? = encoded.takeIf { it.length <= 96 }?.let {
        runCatching { JSONArray("[$it]").get(0) as? String }.getOrNull()
    }?.takeIf { it in setOf("AUTH_INSTALLED", "AUTH_CONFLICT", "ACCOUNT_SELECTED", "USERNAME_SUBMITTED", "PASSWORD_SUBMITTED", "MANUAL_REQUIRED", "REJECTED", "STALE_DOCUMENT") }
    fun observation(encoded: String, nonce: String): QmplusAuthObservation? = encoded.takeIf { it.length <= 1024 }?.let {
        runCatching {
            val json = JSONObject(it)
            require(json.keys().asSequence().toSet() == setOf("v", "stage", "document", "accountMatch", "reason"))
            require(json.get("v") is Number && (json.get("v") as Number).toDouble() == 1.0)
            val stage = json.get("stage") as? String ?: error("Invalid stage.")
            val document = json.get("document") as? String ?: error("Invalid document.")
            val match = json.get("accountMatch") as? Boolean ?: error("Invalid match.")
            val reason = json.get("reason") as? String ?: error("Invalid reason.")
            require(stage in setOf("authenticated", "account", "username", "password", "loading", "manual") && document == nonce && reason in reasons)
            QmplusAuthObservation(stage, document, match, reason)
        }.getOrNull()
    }
}

/** Main-thread state machine. One instance is one presentation, never reused after close;
 * document epochs retire callbacks on navigation/background. Tests drive this real pipeline. */
internal class QmplusAuthFlow(
    private val renderer: QmplusAuthRenderer,
    private val credentials: QmplusAuthCredentials,
    private val scheduler: QmplusAuthScheduler,
    private val savedOptIn: Boolean,
    private val savedRevision: Long,
    private val helper: String,
    private val reveal: () -> Unit,
    private val authenticated: () -> Unit,
    private val reportPhase: (String) -> Unit = {},
    private val quietConnection: Boolean = true,
    private val requestedTarget: String = QmplusPolicy.START_URL,
    private val featureEnabled: () -> Boolean = { true },
) {
    private val gate = QmplusLoginAutomationGate()
    private var url: String? = null
    private var nonce = ""
    private var accountHint: String? = null
    private var closed = false
    private var manual = false
    private var busy = false
    private var installed = false
    private var cancelPoll: (() -> Unit)? = null
    private var cancelDeadline: (() -> Unit)? = null
    private var lastSubmittedStage: String? = null
    private var postSubmitChecks = 0
    private var initialLayoutChecks = 0

    fun begin() {
        if (!checkFeature() || manual || cancelDeadline != null) return
        val weak = WeakReference(this)
        cancelDeadline = scheduler.schedule(25_000) { weak.get()?.manualRequired() }
    }
    fun pageStarted(value: String) {
        if (!checkFeature()) return
        cancelPoll?.invoke(); cancelPoll = null
        gate.beginDocument(); url = value; nonce = UUID.randomUUID().toString()
        accountHint = null; installed = false; busy = false; lastSubmittedStage = null; postSubmitChecks = 0; initialLayoutChecks = 0
        begin()
        if (!QmplusPolicy.isBusinessPage(value) && !QmplusLoginPagePolicy.canInspectAuthenticationPage(value) &&
            !(savedOptIn && (QmplusLoginPagePolicy.isSSOTransit(value) || QmplusLoginPagePolicy.isSSOEntry(value)))) manualRequired()
    }
    fun pageReady(value: String) {
        if (!checkFeature() || url != value || busy || renderer.currentURL != value || !renderer.active) return
        val document = gate.document
        if (QmplusPolicy.isBusinessPage(value)) { inspectSession(document, value); return }
        if (manual || !savedOptIn) { manualRequired(); return }
        if (QmplusLoginPagePolicy.isSSOTransit(value)) { schedulePoll(document, value); return }
        if (QmplusLoginPagePolicy.isSSOEntry(value)) {
            authorized(document, value) {
                if (gate.claimSSO(document, true)) { reportPhase("sso_navigation"); renderer.navigateToOfficialSSO() }
                else manualRequired()
            }
            return
        }
        if (!QmplusLoginPagePolicy.isMicrosoftPage(value)) { manualRequired(); return }
        if (!installed) install(document, value) else inspect(document, value)
    }
    fun manualRequired() {
        if (closed || manual) return
        manual = true; busy = false; accountHint = null
        gate.manualInteractionRequired(); cancelPoll?.invoke(); cancelPoll = null
        cancelDeadline?.invoke(); cancelDeadline = null
        reportPhase("manual"); reveal()
    }
    fun suspend() {
        if (closed) return
        gate.beginDocument(); manualRequired()
    }
    fun interruptedSync() {
        if (!closed) gate.interruptedSync()
    }
    fun close() {
        if (closed) return
        closed = true; gate.close(); accountHint = null; url = null; busy = false
        cancelPoll?.invoke(); cancelDeadline?.invoke(); cancelPoll = null; cancelDeadline = null
        credentials.close(); reportPhase("closed")
    }

    private fun checkedCurrent(document: Long, value: String): Boolean {
        if (!checkFeature() || !gate.accepts(document) || !renderer.active) return false
        if (url != value || renderer.currentURL != value) { manualRequired(); return false }
        return true
    }
    private fun checkFeature(): Boolean {
        if (closed) return false
        if (!runCatching(featureEnabled).getOrDefault(false)) { close(); return false }
        return true
    }
    private fun authorized(document: Long, value: String, action: () -> Unit) {
        if (!checkedCurrent(document, value) || manual || !savedOptIn) return
        busy = true
        val weak = WeakReference(this)
        credentials.authorized(savedRevision) authorizationReply@{ allowed ->
            val owner = weak.get() ?: return@authorizationReply
            if (!owner.checkedCurrent(document, value) || owner.manual) return@authorizationReply
            owner.busy = false
            if (allowed) action() else owner.manualRequired()
        }
    }
    private fun inspectSession(document: Long, value: String) {
        busy = true
        val weak = WeakReference(this)
        evaluate(document, value, guarded(value, QmplusLoginPagePolicy.authenticatedPageScript)) { result ->
            val owner = weak.get() ?: return@evaluate
            if (!owner.checkedCurrent(document, value)) return@evaluate
            owner.busy = false
            if (owner.gate.claimAutomaticSync(document, result == "true")) {
                owner.cancelDeadline?.invoke(); owner.cancelDeadline = null
                owner.cancelPoll?.invoke(); owner.cancelPoll = null
                if (owner.quietConnection) {
                    owner.reportPhase("authenticated"); owner.authenticated()
                } else {
                    // Explicit Open means a visible official page, not Sync and
                    // Finish. Fixed SSO may land on /my; restore the original
                    // validated course/module target without exporting secrets.
                    owner.manual = true; owner.accountHint = null; owner.gate.manualInteractionRequired()
                    if (value != owner.requestedTarget && QmplusPolicy.isBusinessPage(owner.requestedTarget))
                        owner.renderer.openBusinessPage(owner.requestedTarget)
                    owner.reportPhase("detail_visible"); owner.reveal()
                }
            } else if (result != "true") owner.manualRequired()
        }
    }
    private fun install(document: Long, value: String) {
        authorized(document, value) {
            if (helper.isBlank() || helper.length > 64 * 1024) { manualRequired(); return@authorized }
            busy = true; reportPhase("installing")
            val weak = WeakReference(this)
            // The canonical asset is inserted byte-for-byte, not rewritten or a page-provided function.
            evaluate(document, value, "if (window.top === window && location.href === ${JSONObject.quote(value)}) {\n$helper\n} else 'STALE_DOCUMENT';") { encoded ->
                val owner = weak.get() ?: return@evaluate
                if (!owner.checkedCurrent(document, value) || owner.manual) return@evaluate
                owner.busy = false
                if (!owner.gate.installed(document, QmplusAuthResultCodec.code(encoded).orEmpty())) { owner.manualRequired(); return@evaluate }
                owner.installed = true
                owner.loadAccount(document, value)
            }
        }
    }
    private fun loadAccount(document: Long, value: String) {
        busy = true
        val weak = WeakReference(this)
        credentials.account(savedRevision) { account ->
            val owner = weak.get() ?: return@account
            if (!owner.checkedCurrent(document, value) || owner.manual) return@account
            owner.busy = false
            if (account == null || account.length > 320 || !Regex("^[^\\s@]+@[^\\s@]+$").matches(account.trim())) {
                owner.manualRequired(); return@account
            }
            owner.accountHint = account
            owner.inspect(document, value)
        }
    }
    private fun inspect(document: Long, value: String) {
        authorized(document, value) {
            val account = accountHint ?: run { manualRequired(); return@authorized }
            busy = true; reportPhase("inspecting")
            val weak = WeakReference(this)
            evaluate(document, value, guarded(value, "WTSQmAuth.inspect(${JSONObject.quote(nonce)}, ${JSONObject.quote(account)})")) { encoded ->
                val owner = weak.get() ?: return@evaluate
                if (!owner.checkedCurrent(document, value) || owner.manual) return@evaluate
                owner.busy = false
                val state = QmplusAuthResultCodec.observation(encoded, owner.nonce)
                if (state == null) { owner.manualRequired(); return@evaluate }
                when {
                    state.stage == "loading" && state.reason == "LOADING" -> owner.schedulePoll(document, value)
                    state.stage == "manual" && state.reason in setOf("FORM_UNTRUSTED", "KNOWN_FORM_ABSENT") &&
                        !owner.gate.hasAttemptedCredentialSubmission() && owner.initialLayoutChecks++ < 8 ->
                        owner.schedulePoll(document, value)
                    state.reason == "ALREADY_ATTEMPTED" && owner.lastSubmittedStage != null && owner.postSubmitChecks++ < 12 ->
                        owner.schedulePoll(document, value)
                    state.stage == "manual" && state.reason == "ACCOUNT_CHOOSER" && owner.gate.accountSelected(document) &&
                        !owner.gate.passwordAttempted() && owner.lastSubmittedStage == "account" &&
                        owner.postSubmitChecks++ < 6 -> owner.schedulePoll(document, value)
                    state.stage == "manual" && state.reason in setOf("FORM_UNTRUSTED", "KNOWN_FORM_ABSENT") &&
                        owner.lastSubmittedStage == "account" && owner.postSubmitChecks++ < 6 -> owner.schedulePoll(document, value)
                    state.stage == "account" && state.reason == "READY" && state.accountMatch -> owner.submit(document, value, state)
                    state.stage == "username" && state.reason == "READY" -> owner.submit(document, value, state)
                    state.stage == "password" && state.reason == "READY" && state.accountMatch -> owner.submit(document, value, state)
                    else -> owner.manualRequired()
                }
            }
        }
    }
    private fun submit(document: Long, value: String, state: QmplusAuthObservation) {
        authorized(document, value) {
            if (!gate.claimFill(document, state.stage, true, state.accountMatch)) { manualRequired(); return@authorized }
            if (state.stage == "account") {
                busy = true
                val weak = WeakReference(this)
                credentials.account(savedRevision) { account ->
                    val owner = weak.get() ?: return@account
                    if (!owner.checkedCurrent(document, value) || owner.manual) return@account
                    owner.busy = false
                    if (account == null || !account.trim().equals(owner.accountHint?.trim(), ignoreCase = true)) {
                        owner.manualRequired(); return@account
                    }
                    owner.executeSubmit(document, value, state.stage, account, null)
                }
            } else if (state.stage == "username") executeSubmit(document, value, state.stage, accountHint.orEmpty(), null)
            else {
                busy = true
                val weak = WeakReference(this)
                credentials.password(savedRevision) { login ->
                    try {
                        val owner = weak.get() ?: return@password
                        if (!owner.checkedCurrent(document, value) || owner.manual) return@password
                        owner.busy = false
                        if (login == null || login.revision != owner.savedRevision ||
                            !login.account.trim().equals(owner.accountHint?.trim(), ignoreCase = true) ||
                            login.password.isEmpty() || login.password.size > 2048) { owner.manualRequired(); return@password }
                        owner.executeSubmit(document, value, state.stage, login.account, login.password)
                    } finally { login?.erase() }
                }
            }
        }
    }
    private fun executeSubmit(document: Long, value: String, stage: String, account: String, password: CharArray?) {
        if (!checkedCurrent(document, value) || manual) return
        val options = JSONObject().put("document", nonce).put("stage", stage).put("account", account)
        if (stage == "password") options.put("password", String(checkNotNull(password)))
        busy = true
        val weak = WeakReference(this)
        val arguments = options.toString().replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
        evaluate(document, value, guarded(value, "WTSQmAuth.fillAndSubmit($arguments)")) { encoded ->
            val owner = weak.get() ?: return@evaluate
            if (!owner.checkedCurrent(document, value) || owner.manual) return@evaluate
            owner.busy = false
            if (!owner.gate.submitted(document, stage, QmplusAuthResultCodec.code(encoded).orEmpty())) { owner.manualRequired(); return@evaluate }
            owner.lastSubmittedStage = stage; owner.postSubmitChecks = 0
            owner.reportPhase(when (stage) { "account" -> "account_selected"; "username" -> "username_submitted"; else -> "password_submitted" })
            owner.schedulePoll(document, value)
        }
    }
    private fun schedulePoll(document: Long, value: String) {
        cancelPoll?.invoke()
        val weak = WeakReference(this)
        cancelPoll = scheduler.schedule(350) {
            val owner = weak.get() ?: return@schedule
            owner.cancelPoll = null
            if (owner.checkedCurrent(document, value) && !owner.busy) owner.pageReady(value)
        }
    }
    private fun guarded(value: String, expression: String): String =
        "(() => { if (window.top !== window || location.href !== ${JSONObject.quote(value)}) return null; return ($expression); })()"
    private fun evaluate(document: Long, value: String, script: String, completion: (String) -> Unit) {
        if (!checkedCurrent(document, value)) return
        try { renderer.evaluate(script, completion) } catch (_: Exception) { manualRequired() }
    }
}
