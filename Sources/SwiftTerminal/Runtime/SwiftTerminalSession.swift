import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

@MainActor
protocol TerminalRuntimeControlling: AnyObject {
    func send(_ command: TerminalHostCommandEnvelope) async throws
    func registerFontResource(_ font: TerminalCustomFont) async throws -> String
}

@MainActor
protocol TerminalClipboardProviding {
    func readText() -> String?
    func writeText(_ text: String)
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
public final class SwiftTerminalSession {
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

    private weak var runtimeController: (any TerminalRuntimeControlling)?
    private let clipboardProvider: any TerminalClipboardProviding
    private let linkOpener: any TerminalLinkOpening
    private var pendingCommands: [TerminalHostCommandEnvelope] = []
    private var isRuntimeReady = false
    private var hasAppliedInitialText = false
    private var appearanceState = TerminalAppearanceState()
    private var installedCustomFonts: [TerminalCustomFont] = []
    private var isAppearanceSyncInProgress = false
    private var needsAppearanceSync = false
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
        guard configuration.enablesClipboardIntegration,
              let text = clipboardProvider.readText(),
              !text.isEmpty
        else {
            return
        }

        paste(text)
    }

    public func copySelection() {
        guard configuration.enablesClipboardIntegration else {
            return
        }

        enqueue(.copySelection)
    }

    public func selectAll() {
        enqueue(.selectAll)
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
            pendingCommands.append(command)
            return
        }

        send(
            command,
            with: runtimeController,
            failurePrefix: "host command send failed for \(command.type.rawValue)"
        )
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

            for command in queuedCommands {
                _ = await sendPendingCommand(command, with: runtimeController)
            }
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
