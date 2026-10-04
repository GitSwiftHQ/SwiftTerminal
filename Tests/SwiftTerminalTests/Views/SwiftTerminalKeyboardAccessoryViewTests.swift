//
//  SwiftTerminalKeyboardAccessoryViewTests.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/10/04.
//

#if canImport(UIKit)
import Testing
import UIKit
import WebKit
@testable import SwiftTerminal

/// Exercises the fixed-height keyboard accessory and how the iOS web view installs it.
///
/// The test runner has no keyboard, so these tests cover what holds without one: an instance
/// keeps the height it was created with whatever happens to its content, and the web view hands
/// UIKit an instance measured for the content. Where UIKit places the accessory, and the swaps
/// that follow from it, are verified on a simulator against the keyboard's own frame, as the
/// configuration guide describes.
@MainActor
@Suite("SwiftTerminal keyboard accessory", .serialized)
struct SwiftTerminalKeyboardAccessoryViewTests {
    private let contentBottomInset = SwiftTerminalKeyboardAccessoryView.contentBottomInset

    @Test
    func instanceTakesItsHeightFromTheSizingAndDoesNotSizeItself() {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: sizing(content: 46, reserve: 34))

        #expect(accessory.frame.height == 46 + contentBottomInset + 34)
        #expect(!accessory.allowsSelfSizing)
        #expect(accessory.autoresizingMask.contains(.flexibleWidth))
        #expect(accessory.translatesAutoresizingMaskIntoConstraints)
        #expect(accessory.inputViewStyle == .keyboard)
    }

    @Test
    func removingTheContentKeepsTheHeight() {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: sizing(content: 46, reserve: 0))
        let content = makeContent(height: 46)
        accessory.setContentView(content)
        layOut(accessory, width: 402)

        accessory.setContentView(nil)
        layOut(accessory, width: 402)

        #expect(content.superview == nil)
        #expect(accessory.frame.height == 46 + contentBottomInset)
        #expect(accessory.laidOutContentHeight == nil)
    }

    @Test
    func contentThatGrowsShowsItsOwnHeightWithoutResizingTheInstance() {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: sizing(content: 46, reserve: 0))
        let content = makeContent(height: 46)
        accessory.setContentView(content)
        layOut(accessory, width: 402)
        #expect(accessory.laidOutContentHeight == 46)

        content.constraints.first { $0.firstAttribute == .height }?.constant = 60
        layOut(accessory, width: 402)

        #expect(accessory.laidOutContentHeight == 60)
        #expect(accessory.frame.height == 46 + contentBottomInset)
    }

    @Test
    func contentHeightIsUnknownUntilTheContentIsLaidOutAtAWidth() {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: sizing(content: 46, reserve: 0))
        accessory.setContentView(makeContent(height: 46))

        #expect(accessory.laidOutContentHeight == nil)
    }

    @Test
    func contentMovesBetweenInstances() {
        let aboveKeyboard = SwiftTerminalKeyboardAccessoryView(sizing: sizing(content: 46, reserve: 0))
        let docked = SwiftTerminalKeyboardAccessoryView(sizing: sizing(content: 46, reserve: 34))
        let content = makeContent(height: 46)

        aboveKeyboard.setContentView(content)
        docked.setContentView(content)
        layOut(docked, width: 402)

        #expect(content.isDescendant(of: docked))
        #expect(!content.isDescendant(of: aboveKeyboard))
        #expect(docked.laidOutContentHeight == 46)

        // Clearing the instance the content already left does not take it from the other one.
        aboveKeyboard.setContentView(nil)
        #expect(content.isDescendant(of: docked))

        aboveKeyboard.setContentView(content)
        #expect(content.isDescendant(of: aboveKeyboard))
        #expect(!content.isDescendant(of: docked))
    }

    @Test
    func webViewHandsUIKitAnInstanceMeasuredForTheContent() throws {
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let content = makeContent(height: 46)

        webView.setKeyboardAccessoryContentView(content)

        let accessory = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)
        #expect(accessory.sizing.contentHeight == 46)
        #expect(accessory.sizing.bottomReserve == 0)
        #expect(accessory.frame.height == 46 + contentBottomInset)
        #expect(content.isDescendant(of: accessory))
    }

    @Test
    func webViewMeasuresANewContentViewIntoAnotherInstance() throws {
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setKeyboardAccessoryContentView(makeContent(height: 46))
        let first = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)

        let empty = makeContent(height: 0)
        webView.setKeyboardAccessoryContentView(empty)

        let second = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)
        #expect(second !== first)
        #expect(second.frame.height == contentBottomInset)
        #expect(first.frame.height == 46 + contentBottomInset)
        #expect(empty.isDescendant(of: second))
    }

    @Test
    func clearingTheContentRestoresWebKitsAccessoryAndKeepsTheInstanceHeight() throws {
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let content = makeContent(height: 46)
        webView.setKeyboardAccessoryContentView(content)
        let accessory = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)

        webView.setKeyboardAccessoryContentView(nil)

        #expect(!(webView.inputAccessoryView is SwiftTerminalKeyboardAccessoryView))
        #expect(content.superview == nil)
        #expect(accessory.frame.height == 46 + contentBottomInset)

        webView.setKeyboardAccessoryContentView(content)
        #expect(webView.inputAccessoryView === accessory)
    }

    @Test
    func hidingTheKeyboardInstallsAnInstanceThatReservesTheWindowsHomeIndicatorSpace() throws {
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let window = HomeIndicatorWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        webView.frame = window.bounds
        window.addSubview(webView)
        window.isHidden = false
        let content = makeContent(height: 46)
        webView.setKeyboardAccessoryContentView(content)
        let aboveKeyboard = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)

        webView.setSoftwareKeyboardMode(.hidden)

        let docked = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)
        #expect(docked !== aboveKeyboard)
        #expect(docked.sizing.bottomReserve == HomeIndicatorWindow.bottomInset)
        #expect(docked.frame.height == 46 + contentBottomInset + HomeIndicatorWindow.bottomInset)
        #expect(aboveKeyboard.frame.height == 46 + contentBottomInset)
        #expect(content.isDescendant(of: docked))

        // Each instance keeps its height, so the keyboard returns with the first one.
        webView.setSoftwareKeyboardMode(.system)
        #expect(webView.inputAccessoryView === aboveKeyboard)
        #expect(content.isDescendant(of: aboveKeyboard))

        let panel = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 260))
        webView.setSoftwareKeyboardMode(.custom(panel))
        #expect(webView.inputAccessoryView === aboveKeyboard)
        #expect(webView.inputView === panel)
    }

    private func sizing(content: CGFloat, reserve: CGFloat) -> TerminalKeyboardAccessorySizing {
        TerminalKeyboardAccessorySizing(
            contentHeight: content,
            contentBottomInset: contentBottomInset,
            bottomReserve: reserve
        )
    }
}

/// A window whose bottom safe area matches an iPhone's home indicator.
@MainActor
private final class HomeIndicatorWindow: UIWindow {
    static let bottomInset: CGFloat = 34

    override var safeAreaInsets: UIEdgeInsets {
        UIEdgeInsets(top: 0, left: 0, bottom: Self.bottomInset, right: 0)
    }
}

@MainActor
private func makeContent(height: CGFloat) -> UIView {
    let content = UIView()
    content.translatesAutoresizingMaskIntoConstraints = false
    content.heightAnchor.constraint(equalToConstant: height).isActive = true
    return content
}

@MainActor
private func layOut(_ accessory: UIView, width: CGFloat) {
    accessory.frame.size.width = width
    accessory.setNeedsLayout()
    accessory.layoutIfNeeded()
}
#endif
