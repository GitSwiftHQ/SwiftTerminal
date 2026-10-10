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

/// Exercises the keyboard accessory instances and how the iOS web view installs them.
///
/// The test runner has no keyboard, so these tests cover what holds without one: an instance
/// keeps the height it was created with whatever happens to its content, and the web view hands
/// UIKit an instance measured for the content and the mode. Where UIKit places the accessory, and
/// the swaps that follow from it, are verified on a simulator against the keyboard's own frame,
/// as the configuration guide describes.
@MainActor
@Suite("SwiftTerminal keyboard accessory", .serialized)
struct SwiftTerminalKeyboardAccessoryViewTests {
    private let contentBottomInset = SwiftTerminalKeyboardAccessoryView.contentBottomInset
    private let keyboardKeepsRecordedHeight = SwiftTerminalKeyboardAccessoryView.keyboardKeepsRecordedHeight

    @Test
    func fixedHeightInstanceTakesItsHeightFromItsFrame() {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: fixedHeight(content: 46))

        #expect(accessory.frame.height == 46 + contentBottomInset)
        #expect(!accessory.allowsSelfSizing)
        #expect(accessory.autoresizingMask.contains(.flexibleWidth))
        #expect(accessory.translatesAutoresizingMaskIntoConstraints)
        #expect(accessory.inputViewStyle == .keyboard)
    }

    @Test
    func instanceAtTheBottomOfTheScreenSizesItself() {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: docked(content: 46, reserve: 34))
        accessory.setContentView(makeContent(height: 46))

        #expect(accessory.allowsSelfSizing)
        #expect(!accessory.translatesAutoresizingMaskIntoConstraints)
        // It starts with the height it is expected to take, never an empty frame.
        #expect(accessory.frame.height == 46 + contentBottomInset + 34)
        if keyboardKeepsRecordedHeight {
            // The keyboard measures the instance before it has a window or a safe area of its own.
            #expect(fittingHeight(of: accessory) == 46 + contentBottomInset + 34)
        } else {
            // The home indicator space comes from the instance's own safe area.
            #expect(fittingHeight(of: accessory) == 46)
        }
    }

    @Test(.enabled(if: SwiftTerminalKeyboardAccessoryView.keyboardKeepsRecordedHeight))
    func instanceAtTheBottomOfTheScreenKeepsItsHeightWithoutContent() {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: docked(content: 46, reserve: 34))
        let content = makeContent(height: 46)
        accessory.setContentView(content)
        layOut(accessory, width: 402)

        accessory.setContentView(nil)

        #expect(content.superview == nil)
        #expect(fittingHeight(of: accessory) == 46 + contentBottomInset + 34)
    }

    @Test
    func removingTheContentKeepsTheHeight() {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: fixedHeight(content: 46))
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
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: fixedHeight(content: 46))
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
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: fixedHeight(content: 46))
        accessory.setContentView(makeContent(height: 46))

        #expect(accessory.laidOutContentHeight == nil)
    }

    @Test
    func contentMovesBetweenInstances() {
        let aboveKeyboard = SwiftTerminalKeyboardAccessoryView(sizing: fixedHeight(content: 46))
        let dockedBar = SwiftTerminalKeyboardAccessoryView(sizing: docked(content: 46, reserve: 34))
        let content = makeContent(height: 46)

        aboveKeyboard.setContentView(content)
        layOut(aboveKeyboard, width: 402)
        #expect(aboveKeyboard.laidOutContentHeight == 46)

        dockedBar.setContentView(content)

        #expect(content.isDescendant(of: dockedBar))
        #expect(!content.isDescendant(of: aboveKeyboard))
        #expect(aboveKeyboard.laidOutContentHeight == nil)

        // Clearing the instance the content already left does not take it from the other one.
        aboveKeyboard.setContentView(nil)
        #expect(content.isDescendant(of: dockedBar))

        aboveKeyboard.setContentView(content)
        #expect(content.isDescendant(of: aboveKeyboard))
        #expect(!content.isDescendant(of: dockedBar))
    }

    @Test
    func webViewHandsUIKitAnInstanceMeasuredForTheContent() throws {
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let content = makeContent(height: 46)

        webView.setKeyboardAccessoryContentView(content)

        let accessory = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)
        #expect(accessory.sizing.contentHeight == 46)
        #expect(accessory.sizing.bottomReserve == 0)
        #expect(content.isDescendant(of: accessory))
        if keyboardKeepsRecordedHeight {
            #expect(!accessory.sizing.sizesItself)
            #expect(accessory.frame.height == 46 + contentBottomInset)
        } else {
            #expect(accessory.sizing.sizesItself)
        }
    }

    @Test
    func webViewMeasuresANewContentView() throws {
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setKeyboardAccessoryContentView(makeContent(height: 46))
        let first = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)

        let empty = makeContent(height: 0)
        webView.setKeyboardAccessoryContentView(empty)

        let second = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)
        #expect(empty.isDescendant(of: second))
        if keyboardKeepsRecordedHeight {
            #expect(second !== first)
            #expect(second.frame.height == contentBottomInset)
            #expect(first.frame.height == 46 + contentBottomInset)
        } else {
            // The keyboard measures the one instance again for the new content.
            #expect(second === first)
        }
    }

    @Test
    func clearingTheContentRestoresWebKitsAccessoryAndKeepsTheInstance() throws {
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let content = makeContent(height: 46)
        webView.setKeyboardAccessoryContentView(content)
        let accessory = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)
        let height = accessory.frame.height

        webView.setKeyboardAccessoryContentView(nil)

        #expect(!(webView.inputAccessoryView is SwiftTerminalKeyboardAccessoryView))
        #expect(content.superview == nil)
        #expect(accessory.frame.height == height)

        webView.setKeyboardAccessoryContentView(content)
        #expect(webView.inputAccessoryView === accessory)
        #expect(content.isDescendant(of: accessory))
    }

    @Test(.enabled(if: SwiftTerminalKeyboardAccessoryView.keyboardKeepsRecordedHeight))
    func hidingTheKeyboardInstallsAnInstanceForTheBottomOfTheScreen() throws {
        let (webView, window) = makeWebViewInWindow()
        let content = makeContent(height: 46)
        webView.setKeyboardAccessoryContentView(content)
        let aboveKeyboard = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)

        webView.setSoftwareKeyboardMode(.hidden)

        let dockedBar = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)
        #expect(dockedBar !== aboveKeyboard)
        #expect(dockedBar.sizing.sizesItself)
        #expect(dockedBar.sizing.bottomReserve == HomeIndicatorWindow.bottomInset)
        #expect(dockedBar.frame.width == window.bounds.width)
        #expect(fittingHeight(of: dockedBar) == 46 + contentBottomInset + HomeIndicatorWindow.bottomInset)
        #expect(aboveKeyboard.frame.height == 46 + contentBottomInset)
        #expect(content.isDescendant(of: dockedBar))

        // An instance with a fixed height keeps it, so the keyboard returns with the first one.
        webView.setSoftwareKeyboardMode(.system)
        #expect(webView.inputAccessoryView === aboveKeyboard)
        #expect(content.isDescendant(of: aboveKeyboard))

        let panel = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 260))
        webView.setSoftwareKeyboardMode(.custom(panel))
        #expect(webView.inputAccessoryView === aboveKeyboard)
        #expect(webView.inputView === panel)

        // A docked instance that has left the screen is not shown again.
        webView.setSoftwareKeyboardMode(.hidden)
        let secondDockedBar = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)
        #expect(secondDockedBar !== dockedBar)
        #expect(secondDockedBar !== aboveKeyboard)
        #expect(secondDockedBar.sizing.sizesItself)
    }

    @Test(.disabled(if: SwiftTerminalKeyboardAccessoryView.keyboardKeepsRecordedHeight))
    func oneInstanceServesEveryMode() throws {
        let (webView, _) = makeWebViewInWindow()
        let content = makeContent(height: 46)
        webView.setKeyboardAccessoryContentView(content)
        let accessory = try #require(webView.inputAccessoryView as? SwiftTerminalKeyboardAccessoryView)

        let panel = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 260))
        for mode in [SwiftTerminalSoftwareKeyboardMode.hidden, .system, .custom(panel), .hidden] {
            webView.setSoftwareKeyboardMode(mode)

            #expect(webView.inputAccessoryView === accessory)
            #expect(content.isDescendant(of: accessory))
        }
        #expect(accessory.sizing.sizesItself)
    }

    private func fixedHeight(content: CGFloat) -> TerminalKeyboardAccessorySizing {
        TerminalKeyboardAccessorySizing(sizesItself: false, contentHeight: content)
    }

    private func docked(content: CGFloat, reserve: CGFloat) -> TerminalKeyboardAccessorySizing {
        TerminalKeyboardAccessorySizing(sizesItself: true, contentHeight: content, bottomReserve: reserve)
    }

    private func makeWebViewInWindow() -> (SwiftTerminalUIKitWebView, UIWindow) {
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let window = HomeIndicatorWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        webView.frame = window.bounds
        window.addSubview(webView)
        window.isHidden = false
        return (webView, window)
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

/// The height Auto Layout gives an instance that sizes itself at an iPhone's width.
@MainActor
private func fittingHeight(of accessory: UIView) -> CGFloat {
    accessory.systemLayoutSizeFitting(
        CGSize(width: 402, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
    ).height
}
#endif
