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
    private var attemptedContinue = false
    private var attemptedCredentials = false
    private var acknowledgedIdentity = false
    private var requiresManualInteraction = false
    private var installedDocument: Long? = null
    private var submittedUsernameDocument: Long? = null
    private var claimedUsernameDocument: Long? = null
    private var claimedContinueDocument: Long? = null
    private var selectedAccountDocument: Long? = null
    private var claimedAccountDocument: Long? = null
    private var attemptedSSO = false
    private var attemptedLoginEntry = false
    private var attemptedDashboard = false

    fun beginDocument(): Long {
        document++; installedDocument = null; submittedUsernameDocument = null; selectedAccountDocument = null; claimedAccountDocument = null
        claimedUsernameDocument = null; claimedContinueDocument = null
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
        if (!savedOptIn || !accepts(expectedDocument) || requiresManualInteraction || attemptedSSO || hasAttemptedCredentialSubmission()) return false
        attemptedSSO = true; return true
    }
    fun claimLoginEntry(expectedDocument: Long, savedOptIn: Boolean): Boolean {
        if (!savedOptIn || !accepts(expectedDocument) || requiresManualInteraction || attemptedLoginEntry ||
            attemptedSSO || hasAttemptedCredentialSubmission()) return false
        attemptedLoginEntry = true; return true
    }
    fun claimDashboard(expectedDocument: Long): Boolean {
        if (!accepts(expectedDocument) || attemptedDashboard) return false
        attemptedDashboard = true; return true
    }
    fun claimFill(expectedDocument: Long, stage: String, savedOptIn: Boolean, accountMatch: Boolean = false): Boolean {
        if (!savedOptIn || !accepts(expectedDocument) || requiresManualInteraction || installedDocument != expectedDocument) return false
        return when (stage) {
            "account" -> if (attemptedAccount || attemptedUsername || attemptedPassword || attemptedContinue || !accountMatch) false
                else { attemptedAccount = true; attemptedCredentials = true; claimedAccountDocument = expectedDocument; true }
            "username" -> if (attemptedUsername || attemptedPassword || attemptedContinue) false
                else { attemptedUsername = true; attemptedCredentials = true; claimedUsernameDocument = expectedDocument; true }
            "password" -> if (attemptedPassword || attemptedContinue || !accountMatch || !identityAcknowledged(expectedDocument)) false
                else { attemptedPassword = true; true }
            "continue" -> if (attemptedContinue || !accountMatch || !identityAcknowledged(expectedDocument)) false
                else { attemptedContinue = true; claimedContinueDocument = expectedDocument; true }
            else -> false
        }
    }
    fun submitted(expectedDocument: Long, stage: String, result: String): Boolean {
        if (!accepts(expectedDocument) || requiresManualInteraction) return false
        if (stage == "account" && attemptedAccount && claimedAccountDocument == expectedDocument && result == "ACCOUNT_SELECTED") {
            selectedAccountDocument = expectedDocument; acknowledgedIdentity = true; return true
        }
        if (stage == "username" && attemptedUsername && claimedUsernameDocument == expectedDocument && result == "USERNAME_SUBMITTED") {
            submittedUsernameDocument = expectedDocument; acknowledgedIdentity = true; return true
        }
        if (stage == "continue" && attemptedContinue && claimedContinueDocument == expectedDocument && result == "CONTINUE_SUBMITTED") return true
        return stage == "password" && attemptedPassword && result == "PASSWORD_SUBMITTED"
    }
    fun usernameSubmitted(expectedDocument: Long): Boolean = accepts(expectedDocument) && submittedUsernameDocument == expectedDocument
    fun accountSelected(expectedDocument: Long): Boolean = accepts(expectedDocument) && selectedAccountDocument == expectedDocument
    // The connection and credential revision stay fixed, while the helper must
    // still verify the exact visible account again in each real document.
    fun identityAcknowledged(expectedDocument: Long): Boolean = accepts(expectedDocument) && acknowledgedIdentity
    fun acknowledgeCurrentAccount(expectedDocument: Long, accountMatch: Boolean): Boolean {
        if (!accepts(expectedDocument) || requiresManualInteraction || installedDocument != expectedDocument ||
            attemptedPassword || attemptedContinue || !accountMatch) return false
        acknowledgedIdentity = true; return true
    }
    fun passwordAttempted(): Boolean = attemptedPassword
    fun hasAttemptedCredentialSubmission(): Boolean = attemptedCredentials || attemptedPassword || attemptedContinue
    fun manualInteractionRequired() { requiresManualInteraction = true }
    fun close() { active = false; document++ }
}

internal object QmplusLoginPagePolicy {
    // This tenant was observed on the official QMplus SAML redirect. Other
    // tenants/origins/paths remain visible and user-operated, not guessed.
    private const val QM_TENANT = "569df091-b013-40e3-86ee-bd9cb9e25814"
    const val SSO_START_URL = "https://qmplus.qmul.ac.uk/auth/saml2/login.php"
    const val LOGIN_ENTRY_URL = "https://qmplus.qmul.ac.uk/login/index.php"
    fun isSSOEntry(value: String): Boolean = trustedURI(value)?.let {
        it.host.equals("qmplus.qmul.ac.uk", true) &&
            ((it.rawPath == "/login/index.php" && it.rawQuery == null) ||
                (it.rawPath in setOf("/my", "/my/") && it.rawQuery == null) ||
                (it.rawPath == "/" && it.rawQuery in listOf(null, "redirect=0")))
    } == true
    fun isSSOTransit(value: String): Boolean = trustedURI(value)?.let {
        it.host.equals("qmplus.qmul.ac.uk", true) && it.rawPath == "/auth/saml2/login.php" && it.rawQuery == null
    } == true
    fun isOfficialQMPage(value: String): Boolean = runCatching { URI(value) }.getOrNull()?.let {
        it.scheme.equals("https", true) && it.host.equals("qmplus.qmul.ac.uk", true) && it.rawUserInfo == null && it.port in listOf(-1, 443)
    } == true
    private fun trustedURI(value: String): URI? = runCatching { URI(value) }.getOrNull()?.takeIf {
        it.scheme.equals("https", true) && it.rawUserInfo == null && it.port in listOf(-1, 443) && it.rawFragment == null
    }
    fun isMicrosoftPage(value: String): Boolean = trustedURI(value)?.let {
        it.host.equals("login.microsoftonline.com", true) && it.rawPath in setOf("/$QM_TENANT/saml2", "/$QM_TENANT/login", "/kmsi")
    } == true
    fun isVerificationPage(value: String): Boolean = trustedURI(value)?.let {
        it.host.equals("login.microsoftonline.com", true) && it.rawPath.equals("/common/deviceauthtls/reprocess", true)
    } == true
    fun isMicrosoftTransitPage(value: String): Boolean = runCatching { URI(value) }.getOrNull()?.let {
        it.scheme.equals("https", true) && (it.host.equals("login.microsoftonline.com", true) ||
            it.host.equals("device.login.microsoftonline.com", true)) &&
            it.rawUserInfo == null && it.port in listOf(-1, 443) &&
            !isMicrosoftPage(value) && !isVerificationPage(value)
    } == true
    fun canInspectAuthenticationPage(value: String): Boolean = runCatching { URI(value) }.getOrNull()?.let {
        it.scheme.equals("https", true) && it.rawUserInfo == null && it.port in listOf(-1, 443) &&
            it.rawFragment == null && when {
                it.host.equals("qmplus.qmul.ac.uk", true) -> isSSOEntry(value)
                it.host.equals("login.microsoftonline.com", true) -> isMicrosoftPage(value) || isVerificationPage(value)
                else -> false
            }
    } == true

    const val UNKNOWN_PAGE_SCRIPT = "(()=>'unknown')()"
    fun authenticatedPageScript(pageScript: String): String =
        "(() => { const kind = $pageScript; return kind === 'authenticated'; })()"
    fun approvedSSOEntryScript(pageScript: String): String = """
        (() => { const kind = $pageScript; if (kind !== 'guest') return false;
          const targets = new Set(Array.from(document.querySelectorAll('a[href]')).flatMap(link => {
            try { const u = new URL(link.getAttribute('href'), location.href);
              return u.href === '$SSO_START_URL' && u.origin === 'https://qmplus.qmul.ac.uk' &&
                !u.username && !u.password && !u.search && !u.hash ? [u.href] : [];
            } catch { return []; }
          })); return targets.size === 1;
        })()
    """.trimIndent()
    fun approvedGuestEntryScript(pageScript: String): String = """
        (() => { const kind = $pageScript; if (kind !== 'guest') return 'none';
          const targets = new Set(Array.from(document.querySelectorAll('a[href]')).flatMap(link => {
            try { const u = new URL(link.getAttribute('href'), location.href);
              return u.origin === 'https://qmplus.qmul.ac.uk' && !u.username && !u.password && !u.search && !u.hash &&
                [ '$SSO_START_URL', '$LOGIN_ENTRY_URL' ].includes(u.href) ? [u.href] : [];
            } catch { return []; }
          })); return targets.has('$SSO_START_URL') ? 'saml' : targets.has('$LOGIN_ENTRY_URL') ? 'login' : 'none';
        })()
    """.trimIndent()
}

internal enum class QmplusPageKind {
    AUTHENTICATED, GUEST, ERROR, UNKNOWN, LOADING;
    companion object {
        fun decode(encoded: String): QmplusPageKind = runCatching {
            require(encoded.length <= 64)
            when (JSONArray("[$encoded]").get(0) as? String) {
                "authenticated" -> AUTHENTICATED; "guest" -> GUEST; "error" -> ERROR; "loading" -> LOADING; else -> UNKNOWN
            }
        }.getOrDefault(UNKNOWN)
    }
}

internal interface QmplusAuthRenderer {
    val currentURL: String?
    val active: Boolean
    fun evaluate(script: String, completion: (String) -> Unit)
    fun navigateToOfficialSSO()
    fun navigateToOfficialLogin() {}
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
    fun guestEntry(encoded: String): String? = encoded.takeIf { it.length <= 32 }?.let {
        runCatching { JSONArray("[$it]").get(0) as? String }.getOrNull()
    }?.takeIf { it in setOf("saml", "login", "none") }
    private val reasons = setOf("READY", "AUTHENTICATED", "LOADING", "INVALID_NONCE", "STALE_DOCUMENT", "UNTRUSTED_CONTEXT",
        "UNSUPPORTED_PAGE", "ACCOUNT_CHOOSER", "ACCOUNT_HINT_REQUIRED", "FORM_UNTRUSTED", "INTERFERENCE", "KNOWN_FORM_ABSENT", "ACCOUNT_MISMATCH",
        "USERNAME_NOT_SUBMITTED", "ALREADY_ATTEMPTED", "CAPTCHA_REQUIRED", "MFA_REQUIRED", "CURRENT_ACCOUNT_VERIFIED")
    fun code(encoded: String): String? = encoded.takeIf { it.length <= 96 }?.let {
        runCatching { JSONArray("[$it]").get(0) as? String }.getOrNull()
    }?.takeIf { it in setOf("AUTH_INSTALLED", "AUTH_CONFLICT", "ACCOUNT_SELECTED", "USERNAME_SUBMITTED", "PASSWORD_SUBMITTED", "CONTINUE_SUBMITTED", "MANUAL_REQUIRED", "REJECTED", "STALE_DOCUMENT") }
    fun observation(encoded: String, nonce: String): QmplusAuthObservation? = encoded.takeIf { it.length <= 1024 }?.let {
        runCatching {
            val json = JSONObject(it)
            require(json.keys().asSequence().toSet() == setOf("v", "stage", "document", "accountMatch", "reason"))
            require(json.get("v") is Number && (json.get("v") as Number).toDouble() == 1.0)
            val stage = json.get("stage") as? String ?: error("Invalid stage.")
            val document = json.get("document") as? String ?: error("Invalid document.")
            val match = json.get("accountMatch") as? Boolean ?: error("Invalid match.")
            val reason = json.get("reason") as? String ?: error("Invalid reason.")
            require(stage in setOf("authenticated", "account", "username", "password", "continue", "loading", "manual", "challenge") && document == nonce && reason in reasons)
            require((stage == "challenge") == (reason in setOf("CAPTCHA_REQUIRED", "MFA_REQUIRED")))
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
    private val pageScript: String = QmplusLoginPagePolicy.UNKNOWN_PAGE_SCRIPT,
    private val pageObserved: (QmplusPageKind) -> Unit = {},
    private val manualContinuation: () -> Unit = {},
    private val verificationRequired: () -> Unit = reveal,
    private val verificationFinished: () -> Unit = {},
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
    private var waitingForVerification = false

    fun begin() {
        if (!checkFeature() || manual || waitingForVerification || cancelDeadline != null) return
        val weak = WeakReference(this)
        cancelDeadline = scheduler.schedule(25_000) { weak.get()?.manualRequired() }
    }
    fun pageStarted(value: String) {
        if (!checkFeature()) return
        if (waitingForVerification) { waitingForVerification = false; verificationFinished() }
        cancelPoll?.invoke(); cancelPoll = null
        gate.beginDocument(); url = value; nonce = UUID.randomUUID().toString()
        accountHint = null; installed = false; busy = false; lastSubmittedStage = null; postSubmitChecks = 0; initialLayoutChecks = 0
        begin()
        if (!QmplusLoginPagePolicy.isOfficialQMPage(value) && !QmplusLoginPagePolicy.canInspectAuthenticationPage(value) &&
            !QmplusLoginPagePolicy.isMicrosoftTransitPage(value) &&
            !(savedOptIn && (QmplusLoginPagePolicy.isSSOTransit(value) || QmplusLoginPagePolicy.isSSOEntry(value)))) manualRequired()
    }
    fun pageReady(value: String) {
        if (!checkFeature() || url != value || busy || renderer.currentURL != value || !renderer.active) return
        val document = gate.document
        if (QmplusLoginPagePolicy.isOfficialQMPage(value)) { inspectSession(document, value); return }
        if (!manual && QmplusLoginPagePolicy.isVerificationPage(value)) {
            if (!installed) installVerification(document, value) else inspectVerification(document, value)
            return
        }
        if (!manual && QmplusLoginPagePolicy.isMicrosoftTransitPage(value)) {
            // The original connection deadline keeps running across redirects.
            // Only navigation is observed here: no helper, credential read, or action.
            schedulePoll(document, value); return
        }
        if (manual || !savedOptIn) { manualRequired(); return }
        if (!QmplusLoginPagePolicy.isMicrosoftPage(value)) { manualRequired(); return }
        if (!installed) install(document, value) else inspect(document, value)
    }
    fun manualRequired(challenge: Boolean = false) {
        if (closed || manual) return
        if (challenge) {
            cancelDeadline?.invoke(); cancelDeadline = null
            if (!waitingForVerification) { waitingForVerification = true; reportPhase("challenge"); verificationRequired() }
            return
        }
        manual = true; busy = false; accountHint = null; waitingForVerification = false
        gate.manualInteractionRequired(); cancelPoll?.invoke(); cancelPoll = null
        cancelDeadline?.invoke(); cancelDeadline = null
        reportPhase("manual")
        if (!savedOptIn && !QmplusLoginPagePolicy.isVerificationPage(url.orEmpty()) &&
            !QmplusLoginPagePolicy.isMicrosoftTransitPage(url.orEmpty())) reveal() else manualContinuation()
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
        evaluate(document, value, guarded(value, pageScript)) { result ->
            val owner = weak.get() ?: return@evaluate
            if (!owner.checkedCurrent(document, value)) return@evaluate
            owner.busy = false
            val kind = QmplusPageKind.decode(result)
            owner.pageObserved(kind)
            if (kind == QmplusPageKind.ERROR) { owner.reportPhase("QM_ERROR_PAGE"); owner.manualRequired(); return@evaluate }
            if (kind == QmplusPageKind.LOADING || (QmplusLoginPagePolicy.isSSOTransit(value) &&
                    kind != QmplusPageKind.AUTHENTICATED && !owner.manual && owner.savedOptIn)) {
                owner.schedulePoll(document, value); return@evaluate
            }
            if (kind == QmplusPageKind.GUEST && QmplusLoginPagePolicy.isSSOEntry(value) && !owner.manual && owner.savedOptIn) {
                owner.authorized(document, value) {
                    owner.busy = true
                    owner.evaluate(document, value, owner.guarded(value, QmplusLoginPagePolicy.approvedGuestEntryScript(owner.pageScript))) approvalReply@{ approved ->
                        if (!owner.checkedCurrent(document, value) || owner.manual) return@approvalReply
                        owner.busy = false
                        val entry = QmplusAuthResultCodec.guestEntry(approved)
                        if (entry !in setOf("saml", "login")) { owner.manualRequired(); return@approvalReply }
                        owner.authorized(document, value) {
                            if (entry == "saml" && owner.gate.claimSSO(document, true)) {
                                owner.reportPhase("sso_navigation"); owner.renderer.navigateToOfficialSSO()
                            } else if (entry == "login" && value != QmplusLoginPagePolicy.LOGIN_ENTRY_URL && owner.gate.claimLoginEntry(document, true)) {
                                owner.reportPhase("login_entry_navigation"); owner.renderer.navigateToOfficialLogin()
                            } else owner.manualRequired()
                        }
                    }
                }
                return@evaluate
            }
            if (kind == QmplusPageKind.AUTHENTICATED && !QmplusPolicy.isBusinessPage(value)) {
                if (QmplusLoginPagePolicy.isSSOEntry(value) && owner.gate.claimDashboard(document))
                    owner.renderer.openBusinessPage(QmplusPolicy.START_URL)
                else owner.manualRequired()
                return@evaluate
            }
            if (owner.gate.claimAutomaticSync(document, kind == QmplusPageKind.AUTHENTICATED)) {
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
            } else if (kind != QmplusPageKind.AUTHENTICATED) owner.manualRequired()
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

    private fun installVerification(document: Long, value: String) {
        if (!checkedCurrent(document, value) || !QmplusLoginPagePolicy.isVerificationPage(value)) return
        if (helper.isBlank() || helper.length > 64 * 1024) { manualRequired(); return }
        busy = true
        evaluate(document, value, "if (window.top === window && location.href === ${JSONObject.quote(value)}) {\n$helper\n} else 'STALE_DOCUMENT';") { encoded ->
            if (!checkedCurrent(document, value) || manual) return@evaluate
            busy = false
            if (!gate.installed(document, QmplusAuthResultCodec.code(encoded).orEmpty())) { manualRequired(); return@evaluate }
            installed = true
            inspectVerification(document, value)
        }
    }

    private fun inspectVerification(document: Long, value: String) {
        if (!checkedCurrent(document, value) || manual || !QmplusLoginPagePolicy.isVerificationPage(value)) return
        busy = true
        evaluate(document, value, guarded(value, "WTSQmAuth.inspect(${JSONObject.quote(nonce)}, '')")) { encoded ->
            if (!checkedCurrent(document, value) || manual) return@evaluate
            busy = false
            val state = QmplusAuthResultCodec.observation(encoded, nonce)
            when {
                state?.stage == "challenge" -> {
                    manualRequired(challenge = true); schedulePoll(document, value, 750)
                }
                state?.stage == "loading" && state.reason == "LOADING" -> {
                    if (waitingForVerification) { waitingForVerification = false; verificationFinished(); begin() }
                    schedulePoll(document, value)
                }
                else -> manualRequired()
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
            evaluate(document, value, guarded(value, "WTSQmAuth.inspect(${JSONObject.quote(nonce)}, ${JSONObject.quote(account)}, ${gate.identityAcknowledged(document)})")) { encoded ->
                val owner = weak.get() ?: return@evaluate
                if (!owner.checkedCurrent(document, value) || owner.manual) return@evaluate
                owner.busy = false
                val state = QmplusAuthResultCodec.observation(encoded, owner.nonce)
                if (state == null) { owner.manualRequired(); return@evaluate }
                if (state.stage != "challenge" && owner.waitingForVerification) {
                    owner.waitingForVerification = false; owner.verificationFinished(); owner.begin()
                }
                when {
                    state.stage == "challenge" -> {
                        owner.manualRequired(challenge = true); owner.schedulePoll(document, value, 750)
                    }
                    state.stage == "loading" && state.reason == "LOADING" -> owner.schedulePoll(document, value)
                    state.stage == "manual" && state.reason == "ACCOUNT_CHOOSER" &&
                        !owner.gate.hasAttemptedCredentialSubmission() && owner.initialLayoutChecks++ < 8 ->
                        owner.schedulePoll(document, value, if (owner.initialLayoutChecks == 1) 250 else 500)
                    state.stage == "manual" && state.reason in setOf("FORM_UNTRUSTED", "KNOWN_FORM_ABSENT") &&
                        owner.lastSubmittedStage == null && owner.initialLayoutChecks++ < 8 ->
                        owner.schedulePoll(document, value)
                    state.stage == "manual" && owner.lastSubmittedStage in setOf("password", "continue") &&
                        state.reason in setOf("INTERFERENCE", "FORM_UNTRUSTED", "KNOWN_FORM_ABSENT") &&
                        owner.postSubmitChecks++ < 12 -> owner.schedulePoll(document, value)
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
                    state.stage == "password" && state.reason == "CURRENT_ACCOUNT_VERIFIED" && state.accountMatch &&
                        owner.gate.acknowledgeCurrentAccount(document, true) -> owner.submit(document, value, state)
                    state.stage == "continue" && state.reason == "READY" && state.accountMatch -> owner.submit(document, value, state)
                    state.stage == "continue" && state.reason == "CURRENT_ACCOUNT_VERIFIED" && state.accountMatch &&
                        owner.gate.acknowledgeCurrentAccount(document, true) -> owner.submit(document, value, state)
                    else -> owner.manualRequired()
                }
            }
        }
    }
    private fun submit(document: Long, value: String, state: QmplusAuthObservation) {
        if (!QmplusLoginPagePolicy.isMicrosoftPage(value)) { manualRequired(); return }
        authorized(document, value) {
            if (runCatching { URI(value).rawPath == "/kmsi" }.getOrDefault(false) && state.stage != "continue") {
                manualRequired(); return@authorized
            }
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
            } else if (state.stage in setOf("username", "continue")) executeSubmit(document, value, state.stage, accountHint.orEmpty(), null)
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
        if (stage in setOf("password", "continue")) options.put("identityAcknowledged", gate.identityAcknowledged(document))
        busy = true
        val weak = WeakReference(this)
        val arguments = options.toString().replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
        evaluate(document, value, guarded(value, "WTSQmAuth.fillAndSubmit($arguments)")) { encoded ->
            val owner = weak.get() ?: return@evaluate
            if (!owner.checkedCurrent(document, value) || owner.manual) return@evaluate
            owner.busy = false
            if (!owner.gate.submitted(document, stage, QmplusAuthResultCodec.code(encoded).orEmpty())) { owner.manualRequired(); return@evaluate }
            owner.lastSubmittedStage = stage; owner.postSubmitChecks = 0
            owner.reportPhase(when (stage) { "account" -> "account_selected"; "username" -> "username_submitted";
                "continue" -> "continue_submitted"; else -> "password_submitted" })
            owner.schedulePoll(document, value)
        }
    }
    private fun schedulePoll(document: Long, value: String, delayMillis: Long = 350) {
        cancelPoll?.invoke()
        val weak = WeakReference(this)
        cancelPoll = scheduler.schedule(delayMillis) {
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
