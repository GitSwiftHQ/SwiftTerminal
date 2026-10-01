import Foundation
import SwiftUI
import WebKit

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit

public typealias SwiftTerminalContextMenuProvider = @MainActor (_ location: CGPoint) -> UIMenu?
#endif

private let terminalBridgeMessageName = "swiftTerminal"

private struct TerminalNativeBackgroundColor {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init?(cssHex: String) {
        guard let normalizedHex = Self.normalizedHexDigits(from: cssHex) else {
            return nil
        }

        var value: UInt64 = 0
        guard Scanner(string: normalizedHex).scanHexInt64(&value) else {
            return nil
        }

        red = CGFloat((value & 0xFF00_0000) >> 24) / 255
        green = CGFloat((value & 0x00FF_0000) >> 16) / 255
        blue = CGFloat((value & 0x0000_FF00) >> 8) / 255
        alpha = CGFloat(value & 0x0000_00FF) / 255
    }

    private static func normalizedHexDigits(from cssHex: String) -> String? {
        let trimmed = cssHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let expanded: String

        switch hex.count {
        case 3:
            expanded = hex.map { "\($0)\($0)" }.joined() + "FF"
        case 4:
            expanded = hex.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = hex + "FF"
        case 8:
            expanded = hex
        default:
            return nil
        }

        guard expanded.range(
            of: #"^[0-9A-Fa-f]{8}$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }

        return expanded
    }

    #if canImport(AppKit)
    var nsColor: NSColor {
        NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
    #endif

    #if canImport(UIKit)
    var uiColor: UIColor {
        UIColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
    #endif
}

@MainActor
public final class SwiftTerminalCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, TerminalRuntimeControlling {
    private weak var webView: WKWebView?
    private let session: SwiftTerminalSession
    private let fontSchemeHandler = TerminalRuntimeFontSchemeHandler()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var recoveryAttempts = 0
    #if canImport(UIKit)
    private var contextMenuInteraction: UIContextMenuInteraction?
    private var contextMenuProvider: SwiftTerminalContextMenuProvider?
    #endif

    init(session: SwiftTerminalSession) {
        self.session = session
    }

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: terminalBridgeMessageName)
        contentController.addUserScript(
            WKUserScript(
                source: initialAppearanceBridgeScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        contentController.addUserScript(
            WKUserScript(
                source: Self.diagnosticBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController = contentController
        configuration.setURLSchemeHandler(
            fontSchemeHandler,
            forURLScheme: TerminalRuntimeFontSchemeHandler.scheme
        )

        #if canImport(AppKit)
        let webView = SwiftTerminalAppKitWebView(frame: .zero, configuration: configuration)
        webView.selectAllHandler = { [weak self] in
            self?.session.selectAllFocusedControl() ?? false
        }
        webView.copyHandler = { [weak self] in
            self?.session.copyFocusedControl() ?? false
        }
        webView.hasTerminalSelection = { [weak self] in
            self?.session.selectionText != nil
        }
        webView.pastesFileURLsAsPaths = { [weak self] in
            self?.session.pastesFileURLsAsPaths ?? false
        }
        webView.filePathPasteHandler = { [weak self] paths in
            self?.session.pasteFilePaths(paths) ?? false
        }
        #else
        let webView = SwiftTerminalUIKitWebView(frame: .zero, configuration: configuration)
        webView.onKeyboardAccessoryAttachmentChange = { [weak session] isAttached in
            session?.keyboardAccessoryAttachmentDidChange(isAttached)
        }
        session.attachKeyboardInputController(webView)
        #endif
        webView.navigationDelegate = self

        #if canImport(AppKit)
        configureAppKitWebView(webView)
        #else
        configureUIKitWebView(webView)
        #endif

        applyCurrentNativeBackground(to: webView)
        self.webView = webView
        session.attachRuntime(self)
        scheduleRuntimeLoad(in: webView, reason: "initial")
        return webView
    }

    func applyCurrentNativeBackground() {
        guard let webView else {
            return
        }

        applyCurrentNativeBackground(to: webView)
    }

    #if canImport(UIKit)
    func installContextMenuInteraction(on view: UIView) {
        guard contextMenuInteraction == nil else {
            return
        }

        let interaction = UIContextMenuInteraction(delegate: self)
        view.addInteraction(interaction)
        contextMenuInteraction = interaction
    }

    func setContextMenuProvider(_ provider: SwiftTerminalContextMenuProvider?) {
        contextMenuProvider = provider
    }
    #endif

    #if canImport(AppKit)
    func currentNativeBackgroundColor() -> NSColor? {
        currentTerminalNativeBackgroundColor()?.nsColor
    }
    #endif

    #if canImport(UIKit)
    func currentNativeBackgroundColor() -> UIColor? {
        currentTerminalNativeBackgroundColor()?.uiColor
    }
    #endif

    private func initialAppearanceBridgeScript() -> String {
        let command = session.initialAppearanceCommand()
        guard let data = try? encoder.encode(command),
              let json = String(data: data, encoding: .utf8)
        else {
            return "window.swiftTerminalInitialAppearance = undefined;"
        }

        return """
        (() => {
          const command = \(json);
          window.swiftTerminalInitialAppearance = command;
          const theme = command && command.type === "set_appearance" ? command.theme : undefined;
          const root = document.documentElement;
          const setColor = (name, value) => {
            if (typeof value === "string" && value.trim().length > 0) {
              root.style.setProperty(name, value.trim());
            }
          };
          if (root && theme) {
            setColor("--st-body-background", theme.background);
            setColor("--st-body-foreground", theme.foreground);
            root.style.background = theme.background;
          }
        })();
        """
    }

    private func applyCurrentNativeBackground(to webView: WKWebView) {
        guard let color = currentTerminalNativeBackgroundColor() else {
            return
        }

        #if canImport(AppKit)
        webView.layer?.backgroundColor = color.nsColor.cgColor
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = color.nsColor
        }
        #elseif canImport(UIKit)
        webView.backgroundColor = color.uiColor
        webView.scrollView.backgroundColor = color.uiColor
        #endif
    }

    private func currentTerminalNativeBackgroundColor() -> TerminalNativeBackgroundColor? {
        TerminalNativeBackgroundColor(cssHex: session.appearance.theme.background)
            ?? TerminalNativeBackgroundColor(cssHex: SwiftTerminalTheme.default.background)
    }

    #if canImport(UIKit)
    private func configureUIKitWebView(_ webView: WKWebView) {
        webView.isOpaque = false
        webView.backgroundColor = .clear

        // The terminal buffer scrolls inside the runtime's own viewport, so the
        // hosting scroll view must never pan. Leaving it interactive lets the
        // keyboard's automatic inset adjustment drag the whole page upward.
        let scrollView = webView.scrollView
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
    }
    #endif

    #if canImport(AppKit)
    private func configureAppKitWebView(_ webView: WKWebView) {
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }

        configureAppKitScrollViews(in: webView)
        Task { @MainActor [weak webView] in
            guard let webView else {
                return
            }
            self.configureAppKitScrollViews(in: webView)
        }
    }

    private func configureAppKitScrollViews(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.drawsBackground = false
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.contentInsets = NSEdgeInsetsZero
            scrollView.scrollerInsets = NSEdgeInsetsZero
            scrollView.horizontalScrollElasticity = .none
            scrollView.verticalScrollElasticity = .none
        }

        for subview in view.subviews {
            configureAppKitScrollViews(in: subview)
        }
    }
    #endif

    func teardown() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: terminalBridgeMessageName)
        webView?.navigationDelegate = nil
        webView = nil
        session.detachRuntime()
    }

    func send(_ command: TerminalHostCommandEnvelope) async throws {
        guard let webView else {
            return
        }

        let jsonData = try encoder.encode(command)
        let jsonString = String(decoding: jsonData, as: UTF8.self)

        _ = try await webView.callAsyncJavaScript(
            "window.swiftTerminal.receive(commandJSON)",
            arguments: ["commandJSON": jsonString],
            in: nil,
            contentWorld: .page
        )
    }

    func reloadRuntime() {
        guard let webView else {
            return
        }

        recoveryAttempts = 0
        emitLog("webview.reloadRuntime requested")
        scheduleRuntimeLoad(in: webView, reason: "host-request")
    }

    func registerFontResource(_ font: TerminalCustomFont) async throws -> String {
        fontSchemeHandler.register(font).absoluteString
    }

    public func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            message.name == terminalBridgeMessageName,
            let jsonString = message.body as? String,
            let jsonData = jsonString.data(using: .utf8),
            let event = try? decoder.decode(TerminalRuntimeEventEnvelope.self, from: jsonData)
        else {
            return
        }

        session.handleRuntimeEvent(event)
    }

    public func webView(_: WKWebView, didFinish navigation: WKNavigation!) {
        emitLog("webview.didFinishNavigation")
    }

    public func webView(
        _: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        emitLog("webview.didFailNavigation \(error.localizedDescription)")
    }

    public func webView(
        _: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        emitLog("webview.didFailProvisionalNavigation \(error.localizedDescription)")
    }

    public func webViewWebContentProcessDidTerminate(_: WKWebView) {
        emitLog("webview.webContentProcessDidTerminate")
        session.runtimeDidTerminate()

        guard let webView, recoveryAttempts < 1 else {
            return
        }

        recoveryAttempts += 1
        emitLog("webview.reloadingAfterTermination attempt \(recoveryAttempts)")
        scheduleRuntimeLoad(in: webView, reason: "recovery")
    }

    private func scheduleRuntimeLoad(in webView: WKWebView, reason: String) {
        DispatchQueue.main.async { [weak self, weak webView] in
            guard let self, let webView else {
                return
            }

            self.emitLog("webview.loadRuntime \(reason)")
            self.loadRuntime(in: webView)
        }
    }

    private func loadRuntime(in webView: WKWebView) {
        do {
            let entrypointURL = try TerminalRuntimeAssets.entrypointURL()
            let rootDirectoryURL = try TerminalRuntimeAssets.rootDirectoryURL()
            webView.loadFileURL(entrypointURL, allowingReadAccessTo: rootDirectoryURL)
        } catch {
            webView.loadHTMLString(Self.runtimeLoadFailureHTML(for: error), baseURL: nil)
        }
    }

    private func emitLog(_ message: String) {
        session.handleRuntimeEvent(
            TerminalRuntimeEventEnvelope(
                type: .log,
                message: message
            )
        )
    }

    private static let diagnosticBridgeScript = """
    (() => {
      const post = (message) => {
        try {
          window.webkit?.messageHandlers?.swiftTerminal?.postMessage(
            JSON.stringify({ type: 'log', message })
          )
        } catch {}
      }

      window.addEventListener(
        'error',
        (event) => {
          const target = event.target
          if (target instanceof HTMLScriptElement || target instanceof HTMLLinkElement) {
            const url = target.src || target.href || '(unknown resource)'
            post(`resource-error ${target.tagName.toLowerCase()} ${url}`)
            return
          }

          const filename = event.filename || '(inline)'
          post(`window-error ${event.message} @ ${filename}:${event.lineno}:${event.colno}`)
        },
        true
      )

      window.addEventListener('unhandledrejection', (event) => {
        const reason =
          typeof event.reason === 'string'
            ? event.reason
            : event.reason?.message || String(event.reason)
        post(`unhandledrejection ${reason}`)
      })

      const originalConsoleError = console.error.bind(console)
      console.error = (...args) => {
        post(`console.error ${args.map((value) => String(value)).join(' ')}`)
        originalConsoleError(...args)
      }
    })();
    """

    private static func runtimeLoadFailureHTML(for error: Error) -> String {
        let message: String

        if let assetError = error as? TerminalRuntimeAssetError {
            switch assetError {
            case .missingEntrypoint:
                message = "Missing TerminalRuntime/index.html in the Swift package resource bundle."
            }
        } else {
            message = error.localizedDescription
        }

        let escapedMessage = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <title>SwiftTerminal Load Error</title>
            <style>
              :root {
                color-scheme: dark;
              }
              body {
                margin: 0;
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                background: #10151d;
                color: #eef5ff;
                font: 14px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              }
              main {
                max-width: 560px;
                margin: 24px;
                padding: 20px 22px;
                border: 1px solid rgba(124, 199, 255, 0.2);
                border-radius: 14px;
                background: rgba(12, 17, 23, 0.94);
              }
              h1 {
                margin: 0 0 10px;
                font-size: 16px;
              }
              p {
                margin: 0;
                color: #c8d8ea;
              }
              code {
                font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
                color: #eef5ff;
              }
            </style>
          </head>
          <body>
            <main>
              <h1>SwiftTerminal runtime failed to load</h1>
              <p><code>\(escapedMessage)</code></p>
            </main>
          </body>
        </html>
        """
    }
}

#if canImport(UIKit)
extension SwiftTerminalCoordinator: UIScrollViewDelegate {
    // WebKit still scrolls the hosting scroll view programmatically — keyboard
    // focus reveal and inset restoration bypass `isScrollEnabled` — and the
    // terminal page is exactly viewport-sized, so any non-zero offset is
    // spurious and gets pinned back.
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.contentOffset != .zero else {
            return
        }
        scrollView.contentOffset = .zero
    }
}

extension SwiftTerminalCoordinator: UIContextMenuInteractionDelegate {
    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard contextMenuProvider != nil else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else {
                return nil
            }

            return self.contextMenuProvider?(location)
        }
    }
}
#endif

#if canImport(AppKit)
@MainActor
final class SwiftTerminalAppKitWebView: WKWebView {
    var selectAllHandler: (@MainActor () -> Bool)?

    // The Edit menu delivers Select All as a responder action, and WKWebView's
    // own implementation runs a DOM select-all on the runtime's hidden input
    // textarea instead of the terminal buffer. Route the action through the
    // session so the menu matches what Cmd+A already does inside the page.
    override func selectAll(_ sender: Any?) {
        guard selectAllHandler?() == true else {
            super.selectAll(sender)
            return
        }
    }

    // MARK: Copy

    /// Sends Copy to the session; returns `false` to leave it to WebKit.
    var copyHandler: (@MainActor () -> Bool)?

    /// Whether the terminal currently has selected text.
    var hasTerminalSelection: (@MainActor () -> Bool)?

    // The terminal draws its selection itself, so the page's DOM selection is only the caret in
    // the runtime's hidden input, and WebKit leaves the Edit menu's Copy, which Command-C also
    // goes through, disabled while text is selected in the terminal. Copy is enabled while the
    // terminal has a selection and routed through the session, the way Select All is: it copies
    // the search field's selected text while that field has focus and the terminal selection
    // otherwise. WKWebView does not declare `copy:` to Swift, so this is a new Objective-C method
    // that falls back to WebKit's implementation directly.
    @objc func copy(_ sender: Any?) {
        guard copyHandler?() == true else {
            performWebKitEditingAction(#selector(NSText.copy(_:)), sender: sender)
            return
        }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSText.copy(_:)), hasTerminalSelection?() == true {
            return true
        }

        return super.validateUserInterfaceItem(item)
    }

    override var canBecomeKeyView: Bool {
        isInTerminalHostParking ? false : super.canBecomeKeyView
    }

    // MARK: File paths

    /// Whether the session currently wants pasted and dropped files inserted as paths.
    var pastesFileURLsAsPaths: (@MainActor () -> Bool)?

    /// Inserts the given file paths through the session, returning `false` when it declines them.
    var filePathPasteHandler: (@MainActor ([String]) -> Bool)?

    /// The pasteboard Paste reads file URLs from. Tests replace it with a private pasteboard so
    /// they never touch the user's clipboard.
    var pastePasteboard: NSPasteboard = .general

    /// Whether the current drag session is a file drop this view handles instead of WebKit.
    private(set) var isHandlingFileDrop = false

    // Command-V reaches this action the same way the Edit and context menus do: WebKit first offers
    // the key event to the page, which leaves it alone, and AppKit then resends it to the main
    // menu, whose Paste item sends `paste:` down the responder chain. WebKit's own implementation
    // pastes the pasteboard's plain text, which for a file Finder copied is only the item's name,
    // so file URLs are turned into paths here before WebKit sees them. WKWebView does not declare
    // `paste:` to Swift, so this is a new Objective-C method that calls WebKit's directly.
    @objc func paste(_ sender: Any?) {
        guard !pasteFilePathsFromPasteboard() else {
            return
        }

        pasteWithWebKit(sender)
    }

    /// Pastes the paths of the file URLs on ``pastePasteboard`` when the session wants them.
    ///
    /// - Returns: `true` when the paths were pasted; `false` leaves the paste to WebKit.
    func pasteFilePathsFromPasteboard() -> Bool {
        guard pastesFileURLsAsPaths?() == true else {
            return false
        }

        let paths = TerminalFilePathText.filePaths(on: pastePasteboard)
        guard !paths.isEmpty else {
            return false
        }

        return filePathPasteHandler?(paths) == true
    }

    private func pasteWithWebKit(_ sender: Any?) {
        performWebKitEditingAction(#selector(NSText.paste(_:)), sender: sender)
    }

    /// Runs WebKit's own implementation of an editing action this class replaces.
    private func performWebKitEditingAction(_ selector: Selector, sender: Any?) {
        guard WKWebView.instancesRespond(to: selector),
              let implementation = class_getMethodImplementation(WKWebView.self, selector)
        else {
            nextResponder?.tryToPerform(selector, with: sender)
            return
        }

        typealias EditingActionImplementation = @convention(c) (AnyObject, Selector, Any?) -> Void
        unsafeBitCast(implementation, to: EditingActionImplementation.self)(self, selector, sender)
    }

    // A file drop is handled here for the whole drag session, from the moment it enters, so WebKit
    // never starts a drag of its own for it. WebKit refuses file drops on the terminal page, and
    // drags without file URLs, or any drag while the session does not want paths, still go to it.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isHandlingFileDrop = pastesFileURLsAsPaths?() == true
            && !TerminalFilePathText.filePaths(on: sender.draggingPasteboard).isEmpty
        guard isHandlingFileDrop else {
            return super.draggingEntered(sender)
        }

        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isHandlingFileDrop else {
            return super.draggingUpdated(sender)
        }

        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        guard isHandlingFileDrop else {
            super.draggingExited(sender)
            return
        }

        isHandlingFileDrop = false
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isHandlingFileDrop else {
            return super.prepareForDragOperation(sender)
        }

        return true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isHandlingFileDrop else {
            return super.performDragOperation(sender)
        }

        let paths = TerminalFilePathText.filePaths(on: sender.draggingPasteboard)
        return filePathPasteHandler?(paths) == true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        guard isHandlingFileDrop else {
            super.concludeDragOperation(sender)
            return
        }

        isHandlingFileDrop = false
    }
}

/// Hosts the terminal web view and owns its frame instead of pinning it with
/// Auto Layout.
///
/// On macOS 27 a SwiftUI detail that carries an `.inspector` hands this view
/// two frames inside a single layout turn for every step of a live window
/// resize: first a transient frame whose height equals the container's top
/// safe-area inset (the toolbar height, 52 pt in the observed case) and then
/// the real frame. Constraints forward both to WebKit, which commits the
/// transient page size, so the following screen frame paints only that sliver
/// of content with the web view's background underneath it, a blank flash on
/// every drag step. Deferring the frame assignment by one run-loop turn while
/// `isLiveResizing` is true means the web view only ever receives the host's
/// settled bounds for that turn, because both frames arrive synchronously
/// within it. The deferral does not depend on the transient frame existing: if
/// SwiftUI stops emitting it, the deferred assignment simply writes the bounds
/// it would have written immediately, and the only cost while dragging is at
/// most one frame of size lag, which `viewDidEndLiveResize()` closes out.
/// Outside a live resize the frame is applied synchronously, as before.
@MainActor
class SwiftTerminalAppKitHostView: NSView, TerminalKeyboardFocusControlling {
    let webView: WKWebView

    private var isWebViewFrameSyncScheduled = false

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = []
        webView.frame = bounds
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Overridable seam for `inLiveResize` so tests can exercise the deferred
    /// path without driving a real window resize.
    var isLiveResizing: Bool {
        inLiveResize
    }

    /// The web view is anchored to the top-left corner, the way terminal
    /// content is laid out. While a deferred sync is pending the host can be
    /// taller than the web view for one frame; with a flipped coordinate
    /// system that frame only leaves a sliver of host background at the
    /// bottom instead of shifting every row of text down by the height delta.
    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var canBecomeKeyView: Bool {
        isInTerminalHostParking ? false : super.canBecomeKeyView
    }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(webView)
        return true
    }

    /// The window the terminal is currently in, which a host uses to inspect keyboard focus.
    var keyboardFocusWindow: NSWindow? {
        window
    }

    /// Whether the terminal's web view currently holds the window's keyboard focus.
    var holdsKeyboardFocus: Bool {
        guard let window else {
            return false
        }

        return window.firstResponder === webView
    }

    /// Gives the terminal's web view the window's keyboard focus.
    ///
    /// The host forwards first responder to the web view, so the window's own responder ends up on
    /// the view that receives key events. Callers that already hold it change nothing, which keeps
    /// hosts where the framework hands focus to the terminal on its own untouched.
    ///
    /// - Returns: `true` when the terminal holds the window's first responder afterwards.
    @discardableResult
    func takeKeyboardFocus() -> Bool {
        guard let window else {
            return false
        }

        guard window.firstResponder !== webView else {
            return true
        }

        return window.makeFirstResponder(webView)
    }

    override func layout() {
        super.layout()
        updateWebViewFrame()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateWebViewFrame()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        syncWebViewFrame()
    }

    func setBackgroundColor(_ color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }

    private func updateWebViewFrame() {
        guard isLiveResizing else {
            syncWebViewFrame()
            return
        }

        guard !isWebViewFrameSyncScheduled else {
            return
        }

        isWebViewFrameSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.isWebViewFrameSyncScheduled = false
            self.syncWebViewFrame()
        }
    }

    private func syncWebViewFrame() {
        guard webView.frame != bounds else {
            return
        }

        webView.frame = bounds
    }
}

@MainActor
final class SwiftTerminalViewStorage {
    let coordinator: SwiftTerminalCoordinator
    private let session: SwiftTerminalSession
    private var hostView: SwiftTerminalAppKitHostView?

    init(session: SwiftTerminalSession) {
        self.session = session
        coordinator = SwiftTerminalCoordinator(session: session)
    }

    /// The host view this storage owns, once one has been built.
    var currentHostView: SwiftTerminalAppKitHostView? {
        hostView
    }

    isolated deinit {
        // The host outlives SwiftUI's views: while no slot holds it, it waits
        // in a window's parking container. Nothing else would take it out of
        // that container once the session is gone, so it is detached here, and
        // a container left with nothing in it goes away with it.
        if let hostView {
            let container = hostView.superview as? SwiftTerminalHostParkingView
            hostView.removeFromSuperview()
            container?.removeFromSuperviewWhenEmpty()
        }

        coordinator.teardown()
    }

    func makeHostView() -> SwiftTerminalAppKitHostView {
        if let hostView {
            return hostView
        }

        let webView = coordinator.makeWebView()
        let hostView = SwiftTerminalAppKitHostView(webView: webView)
        if let color = coordinator.currentNativeBackgroundColor() {
            hostView.setBackgroundColor(color)
        }
        self.hostView = hostView
        session.attachKeyboardFocusController(hostView)
        return hostView
    }

    func updateHostViewBackground() {
        guard let color = coordinator.currentNativeBackgroundColor() else {
            return
        }

        hostView?.setBackgroundColor(color)
    }
}

public struct SwiftTerminalView: NSViewRepresentable {
    private let storage: SwiftTerminalViewStorage

    public init(session: SwiftTerminalSession = .init()) {
        storage = SwiftTerminalViewStorage(session: session)
    }

    public func makeCoordinator() -> SwiftTerminalCoordinator {
        storage.coordinator
    }

    public func makeNSView(context _: Context) -> NSView {
        // Build the host view now, not when a slot first reaches a window.
        // Creating it is what attaches the session's runtime, and a session can
        // start its shell before SwiftUI has mounted anything; deferring this
        // made those sessions fail with an unavailable runtime.
        _ = storage.makeHostView()

        // The slot claims the host only once it is in a window, which is what
        // keeps the host from ever becoming windowless. It must not retain the
        // storage: a parked slot would otherwise keep a finished session and
        // its web content alive.
        return SwiftTerminalHostSlotView { [weak storage] in
            storage?.makeHostView()
        }
    }

    public func updateNSView(_: NSView, context: Context) {
        context.coordinator.applyCurrentNativeBackground()
        storage.updateHostViewBackground()
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator _: SwiftTerminalCoordinator) {
        // A slot that still holds the host when SwiftUI discards it has not
        // been through `viewWillMove(toWindow:)`, so it hands the host over now
        // while it still has a window to hand it to.
        (nsView as? SwiftTerminalHostSlotView)?.parkHostedTerminalView()
    }
}
#endif

#if canImport(UIKit)
/// The view that hosts the terminal's web view on iOS.
///
/// It takes part in the focus system without drawing a focus effect, and it can become the first
/// responder only while it hands the keyboard focus to the web content. Becoming the first
/// responder while focusable is what moves the focus system's focused item into the terminal:
/// UIKit moves focus to a new first responder only when that responder can be focused, and
/// WebKit's content view cannot. Outside the hand-off the host declines the first responder, so a
/// web content view that resigns, for example when the person taps a sidebar row, does not leave
/// it on the host.
@MainActor
final class SwiftTerminalUIKitHostView: UIView, TerminalKeyboardFocusControlling {
    let webView: WKWebView

    private var isHandingOffKeyboardFocus = false

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .clear
        focusEffect = nil
        addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFocused: Bool {
        true
    }

    override var canBecomeFirstResponder: Bool {
        isHandingOffKeyboardFocus
    }

    var keyboardFocusHostView: UIView {
        self
    }

    /// Whether the first responder is the web view or a view inside it, which is WebKit's content
    /// view once the terminal has been tapped or handed the focus.
    var holdsKeyboardFocus: Bool {
        guard window != nil else {
            return false
        }

        var pendingViews: [UIView] = [webView]
        while !pendingViews.isEmpty {
            let candidate = pendingViews.removeFirst()
            if candidate.isFirstResponder {
                return true
            }
            pendingViews.append(contentsOf: candidate.subviews)
        }

        return false
    }

    /// Whether the focus system has focused an item outside the terminal, which then receives
    /// hardware key presses ahead of the first responder.
    var isFocusedItemOutsideTerminal: Bool {
        guard let focusedItem = UIFocusSystem.focusSystem(for: self)?.focusedItem else {
            return false
        }

        return !contains(focusedItem)
    }

    /// Hands the keyboard focus to the web content through the host.
    ///
    /// The host becomes the first responder while focusable, which takes the focused item away
    /// from wherever it was, and then gives the first responder to the web view, which passes it
    /// on to WebKit's content view; UIKit then leaves no item focused, so key presses go to the
    /// content view. A terminal that already holds the first responder with nothing outside it
    /// focused changes nothing.
    ///
    /// - Returns: `true` when the web content holds the first responder afterwards.
    @discardableResult
    func takeKeyboardFocus() -> Bool {
        guard window != nil else {
            return false
        }

        if holdsKeyboardFocus, !isFocusedItemOutsideTerminal {
            return true
        }

        isHandingOffKeyboardFocus = true
        defer {
            isHandingOffKeyboardFocus = false
        }

        _ = becomeFirstResponder()
        _ = webView.becomeFirstResponder()
        if isFirstResponder {
            // The web content declined, so the host gives the responder up instead of keeping
            // one it cannot use.
            _ = resignFirstResponder()
        }

        return holdsKeyboardFocus
    }

    func setBackgroundColor(_ color: UIColor) {
        backgroundColor = color
    }
}

public struct SwiftTerminalView: UIViewRepresentable {
    private let storage: SwiftTerminalViewStorage

    public init(session: SwiftTerminalSession = .init()) {
        storage = SwiftTerminalViewStorage(session: session)
    }

    public func swiftTerminalContextMenu(_ provider: SwiftTerminalContextMenuProvider?) -> Self {
        storage.updateContextMenuProvider(provider)
        return self
    }

    public func makeCoordinator() -> SwiftTerminalCoordinator {
        storage.coordinator
    }

    public func makeUIView(context _: Context) -> UIView {
        storage.makeHostView()
    }

    public func updateUIView(_: UIView, context: Context) {
        context.coordinator.applyCurrentNativeBackground()
        storage.updateHostViewBackground()
    }

    public static func dismantleUIView(_: UIView, coordinator _: SwiftTerminalCoordinator) {}
}

@MainActor
private final class SwiftTerminalViewStorage {
    let coordinator: SwiftTerminalCoordinator
    private let session: SwiftTerminalSession
    private var hostView: SwiftTerminalUIKitHostView?

    init(session: SwiftTerminalSession) {
        self.session = session
        coordinator = SwiftTerminalCoordinator(session: session)
    }

    isolated deinit {
        coordinator.teardown()
    }

    func makeHostView() -> SwiftTerminalUIKitHostView {
        if let hostView {
            return hostView
        }

        let webView = coordinator.makeWebView()
        let hostView = SwiftTerminalUIKitHostView(webView: webView)
        coordinator.installContextMenuInteraction(on: hostView)
        if let color = coordinator.currentNativeBackgroundColor() {
            hostView.setBackgroundColor(color)
        }
        self.hostView = hostView
        session.attachKeyboardFocusController(hostView)
        return hostView
    }

    func updateHostViewBackground() {
        guard let color = coordinator.currentNativeBackgroundColor() else {
            return
        }

        hostView?.setBackgroundColor(color)
    }

    func updateContextMenuProvider(_ provider: SwiftTerminalContextMenuProvider?) {
        coordinator.setContextMenuProvider(provider)
    }
}
#endif
