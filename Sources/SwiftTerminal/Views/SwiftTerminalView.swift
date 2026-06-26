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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self

        #if canImport(AppKit)
        configureAppKitWebView(webView)
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        let scrollView = webView.scrollView
        scrollView.backgroundColor = .clear
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
private final class SwiftTerminalAppKitHostView: NSView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
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

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(webView)
        return true
    }

    func setBackgroundColor(_ color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
}

@MainActor
private final class SwiftTerminalViewStorage {
    let coordinator: SwiftTerminalCoordinator
    private var hostView: SwiftTerminalAppKitHostView?

    init(session: SwiftTerminalSession) {
        coordinator = SwiftTerminalCoordinator(session: session)
    }

    isolated deinit {
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
        storage.makeHostView()
    }

    public func updateNSView(_: NSView, context: Context) {
        context.coordinator.applyCurrentNativeBackground()
        storage.updateHostViewBackground()
    }

    public static func dismantleNSView(_: NSView, coordinator _: SwiftTerminalCoordinator) {}
}
#endif

#if canImport(UIKit)
@MainActor
private final class SwiftTerminalUIKitHostView: UIView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .clear
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
    private var hostView: SwiftTerminalUIKitHostView?

    init(session: SwiftTerminalSession) {
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
