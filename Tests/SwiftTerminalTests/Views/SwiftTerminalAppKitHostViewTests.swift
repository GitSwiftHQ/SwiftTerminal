#if canImport(AppKit)
import AppKit
import Testing
import WebKit
@testable import SwiftTerminal

/// Exercises the host view's frame ownership on macOS.
///
/// The suite is `.serialized` by contract, not by preference: its tests share
/// one `WKWebView` through `makeHostedWebView()`, and a test that suspends
/// while another one reparents that instance would observe the other test's
/// geometry. See `makeHostedWebView()` for why the instance is shared.
@MainActor
@Suite("SwiftTerminalAppKitHostView frame synchronization", .serialized)
struct SwiftTerminalAppKitHostViewTests {
    @Test
    func initializationHostsTheWebViewWithoutAutoLayout() {
        let webView = makeHostedWebView()
        let host = SwiftTerminalAppKitHostView(webView: webView)

        #expect(webView.superview === host)
        #expect(webView.translatesAutoresizingMaskIntoConstraints)
        #expect(webView.autoresizingMask == [])
        #expect(webView.constraints.isEmpty)
        #expect(host.constraints.isEmpty)
    }

    @Test
    func frameChangeOutsideLiveResizeSynchronizesImmediately() {
        let webView = makeHostedWebView()
        let host = SwiftTerminalAppKitHostView(webView: webView)

        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)

        #expect(webView.frame == NSRect(x: 0, y: 0, width: 640, height: 480))
        #expect(webView.frame == host.bounds)
    }

    @Test
    func layoutPassOutsideLiveResizeSynchronizesImmediately() {
        let webView = makeHostedWebView()
        let host = SwiftTerminalAppKitHostView(webView: webView)

        host.setFrameSize(NSSize(width: 800, height: 600))
        webView.frame = .zero
        host.layout()

        #expect(webView.frame == NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test
    func frameChangeDuringLiveResizeDefersSynchronizationByOneTurn() async {
        let webView = makeHostedWebView()
        let host = LiveResizingHostView(webView: webView)

        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)

        #expect(webView.frame == .zero)

        await yieldMainQueueTurn()

        #expect(webView.frame == NSRect(x: 0, y: 0, width: 900, height: 700))
    }

    @Test
    func layoutPassDuringLiveResizeDefersSynchronizationByOneTurn() async {
        let webView = makeHostedWebView()
        let host = LiveResizingHostView(webView: webView)

        host.setFrameSize(NSSize(width: 500, height: 400))
        await yieldMainQueueTurn()
        webView.frame = .zero
        host.layout()

        #expect(webView.frame == .zero)

        await yieldMainQueueTurn()

        #expect(webView.frame == NSRect(x: 0, y: 0, width: 500, height: 400))
    }

    @Test
    func transientFrameDuringLiveResizeNeverReachesTheWebView() async {
        let webView = makeHostedWebView()
        let host = LiveResizingHostView(webView: webView)
        let settledFrame = NSRect(x: 0, y: 0, width: 1024, height: 768)

        host.frame = NSRect(x: 0, y: 0, width: 1024, height: 52)
        host.frame = settledFrame

        #expect(webView.frame == .zero)

        await yieldMainQueueTurn()

        #expect(webView.frame == settledFrame)

        await yieldMainQueueTurn()

        #expect(webView.frame == settledFrame)
    }

    @Test
    func endingLiveResizeSynchronizesImmediately() {
        let webView = makeHostedWebView()
        let host = LiveResizingHostView(webView: webView)

        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)

        #expect(webView.frame == .zero)

        host.viewDidEndLiveResize()

        #expect(webView.frame == NSRect(x: 0, y: 0, width: 320, height: 240))
    }
}

@MainActor
private final class LiveResizingHostView: SwiftTerminalAppKitHostView {
    override var isLiveResizing: Bool {
        true
    }
}

@MainActor
private enum SharedTestWebView {
    static let shared = WKWebView(frame: .zero)
}

/// Returns the suite's single `WKWebView`, detached from any previous host.
///
/// The first `WKWebView` initialization occupies the main thread for roughly a
/// tenth of a second while WebKit starts up, which is long enough to disturb
/// the timing-sensitive runtime tests running alongside this suite, so its
/// serialized tests share one instance instead of allocating one each.
@MainActor
private func makeHostedWebView() -> WKWebView {
    let webView = SharedTestWebView.shared
    webView.removeFromSuperview()
    webView.frame = .zero
    return webView
}

/// Waits for one turn of the main dispatch queue. The host schedules its
/// deferred frame synchronization with `DispatchQueue.main.async`, so a block
/// enqueued afterwards on the same serial queue runs after that work is done.
@MainActor
private func yieldMainQueueTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}
#endif
