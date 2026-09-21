#if canImport(AppKit)
import AppKit
import Testing
import WebKit
@testable import SwiftTerminal

/// Exercises the hand-off that keeps a terminal's host view inside a window
/// while SwiftUI rebuilds the views around it.
///
/// The suite is `.serialized` by contract, not by preference: its tests move one
/// shared `WKWebView` between windows, and a test that suspends while another
/// one reparents that instance would observe the other test's hierarchy.
@MainActor
@Suite("SwiftTerminalHostSlotView window hand-off", .serialized)
struct SwiftTerminalHostSlotViewTests {
    @Test
    func slotClaimsTheHostWhenItEntersAWindow() {
        let host = makeHost()
        let slot = makeSlot(providing: host)

        #expect(slot.hostedTerminalView == nil)

        let window = makeWindow(hosting: slot)

        #expect(slot.hostedTerminalView === host)
        #expect(host.superview === slot)
        #expect(host.window === window)
    }

    @Test
    func slotParksTheHostInTheWindowWhenItLeaves() {
        let host = makeHost()
        let slot = makeSlot(providing: host)
        let window = makeWindow(hosting: slot)

        slot.removeFromSuperview()

        let container = SwiftTerminalHostParkingView.installedContainer(in: window)
        #expect(container != nil)
        #expect(host.superview === container)
        // Transparent, not hidden: a hidden view is not visible to WebKit, and
        // a page that stays non-visible has its backing stores released.
        #expect(container?.alphaValue == 0)
        #expect(container?.isHidden == false)
        #expect(container?.hitTest(NSPoint(x: 10, y: 10)) == nil)
        // The point of parking: the host is still in the window it was in.
        #expect(host.window === window)
        #expect(slot.hostedTerminalView == nil)
    }

    @Test
    func secondSlotInTheSameWindowReclaimsTheParkedHost() {
        let host = makeHost()
        let window = makeWindow()
        let first = makeSlot(providing: host)
        mount(first, in: window)
        first.removeFromSuperview()

        #expect(host.window === window)

        let second = makeSlot(providing: host)
        mount(second, in: window)

        #expect(second.hostedTerminalView === host)
        #expect(host.superview === second)
        #expect(host.window === window)
    }

    @Test
    func reclaimingTheLastParkedHostRemovesTheContainer() {
        let host = makeHost()
        let window = makeWindow()
        let first = makeSlot(providing: host)
        mount(first, in: window)
        first.removeFromSuperview()

        #expect(SwiftTerminalHostParkingView.installedContainer(in: window) != nil)

        let second = makeSlot(providing: host)
        mount(second, in: window)

        #expect(SwiftTerminalHostParkingView.installedContainer(in: window) == nil)
    }

    @Test
    func closingTheWindowReleasesEveryParkedHost() {
        let host = makeHost()
        let window = makeWindow()
        let slot = makeSlot(providing: host)
        mount(slot, in: window)
        slot.removeFromSuperview()

        #expect(host.window === window)

        window.close()

        #expect(host.superview == nil)
        #expect(host.window == nil)
        #expect(SwiftTerminalHostParkingView.installedContainer(in: window) == nil)
    }

    @Test
    func slotInAnotherWindowReclaimsTheHost() {
        let host = makeHost()
        let source = makeWindow()
        let destination = makeWindow()
        let first = makeSlot(providing: host)
        mount(first, in: source)
        first.removeFromSuperview()

        let second = makeSlot(providing: host)
        mount(second, in: destination)

        #expect(second.hostedTerminalView === host)
        #expect(host.window === destination)
        #expect(SwiftTerminalHostParkingView.installedContainer(in: source) == nil)
    }

    @Test
    func parkedViewsLeaveTheKeyViewLoop() {
        let host = makeHost()
        let slot = makeSlot(providing: host)
        let window = makeWindow(hosting: slot)

        #expect(host.canBecomeKeyView)

        slot.removeFromSuperview()

        #expect(!host.canBecomeKeyView)
        #expect(!host.webView.canBecomeKeyView)
        #expect(SwiftTerminalHostParkingView.installedContainer(in: window)?.canBecomeKeyView == false)
    }

    @Test
    func parkedHostsAreNotReachableThroughAccessibility() {
        let host = makeHost()
        let slot = makeSlot(providing: host)
        let window = makeWindow(hosting: slot)

        // The host view is an ignored element, so the tree surfaces the web
        // area underneath it. While a slot holds the terminal, that is exactly
        // what an assistive technology should find.
        let claimed = slot.accessibilityChildren()?.contains { $0 as AnyObject === host.webView } ?? false
        #expect(claimed)

        slot.removeFromSuperview()

        let container = SwiftTerminalHostParkingView.installedContainer(in: window)
        #expect(container != nil)
        #expect(host.superview === container)
        #expect(container?.isAccessibilityElement() == false)
        #expect(container?.accessibilityChildren()?.isEmpty == true)
        #expect(container?.accessibilityChildrenInNavigationOrder()?.isEmpty == true)

        // An ignored container is replaced by its unignored descendants, so the
        // parked terminal must not surface through that substitution either.
        let parked = container.map { NSAccessibility.unignoredChildren(from: [$0]) } ?? []
        #expect(parked.isEmpty)
    }

    @Test
    func slotForwardsFirstResponderToTheWebView() {
        let host = makeHost()
        let slot = makeSlot(providing: host)
        let window = makeWindow(hosting: slot)

        #expect(slot.acceptsFirstResponder)
        #expect(window.makeFirstResponder(slot))
        #expect(window.firstResponder === host.webView)
    }

    @Test
    func emptySlotBoundsNeverReachTheHost() {
        let host = makeHost()
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let slot = makeSlot(providing: host)
        slot.frame = .zero
        _ = makeWindow(hosting: slot)

        // Claiming happens before SwiftUI has laid the slot out, so the host
        // must keep the geometry it was parked with rather than be squashed.
        #expect(host.frame == NSRect(x: 0, y: 0, width: 640, height: 480))

        slot.setFrameSize(NSSize(width: 800, height: 600))

        #expect(host.frame == NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test
    func slotLayoutGivesTheHostTheSlotGeometry() {
        let host = makeHost()
        let slot = makeSlot(providing: host)
        slot.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        _ = makeWindow(hosting: slot)

        host.frame = .zero
        slot.layout()

        #expect(host.frame == NSRect(x: 0, y: 0, width: 500, height: 400))
    }

    @Test
    func storageDeinitDetachesTheParkedHostAndItsContainer() {
        let window = makeWindow()
        var storage: SwiftTerminalViewStorage? = SwiftTerminalViewStorage(session: SwiftTerminalSession())
        let host = storage?.makeHostView()
        #expect(host != nil)
        let slot = SwiftTerminalHostSlotView { [weak storage] in storage?.currentHostView }
        mount(slot, in: window)
        slot.removeFromSuperview()

        #expect(host?.window === window)
        #expect(SwiftTerminalHostParkingView.installedContainer(in: window) != nil)

        storage = nil

        #expect(host?.superview == nil)
        #expect(SwiftTerminalHostParkingView.installedContainer(in: window) == nil)
    }
}

@MainActor
private enum SharedSlotTestWebView {
    /// The terminal's own subclass, so the suite exercises the key-view
    /// behaviour the app actually ships rather than a bare `WKWebView`.
    static let shared = SwiftTerminalAppKitWebView(frame: .zero, configuration: WKWebViewConfiguration())
}

/// Returns a host view over the suite's single `WKWebView`.
///
/// The first `WKWebView` initialization occupies the main thread for roughly a
/// tenth of a second while WebKit starts up, which is long enough to disturb the
/// timing-sensitive runtime tests running alongside this suite, so its
/// serialized tests share one instance instead of allocating one each.
@MainActor
private func makeHost() -> SwiftTerminalAppKitHostView {
    let webView = SharedSlotTestWebView.shared
    webView.removeFromSuperview()
    webView.frame = .zero
    return SwiftTerminalAppKitHostView(webView: webView)
}

@MainActor
private func makeSlot(providing host: SwiftTerminalAppKitHostView) -> SwiftTerminalHostSlotView {
    SwiftTerminalHostSlotView { host }
}

/// Returns a borderless window the test keeps alive across `close()`, which
/// otherwise releases a programmatically created window out from under the test.
@MainActor
private func makeWindow() -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
        styleMask: [.borderless],
        backing: .buffered,
        defer: true
    )
    window.isReleasedWhenClosed = false
    return window
}

@MainActor
private func makeWindow(hosting view: NSView) -> NSWindow {
    let window = makeWindow()
    mount(view, in: window)
    return window
}

@MainActor
private func mount(_ view: NSView, in window: NSWindow) {
    window.contentView?.addSubview(view)
}
#endif
