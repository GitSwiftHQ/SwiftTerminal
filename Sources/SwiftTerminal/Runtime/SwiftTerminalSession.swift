import Foundation
import Observation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

@MainActor
protocol TerminalRuntimeControlling: AnyObject {
    func send(_ command: TerminalHostCommandEnvelope) async throws
    func reloadRuntime()
    func registerFontResource(_ font: TerminalCustomFont) async throws -> String
}

#if canImport(AppKit)
/// The terminal's platform view, which can take the window's keyboard focus on request.
@MainActor
protocol TerminalKeyboardFocusControlling: AnyObject {
    var keyboardFocusWindow: NSWindow? { get }
    var holdsKeyboardFocus: Bool { get }

    @discardableResult
    func takeKeyboardFocus() -> Bool
}
#elseif canImport(UIKit)
/// The terminal's platform view, which can take the keyboard focus on request.
@MainActor
protocol TerminalKeyboardFocusControlling: AnyObject {
    var keyboardFocusHostView: UIView { get }
    var holdsKeyboardFocus: Bool { get }

    @discardableResult
    func takeKeyboardFocus() -> Bool
}
#endif

#if canImport(UIKit)
/// The terminal's web view, which owns the keyboard input views on iOS.
@MainActor
protocol TerminalKeyboardInputControlling: AnyObject {
    func setKeyboardAccessoryContentView(_ contentView: UIView?)
    func setSoftwareKeyboardMode(_ mode: SwiftTerminalSoftwareKeyboardMode)
    func resignKeyboardFocus()
}
#endif

@MainActor
protocol TerminalClipboardProviding {
    func readText() -> String?
    func writeText(_ text: String)
    /// The paths of the file URLs on the clipboard, which is how Finder copies files and folders.
    func readFilePaths() -> [String]
}

@MainActor
protocol TerminalLinkOpening {
    func open(_ url: URL)
}

public struct SwiftTerminalConfiguration: Sendable, Equatable {
    public static let defaultScrollback = 1000

    public var enablesSearchUI: Bool
    public var enablesKeyboardShortcuts: Bool
    public var enablesClipboardIntegration: Bool
    public var opensLinksByDefault: Bool
    public var enablesRuntimeDiagnostics: Bool
    public var scrollback: Int
    public var initialText: String?

    public var terminalContentLimit: Int {
        get {
            scrollback
        }
        set {
            scrollback = max(0, newValue)
        }
    }

    public init(
        enablesSearchUI: Bool = true,
        enablesKeyboardShortcuts: Bool = true,
        enablesClipboardIntegration: Bool = true,
        opensLinksByDefault: Bool = true,
        enablesRuntimeDiagnostics: Bool = false,
        scrollback: Int = defaultScrollback,
        initialText: String? = nil
    ) {
        self.enablesSearchUI = enablesSearchUI
        self.enablesKeyboardShortcuts = enablesKeyboardShortcuts
        self.enablesClipboardIntegration = enablesClipboardIntegration
        self.opensLinksByDefault = opensLinksByDefault
        self.enablesRuntimeDiagnostics = enablesRuntimeDiagnostics
        self.scrollback = max(0, scrollback)
        self.initialText = initialText
    }

    public static let `default` = Self()

    func normalized() -> Self {
        Self(
            enablesSearchUI: enablesSearchUI,
            enablesKeyboardShortcuts: enablesKeyboardShortcuts,
            enablesClipboardIntegration: enablesClipboardIntegration,
            opensLinksByDefault: opensLinksByDefault,
            enablesRuntimeDiagnostics: enablesRuntimeDiagnostics,
            scrollback: max(0, scrollback),
            initialText: initialText
        )
    }
}

private struct TerminalAppearanceState: Equatable {
    var appearance = SwiftTerminalAppearance.default
    var customFonts: [TerminalCustomFont] = []
}

private struct TerminalAppearanceCommandBatch {
    var commands: [TerminalHostCommandEnvelope]
    var installedCustomFonts: [TerminalCustomFont]
}

private struct PendingRuntimeCommand {
    var id: Int
    var command: TerminalHostCommandEnvelope
    var continuation: CheckedContinuation<Void, any Error>?
}

public enum SwiftTerminalLifecycleError: Error, Equatable, Sendable, LocalizedError {
    case runtimeUnavailable

    public var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            "The SwiftTerminal runtime is unavailable."
        }
    }
}

@MainActor
private struct SystemTerminalClipboardProvider: TerminalClipboardProviding {
    func readText() -> String? {
        #if canImport(AppKit)
        NSPasteboard.general.string(forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string
        #else
        nil
        #endif
    }

    func writeText(_ text: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    func readFilePaths() -> [String] {
        #if canImport(AppKit)
        TerminalFilePathText.filePaths(on: .general)
        #else
        []
        #endif
    }
}

@MainActor
private struct SystemTerminalLinkOpener: TerminalLinkOpening {
    func open(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

@MainActor
public final class SwiftTerminalSession: Observable {
    public var configuration: SwiftTerminalConfiguration {
        didSet {
            let normalizedConfiguration = configuration.normalized()
            guard configuration == normalizedConfiguration else {
                configuration = normalizedConfiguration
                return
            }

            guard configuration != oldValue else {
                return
            }

            syncRuntimeFeatureFlagsIfNeeded()
        }
    }

    public var onEvent: (@MainActor (TerminalRuntimeEventEnvelope) -> Void)?

    public private(set) var selectionText: String?
    public private(set) var searchState = SwiftTerminalSearchState.empty
    public private(set) var windowTitle: String?

    public var appearance: SwiftTerminalAppearance {
        get {
            appearanceState.appearance
        }
        set {
            let normalizedAppearance = newValue.normalized()
            guard appearanceState.appearance != normalizedAppearance else {
                return
            }

            appearanceState.appearance = normalizedAppearance
            syncRuntimeAppearanceIfNeeded()
        }
    }

    /// The sticky modifier state the runtime applies to the next keys.
    ///
    /// The runtime turns a one-shot modifier off once a key uses it and reports the change, so
    /// this always mirrors what the next key will carry. Observable.
    public var keyModifierStates: SwiftTerminalKeyModifierStates {
        get {
            observationRegistrar.access(self, keyPath: \.keyModifierStates)
            return storedKeyModifierStates
        }
        set {
            setKeyModifiers(newValue)
        }
    }

    /// Whether the Option key sends an escape prefix, the way a terminal's Meta key does, instead
    /// of the character from the keyboard's Option layer. xterm applies it where it detects a Mac
    /// platform, which includes iPadOS web views that report a desktop platform.
    public var optionIsMeta = false {
        didSet {
            guard optionIsMeta != oldValue else {
                return
            }

            enqueue(.setOptionIsMeta(optionIsMeta))
        }
    }

    #if canImport(AppKit)
    /// Whether files pasted or dropped on the terminal insert their paths, the way Terminal.app
    /// does, instead of the text WebKit would paste for them.
    ///
    /// Finder puts a copied file or folder on the pasteboard as a file URL whose plain-text form
    /// is only the item's name. While this is `true`, pasting such a pasteboard, with Command-V, the
    /// Edit menu, the context menu, or ``pasteFromClipboard()``, and dropping files from Finder
    /// insert each item's full path instead, escaped for the shell and followed by a space. The
    /// text goes through ``paste(_:)``, so bracketed paste applies and nothing runs on its own.
    /// Pasteboards without file URLs paste as before. Set this to `false` to leave file URLs to
    /// WebKit, for example when a host handles dropped files itself. Defaults to `true`.
    public var pastesFileURLsAsPaths = true
    #endif

    private let observationRegistrar = ObservationRegistrar()
    private var storedKeyModifierStates = SwiftTerminalKeyModifierStates.off
    private weak var runtimeController: (any TerminalRuntimeControlling)?
    private weak var keyboardFocusController: (any TerminalKeyboardFocusControlling)?
    #if canImport(UIKit)
    private weak var keyboardInputController: (any TerminalKeyboardInputControlling)?
    private var storedIsKeyboardAccessoryAttached = false
    private var storedSoftwareKeyboardMode = SwiftTerminalSoftwareKeyboardMode.system
    #endif
    private let clipboardProvider: any TerminalClipboardProviding
    private let linkOpener: any TerminalLinkOpening
    private var pendingCommands: [PendingRuntimeCommand] = []
    private var isRuntimeReady = false
    private var hasAppliedInitialText = false
    private var appearanceState = TerminalAppearanceState()
    private var installedCustomFonts: [TerminalCustomFont] = []
    private var isAppearanceSyncInProgress = false
    private var needsAppearanceSync = false
    private var nextPendingRuntimeCommandID = 0
    private var nextBufferSnapshotRequestSequence = 0
    private var pendingBufferSnapshotRequests: [
        String: CheckedContinuation<SwiftTerminalBufferSnapshot, any Error>
    ] = [:]

    public init(
        configuration: SwiftTerminalConfiguration = .default,
        appearance: SwiftTerminalAppearance = .default
    ) {
        self.configuration = configuration
        appearanceState = TerminalAppearanceState(appearance: appearance.normalized())
        clipboardProvider = SystemTerminalClipboardProvider()
        linkOpener = SystemTerminalLinkOpener()
    }

    init(
        configuration: SwiftTerminalConfiguration = .default,
        appearance: SwiftTerminalAppearance = .default,
        clipboardProvider: any TerminalClipboardProviding,
        linkOpener: any TerminalLinkOpening = SystemTerminalLinkOpener()
    ) {
        self.configuration = configuration
        appearanceState = TerminalAppearanceState(appearance: appearance.normalized())
        self.clipboardProvider = clipboardProvider
        self.linkOpener = linkOpener
    }

    public func write(_ text: String) {
        enqueue(.write(text))
    }

    public func clear() {
        enqueue(.clear)
    }

    public func focus() {
        enqueue(.focus)
    }

    #if canImport(AppKit)
    /// The window the terminal is currently in.
    ///
    /// A host that inspects keyboard focus around the terminal uses this when the application has
    /// no key window of its own to ask.
    public var keyboardFocusWindow: NSWindow? {
        keyboardFocusController?.keyboardFocusWindow
    }

    /// Whether this terminal currently holds the window's keyboard focus.
    ///
    /// A host that drives focus for several terminals uses this to tell its own terminal apart from
    /// another one that holds the first responder.
    public var holdsKeyboardFocus: Bool {
        keyboardFocusController?.holdsKeyboardFocus ?? false
    }

    /// Gives the terminal the window's keyboard focus, so key presses reach the shell without a
    /// click inside the terminal.
    ///
    /// AppKit delivers keyboard input to the window's first responder, which `focus()` alone does
    /// not change: it focuses the terminal inside the runtime. A host that decides the terminal
    /// should be typed into, such as one that just put a session on screen, calls this to move the
    /// first responder as well. A terminal that already holds it stays as it is, and a terminal
    /// whose view is not in a window reports `false`.
    ///
    /// - Returns: `true` when the terminal holds the window's first responder afterwards.
    @discardableResult
    public func takeKeyboardFocus() -> Bool {
        keyboardFocusController?.takeKeyboardFocus() ?? false
    }
    #elseif canImport(UIKit)
    /// The view that hosts the terminal, which is the focus environment around the terminal's web
    /// content.
    ///
    /// A host that inspects the keyboard focus around the terminal asks this view's focus system
    /// for its focused item and checks whether the view contains it with `contains(_:)`. It is
    /// `nil` until the terminal's view is built.
    public var keyboardFocusHostView: UIView? {
        keyboardFocusController?.keyboardFocusHostView
    }

    /// Whether the first responder is the terminal's web content.
    ///
    /// The web content becomes the first responder when the person taps the terminal or the host
    /// calls ``takeKeyboardFocus()``, and the keyboard accessory follows it. With a hardware
    /// keyboard, UIKit can still deliver key presses to the focus system's focused item instead,
    /// so a host that needs to know where key presses go also checks that the focused item is
    /// `nil` or inside ``keyboardFocusHostView``. The keyboard focus guide describes when the two
    /// differ.
    public var holdsKeyboardFocus: Bool {
        keyboardFocusController?.holdsKeyboardFocus ?? false
    }

    /// Gives the terminal the keyboard focus, so key presses reach the shell, including those
    /// from a hardware keyboard.
    ///
    /// The terminal's host view becomes the first responder for a moment and hands it to the web
    /// content, which also takes the focus system's focused item away from another view, such as
    /// a sidebar row, that would otherwise receive hardware key presses. A terminal whose web
    /// content already holds the first responder while nothing outside the terminal is focused
    /// stays as it is, and a terminal whose view is not in a window reports `false`. Without a
    /// hardware keyboard, taking the focus shows the software keyboard, so call this only when
    /// the terminal should be typed into.
    ///
    /// - Returns: `true` when the terminal's web content holds the first responder afterwards.
    @discardableResult
    public func takeKeyboardFocus() -> Bool {
        keyboardFocusController?.takeKeyboardFocus() ?? false
    }
    #endif

    func attachKeyboardFocusController(_ controller: any TerminalKeyboardFocusControlling) {
        keyboardFocusController = controller
    }

    #if canImport(UIKit)
    /// A view the terminal shows above the system keyboard in place of WebKit's form assistant bar.
    ///
    /// The terminal wraps the view in a keyboard-styled input view, which takes its height from
    /// the view's Auto Layout height and, on iOS 26 and later, draws it inside a glass rounded
    /// rectangle. UIKit keeps the height it recorded for a shown accessory, so the terminal never
    /// resizes one: when the view's height or the home indicator space below the bar changes, it
    /// shows another accessory with the new height, which keeps `keyboardLayoutGuide` and the
    /// SwiftUI keyboard safe area in line with the bar on screen. The bar rises and falls with the keyboard, stays at the bottom of the screen
    /// while ``softwareKeyboardMode`` is `.hidden`, and sits above a host panel while it is
    /// `.custom(_:)`. A view with no height keeps WebKit's bar away without showing a bar. Set it to `nil` to restore WebKit's default
    /// accessory. The session keeps a strong reference to the view.
    public var keyboardAccessoryContentView: UIView? {
        didSet {
            guard keyboardAccessoryContentView !== oldValue else {
                return
            }

            keyboardInputController?.setKeyboardAccessoryContentView(keyboardAccessoryContentView)
        }
    }

    /// Whether the keyboard accessory is currently in a window, which is the case while the
    /// terminal holds the keyboard focus and a ``keyboardAccessoryContentView`` is set.
    ///
    /// A host that shows its own bar while the terminal has no keyboard uses this as the single
    /// signal for which bar is on screen. Observable.
    public private(set) var isKeyboardAccessoryAttached: Bool {
        get {
            observationRegistrar.access(self, keyPath: \.isKeyboardAccessoryAttached)
            return storedIsKeyboardAccessoryAttached
        }
        set {
            guard storedIsKeyboardAccessoryAttached != newValue else {
                return
            }

            observationRegistrar.withMutation(of: self, keyPath: \.isKeyboardAccessoryAttached) {
                storedIsKeyboardAccessoryAttached = newValue
            }
        }
    }

    /// What the terminal shows in place of the software keyboard while it holds the keyboard
    /// focus.
    ///
    /// In every mode the terminal's input stays focused, so the keyboard accessory remains on
    /// screen and keys sent with ``sendKey(_:modifiers:)`` or typed on a hardware keyboard keep
    /// arriving. `.hidden` leaves only the accessory at the bottom of the screen, and
    /// `.custom(_:)` shows a host view, such as a panel of extra keys, where the keyboard was.
    /// Changing the mode takes effect at once, without a tap on the terminal; setting it back to
    /// `.system` brings the system keyboard back. Observable.
    public var softwareKeyboardMode: SwiftTerminalSoftwareKeyboardMode {
        get {
            observationRegistrar.access(self, keyPath: \.softwareKeyboardMode)
            return storedSoftwareKeyboardMode
        }
        set {
            guard storedSoftwareKeyboardMode != newValue else {
                return
            }

            observationRegistrar.withMutation(of: self, keyPath: \.softwareKeyboardMode) {
                storedSoftwareKeyboardMode = newValue
            }
            keyboardInputController?.setSoftwareKeyboardMode(newValue)
        }
    }

    /// Hides the software keyboard while the terminal keeps the keyboard focus.
    ///
    /// A shorthand for ``softwareKeyboardMode``: `true` sets `.hidden`, `false` sets `.system`.
    /// It reads `true` only while the mode is `.hidden`. Observable.
    public var isSoftwareKeyboardSuppressed: Bool {
        get {
            softwareKeyboardMode == .hidden
        }
        set {
            softwareKeyboardMode = newValue ? .hidden : .system
        }
    }

    /// Takes the keyboard focus away from the terminal, which dismisses the software keyboard and
    /// the keyboard accessory.
    ///
    /// A host calls this when it removes the terminal from the screen, so WebKit does not keep a
    /// focused input behind other text fields.
    public func resignKeyboardFocus() {
        keyboardInputController?.resignKeyboardFocus()
    }

    /// Plays the system keyboard click, which the system only does while the keyboard accessory
    /// is visible and the person has keyboard clicks turned on.
    public func playInputClick() {
        UIDevice.current.playInputClick()
    }

    func attachKeyboardInputController(_ controller: any TerminalKeyboardInputControlling) {
        keyboardInputController = controller
        controller.setSoftwareKeyboardMode(storedSoftwareKeyboardMode)
        controller.setKeyboardAccessoryContentView(keyboardAccessoryContentView)
    }

    func keyboardAccessoryAttachmentDidChange(_ isAttached: Bool) {
        isKeyboardAccessoryAttached = isAttached
    }
    #endif

    /// Sends a key to the shell as if it were typed into the terminal.
    ///
    /// The runtime merges `modifiers` with the sticky ``keyModifierStates``, encodes the key the
    /// way xterm does for the current cursor-key mode, and delivers it through the terminal's
    /// input event. A one-shot sticky modifier turns off afterwards. The terminal does not need
    /// the keyboard focus. Keys the runtime cannot encode, such as an empty character or a
    /// function key outside F1 through F12, are ignored.
    public func sendKey(_ key: SwiftTerminalKey, modifiers: SwiftTerminalKeyModifiers = []) {
        guard let command = TerminalHostCommandEnvelope.sendKey(key, modifiers: modifiers) else {
            return
        }

        enqueue(command)
    }

    /// Sets the sticky modifiers the runtime applies to the next keys, including single printable
    /// characters typed on the system keyboard.
    public func setKeyModifiers(_ states: SwiftTerminalKeyModifierStates) {
        updateKeyModifierStates(states)
        enqueue(.setKeyModifiers(states))
    }

    private func updateKeyModifierStates(_ states: SwiftTerminalKeyModifierStates) {
        guard storedKeyModifierStates != states else {
            return
        }

        observationRegistrar.withMutation(of: self, keyPath: \.keyModifierStates) {
            storedKeyModifierStates = states
        }
    }

    /// Resets local terminal modes, moves the cursor to a fresh line below the previous session's
    /// output, and waits for the runtime to acknowledge the reset.
    public func resetStateForNewRemoteSessionAcknowledged() async throws {
        try await sendLifecycleBarrier(.resetTerminalState)
    }

    /// Queues a local terminal mode reset for existing integrations that use fire-and-forget commands.
    public func resetStateForNewRemoteSession() {
        enqueue(.resetTerminalState)
    }

    /// Rebuilds the embedded runtime and creates a fresh xterm instance.
    public func reloadRuntime() {
        guard let runtimeController else {
            return
        }

        runtimeDidTerminate()
        runtimeController.reloadRuntime()
    }

    public func setAppearance(_ appearance: SwiftTerminalAppearance) {
        self.appearance = appearance
    }

    public func setFontFamily(_ family: String) {
        var updatedAppearance = appearance
        updatedAppearance.fontFamily = family
        appearance = updatedAppearance
    }

    public func setFontSize(_ size: Double) {
        var updatedAppearance = appearance
        updatedAppearance.fontSize = size
        appearance = updatedAppearance
    }

    public func setLineHeight(_ value: Double) {
        var updatedAppearance = appearance
        updatedAppearance.lineHeight = value
        appearance = updatedAppearance
    }

    public func setScrollback(_ value: Int) {
        var updatedConfiguration = configuration
        updatedConfiguration.scrollback = value
        configuration = updatedConfiguration
    }

    public func setTerminalContentLimit(_ value: Int) {
        setScrollback(value)
    }

    public func setLetterSpacing(_ value: Int) {
        var updatedAppearance = appearance
        updatedAppearance.letterSpacing = value
        appearance = updatedAppearance
    }

    public func setContentInsets(_ value: SwiftTerminalContentInsets) {
        var updatedAppearance = appearance
        updatedAppearance.contentInsets = value
        appearance = updatedAppearance
    }

    public func setContentPadding(_ value: Double) {
        setContentInsets(.init(all: value))
    }

    public func setContentPadding(
        top: Double,
        right: Double,
        bottom: Double,
        left: Double
    ) {
        setContentInsets(
            .init(
                top: top,
                right: right,
                bottom: bottom,
                left: left
            )
        )
    }

    public func setTheme(_ theme: SwiftTerminalTheme) {
        var updatedAppearance = appearance
        updatedAppearance.theme = theme
        appearance = updatedAppearance
    }

    public func setCursorStyle(_ style: SwiftTerminalCursorStyle) {
        var updatedAppearance = appearance
        updatedAppearance.cursorStyle = style
        appearance = updatedAppearance
    }

    public func setCursorBlink(_ enabled: Bool) {
        var updatedAppearance = appearance
        updatedAppearance.cursorBlink = enabled
        appearance = updatedAppearance
    }

    public func setInactiveCursorStyle(_ style: SwiftTerminalInactiveCursorStyle) {
        var updatedAppearance = appearance
        updatedAppearance.inactiveCursorStyle = style
        appearance = updatedAppearance
    }

    public func setScrollbarVisibility(_ visibility: SwiftTerminalScrollbarVisibility) {
        var updatedAppearance = appearance
        updatedAppearance.scrollbarVisibility = visibility
        appearance = updatedAppearance
    }

    public func registerCustomFont(_ font: TerminalCustomFont) {
        registerCustomFontSet([font])
    }

    public func registerCustomFontSet(_ fonts: [TerminalCustomFont]) {
        let normalizedFonts = normalizedCustomFontSet(from: fonts)
        guard !normalizedFonts.isEmpty,
              let resolvedFamily = normalizedFonts.first?.family
        else {
            return
        }

        appearanceState.customFonts = normalizedFonts

        var updatedAppearance = appearance
        updatedAppearance.fontFamily = resolvedFamily
        if updatedAppearance != appearance {
            appearance = updatedAppearance
            return
        }

        syncRuntimeAppearanceIfNeeded()
    }

    public func paste(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        enqueue(.paste(text))
    }

    public func pasteFromClipboard() {
        guard configuration.enablesClipboardIntegration else {
            return
        }

        #if canImport(AppKit)
        if pastesFileURLsAsPaths, pasteFilePaths(clipboardProvider.readFilePaths()) {
            return
        }
        #endif

        guard let text = clipboardProvider.readText(), !text.isEmpty else {
            return
        }

        paste(text)
    }

    #if canImport(AppKit)
    /// Pastes the shell-escaped `paths` when ``pastesFileURLsAsPaths`` is on.
    ///
    /// - Returns: `true` when the paths were pasted, and `false` when the session leaves the
    ///   content to the caller's usual handling because the option is off or there is no path.
    @discardableResult
    func pasteFilePaths(_ paths: [String]) -> Bool {
        guard pastesFileURLsAsPaths,
              let text = TerminalFilePathText.insertionText(forPaths: paths)
        else {
            return false
        }

        paste(text)
        return true
    }
    #endif

    public func copySelection() {
        guard configuration.enablesClipboardIntegration else {
            return
        }

        enqueue(.copySelection)
    }

    public func selectAll() {
        enqueue(.selectAll)
    }

    /// Copies what the Edit menu's Copy means for the focused control: the text selected in the
    /// search field while it has focus, the terminal selection otherwise.
    ///
    /// - Returns: `false` when the session leaves Copy to WebKit, because clipboard integration is
    ///   off or the runtime is not ready.
    @discardableResult
    func copyFocusedControl() -> Bool {
        guard configuration.enablesClipboardIntegration,
              let runtimeController,
              isRuntimeReady
        else {
            return false
        }

        send(
            .copyFocusedControl,
            with: runtimeController,
            failurePrefix: "host command send failed for copy_focused_control"
        )
        return true
    }

    @discardableResult
    func selectAllFocusedControl() -> Bool {
        guard let runtimeController, isRuntimeReady else {
            return false
        }

        send(
            .selectAllFocusedControl,
            with: runtimeController,
            failurePrefix: "host command send failed for select_all_focused_control"
        )
        return true
    }

    func openExternalLink(_ url: URL) {
        linkOpener.open(url)
    }

    public func showSearch() {
        guard configuration.enablesSearchUI else {
            return
        }
        enqueue(.setSearchVisible(true))
    }

    public func hideSearch() {
        enqueue(.setSearchVisible(false))
    }

    public func clearSearch() {
        enqueue(.clearSearch)
    }

    public func currentSelectionText() -> String? {
        selectionText
    }

    public func currentSearchState() -> SwiftTerminalSearchState {
        searchState
    }

    public func currentWindowTitle() -> String? {
        windowTitle
    }

    public func currentBufferSnapshot(
        maxLines: Int? = nil,
        trimRight: Bool = true
    ) async throws -> SwiftTerminalBufferSnapshot {
        guard let runtimeController, isRuntimeReady else {
            throw SwiftTerminalBufferSnapshotError.runtimeUnavailable
        }

        let requestID = nextBufferSnapshotRequestID()
        let normalizedMaxLines = maxLines.map { max(0, $0) }

        return try await withCheckedThrowingContinuation { continuation in
            pendingBufferSnapshotRequests[requestID] = continuation

            Task { @MainActor in
                do {
                    try await runtimeController.send(
                        .requestBufferSnapshot(
                            requestID: requestID,
                            maxLines: normalizedMaxLines,
                            trimRight: trimRight
                        )
                    )
                } catch {
                    pendingBufferSnapshotRequests.removeValue(forKey: requestID)?
                        .resume(throwing: error)
                }
            }
        }
    }

    public func searchNext(_ query: String, caseSensitive: Bool = false) {
        searchNext(
            query,
            options: SwiftTerminalSearchOptions(caseSensitive: caseSensitive)
        )
    }

    public func searchNext(_ query: String, options: SwiftTerminalSearchOptions) {
        guard !query.isEmpty else {
            return
        }
        enqueue(.searchNext(query, options: options))
    }

    public func searchPrevious(_ query: String, caseSensitive: Bool = false) {
        searchPrevious(
            query,
            options: SwiftTerminalSearchOptions(caseSensitive: caseSensitive)
        )
    }

    public func searchPrevious(
        _ query: String,
        options: SwiftTerminalSearchOptions
    ) {
        guard !query.isEmpty else {
            return
        }
        enqueue(.searchPrevious(query, options: options))
    }

    func attachRuntime(_ runtimeController: any TerminalRuntimeControlling) {
        self.runtimeController = runtimeController
        isRuntimeReady = false
        installedCustomFonts = []
        isAppearanceSyncInProgress = false
        needsAppearanceSync = false
    }

    func initialAppearanceCommand() -> TerminalHostCommandEnvelope {
        makeAppearanceCommand(for: appearanceState.appearance)
    }

    func detachRuntime() {
        runtimeController = nil
        isRuntimeReady = false
        installedCustomFonts = []
        isAppearanceSyncInProgress = false
        needsAppearanceSync = false
        selectionText = nil
        searchState = .empty
        windowTitle = nil
        failPendingRuntimeCommandContinuations(with: SwiftTerminalLifecycleError.runtimeUnavailable)
        failPendingBufferSnapshotRequests(with: .runtimeUnavailable)
    }

    func runtimeDidTerminate() {
        isRuntimeReady = false
        installedCustomFonts = []
        isAppearanceSyncInProgress = false
        needsAppearanceSync = false
        selectionText = nil
        searchState = .empty
        windowTitle = nil
        failPendingRuntimeCommandContinuations(with: SwiftTerminalLifecycleError.runtimeUnavailable)
        failPendingBufferSnapshotRequests(with: .runtimeUnavailable)
    }

    func handleRuntimeEvent(_ event: TerminalRuntimeEventEnvelope) {
        if event.type == .ready {
            runtimeDidBecomeReady()
        }

        if event.type == .selectionChanged {
            selectionText = normalizedSelectionText(from: event.text)
        }

        if event.type == .searchStateChanged {
            searchState = makeSearchState(from: event)
        }

        if event.type == .bufferSnapshot {
            handleBufferSnapshotEvent(event)
            return
        }

        if event.type == .titleChanged {
            windowTitle = event.title
        }

        if event.type == .keyModifiersChanged,
           let states = event.keyModifierStates
        {
            updateKeyModifierStates(states)
        }

        if event.type == .linkActivated,
           configuration.opensLinksByDefault,
           let urlString = event.url,
           let url = URL(string: urlString)
        {
            openExternalLink(url)
        }

        if event.type == .clipboardReadRequest {
            handleClipboardReadRequest(event)
            return
        }

        if event.type == .clipboardWriteRequest {
            handleClipboardWriteRequest(event)
            return
        }

        onEvent?(event)
    }

    private func normalizedSelectionText(from text: String?) -> String? {
        guard let text, !text.isEmpty else {
            return nil
        }

        return text
    }

    private func nextBufferSnapshotRequestID() -> String {
        nextBufferSnapshotRequestSequence += 1
        return "buffer-snapshot-\(nextBufferSnapshotRequestSequence)"
    }

    private func handleBufferSnapshotEvent(_ event: TerminalRuntimeEventEnvelope) {
        guard let requestID = event.requestID else {
            reportLog("buffer snapshot response missing requestID")
            return
        }

        guard let continuation = pendingBufferSnapshotRequests.removeValue(
            forKey: requestID
        ) else {
            reportLog("buffer snapshot response for unknown requestID \(requestID)")
            return
        }

        guard let snapshot = makeBufferSnapshot(from: event) else {
            continuation.resume(
                throwing: SwiftTerminalBufferSnapshotError.missingSnapshotPayload(
                    requestID: requestID
                )
            )
            return
        }

        continuation.resume(returning: snapshot)
    }

    private func makeBufferSnapshot(
        from event: TerminalRuntimeEventEnvelope
    ) -> SwiftTerminalBufferSnapshot? {
        guard let bufferType = event.bufferType,
              let totalLineCount = event.totalLineCount,
              let startLine = event.startLine,
              let endLine = event.endLine,
              let isTruncated = event.isTruncated,
              let lines = event.lines
        else {
            return nil
        }

        return SwiftTerminalBufferSnapshot(
            bufferType: bufferType,
            cols: event.cols ?? 0,
            rows: event.rows ?? 0,
            viewportY: event.viewportY ?? 0,
            baseY: event.baseY ?? 0,
            totalLineCount: totalLineCount,
            startLine: startLine,
            endLine: endLine,
            isTruncated: isTruncated,
            lines: lines
        )
    }

    private func failPendingBufferSnapshotRequests(
        with error: SwiftTerminalBufferSnapshotError
    ) {
        let continuations = pendingBufferSnapshotRequests.values
        pendingBufferSnapshotRequests.removeAll(keepingCapacity: true)

        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func failPendingRuntimeCommandContinuations(with error: any Error) {
        var retainedCommands: [PendingRuntimeCommand] = []
        retainedCommands.reserveCapacity(pendingCommands.count)

        for pendingCommand in pendingCommands {
            if let continuation = pendingCommand.continuation {
                continuation.resume(throwing: error)
            } else {
                retainedCommands.append(pendingCommand)
            }
        }

        pendingCommands = retainedCommands
    }

    private func makeSearchState(
        from event: TerminalRuntimeEventEnvelope
    ) -> SwiftTerminalSearchState {
        SwiftTerminalSearchState(
            isVisible: event.visible ?? false,
            query: event.query ?? "",
            options: SwiftTerminalSearchOptions(
                caseSensitive: event.caseSensitive ?? false,
                usesRegex: event.regex ?? false,
                matchesWholeWord: event.wholeWord ?? false
            ),
            resultIndex: event.resultIndex ?? 0,
            resultCount: event.resultCount ?? 0,
            errorMessage: event.errorMessage
        )
    }

    private func runtimeDidBecomeReady() {
        isRuntimeReady = true
        flushPendingCommands()
    }

    private func enqueue(_ command: TerminalHostCommandEnvelope) {
        guard let runtimeController, isRuntimeReady else {
            pendingCommands.append(
                PendingRuntimeCommand(
                    id: makePendingRuntimeCommandID(),
                    command: command
                )
            )
            return
        }

        send(
            command,
            with: runtimeController,
            failurePrefix: "host command send failed for \(command.type.rawValue)"
        )
    }

    private func sendLifecycleBarrier(
        _ command: TerminalHostCommandEnvelope
    ) async throws {
        try Task.checkCancellation()

        guard let runtimeController else {
            throw SwiftTerminalLifecycleError.runtimeUnavailable
        }

        guard isRuntimeReady else {
            try await enqueueLifecycleBarrier(command)
            return
        }

        try await runtimeController.send(command)
        try Task.checkCancellation()
    }

    private func enqueueLifecycleBarrier(
        _ command: TerminalHostCommandEnvelope
    ) async throws {
        let commandID = makePendingRuntimeCommandID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (
                continuation: CheckedContinuation<Void, any Error>
            ) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                pendingCommands.append(
                    PendingRuntimeCommand(
                        id: commandID,
                        command: command,
                        continuation: continuation
                    )
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingRuntimeCommand(id: commandID)
            }
        }

        try Task.checkCancellation()
    }

    private func cancelPendingRuntimeCommand(id: Int) {
        guard let index = pendingCommands.firstIndex(where: { $0.id == id }) else {
            return
        }

        let pendingCommand = pendingCommands.remove(at: index)
        pendingCommand.continuation?.resume(throwing: CancellationError())
    }

    private func makePendingRuntimeCommandID() -> Int {
        defer {
            nextPendingRuntimeCommandID += 1
        }
        return nextPendingRuntimeCommandID
    }

    private func flushPendingCommands() {
        guard let runtimeController, isRuntimeReady else {
            return
        }

        let queuedCommands = pendingCommands
        pendingCommands.removeAll(keepingCapacity: true)

        Task { @MainActor in
            let bootstrapAppearanceState = appearanceState
            let bootstrapAppearanceBatch = await makeAppearanceCommandBatch(
                with: runtimeController,
                appearanceState: bootstrapAppearanceState
            )
            _ = await sendPendingCommand(
                currentFeatureFlagsCommand(),
                with: runtimeController
            )
            await sendAppearanceCommandBatch(
                bootstrapAppearanceBatch,
                with: runtimeController
            )
            if let initialTextCommand = makeInitialTextCommand() {
                _ = await sendPendingCommand(initialTextCommand, with: runtimeController)
            }
            // A reloaded runtime starts with Option as a plain key and no sticky modifiers,
            // so the session restores the state its host last asked for.
            if optionIsMeta {
                _ = await sendPendingCommand(.setOptionIsMeta(true), with: runtimeController)
            }
            if !storedKeyModifierStates.isOff {
                _ = await sendPendingCommand(
                    .setKeyModifiers(storedKeyModifierStates),
                    with: runtimeController
                )
            }

            for command in queuedCommands {
                await sendPendingCommand(command, with: runtimeController)
            }
        }
    }

    private func sendPendingCommand(
        _ pendingCommand: PendingRuntimeCommand,
        with runtimeController: any TerminalRuntimeControlling
    ) async {
        do {
            try await runtimeController.send(pendingCommand.command)
            pendingCommand.continuation?.resume()
        } catch {
            reportLog("pending command send failed for \(pendingCommand.command.type.rawValue): \(error.localizedDescription)")
            pendingCommand.continuation?.resume(throwing: error)
        }
    }

    private func sendPendingCommand(
        _ command: TerminalHostCommandEnvelope,
        with runtimeController: any TerminalRuntimeControlling
    ) async -> Bool {
        do {
            try await runtimeController.send(command)
            return true
        } catch {
            reportLog("pending command send failed for \(command.type.rawValue): \(error.localizedDescription)")
            return false
        }
    }

    private func send(
        _ command: TerminalHostCommandEnvelope,
        with runtimeController: any TerminalRuntimeControlling,
        failurePrefix: String
    ) {
        Task { @MainActor in
            do {
                try await runtimeController.send(command)
            } catch {
                reportLog("\(failurePrefix): \(error.localizedDescription)")
            }
        }
    }

    private func syncRuntimeFeatureFlagsIfNeeded() {
        guard let runtimeController, isRuntimeReady else {
            return
        }

        send(
            currentFeatureFlagsCommand(),
            with: runtimeController,
            failurePrefix: "runtime feature sync failed"
        )
    }

    private func syncRuntimeAppearanceIfNeeded() {
        guard runtimeController != nil, isRuntimeReady else {
            return
        }

        needsAppearanceSync = true

        guard !isAppearanceSyncInProgress else {
            return
        }

        Task { @MainActor in
            await drainAppearanceSyncQueue()
        }
    }

    private func currentFeatureFlagsCommand() -> TerminalHostCommandEnvelope {
        .setFeatureFlags(
            enablesSearchUI: configuration.enablesSearchUI,
            enablesKeyboardShortcuts: configuration.enablesKeyboardShortcuts,
            enablesClipboardIntegration: configuration.enablesClipboardIntegration,
            enablesRuntimeDiagnostics: configuration.enablesRuntimeDiagnostics,
            scrollback: configuration.scrollback
        )
    }

    private func makeInitialTextCommand() -> TerminalHostCommandEnvelope? {
        if !hasAppliedInitialText,
           let initialText = configuration.initialText,
           !initialText.isEmpty
        {
            hasAppliedInitialText = true
            return .write(initialText)
        }

        return nil
    }

    private func makeAppearanceCommandBatch(
        with runtimeController: any TerminalRuntimeControlling,
        appearanceState: TerminalAppearanceState
    ) async -> TerminalAppearanceCommandBatch {
        var commands: [TerminalHostCommandEnvelope] = []
        let customFontsToInstall = customFontsToInstall(for: appearanceState)

        for customFont in customFontsToInstall {
            do {
                let fontURL = try await runtimeController.registerFontResource(customFont)
                commands.append(
                    .installFont(
                        family: customFont.family,
                        url: fontURL,
                        format: customFont.format,
                        variant: customFont.variant
                    )
                )
            } catch {
                reportLog(
                    "font registration failed for \(customFont.family) \(customFont.variant.rawValue): \(error.localizedDescription)"
                )
            }
        }

        commands.append(
            makeAppearanceCommand(for: appearanceState.appearance)
        )

        return TerminalAppearanceCommandBatch(
            commands: commands,
            installedCustomFonts: customFontsToInstall
        )
    }

    private func makeAppearanceCommand(
        for appearance: SwiftTerminalAppearance
    ) -> TerminalHostCommandEnvelope {
        .setAppearance(
            fontFamily: appearance.fontFamily,
            fontSize: appearance.fontSize,
            lineHeight: appearance.lineHeight,
            letterSpacing: appearance.letterSpacing,
            contentInsets: appearance.contentInsets,
            cursorStyle: appearance.cursorStyle,
            cursorBlink: appearance.cursorBlink,
            inactiveCursorStyle: appearance.inactiveCursorStyle,
            scrollbarVisibility: appearance.scrollbarVisibility,
            theme: appearance.theme
        )
    }

    private func drainAppearanceSyncQueue() async {
        guard isRuntimeReady else {
            needsAppearanceSync = false
            return
        }

        // Coalesce rapid appearance updates into the latest visible state
        // while keeping install_font and set_appearance ordered on the bridge.
        isAppearanceSyncInProgress = true
        defer {
            isAppearanceSyncInProgress = false
        }

        while needsAppearanceSync, isRuntimeReady {
            guard let currentRuntimeController = self.runtimeController else {
                break
            }

            needsAppearanceSync = false
            let appearanceSnapshot = appearanceState
            let commandBatch = await makeAppearanceCommandBatch(
                with: currentRuntimeController,
                appearanceState: appearanceSnapshot
            )
            await sendAppearanceCommandBatch(
                commandBatch,
                with: currentRuntimeController
            )
        }
    }

    private func sendAppearanceCommandBatch(
        _ commandBatch: TerminalAppearanceCommandBatch,
        with runtimeController: any TerminalRuntimeControlling
    ) async {
        var didSendAllCommands = true

        for command in commandBatch.commands {
            do {
                try await runtimeController.send(command)
            } catch {
                didSendAllCommands = false
                reportLog("runtime appearance sync failed for \(command.type.rawValue): \(error.localizedDescription)")
            }
        }

        if didSendAllCommands,
           !commandBatch.installedCustomFonts.isEmpty
        {
            installedCustomFonts = commandBatch.installedCustomFonts
        }
    }

    private func customFontsToInstall(
        for appearanceState: TerminalAppearanceState
    ) -> [TerminalCustomFont] {
        guard !appearanceState.customFonts.isEmpty else {
            return []
        }

        guard appearanceState.customFonts.allSatisfy({
            $0.family == appearanceState.appearance.fontFamily
        }) else {
            return []
        }

        guard installedCustomFonts != appearanceState.customFonts else {
            return []
        }

        return appearanceState.customFonts
    }

    private func normalizedCustomFontSet(
        from fonts: [TerminalCustomFont]
    ) -> [TerminalCustomFont] {
        var normalizedFontsByVariant: [TerminalCustomFontVariant: TerminalCustomFont] = [:]
        var resolvedFamily: String?

        for font in fonts {
            let trimmedFamily = font.family.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedFamily.isEmpty, !font.data.isEmpty else {
                continue
            }

            if resolvedFamily == nil {
                resolvedFamily = trimmedFamily
            }

            guard trimmedFamily == resolvedFamily else {
                continue
            }

            normalizedFontsByVariant[font.variant] = TerminalCustomFont(
                family: trimmedFamily,
                format: font.format,
                data: font.data,
                variant: font.variant
            )
        }

        return TerminalCustomFontVariant.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { normalizedFontsByVariant[$0] }
    }

    private func handleClipboardReadRequest(_ event: TerminalRuntimeEventEnvelope) {
        guard let requestID = event.requestID else {
            reportLog("clipboard read request missing requestID")
            return
        }

        guard let runtimeController, isRuntimeReady else {
            reportLog("clipboard read request received without ready runtime")
            return
        }

        let text = configuration.enablesClipboardIntegration ? (clipboardProvider.readText() ?? "") : ""
        send(
            .clipboardReadResult(requestID: requestID, text: text),
            with: runtimeController,
            failurePrefix: "clipboard read response failed"
        )
    }

    private func handleClipboardWriteRequest(_ event: TerminalRuntimeEventEnvelope) {
        guard let requestID = event.requestID else {
            reportLog("clipboard write request missing requestID")
            return
        }

        guard let runtimeController, isRuntimeReady else {
            reportLog("clipboard write request received without ready runtime")
            return
        }

        if configuration.enablesClipboardIntegration,
           let text = event.text
        {
            clipboardProvider.writeText(text)
        }

        send(
            .clipboardWriteResult(requestID: requestID),
            with: runtimeController,
            failurePrefix: "clipboard write response failed"
        )
    }

    private func reportLog(_ message: String) {
        onEvent?(
            TerminalRuntimeEventEnvelope(
                type: .log,
                message: message
            )
        )
    }
}
