//
//  SwiftTerminalUIKitHostViewTests.swift
//  SwiftTerminal
//
//  Created by GitSwift on 2026/10/01.
//

#if canImport(UIKit)
import Testing
import UIKit
import WebKit
@testable import SwiftTerminal

/// Exercises the iOS host view's part in keyboard focus.
///
/// The test runner has no scene to make a window key in, so these tests cover what does not need
/// a key window: the host's focus and first-responder capabilities, and what a hand-off leaves
/// behind. Delivery of hardware key presses is verified on a device or simulator with a hardware
/// keyboard, as the keyboard focus guide describes.
@MainActor
@Suite("SwiftTerminalUIKitHostView keyboard focus", .serialized)
struct SwiftTerminalUIKitHostViewTests {
    @Test
    func hostIsFocusableWithoutAFocusEffect() {
        let host = SwiftTerminalUIKitHostView(webView: makeWebView())

        #expect(host.canBecomeFocused)
        #expect(host.focusEffect == nil)
    }

    @Test
    func hostDeclinesTheFirstResponderOutsideAHandOff() {
        let host = SwiftTerminalUIKitHostView(webView: makeWebView())
        let window = makeWindow(hosting: host)

        #expect(!host.canBecomeFirstResponder)
        #expect(!host.becomeFirstResponder())
        #expect(!host.isFirstResponder)
        #expect(host.window === window)
    }

    @Test
    func hostReportsItselfAsTheKeyboardFocusEnvironment() {
        let host = SwiftTerminalUIKitHostView(webView: makeWebView())

        #expect(host.keyboardFocusHostView === host)
    }

    @Test
    func keyboardFocusRequestWithoutAWindowReportsFailure() {
        let webView = makeWebView()
        let host = SwiftTerminalUIKitHostView(webView: webView)

        #expect(!host.takeKeyboardFocus())
        #expect(!host.holdsKeyboardFocus)
        #expect(!host.isFirstResponder)
        #expect(!host.canBecomeFirstResponder)
    }

    @Test
    func handOffNeverLeavesTheFirstResponderOnTheHost() {
        let host = SwiftTerminalUIKitHostView(webView: makeWebView())
        let window = makeWindow(hosting: host)

        let took = host.takeKeyboardFocus()

        #expect(!host.isFirstResponder)
        #expect(!host.canBecomeFirstResponder)
        #expect(took == host.holdsKeyboardFocus)
        #expect(host.window === window)
    }

    @Test
    func keyboardFocusIsNotHeldBeforeTheWebContentIsFocused() {
        let host = SwiftTerminalUIKitHostView(webView: makeWebView())
        let window = makeWindow(hosting: host)

        #expect(!host.holdsKeyboardFocus)
        #expect(!host.isFocusedItemOutsideTerminal)
        #expect(host.window === window)
    }

    @Test
    func sessionExposesTheAttachedHostView() {
        let session = SwiftTerminalSession()
        let host = SwiftTerminalUIKitHostView(webView: makeWebView())

        #expect(session.keyboardFocusHostView == nil)
        #expect(!session.holdsKeyboardFocus)
        #expect(!session.takeKeyboardFocus())

        session.attachKeyboardFocusController(host)

        #expect(session.keyboardFocusHostView === host)
        #expect(!session.holdsKeyboardFocus)
    }
}

@MainActor
private func makeWebView() -> WKWebView {
    WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
}

/// Returns a window that hosts `view`, so the host has a window to hand the responder within.
@MainActor
private func makeWindow(hosting view: UIView) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
    view.frame = window.bounds
    window.addSubview(view)
    window.isHidden = false
    return window
}
#endif
