import XCTest
import WebKit
#if os(iOS)
import UIKit
@testable import WhereToStudyiOS
#else
@testable import WhereToStudyMac
#endif

// Real WebKit DOM, synthetic credentials and inline HTML only. No official
// login, network request, persistent profile or production secret is used.
@MainActor
final class QMplusSilentWebKitTests: XCTestCase {
    private let account = "synthetic@example.invalid"
    private let password = "synthetic-only"
    private let nonce = "silentQA123"

    func testOwnedPlaceholderAutofillDoesNotFocusFieldsOrOpenKeyboard() async throws {
        let browser = makeBrowser()
        #if os(iOS)
        let probe = KeyboardProbe()
        let observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { probe.count += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 760))
        let controller = UIViewController()
        window.rootViewController = controller
        let container = QMplusWebViewContainer(frame: window.bounds)
        controller.view.addSubview(container)
        container.configure(browser, lease: .init(presentation: 1, role: .quiet, browser: ObjectIdentifier(browser))) { true }
        window.makeKeyAndVisible()
        defer { container.detachIfOwned(); window.isHidden = true }
        #endif
        try await load("""
            <form id="i0281" action="https://login.microsoftonline.com/\(QMplusAutofillPolicy.tenant)/login">
              <div class="placeholderContainer"><input id="i0116" name="loginfmt" type="email">
                <div class="placeholderInnerContainer"><div class="placeholder" aria-hidden="true">Synthetic hint</div></div>
              </div>
              <input id="idSIButton9" type="submit" value="Synthetic Next">
            </form>
            <script>
            window.syntheticFocusCount = 0;
            document.addEventListener('focusin', () => { window.syntheticFocusCount++; });
            document.querySelector('form').addEventListener('submit', event => {
              event.preventDefault();
              document.querySelector('.placeholderContainer').remove();
              const identity = document.createElement('div'); identity.id = 'displayName';
              identity.textContent = 'synthetic@example.invalid'; document.querySelector('form').prepend(identity);
              const field = document.createElement('input'); field.id='i0118'; field.name='passwd'; field.type='password';
              document.querySelector('form').insertBefore(field, document.querySelector('#idSIButton9'));
            }, {once:true});
            document.querySelector('form').addEventListener('submit', event => { event.preventDefault(); });
            </script>
            """, in: browser)
        let evaluator = QMplusWebKitAutofillEvaluator(browser: browser)
        let installed = await install(evaluator)
        XCTAssertEqual(installed, .installed)
        let usernameState = await inspect(evaluator)
        XCTAssertEqual(usernameState?.stage, .username)
        let usernameACK = await submit(evaluator, .username(document: nonce, account: account))
        XCTAssertEqual(usernameACK, .usernameSubmitted)
        let passwordState = await inspect(evaluator)
        XCTAssertEqual(passwordState?.stage, .password)
        XCTAssertEqual(passwordState?.reason, .ready)
        let passwordACK = await submit(evaluator, .password(document: nonce, account: account, password: password,
                                                          identityAcknowledged: true))
        XCTAssertEqual(passwordACK, .passwordSubmitted)
        let result = try await metadata(browser, "return JSON.stringify({focus:window.syntheticFocusCount,active:document.activeElement?.tagName});")
        XCTAssertTrue(result.contains("\"focus\":0"), result)
        XCTAssertFalse(result.contains("\"active\":\"INPUT\""), result)
        #if os(iOS)
        XCTAssertEqual(probe.count, 0, "A background fill must not request the native keyboard")
        #endif
    }

    func testLocalizedMethodPickerIsAReadOnlyMFAChallengeInActualWebKit() async throws {
        let browser = makeBrowser()
        try await load("""
            <div id="idDiv_SAOTCS_Title">选择验证方式<span> — synthetic description</span></div>
            <input type="tel" id="synthetic-phone"><button id="synthetic-sms">Synthetic SMS</button>
            <button id="synthetic-call">Synthetic Call</button>
            <script>window.syntheticClicks=0;document.addEventListener('click',()=>window.syntheticClicks++);</script>
            """, in: browser)
        let evaluator = QMplusWebKitAutofillEvaluator(browser: browser)
        let installed = await install(evaluator)
        XCTAssertEqual(installed, .installed)
        let state = await inspect(evaluator)
        XCTAssertEqual(state?.stage, .challenge)
        XCTAssertEqual(state?.reason, .mfaRequired)
        let rejected = await submit(evaluator, .username(document: nonce, account: account))
        XCTAssertEqual(rejected, .manual)
        let result = try await metadata(browser, "return JSON.stringify({clicks:window.syntheticClicks,phoneEmpty:document.querySelector('#synthetic-phone').value===''});")
        XCTAssertTrue(result.contains("\"clicks\":0"), result)
        XCTAssertTrue(result.contains("\"phoneEmpty\":true"), result)
    }

    private func makeBrowser() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 760), configuration: configuration)
    }
    private func load(_ body: String, in browser: WKWebView) async throws {
        let completion = expectation(description: "Synthetic inline page loads")
        let delegate = InlineNavigation(completion)
        browser.navigationDelegate = delegate
        let html = """
            <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{margin:20px}input{display:block;width:260px;height:40px;margin:12px 0}
            input[type=submit]{width:120px}.placeholderContainer{position:relative;width:270px;height:54px}
            .placeholderInnerContainer{position:absolute;left:0;top:12px;width:264px;height:44px}
            .placeholder{width:100%;height:100%;pointer-events:auto}#displayName{width:270px;height:32px}
            #idDiv_SAOTCS_Title{width:320px;min-height:40px}</style>\(body)
            """
        browser.loadHTMLString(html, baseURL: URL(string: "https://login.microsoftonline.com/\(QMplusAutofillPolicy.tenant)/saml2"))
        await fulfillment(of: [completion], timeout: 10)
        XCTAssertNil(delegate.failure)
        browser.navigationDelegate = nil
    }
    private func source() throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "qmplus-auth", withExtension: "js") ??
                                Bundle.main.url(forResource: "qmplus-auth", withExtension: "js"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func install(_ evaluator: QMplusWebKitAutofillEvaluator) async -> QMplusAuthInstallResult {
        guard let source = try? source() else { return .unavailable }
        return await withCheckedContinuation { continuation in evaluator.install(source) { continuation.resume(returning: $0) } }
    }
    private func inspect(_ evaluator: QMplusWebKitAutofillEvaluator) async -> QMplusAuthInspection? {
        await withCheckedContinuation { continuation in
            evaluator.inspect(nonce: nonce, accountHint: account) { continuation.resume(returning: $0) }
        }
    }
    private func submit(_ evaluator: QMplusWebKitAutofillEvaluator, _ value: QMplusAuthSubmission) async -> QMplusAuthSubmissionResult? {
        await withCheckedContinuation { continuation in evaluator.submit(value) { continuation.resume(returning: $0) } }
    }
    private func metadata(_ browser: WKWebView, _ function: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            browser.callAsyncJavaScript(function, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value as? String ?? "")
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
private final class InlineNavigation: NSObject, WKNavigationDelegate {
    let completion: XCTestExpectation
    var failure: Error?
    init(_ completion: XCTestExpectation) { self.completion = completion }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { completion.fulfill() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failure = error; completion.fulfill()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failure = error; completion.fulfill()
    }
}
#if os(iOS)
@MainActor private final class KeyboardProbe { var count = 0 }
#endif
