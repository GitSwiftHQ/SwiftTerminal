//
//  SwiftTerminalUIKitHostSlotTests.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/10/10.
//

#if canImport(UIKit)
import Testing
import UIKit
import WebKit
@testable import SwiftTerminal

/// Exercises how the iOS terminal view's slots share its one host view.
///
/// Each test stands for representables that SwiftUI holds for the same terminal view at once,
/// such as the screen a size-class change rebuilds and a sheet above it, by putting slots in a
/// window and taking them out again in the order SwiftUI does.
@MainActor
@Suite("SwiftTerminal iOS host slots", .serialized)
struct SwiftTerminalUIKitHostSlotTests {
    @Test
    func makingASlotCreatesTheHostViewWithoutPlacingIt() {
        let fixture = Fixture()

        let slot = fixture.registry.makeSlot()

        #expect(fixture.hostRequests == 1)
        #expect(fixture.host.superview == nil)
        #expect(slot.hostedTerminalView == nil)
    }

    @Test
    func slotThatEntersAWindowHoldsTheHostView() {
        let fixture = Fixture()
        let slot = fixture.registry.makeSlot()

        fixture.window.addSubview(slot)

        #expect(fixture.host.superview === slot)
        #expect(slot.hostedTerminalView === fixture.host)
    }

    @Test
    func newerSlotTakesTheHostViewFromAnOlderOne() {
        let fixture = Fixture()
        let older = fixture.registry.makeSlot()
        let newer = fixture.registry.makeSlot()
        fixture.window.addSubview(older)

        fixture.window.addSubview(newer)

        #expect(fixture.host.superview === newer)
        #expect(older.hostedTerminalView == nil)
    }

    @Test
    func olderSlotLeavingItsWindowLeavesTheHostViewInTheNewerOne() {
        let fixture = Fixture()
        let older = fixture.registry.makeSlot()
        let newer = fixture.registry.makeSlot()
        fixture.window.addSubview(older)
        fixture.window.addSubview(newer)

        older.removeFromSuperview()

        #expect(fixture.host.superview === newer)
        #expect(fixture.host.window === fixture.window)
    }

    @Test
    func hostViewReturnsToTheSlotStillInAWindowWhenItsSlotLeaves() {
        let fixture = Fixture()
        let older = fixture.registry.makeSlot()
        let newer = fixture.registry.makeSlot()
        fixture.window.addSubview(older)
        fixture.window.addSubview(newer)

        newer.removeFromSuperview()

        #expect(fixture.host.superview === older)
        #expect(fixture.host.window === fixture.window)
    }

    @Test
    func hostViewGoesToTheMostRecentSlotStillInAWindow() {
        let fixture = Fixture()
        let first = fixture.registry.makeSlot()
        let second = fixture.registry.makeSlot()
        let third = fixture.registry.makeSlot()
        fixture.window.addSubview(first)
        fixture.window.addSubview(second)
        fixture.window.addSubview(third)

        third.removeFromSuperview()

        #expect(fixture.host.superview === second)
    }

    @Test
    func hostViewWaitsInItsSlotUntilAnotherSlotEntersAWindow() {
        let fixture = Fixture()
        let leaving = fixture.registry.makeSlot()
        fixture.window.addSubview(leaving)

        leaving.removeFromSuperview()

        #expect(fixture.host.superview === leaving)
        #expect(fixture.host.window == nil)

        let arriving = fixture.registry.makeSlot()
        fixture.window.addSubview(arriving)

        #expect(fixture.host.superview === arriving)
        #expect(fixture.host.window === fixture.window)
    }

    @Test
    func slotThatEntersAgainTakesTheHostViewBack() {
        let fixture = Fixture()
        let returning = fixture.registry.makeSlot()
        let other = fixture.registry.makeSlot()
        fixture.window.addSubview(returning)
        fixture.window.addSubview(other)
        returning.removeFromSuperview()

        fixture.window.addSubview(returning)

        #expect(fixture.host.superview === returning)
    }

    @Test
    func hostViewTakesTheSlotGeometryButNeverAnEmptyFrame() {
        let fixture = Fixture()
        let initialFrame = CGRect(x: 0, y: 0, width: 120, height: 80)
        fixture.host.frame = initialFrame
        let slot = fixture.registry.makeSlot()

        fixture.window.addSubview(slot)
        slot.layoutIfNeeded()

        #expect(fixture.host.frame == initialFrame)

        slot.frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        slot.layoutIfNeeded()

        #expect(fixture.host.frame == CGRect(x: 0, y: 0, width: 300, height: 200))
    }
}

/// One terminal view's host view, the registry that places it, and a window to place it in.
@MainActor
private final class Fixture {
    let host = SwiftTerminalUIKitHostView(
        webView: WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    )
    let window: UIWindow
    private(set) var hostRequests = 0
    private(set) lazy var registry = SwiftTerminalUIKitHostSlotRegistry { [unowned self] in
        hostRequests += 1
        return host
    }

    init() {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        window.isHidden = false
    }
}
#endif
