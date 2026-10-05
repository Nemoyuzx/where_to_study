#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import WhereToStudyMac

@MainActor
final class QMplusToolbarRenderingTests: XCTestCase {
    func testOnlyReloadRemainsVisibleInBothLanguages() async throws {
        for language in [AppLanguage.simplifiedChinese, .english] {
                let actions = QMplusToolbarActionDescriptor.actions(language: language)
                XCTAssertEqual(actions.map(\.id), ["qmplus.connection.reload"])
                XCTAssertEqual(actions.map(\.label), [AppLocalization.string("打开 QMplus 官方登录页", language: language)])
                XCTAssertEqual(actions.map(\.enabled), [true])
                XCTAssertEqual(actions.map(\.image), [String?.some("arrow.clockwise")])
                let content = QMplusConnectionToolbarActions(language: language, reload: {})
                let host = NSHostingView(rootView: content.padding(12))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 80),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                defer { window.contentView = nil; window.close() }
                for _ in 0..<40 {
                    host.layoutSubtreeIfNeeded()
                    if host.fittingSize.width > 0, host.fittingSize.height > 0 { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                let fitted = host.fittingSize
                XCTAssertGreaterThan(fitted.width, 0)
                XCTAssertGreaterThan(fitted.height, 0)
                XCTAssertLessThanOrEqual(fitted.width, host.bounds.width + 1)
                XCTAssertLessThanOrEqual(fitted.height, host.bounds.height + 1)
        }
    }

}
#endif
