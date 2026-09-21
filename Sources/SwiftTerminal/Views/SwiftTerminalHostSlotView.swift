#if canImport(AppKit)
import AppKit

/// Stands in for the terminal host view inside SwiftUI's view tree so the host's
/// window membership stops following SwiftUI's view recycling.
///
/// A SwiftUI detail that is rebuilt whenever the selection changes creates a
/// fresh representable adaptor every time, and the cached host view is moved
/// out of the old adaptor and into the new one. That move takes the hosted
/// `WKWebView` out of its window: on macOS 27 WebKit drops the page's remote
/// layer tree shortly afterwards, and even when the tree survives a short
/// excursion the window transition alone costs a recomposite. Either way the
/// terminal repaints from nothing for several frames on every switch.
///
/// The representable therefore hands SwiftUI a slot, which carries no web
/// content and is cheap to build and discard. The host view is claimed only
/// once the slot is itself in a window, and it is handed to that window's
/// parking container when the slot leaves, so the host moves from container to
/// container *inside one window* and never becomes windowless. The single
/// unavoidable window transition is the session's first mount.
///
/// The slot mirrors the host's first-responder behaviour. SwiftUI promotes the
/// window's first responder to the representable's own view, which is now the
/// slot, so a slot that refused first responder would strand keyboard input on
/// SwiftUI's key-view placeholder.
@MainActor
final class SwiftTerminalHostSlotView: NSView {
    private let hostProvider: () -> SwiftTerminalAppKitHostView?

    init(hostProvider: @escaping () -> SwiftTerminalAppKitHostView?) {
        self.hostProvider = hostProvider
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The host view this slot currently holds, if it has claimed one.
    var hostedTerminalView: SwiftTerminalAppKitHostView? {
        subviews.first { $0 is SwiftTerminalAppKitHostView } as? SwiftTerminalAppKitHostView
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        guard let host = hostedTerminalView else {
            return super.becomeFirstResponder()
        }

        window?.makeFirstResponder(host.webView)
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            return
        }

        claimHostedTerminalView()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // A slot moving to another window carries the host with it as an
        // ordinary subview; only a slot leaving the window entirely has to hand
        // the host over, and it does so before the move so the host is already
        // somewhere else by the time the window reference goes away.
        if newWindow == nil {
            parkHostedTerminalView()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        synchronizeHostFrame()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        synchronizeHostFrame()
    }

    /// Takes the host view from wherever it currently lives — this window's
    /// parking container, another slot, or nothing at all — and hosts it here.
    func claimHostedTerminalView() {
        guard let host = hostProvider(), host.superview !== self else {
            return
        }

        let previousContainer = host.superview as? SwiftTerminalHostParkingView
        host.autoresizingMask = []
        addSubview(host)
        previousContainer?.removeFromSuperviewWhenEmpty()
        synchronizeHostFrame()
    }

    /// Hands the host view to the parking container of the window the slot is
    /// still in, so the host keeps its window across the hand-off.
    func parkHostedTerminalView() {
        guard let window, let host = hostedTerminalView else {
            return
        }

        SwiftTerminalHostParkingView.container(in: window)?.park(host)
    }

    /// Gives the host the slot's geometry, but never an empty one.
    ///
    /// A slot is built before SwiftUI has laid it out, so its bounds start out
    /// empty. The host forwards its own bounds to the web view, and an empty
    /// frame would make WebKit re-tile the page for a zero-sized viewport and
    /// throw away exactly the painted content this type exists to preserve, so
    /// the host keeps its parked geometry until the slot has a real one.
    private func synchronizeHostFrame() {
        guard let host = hostedTerminalView else {
            return
        }

        let target = bounds
        guard !target.isEmpty, host.frame != target else {
            return
        }

        host.frame = target
    }
}

/// Holds terminal host views inside a window while no slot wants them.
///
/// The container is fully transparent rather than hidden. Hiding it would be
/// the tidier way to keep it out of hit testing and the key view loop, but a
/// hidden view is not visible as far as WebKit is concerned, and the backing
/// stores of a page that is in a window but not visible are released once it
/// has been that way for a while: a terminal parked for a few seconds came back
/// intact, one parked for half a minute came back blank. A transparent view is
/// still a visible one, so the page stays painted for as long as it is parked.
/// Hit testing and the key view loop are therefore handled explicitly, here and
/// on the parked views themselves.
///
/// The container is sized to the window's content view but never resizes or
/// clips its hosts: a host keeps the real geometry it had when it was parked,
/// because a smaller visible rectangle makes WebKit discard the painted tiles
/// for everything outside it.
@MainActor
final class SwiftTerminalHostParkingView: NSView {
    /// Returns the window's parking container, creating it on first use.
    ///
    /// The container is found by walking the content view's subviews rather
    /// than through a table keyed by window, so there is no registry to keep in
    /// step with window lifetimes.
    static func container(in window: NSWindow) -> SwiftTerminalHostParkingView? {
        guard let contentView = window.contentView else {
            return nil
        }

        if let existing = contentView.subviews.first(where: { $0 is SwiftTerminalHostParkingView }) {
            return existing as? SwiftTerminalHostParkingView
        }

        let container = SwiftTerminalHostParkingView(frame: contentView.bounds)
        container.translatesAutoresizingMaskIntoConstraints = true
        container.autoresizingMask = [.width, .height]
        container.alphaValue = 0
        contentView.addSubview(container, positioned: .below, relativeTo: nil)
        return container
    }

    /// Returns the container already installed in `window`, without creating one.
    static func installedContainer(in window: NSWindow) -> SwiftTerminalHostParkingView? {
        window.contentView?.subviews.first { $0 is SwiftTerminalHostParkingView } as? SwiftTerminalHostParkingView
    }

    /// Keeps the pointer out of the parked hosts.
    ///
    /// A transparent view still hit-tests, so without this every click over the
    /// window's content would land here instead of on the interface.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override var canBecomeKeyView: Bool {
        false
    }

    /// Keeps parked terminals out of the accessibility tree.
    ///
    /// The container is transparent rather than hidden, so without this an
    /// assistive technology would report every parked terminal's web area
    /// alongside the one that is actually on screen.
    override func isAccessibilityElement() -> Bool {
        false
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? {
        []
    }

    func park(_ host: SwiftTerminalAppKitHostView) {
        guard host.superview !== self else {
            return
        }

        let frame = host.frame
        addSubview(host)
        host.frame = frame
    }

    func removeFromSuperviewWhenEmpty() {
        guard subviews.isEmpty else {
            return
        }

        removeFromSuperview()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    /// Lets go of every parked host as the window closes.
    ///
    /// The hosts outlive the window — their sessions own them — so they are
    /// detached explicitly instead of being left as subviews of a container
    /// that is about to disappear with the content view.
    @objc private func windowWillClose() {
        for subview in subviews {
            subview.removeFromSuperview()
        }

        removeFromSuperview()
    }
}

extension NSView {
    /// Whether the view is waiting in a window's parking container rather than
    /// being on screen. Parked views take themselves out of the key view loop,
    /// which a hidden container would otherwise have done for them.
    var isInTerminalHostParking: Bool {
        var ancestor = superview
        while let view = ancestor {
            if view is SwiftTerminalHostParkingView {
                return true
            }
            ancestor = view.superview
        }

        return false
    }
}
#endif
