//
//  ContentView.swift
//  SwiftTerminalExample
//
//  Created by GitSwift LLC on 10/4/2026.
//

import Foundation
import Observation
import SwiftTerminal
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class TerminalDemoModel {
    let session: SwiftTerminalSession

    var commandText = "echo SwiftTerminal example ready"
    var searchText = ""
    var caseSensitiveSearch = false
    var usesRegexSearch = false
    var matchesWholeWordSearch = false
    var searchState: SwiftTerminalSearchState
    var fontFamily = "SF Mono"
    var fontSize = 14.0
    var lineHeight = 1.0
    var letterSpacing = 0
    var contentInsetTop = 0.0
    var contentInsetRight = 0.0
    var contentInsetBottom = 0.0
    var contentInsetLeft = 0.0
    var cursorStyle = SwiftTerminalCursorStyle.block
    var cursorBlink = true
    var inactiveCursorStyle = SwiftTerminalInactiveCursorStyle.outline
    var scrollbarVisibility = SwiftTerminalScrollbarVisibility.automatic
    var scrollback = SwiftTerminalConfiguration.defaultScrollback
    var regularFontFileName = "Built-in stack"
    var boldFontFileName = "Not imported"
    var italicFontFileName = "Not imported"
    var boldItalicFontFileName = "Not imported"
    var builtInThemeSearch = ""
    var selectedBuiltInThemeName = ""
    var customTheme: SwiftTerminalTheme
    var appliedTheme: SwiftTerminalTheme
    var latestWindowTitle: String?
    var latestBufferSnapshotSummary = "No buffer snapshot captured"
    var eventLog: [String] = []

    private var sampleBatch = 1
    private var interactiveInputBuffer = ""
    private var suppressedSearchSynchronizations = 0
    private var importedCustomFonts: [TerminalCustomFontVariant: TerminalCustomFont] = [:]

    init() {
        let configuration = SwiftTerminalConfiguration(
            initialText: Self.initialTranscript
        )
        let session = SwiftTerminalSession(configuration: configuration)
        self.session = session
        searchState = session.searchState
        appliedTheme = session.appearance.theme
        customTheme = session.appearance.theme
        contentInsetTop = session.appearance.contentInsets.top
        contentInsetRight = session.appearance.contentInsets.right
        contentInsetBottom = session.appearance.contentInsets.bottom
        contentInsetLeft = session.appearance.contentInsets.left
        cursorStyle = session.appearance.cursorStyle
        cursorBlink = session.appearance.cursorBlink
        inactiveCursorStyle = session.appearance.inactiveCursorStyle
        scrollbarVisibility = session.appearance.scrollbarVisibility
        scrollback = session.configuration.scrollback
        session.onEvent = { [weak self] event in
            self?.record(event)
        }
    }

    var builtInThemeCount: Int {
        SwiftTerminalThemes.builtIn.count
    }

    private var searchOptions: SwiftTerminalSearchOptions {
        SwiftTerminalSearchOptions(
            caseSensitive: caseSensitiveSearch,
            usesRegex: usesRegexSearch,
            matchesWholeWord: matchesWholeWordSearch
        )
    }

    var filteredBuiltInThemes: [SwiftTerminalTheme] {
        let query = builtInThemeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return SwiftTerminalThemes.builtIn
        }

        return SwiftTerminalThemes.builtIn.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var terminalTitle: String {
        let resolvedTitle = (latestWindowTitle ?? session.currentWindowTitle())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedTitle, !resolvedTitle.isEmpty else {
            return "Terminal"
        }

        return resolvedTitle
    }

    func appendCommandLine() {
        guard !commandText.isEmpty else {
            return
        }

        session.write("$ \(commandText)\r\n")
        recordLocal("host.write $ \(commandText)")
    }

    func appendSampleOutput() {
        session.write(Self.sampleChunk(number: sampleBatch))
        recordLocal("host.write sample batch \(sampleBatch)")
        sampleBatch += 1
    }

    func clearTerminal() {
        session.clear()
        interactiveInputBuffer = ""
        session.write(Self.prompt)
        recordLocal("host.clear")
    }

    func focusTerminal() {
        session.focus()
        recordLocal("host.focus")
    }

    func applyFontFamily() {
        var appearance = session.appearance
        appearance.fontFamily = fontFamily
        session.appearance = appearance
        recordLocal("host.setFontFamily \(fontFamily)")
    }

    func applyFontSize() {
        var appearance = session.appearance
        appearance.fontSize = fontSize
        session.appearance = appearance
        recordLocal("host.setFontSize \(String(format: "%.1f", fontSize))")
    }

    func applyLineHeight() {
        var appearance = session.appearance
        appearance.lineHeight = lineHeight
        session.appearance = appearance
        recordLocal("host.setLineHeight \(String(format: "%.2f", lineHeight))")
    }

    func applyLetterSpacing() {
        var appearance = session.appearance
        appearance.letterSpacing = letterSpacing
        session.appearance = appearance
        recordLocal("host.setLetterSpacing \(letterSpacing)")
    }

    func applyScrollback() {
        var configuration = session.configuration
        configuration.terminalContentLimit = scrollback
        session.configuration = configuration
        scrollback = session.configuration.terminalContentLimit
        recordLocal("host.setTerminalContentLimit \(session.configuration.terminalContentLimit)")
    }

    func applyCursorScrollbarAndInsetsSettings() {
        var appearance = session.appearance
        appearance.contentInsets = SwiftTerminalContentInsets(
            top: contentInsetTop,
            right: contentInsetRight,
            bottom: contentInsetBottom,
            left: contentInsetLeft
        )
        appearance.cursorStyle = cursorStyle
        appearance.cursorBlink = cursorBlink
        appearance.inactiveCursorStyle = inactiveCursorStyle
        appearance.scrollbarVisibility = scrollbarVisibility
        session.appearance = appearance
        recordLocal(
            "host.setAppearance insets=(\(Int(contentInsetTop)),\(Int(contentInsetRight)),\(Int(contentInsetBottom)),\(Int(contentInsetLeft))) cursor=\(cursorStyle.rawValue) blink=\(cursorBlink) inactive=\(inactiveCursorStyle.rawValue) scrollbar=\(scrollbarVisibility.rawValue)"
        )
    }

    func applyBuiltInTheme(_ theme: SwiftTerminalTheme) {
        selectedBuiltInThemeName = theme.name
        customTheme = theme
        setTheme(theme)
        recordLocal("host.setTheme builtin \(theme.name)")
    }

    func applyDefaultTheme() {
        selectedBuiltInThemeName = ""
        customTheme = .default
        setTheme(.default)
        recordLocal("host.setTheme \(SwiftTerminalTheme.default.name)")
    }

    func loadCurrentThemeIntoCustomEditor() {
        customTheme = appliedTheme
    }

    func resetCustomThemeEditor() {
        customTheme = .default
    }

    func applyCustomTheme() {
        let normalizedTheme = customTheme.normalized()
        customTheme = normalizedTheme
        selectedBuiltInThemeName = ""
        setTheme(normalizedTheme)
        recordLocal("host.setTheme custom \(normalizedTheme.name)")
    }

    func setCustomThemeName(_ name: String) {
        var updatedTheme = customTheme
        updatedTheme.name = name
        customTheme = updatedTheme
    }

    func customThemeValue(for role: ThemeColorRole) -> String {
        role.value(in: customTheme)
    }

    func setCustomThemeValue(_ value: String, for role: ThemeColorRole) {
        var updatedTheme = customTheme
        role.assign(value, to: &updatedTheme)
        customTheme = updatedTheme
    }

    func customThemeColor(for role: ThemeColorRole) -> Color {
        ThemeColorCodec.color(from: customThemeValue(for: role))
    }

    func setCustomThemeColor(_ color: Color, for role: ThemeColorRole) {
        setCustomThemeValue(ThemeColorCodec.string(from: color), for: role)
    }

    func importCustomFont(
        from url: URL,
        variant: TerminalCustomFontVariant
    ) {
        guard let format = TerminalFontFormat(pathExtension: url.pathExtension) else {
            recordLocal("host.registerCustomFont unsupported \(url.lastPathComponent)")
            return
        }

        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let trimmedFamily = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedFamily: String
            if !trimmedFamily.isEmpty {
                resolvedFamily = trimmedFamily
            } else if let existingFamily = importedCustomFonts.values.first?.family {
                resolvedFamily = existingFamily
            } else {
                resolvedFamily = url.deletingPathExtension().lastPathComponent
            }

            importedCustomFonts[variant] = TerminalCustomFont(
                family: resolvedFamily,
                format: format,
                data: data,
                variant: variant
            )
            session.registerCustomFontSet(sortedImportedCustomFonts())
            fontFamily = resolvedFamily
            setFontFileName(url.lastPathComponent, for: variant)
            recordLocal(
                "host.registerCustomFontSet \(resolvedFamily) \(variant.rawValue) from \(url.lastPathComponent)"
            )
        } catch {
            recordLocal("host.registerCustomFontSet failed \(error.localizedDescription)")
        }
    }

    private func sortedImportedCustomFonts() -> [TerminalCustomFont] {
        TerminalCustomFontVariant.allCases
            .compactMap { importedCustomFonts[$0] }
    }

    private func setFontFileName(
        _ fileName: String,
        for variant: TerminalCustomFontVariant
    ) {
        switch variant {
        case .regular:
            regularFontFileName = fileName
        case .bold:
            boldFontFileName = fileName
        case .italic:
            italicFontFileName = fileName
        case .boldItalic:
            boldItalicFontFileName = fileName
        }
    }

    func pasteClipboard() {
        session.pasteFromClipboard()
        recordLocal("host.pasteFromClipboard")
    }

    func copySelection() {
        session.copySelection()
        recordLocal("host.copySelection")
    }

    func selectAll() {
        session.selectAll()
        recordLocal("host.selectAll")
    }

    func captureBufferSnapshot() {
        Task {
            do {
                let snapshot = try await session.currentBufferSnapshot()
                latestBufferSnapshotSummary =
                    "\(snapshot.lines.count)/\(snapshot.totalLineCount) \(snapshot.bufferType.rawValue) buffer lines, viewport \(snapshot.viewportY), \(snapshot.cols)x\(snapshot.rows)"
                recordLocal("host.currentBufferSnapshot \(latestBufferSnapshotSummary)")
            } catch {
                latestBufferSnapshotSummary = "Snapshot failed: \(error.localizedDescription)"
                recordLocal("host.currentBufferSnapshot failed \(error.localizedDescription)")
            }
        }
    }

    func emitBell() {
        session.write("\u{0007}")
        recordLocal("host.write bell")
    }

    func setDemoWindowTitle() {
        let title = "SwiftTerminal Demo Session"
        session.write("\u{001B}]0;\(title)\u{0007}")
        recordLocal("host.write title \(title)")
    }

    func openSearch() {
        session.showSearch()
        recordLocal("host.showSearch")
    }

    func clearSearch() {
        session.clearSearch()
        recordLocal("host.clearSearch")
    }

    func searchNext() {
        guard !searchText.isEmpty else {
            clearSearch()
            return
        }

        session.searchNext(searchText, options: searchOptions)
        recordLocal("host.searchNext \"\(searchText)\"")
    }

    func searchPrevious() {
        guard !searchText.isEmpty else {
            clearSearch()
            return
        }

        session.searchPrevious(searchText, options: searchOptions)
        recordLocal("host.searchPrevious \"\(searchText)\"")
    }

    func synchronizeSearchPreview() {
        guard !consumeSuppressedSearchSynchronization() else {
            return
        }

        guard !searchText.isEmpty else {
            session.clearSearch()
            return
        }

        session.searchNext(searchText, options: searchOptions)
    }

    private func setTheme(_ theme: SwiftTerminalTheme) {
        var appearance = session.appearance
        appearance.theme = theme
        session.appearance = appearance
        appliedTheme = theme
    }

    private func consumeSuppressedSearchSynchronization() -> Bool {
        guard suppressedSearchSynchronizations > 0 else {
            return false
        }

        suppressedSearchSynchronizations -= 1
        return true
    }

    private func applyRuntimeSearchState(_ updatedSearchState: SwiftTerminalSearchState) {
        let changedFieldCount =
            (searchText != updatedSearchState.query ? 1 : 0) +
            (caseSensitiveSearch != updatedSearchState.options.caseSensitive ? 1 : 0) +
            (usesRegexSearch != updatedSearchState.options.usesRegex ? 1 : 0) +
            (matchesWholeWordSearch != updatedSearchState.options.matchesWholeWord ? 1 : 0)

        if changedFieldCount > 0 {
            suppressedSearchSynchronizations += changedFieldCount
        }

        searchState = updatedSearchState
        searchText = updatedSearchState.query
        caseSensitiveSearch = updatedSearchState.options.caseSensitive
        usesRegexSearch = updatedSearchState.options.usesRegex
        matchesWholeWordSearch = updatedSearchState.options.matchesWholeWord
    }

    var searchRuntimeSummary: String {
        let visibility = searchState.isVisible ? "Visible" : "Hidden"

        if let errorMessage = searchState.errorMessage {
            return "Runtime search UI: \(visibility) • \(errorMessage)"
        }

        guard !searchState.query.isEmpty else {
            return "Runtime search UI: \(visibility) • No active query"
        }

        return "Runtime search UI: \(visibility) • \(searchState.resultIndex)/\(searchState.resultCount) matches"
    }

    private func searchStateLogLine(_ state: SwiftTerminalSearchState) -> String {
        let visibility = state.isVisible ? "visible" : "hidden"

        if let errorMessage = state.errorMessage {
            return "runtime.search_state \(visibility) error=\(errorMessage)"
        }

        guard !state.query.isEmpty else {
            return "runtime.search_state \(visibility) query=<empty>"
        }

        return "runtime.search_state \(visibility) \(state.resultIndex)/\(state.resultCount) \"\(state.query)\""
    }

    private func record(_ event: TerminalRuntimeEventEnvelope) {
        let line: String

        switch event.type {
        case .ready:
            line = "runtime.ready"
        case .input:
            handleRuntimeInput(event.text ?? "")
            line = "runtime.input \(event.text ?? "")"
        case .selectionChanged:
            line = "runtime.selection_changed"
        case .resize:
            line = "runtime.resize \(event.cols ?? 0)x\(event.rows ?? 0)"
        case .searchResults:
            return
        case .searchStateChanged:
            let updatedSearchState = session.searchState
            applyRuntimeSearchState(updatedSearchState)
            line = searchStateLogLine(updatedSearchState)
        case .bufferSnapshot:
            return
        case .titleChanged:
            latestWindowTitle = session.currentWindowTitle()
            let title = latestWindowTitle ?? event.title ?? ""
            line = title.isEmpty ? "runtime.title_changed <empty>" : "runtime.title_changed \(title)"
        case .bell:
            line = "runtime.bell"
        case .linkActivated:
            line = "runtime.link_activated \(event.url ?? "")"
        case .clipboardReadRequest:
            line = "runtime.clipboard_read_request \(event.requestID ?? "")"
        case .clipboardWriteRequest:
            line = "runtime.clipboard_write_request \(event.requestID ?? "")"
        case .log:
            line = "runtime.log \(event.message ?? "")"
        }

        eventLog.insert(line, at: 0)
        eventLog = Array(eventLog.prefix(12))
    }

    private func recordLocal(_ line: String) {
        eventLog.insert(line, at: 0)
        eventLog = Array(eventLog.prefix(12))
    }

    private func handleRuntimeInput(_ text: String) {
        for character in text {
            if let scalar = character.unicodeScalars.first,
               character.unicodeScalars.count == 1 {
                switch scalar.value {
            case 3:
                interactiveInputBuffer = ""
                session.write("^C\r\n\(Self.prompt)")
                continue
            case 8, 127:
                guard !interactiveInputBuffer.isEmpty else {
                    continue
                }

                let removedCharacter = interactiveInputBuffer.removeLast()
                session.write(Self.eraseSequence(for: removedCharacter))
                continue
            case 10, 13:
                let submittedCommand = interactiveInputBuffer
                interactiveInputBuffer = ""
                session.write("\r\n")
                if let response = Self.simulatedResponse(for: submittedCommand) {
                    session.write(response)
                }
                session.write(Self.prompt)
                continue
            default:
                if CharacterSet.controlCharacters.contains(scalar) {
                    continue
                }
                }
            }

            guard !character.unicodeScalars.allSatisfy({
                CharacterSet.controlCharacters.contains($0)
            }) else {
                continue
            }

            interactiveInputBuffer.append(character)
            session.write(String(character))
        }
    }

    private static func eraseSequence(for character: Character) -> String {
        let width = max(1, terminalColumnWidth(of: character))
        return String(repeating: "\u{8}", count: width)
            + String(repeating: " ", count: width)
            + String(repeating: "\u{8}", count: width)
    }

    private static func terminalColumnWidth(of character: Character) -> Int {
        var width = 0

        for scalar in character.unicodeScalars {
            if isZeroWidthScalar(scalar) {
                continue
            }

            if isWideScalar(scalar) {
                width = max(width, 2)
            } else {
                width += 1
            }
        }

        return max(width, 1)
    }

    private static func isZeroWidthScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0300...0x036F,
             0x0483...0x0489,
             0x0591...0x05BD,
             0x05BF,
             0x05C1...0x05C2,
             0x05C4...0x05C5,
             0x05C7,
             0x0610...0x061A,
             0x064B...0x065F,
             0x0670,
             0x06D6...0x06DC,
             0x06DF...0x06E4,
             0x06E7...0x06E8,
             0x06EA...0x06ED,
             0x0711,
             0x0730...0x074A,
             0x07A6...0x07B0,
             0x07EB...0x07F3,
             0x0816...0x0819,
             0x081B...0x0823,
             0x0825...0x0827,
             0x0829...0x082D,
             0x0859...0x085B,
             0x08D3...0x08E1,
             0x08E3...0x0903,
             0x093A,
             0x093C,
             0x0941...0x0948,
             0x094D,
             0x0951...0x0957,
             0x0962...0x0963,
             0x0981,
             0x09BC,
             0x09C1...0x09C4,
             0x09CD,
             0x09E2...0x09E3,
             0x0A01...0x0A02,
             0x0A3C,
             0x0A41...0x0A42,
             0x0A47...0x0A48,
             0x0A4B...0x0A4D,
             0x0A51,
             0x0A70...0x0A71,
             0x0A75,
             0x0A81...0x0A82,
             0x0ABC,
             0x0AC1...0x0AC5,
             0x0AC7...0x0AC8,
             0x0ACD,
             0x0AE2...0x0AE3,
             0x0B01,
             0x0B3C,
             0x0B3F,
             0x0B41...0x0B44,
             0x0B4D,
             0x0B56,
             0x0B62...0x0B63,
             0x0B82,
             0x0BC0,
             0x0BCD,
             0x0C00,
             0x0C04,
             0x0C3E...0x0C40,
             0x0C46...0x0C48,
             0x0C4A...0x0C4D,
             0x0C55...0x0C56,
             0x0C62...0x0C63,
             0x0C81,
             0x0CBC,
             0x0CBF,
             0x0CC6,
             0x0CCC...0x0CCD,
             0x0CE2...0x0CE3,
             0x0D00...0x0D01,
             0x0D3B...0x0D3C,
             0x0D41...0x0D44,
             0x0D4D,
             0x0D62...0x0D63,
             0x0DCA,
             0x0DD2...0x0DD4,
             0x0DD6,
             0x0E31,
             0x0E34...0x0E3A,
             0x0E47...0x0E4E,
             0x0EB1,
             0x0EB4...0x0EBC,
             0x0EC8...0x0ECD,
             0x0F18...0x0F19,
             0x0F35,
             0x0F37,
             0x0F39,
             0x0F71...0x0F7E,
             0x0F80...0x0F84,
             0x0F86...0x0F87,
             0x0F8D...0x0F97,
             0x0F99...0x0FBC,
             0x0FC6,
             0x102D...0x1030,
             0x1032...0x1037,
             0x1039...0x103A,
             0x103D...0x103E,
             0x1058...0x1059,
             0x105E...0x1060,
             0x1071...0x1074,
             0x1082,
             0x1085...0x1086,
             0x108D,
             0x109D,
             0x135D...0x135F,
             0x1712...0x1714,
             0x1732...0x1734,
             0x1752...0x1753,
             0x1772...0x1773,
             0x17B4...0x17B5,
             0x17B7...0x17BD,
             0x17C6,
             0x17C9...0x17D3,
             0x17DD,
             0x180B...0x180D,
             0x1885...0x1886,
             0x18A9,
             0x1920...0x1922,
             0x1927...0x1928,
             0x1932,
             0x1939...0x193B,
             0x1A17...0x1A18,
             0x1A1B,
             0x1A56,
             0x1A58...0x1A5E,
             0x1A60,
             0x1A62,
             0x1A65...0x1A6C,
             0x1A73...0x1A7C,
             0x1A7F,
             0x1AB0...0x1AFF,
             0x1B00...0x1B03,
             0x1B34,
             0x1B36...0x1B3A,
             0x1B3C,
             0x1B42,
             0x1B6B...0x1B73,
             0x1B80...0x1B81,
             0x1BA2...0x1BA5,
             0x1BA8...0x1BA9,
             0x1BAB...0x1BAD,
             0x1BE6,
             0x1BE8...0x1BE9,
             0x1BED,
             0x1BEF...0x1BF1,
             0x1C2C...0x1C33,
             0x1C36...0x1C37,
             0x1CD0...0x1CD2,
             0x1CD4...0x1CE0,
             0x1CE2...0x1CE8,
             0x1CED,
             0x1CF4,
             0x1CF8...0x1CF9,
             0x1DC0...0x1DFF,
             0x200B...0x200F,
             0x202A...0x202E,
             0x2060...0x2064,
             0x2066...0x206F,
             0x20D0...0x20FF,
             0xFE00...0xFE0F,
             0xFE20...0xFE2F,
             0xFEFF,
             0xFFF9...0xFFFB:
            return true
        default:
            return false
        }
    }

    private static func isWideScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,
             0x231A...0x231B,
             0x2329...0x232A,
             0x23E9...0x23EC,
             0x23F0,
             0x23F3,
             0x25FD...0x25FE,
             0x2614...0x2615,
             0x2648...0x2653,
             0x267F,
             0x2693,
             0x26A1,
             0x26AA...0x26AB,
             0x26BD...0x26BE,
             0x26C4...0x26C5,
             0x26CE,
             0x26D4,
             0x26EA,
             0x26F2...0x26F3,
             0x26F5,
             0x26FA,
             0x26FD,
             0x2705,
             0x270A...0x270B,
             0x2728,
             0x274C,
             0x274E,
             0x2753...0x2755,
             0x2757,
             0x2795...0x2797,
             0x27B0,
             0x27BF,
             0x2B1B...0x2B1C,
             0x2B50,
             0x2B55,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F004,
             0x1F0CF,
             0x1F18E,
             0x1F191...0x1F19A,
             0x1F200...0x1F202,
             0x1F210...0x1F23B,
             0x1F240...0x1F248,
             0x1F250...0x1F251,
             0x1F300...0x1FAFF,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }

    private static func simulatedResponse(for command: String) -> String? {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            return nil
        }

        switch trimmedCommand {
        case "help":
            return """
            Available demo commands:
            - help
            - clear
            - bell
            - theme
            - fonts
            - title <text>
            - echo <text>

            """
        case "clear":
            return "(Use the host Clear button if you want a full terminal reset.)\r\n"
        case "bell":
            return "\u{0007}"
        case "theme":
            return "Use the Theme Controls panel above to switch built-in themes or edit a custom palette.\r\n"
        case "fonts":
            return "Use the Font Controls panel above to change family, size, spacing, or import regular/bold/italic faces for one custom font family.\r\n"
        default:
            if trimmedCommand.hasPrefix("title ") {
                let title = String(trimmedCommand.dropFirst(6))
                return "\u{001B}]0;\(title)\u{0007}"
            }

            if trimmedCommand.hasPrefix("echo ") {
                return "\(trimmedCommand.dropFirst(5))\r\n"
            }

            return "demo: \(trimmedCommand)\r\n"
        }
    }

    private static let prompt = "$ "

    #if os(macOS)
    private static let linkInteractionHint = "Hover the example link for a moment to verify underline and Follow link (cmd + click), then Cmd-click to open it"
    #else
    private static let linkInteractionHint = "Tap the example link to verify the native link menu"
    #endif

    private static let initialTranscript = """
    SwiftTerminal example
    ---------------------
    This app is the manual validation harness for the package.
    Search targets: terminal terminal Terminal
    Link test: https://example.com/docs
    ANSI sample: \u{001B}[32mgreen\u{001B}[0m \u{001B}[33myellow\u{001B}[0m \u{001B}[36mcyan\u{001B}[0m

    Try these paths:
    - Press Cmd-F to open the built-in search UI
    - Select a single-line word, then press Cmd-F to prefill the search query from the selection
    - Use Enter, Shift-Enter, and the search buttons inside the search UI to jump between matches
    - Use the search buttons to toggle case, whole-word, and regex search
    - Press Ctrl-A, Ctrl-F, Ctrl-C, Cmd-C, Cmd-V, Cmd-A, and shifted punctuation to verify terminal input stays on the default xterm path
    - Run `bell` or click Emit Bell to verify runtime bell events
    - Run `title demo-shell` or click Set Demo Title to verify runtime title-change events
    - Apply a built-in iTerm2 theme or edit a custom theme from the Theme Controls section
    - Apply font family, size, line height, and letter spacing from the Font Controls section
    - Switch scrollbar visibility, content padding, and focused or inactive cursor styles from the Cursor & Scrollbar Controls section
    - Import a local .ttf, .otf, .woff, or .woff2 file without starting a web server
    - Use the host controls to send text and search commands
    - \(linkInteractionHint)

    $ 
    """

    private static func sampleChunk(number: Int) -> String {
        """
        Batch \(number)
        --------
        swift terminal runtime \(number)
        search needle \(number % 2 == 0 ? "Terminal" : "terminal")
        timestamp marker \(number)
        \u{001B}[35mcolored line \(number)\u{001B}[0m

        """
    }
}

@MainActor
struct ContentView: View {
    private enum ExamplePane: String, CaseIterable, Identifiable {
        case terminal
        case session
        case theme
        case search
        case events

        var id: Self { self }

        var title: String {
            switch self {
            case .terminal:
                "Terminal"
            case .session:
                "Session"
            case .theme:
                "Theme"
            case .search:
                "Search"
            case .events:
                "Events"
            }
        }

        var icon: String {
            switch self {
            case .terminal:
                "terminal"
            case .session:
                "slider.horizontal.3"
            case .theme:
                "paintpalette"
            case .search:
                "magnifyingglass"
            case .events:
                "list.bullet.rectangle"
            }
        }
    }

    @State private var model = TerminalDemoModel()
    @State private var showsFontImporter = false
    @State private var fontImportTarget = TerminalCustomFontVariant.regular
    @State private var selectedPane: ExamplePane? = .terminal

    private static let supportedFontTypes: [UTType] = [
        UTType(filenameExtension: "ttf"),
        UTType(filenameExtension: "otf"),
        UTType(filenameExtension: "woff"),
        UTType(filenameExtension: "woff2"),
    ]
    .compactMap { $0 }

    private let themeEditorColumns = [
        GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top),
    ]

    var body: some View {
        NavigationSplitView {
            List(ExamplePane.allCases, selection: $selectedPane) { pane in
                NavigationLink(value: pane) {
                    Label(pane.title, systemImage: pane.icon)
                }
            }
            .navigationTitle("SwiftTerminal")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
        } detail: {
            detailContent(for: selectedPane ?? .terminal)
                .navigationTitle(detailTitle(for: selectedPane ?? .terminal))
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(
            isPresented: $showsFontImporter,
            allowedContentTypes: Self.supportedFontTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else {
                    return
                }
                model.importCustomFont(from: url, variant: fontImportTarget)
            case let .failure(error):
                model.eventLog.insert("host.importFont failed \(error.localizedDescription)", at: 0)
                model.eventLog = Array(model.eventLog.prefix(12))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SwiftTerminal Example")
                .font(.largeTitle.weight(.semibold))
            Text("This app is for manual verification of the package UI and runtime behavior. Use the sidebar to switch between the full terminal surface and the supporting control pages.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detailContent(for pane: ExamplePane) -> some View {
        switch pane {
        case .terminal:
            terminalDetail
        case .session:
            scrollDetail {
                header
                commandPanel
                configurationPanel
                fontPanel
                appearancePanel
            }
        case .theme:
            scrollDetail {
                header
                themePanel
            }
        case .search:
            scrollDetail {
                header
                searchPanel
            }
        case .events:
            scrollDetail {
                header
                eventPanel
            }
        }
    }

    private func detailTitle(for pane: ExamplePane) -> String {
        switch pane {
        case .terminal:
            model.terminalTitle
        default:
            pane.title
        }
    }

    private func scrollDetail<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var commandPanel: some View {
        GroupBox("Host Controls") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Command or text to append", text: $model.commandText)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Write Line") {
                        model.appendCommandLine()
                    }

                    Button("Append Sample Output") {
                        model.appendSampleOutput()
                    }

                    Button("Focus Terminal") {
                        model.focusTerminal()
                    }

                    Button("Clear") {
                        model.clearTerminal()
                    }
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Button("Paste Clipboard") {
                        model.pasteClipboard()
                    }

                    Button("Copy Selection") {
                        model.copySelection()
                    }

                    Button("Select All") {
                        model.selectAll()
                    }

                    Button("Emit Bell") {
                        model.emitBell()
                    }

                    Button("Set Demo Title") {
                        model.setDemoWindowTitle()
                    }
                }
                .buttonStyle(.bordered)

                HStack {
                    Button("Capture Buffer Snapshot") {
                        model.captureBufferSnapshot()
                    }

                    Text(model.latestBufferSnapshotSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var themePanel: some View {
        GroupBox("Theme Controls") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Built-in themes are generated from \(SwiftTerminalThemes.builtInSourceName). This snapshot includes \(model.builtInThemeCount) themes and can be mixed with custom edits before applying.")
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 12) {
                    TextField("Filter built-in themes", text: $model.builtInThemeSearch)
                        .textFieldStyle(.roundedBorder)

                    Button("Apply SwiftTerminal Default") {
                        model.applyDefaultTheme()
                    }

                    Link("Source Repository", destination: SwiftTerminalThemes.builtInSourceRepositoryURL)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.filteredBuiltInThemes) { theme in
                            Button {
                                model.applyBuiltInTheme(theme)
                            } label: {
                                HStack(spacing: 12) {
                                    ThemeSwatchesView(theme: theme)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(theme.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text(theme.background)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if model.selectedBuiltInThemeName == theme.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            model.selectedBuiltInThemeName == theme.name
                                            ? Color.accentColor.opacity(0.12)
                                            : Color.primary.opacity(0.04)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 240)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Theme Editor")
                        .font(.headline)

                    Text("Load the current theme or any built-in theme into this editor, tweak the key colors and ANSI palette, then apply the result to the live terminal.")
                        .foregroundStyle(.secondary)

                    TextField(
                        "Custom theme name",
                        text: Binding(
                            get: { model.customTheme.name },
                            set: { model.setCustomThemeName($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    LazyVGrid(columns: themeEditorColumns, spacing: 12) {
                        ForEach(ThemeColorRole.primaryRoles) { role in
                            ThemeColorEditorRow(
                                role: role,
                                text: customThemeTextBinding(for: role),
                                color: customThemeColorBinding(for: role)
                            )
                        }
                    }

                    DisclosureGroup("ANSI Palette") {
                        LazyVGrid(columns: themeEditorColumns, spacing: 12) {
                            ForEach(ThemeColorRole.ansiRoles) { role in
                                ThemeColorEditorRow(
                                    role: role,
                                    text: customThemeTextBinding(for: role),
                                    color: customThemeColorBinding(for: role)
                                )
                            }
                        }
                        .padding(.top, 12)
                    }

                    HStack {
                        Button("Load Current Theme") {
                            model.loadCurrentThemeIntoCustomEditor()
                        }

                        Button("Reset Editor") {
                            model.resetCustomThemeEditor()
                        }

                        Button("Apply Custom Theme") {
                            model.applyCustomTheme()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var fontPanel: some View {
        GroupBox("Font Controls") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Font family", text: $model.fontFamily)
                        .textFieldStyle(.roundedBorder)

                    Stepper(value: $model.fontSize, in: 8 ... 28, step: 1) {
                        Text("Size \(Int(model.fontSize))")
                            .frame(minWidth: 80, alignment: .leading)
                    }
                }

                HStack {
                    Stepper(value: $model.lineHeight, in: 1.0 ... 2.0, step: 0.1) {
                        Text("Line Height \(String(format: "%.1f", model.lineHeight))")
                            .frame(minWidth: 140, alignment: .leading)
                    }

                    Stepper(value: $model.letterSpacing, in: 0 ... 8, step: 1) {
                        Text("Letter Spacing \(model.letterSpacing)")
                            .frame(minWidth: 150, alignment: .leading)
                    }
                }

                HStack {
                    Button("Apply Family") {
                        model.applyFontFamily()
                    }

                    Button("Apply Size") {
                        model.applyFontSize()
                    }

                    Button("Apply Line Height") {
                        model.applyLineHeight()
                    }

                    Button("Apply Letter Spacing") {
                        model.applyLetterSpacing()
                    }
                }
                .buttonStyle(.bordered)

                HStack {
                    Button("Import Regular") {
                        fontImportTarget = .regular
                        showsFontImporter = true
                    }

                    Button("Import Bold") {
                        fontImportTarget = .bold
                        showsFontImporter = true
                    }

                    Button("Import Italic") {
                        fontImportTarget = .italic
                        showsFontImporter = true
                    }

                    Button("Import Bold Italic") {
                        fontImportTarget = .boldItalic
                        showsFontImporter = true
                    }
                }
                .buttonStyle(.bordered)

                Text("Import one face at a time for the same family. When regular, bold, italic, or bold italic files are all present, the runtime can match the right face instead of reusing one file for every style.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Regular: \(model.regularFontFileName)")
                    Text("Bold: \(model.boldFontFileName)")
                    Text("Italic: \(model.italicFontFileName)")
                    Text("Bold Italic: \(model.boldItalicFontFileName)")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var configurationPanel: some View {
        GroupBox("Session Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: $model.scrollback, in: 0 ... 50_000, step: 500) {
                    Text("Content limit \(model.scrollback) lines")
                        .frame(minWidth: 190, alignment: .leading)
                }

                Text("This controls xterm's retained terminal content. `0` disables scrollback, larger values keep more history for buffer snapshots and use more memory.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Apply Content Limit") {
                    model.applyScrollback()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var searchPanel: some View {
        GroupBox("Search Controls") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Search text", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.searchNext()
                        }
                }

                HStack {
                    Toggle("Case Sensitive", isOn: $model.caseSensitiveSearch)
                        .toggleStyle(.switch)

                    Toggle("Whole Word", isOn: $model.matchesWholeWordSearch)
                        .toggleStyle(.switch)

                    Toggle("Regex", isOn: $model.usesRegexSearch)
                        .toggleStyle(.switch)
                }

                HStack {
                    Button("Open Search UI") {
                        model.openSearch()
                    }

                    Button("Clear Search") {
                        model.clearSearch()
                    }

                    Button("Previous") {
                        model.searchPrevious()
                    }

                    Button("Next") {
                        model.searchNext()
                    }
                }
                .buttonStyle(.bordered)

                Text(model.searchRuntimeSummary)
                    .font(.footnote)
                    .foregroundStyle(
                        model.searchState.errorMessage == nil ? Color.secondary : Color.red
                    )
            }
        }
        .onChange(of: model.searchText) {
            model.synchronizeSearchPreview()
        }
        .onChange(of: model.caseSensitiveSearch) {
            model.synchronizeSearchPreview()
        }
        .onChange(of: model.matchesWholeWordSearch) {
            model.synchronizeSearchPreview()
        }
        .onChange(of: model.usesRegexSearch) {
            model.synchronizeSearchPreview()
        }
    }

    private var appearancePanel: some View {
        GroupBox("Cursor, Scrollbar & Content Insets") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    Picker("Focused Cursor", selection: $model.cursorStyle) {
                        ForEach(SwiftTerminalCursorStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Blink", isOn: $model.cursorBlink)
                        .toggleStyle(.switch)
                }

                HStack(alignment: .center, spacing: 16) {
                    Picker("Inactive Cursor", selection: $model.inactiveCursorStyle) {
                        ForEach(SwiftTerminalInactiveCursorStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Picker("Scrollbar", selection: $model.scrollbarVisibility) {
                        ForEach(SwiftTerminalScrollbarVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.displayName).tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(value: $model.contentInsetTop, in: 0 ... 48, step: 2) {
                            Text("Top \(Int(model.contentInsetTop))")
                                .frame(minWidth: 120, alignment: .leading)
                        }

                        Stepper(value: $model.contentInsetBottom, in: 0 ... 48, step: 2) {
                            Text("Bottom \(Int(model.contentInsetBottom))")
                                .frame(minWidth: 120, alignment: .leading)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(value: $model.contentInsetLeft, in: 0 ... 48, step: 2) {
                            Text("Left \(Int(model.contentInsetLeft))")
                                .frame(minWidth: 120, alignment: .leading)
                        }

                        Stepper(value: $model.contentInsetRight, in: 0 ... 48, step: 2) {
                            Text("Right \(Int(model.contentInsetRight))")
                                .frame(minWidth: 120, alignment: .leading)
                        }
                    }
                }

                Text("These insets keep the extra space on the same terminal background instead of revealing the host background behind the text.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Apply Cursor, Scrollbar & Insets") {
                    model.applyCursorScrollbarAndInsetsSettings()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var terminalDetail: some View {
        ZStack {
            ThemeColorCodec.color(from: model.appliedTheme.background)
                .ignoresSafeArea()

            SwiftTerminalView(session: model.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var eventPanel: some View {
        GroupBox("Recent Events") {
            VStack(alignment: .leading, spacing: 8) {
                if model.eventLog.isEmpty {
                    Text("No events yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.eventLog.enumerated()), id: \.offset) { entry in
                        Text(entry.element)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func customThemeTextBinding(for role: ThemeColorRole) -> Binding<String> {
        Binding(
            get: { model.customThemeValue(for: role) },
            set: { model.setCustomThemeValue($0, for: role) }
        )
    }

    private func customThemeColorBinding(for role: ThemeColorRole) -> Binding<Color> {
        Binding(
            get: { model.customThemeColor(for: role) },
            set: { model.setCustomThemeColor($0, for: role) }
        )
    }
}

#Preview {
    ContentView()
}

private extension SwiftTerminalCursorStyle {
    var displayName: String {
        switch self {
        case .block:
            "Block"
        case .underline:
            "Underline"
        case .bar:
            "Bar"
        }
    }
}

private extension SwiftTerminalInactiveCursorStyle {
    var displayName: String {
        switch self {
        case .outline:
            "Outline"
        case .block:
            "Block"
        case .bar:
            "Bar"
        case .underline:
            "Underline"
        case .hidden:
            "Hidden"
        }
    }
}

private extension SwiftTerminalScrollbarVisibility {
    var displayName: String {
        switch self {
        case .automatic:
            "Automatic"
        case .visible:
            "Visible"
        case .hidden:
            "Hidden"
        }
    }
}
