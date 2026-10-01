//
//  SwiftTerminalAppKitWebViewCopyTests.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/10/01.
//

#if canImport(AppKit)
import AppKit
import Testing
import WebKit
@testable import SwiftTerminal

/// Exercises how the macOS terminal web view routes the Edit menu's Copy through the session.
///
/// The web view never loads the runtime here, so nothing reaches the pasteboard; the tests check
/// the routing and the menu validation only.
@MainActor
@Suite("SwiftTerminalAppKitWebView copy", .serialized)
struct SwiftTerminalAppKitWebViewCopyTests {
    @Test
    func copyActionIsAnObjectiveCOverrideOfWebKitCopy() {
        let selector = #selector(NSText.copy(_:))

        #expect(WKWebView.instancesRespond(to: selector))
        #expect(
            class_getMethodImplementation(SwiftTerminalAppKitWebView.self, selector)
                != class_getMethodImplementation(WKWebView.self, selector)
        )
    }

    @Test
    func copyGoesThroughTheHandler() {
        let webView = SharedCopyTestWebView.shared
        var copyCount = 0
        webView.copyHandler = {
            copyCount += 1
            return true
        }
        defer {
            webView.copyHandler = nil
        }

        webView.copy(nil)

        #expect(copyCount == 1)
    }

    @Test
    func copyIsEnabledWhileTheTerminalHasSelectedText() {
        let webView = SharedCopyTestWebView.shared
        webView.hasTerminalSelection = { true }
        defer {
            webView.hasTerminalSelection = nil
        }

        #expect(webView.validateUserInterfaceItem(copyMenuItem()))
    }

    @Test
    func otherItemsAreLeftToWebKit() {
        let webView = SharedCopyTestWebView.shared
        webView.hasTerminalSelection = { true }
        defer {
            webView.hasTerminalSelection = nil
        }
        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")

        #expect(
            webView.validateUserInterfaceItem(cutItem)
                == WKWebView.instanceMethodValidation(of: cutItem, on: webView)
        )
    }

    @Test
    func coordinatorRoutesCopyThroughTheSession() async throws {
        let session = SwiftTerminalSession()
        let coordinator = SwiftTerminalCoordinator(session: session)
        let webView = try #require(coordinator.makeWebView() as? SwiftTerminalAppKitWebView)
        defer {
            coordinator.teardown()
        }

        #expect(webView.hasTerminalSelection?() == false)
        // The runtime has not loaded, so the session leaves Copy to WebKit.
        #expect(webView.copyHandler?() == false)

        session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .selectionChanged, text: "token"))

        #expect(webView.hasTerminalSelection?() == true)
    }

    private func copyMenuItem() -> NSMenuItem {
        NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    }
}

@MainActor
private enum SharedCopyTestWebView {
    static let shared = SwiftTerminalAppKitWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
}

private extension WKWebView {
    /// WebKit's own validation of `item`, bypassing the terminal web view's override.
    @MainActor
    static func instanceMethodValidation(of item: NSMenuItem, on webView: WKWebView) -> Bool {
        let selector = #selector(WKWebView.validateUserInterfaceItem(_:))
        let implementation = class_getMethodImplementation(WKWebView.self, selector)
        typealias Validation = @convention(c) (AnyObject, Selector, NSMenuItem) -> Bool
        return unsafeBitCast(implementation, to: Validation.self)(webView, selector, item)
    }
}
#endif
