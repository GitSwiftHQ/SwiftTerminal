import Foundation
import Testing
@testable import SwiftTerminal

@MainActor
private final class RuntimeControllerSpy: TerminalRuntimeControlling {
    var commands: [TerminalHostCommandEnvelope] = []
    var registeredFonts: [TerminalCustomFont] = []

    func send(_ command: TerminalHostCommandEnvelope) async throws {
        commands.append(command)
    }

    func registerFontResource(_ font: TerminalCustomFont) async throws -> String {
        registeredFonts.append(font)
        return "swiftterminalfont://font/\(registeredFonts.count)"
    }
}

@MainActor
private final class ClipboardProviderSpy: TerminalClipboardProviding {
    var textToRead: String?
    var writtenTexts: [String] = []

    func readText() -> String? {
        textToRead
    }

    func writeText(_ text: String) {
        writtenTexts.append(text)
    }
}

@MainActor
private final class LinkOpenerSpy: TerminalLinkOpening {
    var openedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}

@MainActor
private func waitForAsyncBridge() async throws {
    try await Task.sleep(for: .milliseconds(10))
}

private func expectedAppearanceCommand(
    fontFamily: String,
    fontSize: Double,
    lineHeight: Double,
    letterSpacing: Int,
    contentInsets: SwiftTerminalContentInsets = .zero,
    cursorStyle: SwiftTerminalCursorStyle = .block,
    cursorBlink: Bool = true,
    inactiveCursorStyle: SwiftTerminalInactiveCursorStyle = .outline,
    scrollbarVisibility: SwiftTerminalScrollbarVisibility = .automatic,
    theme: SwiftTerminalTheme = .default
) -> TerminalHostCommandEnvelope {
    .setAppearance(
        fontFamily: fontFamily,
        fontSize: fontSize,
        lineHeight: lineHeight,
        letterSpacing: letterSpacing,
        contentInsets: contentInsets,
        cursorStyle: cursorStyle,
        cursorBlink: cursorBlink,
        inactiveCursorStyle: inactiveCursorStyle,
        scrollbarVisibility: scrollbarVisibility,
        theme: theme
    )
}

private func expectedConfigurationCommand(
    enablesSearchUI: Bool = true,
    enablesKeyboardShortcuts: Bool = true,
    enablesClipboardIntegration: Bool = true,
    scrollback: Int = SwiftTerminalConfiguration.defaultScrollback
) -> TerminalHostCommandEnvelope {
    .setFeatureFlags(
        enablesSearchUI: enablesSearchUI,
        enablesKeyboardShortcuts: enablesKeyboardShortcuts,
        enablesClipboardIntegration: enablesClipboardIntegration,
        scrollback: scrollback
    )
}

@Test
@MainActor
func initialTextIsOnlyAppliedOnFirstReady() async throws {
    let session = SwiftTerminalSession(
        configuration: SwiftTerminalConfiguration(initialText: "hello\r\n")
    )
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            expectedConfigurationCommand(),
            expectedAppearanceCommand(
                fontFamily: #"SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace"#,
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0
            ),
            .write("hello\r\n"),
        ]
    )

    runtime.commands.removeAll()
    session.runtimeDidTerminate()
    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            expectedConfigurationCommand(),
            expectedAppearanceCommand(
                fontFamily: #"SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace"#,
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )
}

@Test
@MainActor
func customInitialAppearanceBootstrapsOnFirstReady() async throws {
    let theme = try #require(SwiftTerminalThemes.builtIn(named: "Dracula"))
    let appearance = SwiftTerminalAppearance(
        fontFamily: "Fira Code",
        fontSize: 16,
        lineHeight: 1.3,
        letterSpacing: 2,
        contentInsets: .init(top: 12, right: 10, bottom: 8, left: 6),
        theme: theme
    )
    let session = SwiftTerminalSession(appearance: appearance)
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            expectedConfigurationCommand(),
            expectedAppearanceCommand(
                fontFamily: "Fira Code",
                fontSize: 16,
                lineHeight: 1.3,
                letterSpacing: 2,
                contentInsets: .init(top: 12, right: 10, bottom: 8, left: 6),
                theme: theme
            ),
        ]
    )
}

@Test
@MainActor
func initialAppearanceCommandUsesSessionAppearance() async throws {
    let theme = SwiftTerminalTheme(
        name: "Initial Test",
        foreground: "#E5E9F0",
        background: "#2E3440",
        cursor: "#88C0D0"
    )
    let appearance = SwiftTerminalAppearance(
        fontFamily: "JetBrains Mono",
        fontSize: 15,
        lineHeight: 1.2,
        letterSpacing: 1,
        contentInsets: .init(top: 2, right: 4, bottom: 6, left: 8),
        cursorStyle: .bar,
        cursorBlink: false,
        inactiveCursorStyle: .hidden,
        scrollbarVisibility: .hidden,
        theme: theme
    )
    let session = SwiftTerminalSession(appearance: appearance)

    #expect(
        session.initialAppearanceCommand() == expectedAppearanceCommand(
            fontFamily: "JetBrains Mono",
            fontSize: 15,
            lineHeight: 1.2,
            letterSpacing: 1,
            contentInsets: .init(top: 2, right: 4, bottom: 6, left: 8),
            cursorStyle: .bar,
            cursorBlink: false,
            inactiveCursorStyle: .hidden,
            scrollbarVisibility: .hidden,
            theme: theme
        )
    )
}

@Test
@MainActor
func pendingCommandsFlushAfterRuntimeReload() async throws {
    let session = SwiftTerminalSession(
        configuration: SwiftTerminalConfiguration(initialText: "hello\r\n")
    )
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.runtimeDidTerminate()
    session.write("after-reload\r\n")

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            expectedConfigurationCommand(),
            expectedAppearanceCommand(
                fontFamily: #"SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace"#,
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0
            ),
            .write("after-reload\r\n"),
        ]
    )
}

@Test
@MainActor
func customScrollbackBootstrapsOnFirstReady() async throws {
    let session = SwiftTerminalSession(
        configuration: SwiftTerminalConfiguration(scrollback: 5000)
    )
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            expectedConfigurationCommand(scrollback: 5000),
            expectedAppearanceCommand(
                fontFamily: #"SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace"#,
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )
}

@Test
@MainActor
func configurationPropertyAssignmentNormalizesAndSyncsScrollback() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()

    session.configuration = SwiftTerminalConfiguration(scrollback: -50)
    try await waitForAsyncBridge()

    #expect(session.configuration.scrollback == 0)
    #expect(runtime.commands == [expectedConfigurationCommand(scrollback: 0)])
}

@Test
@MainActor
func terminalContentLimitAliasesScrollback() async throws {
    var configuration = SwiftTerminalConfiguration(scrollback: 750)

    #expect(configuration.terminalContentLimit == 750)

    configuration.terminalContentLimit = -40

    #expect(configuration.scrollback == 0)
    #expect(configuration.terminalContentLimit == 0)

    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.setTerminalContentLimit(2400)
    try await waitForAsyncBridge()

    #expect(session.configuration.scrollback == 2400)
    #expect(session.configuration.terminalContentLimit == 2400)
    #expect(runtime.commands == [expectedConfigurationCommand(scrollback: 2400)])
}

@Test
@MainActor
func appearancePropertyAssignmentNormalizesAndSyncs() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.appearance = SwiftTerminalAppearance(
        fontFamily: "   ",
        fontSize: 4,
        lineHeight: 0.5,
        letterSpacing: -1,
        contentInsets: .init(top: -5, right: 4, bottom: -3, left: 2)
    )
    try await waitForAsyncBridge()

    #expect(
        session.appearance == SwiftTerminalAppearance(
            fontFamily: SwiftTerminalAppearance.defaultFontFamily,
            fontSize: 6,
            lineHeight: 1,
            letterSpacing: 0,
            contentInsets: .init(top: 0, right: 4, bottom: 0, left: 2)
        )
    )
    #expect(
        runtime.commands == [
            expectedAppearanceCommand(
                fontFamily: SwiftTerminalAppearance.defaultFontFamily,
                fontSize: 6,
                lineHeight: 1,
                letterSpacing: 0,
                contentInsets: .init(top: 0, right: 4, bottom: 0, left: 2)
            ),
        ]
    )
}

@Test
@MainActor
func rapidAppearanceChangesCoalesceToLatestAppearance() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.setFontFamily("Fira Code")
    session.setFontSize(16)
    session.setLineHeight(1.3)
    session.setLetterSpacing(2)
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            expectedAppearanceCommand(
                fontFamily: "Fira Code",
                fontSize: 16,
                lineHeight: 1.3,
                letterSpacing: 2
            ),
        ]
    )
}

@Test
@MainActor
func themeChangesSyncThroughAppearance() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()
    let theme = try #require(SwiftTerminalThemes.builtIn(named: "Dracula"))

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.setTheme(theme)
    try await waitForAsyncBridge()

    #expect(session.appearance.theme == theme)
    #expect(
        runtime.commands == [
            expectedAppearanceCommand(
                fontFamily: SwiftTerminalAppearance.defaultFontFamily,
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0,
                theme: theme
            ),
        ]
    )
}

@Test
@MainActor
func cursorScrollbarAndContentInsetsChangesSyncThroughAppearance() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.setContentPadding(top: 18, right: 16, bottom: 14, left: 12)
    session.setCursorStyle(.underline)
    session.setCursorBlink(false)
    session.setInactiveCursorStyle(.bar)
    session.setScrollbarVisibility(.hidden)
    try await waitForAsyncBridge()

    #expect(
        session.appearance == SwiftTerminalAppearance(
            contentInsets: .init(top: 18, right: 16, bottom: 14, left: 12),
            cursorStyle: .underline,
            cursorBlink: false,
            inactiveCursorStyle: .bar,
            scrollbarVisibility: .hidden
        )
    )
    #expect(
        runtime.commands == [
            expectedAppearanceCommand(
                fontFamily: SwiftTerminalAppearance.defaultFontFamily,
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0,
                contentInsets: .init(top: 18, right: 16, bottom: 14, left: 12),
                cursorStyle: .underline,
                cursorBlink: false,
                inactiveCursorStyle: .bar,
                scrollbarVisibility: .hidden
            ),
        ]
    )
}

@Test
@MainActor
func legacyAppearanceSettersKeepPublicAppearanceInSync() {
    let session = SwiftTerminalSession()

    session.setFontFamily("Fira Code")
    session.setFontSize(16)
    session.setLineHeight(1.3)
    session.setLetterSpacing(2)
    session.setContentPadding(16)
    session.setCursorStyle(.bar)
    session.setCursorBlink(false)
    session.setInactiveCursorStyle(.hidden)
    session.setScrollbarVisibility(.visible)

    #expect(
        session.appearance == SwiftTerminalAppearance(
            fontFamily: "Fira Code",
            fontSize: 16,
            lineHeight: 1.3,
            letterSpacing: 2,
            contentInsets: .init(all: 16),
            cursorStyle: .bar,
            cursorBlink: false,
            inactiveCursorStyle: .hidden,
            scrollbarVisibility: .visible
        )
    )
}

@Test
@MainActor
func appearanceSpacingValuesAreClampedBeforeSync() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.setLineHeight(0.75)
    session.setLetterSpacing(-2)
    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            expectedConfigurationCommand(),
            expectedAppearanceCommand(
                fontFamily: #"SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace"#,
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )
}

@Test
@MainActor
func customFontRegistersBeforeAppearanceCommand() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()
    let font = TerminalCustomFont(
        family: "My Mono",
        format: .ttf,
        data: Data("font-data".utf8)
    )

    session.registerCustomFont(font)
    session.setFontSize(15)
    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(runtime.registeredFonts == [font])
    #expect(
        runtime.commands == [
            expectedConfigurationCommand(),
            .installFont(
                family: "My Mono",
                url: "swiftterminalfont://font/1",
                format: .ttf,
                variant: .regular
            ),
            expectedAppearanceCommand(
                fontFamily: "My Mono",
                fontSize: 15,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )
}

@Test
@MainActor
func customFontRetainsSpacingAppearanceValues() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()
    let font = TerminalCustomFont(
        family: "My Mono",
        format: .ttf,
        data: Data("font-data".utf8)
    )

    session.registerCustomFont(font)
    session.setFontSize(15)
    session.setLineHeight(1.4)
    session.setLetterSpacing(3)
    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(runtime.registeredFonts == [font])
    #expect(
        runtime.commands == [
            expectedConfigurationCommand(),
            .installFont(
                family: "My Mono",
                url: "swiftterminalfont://font/1",
                format: .ttf,
                variant: .regular
            ),
            expectedAppearanceCommand(
                fontFamily: "My Mono",
                fontSize: 15,
                lineHeight: 1.4,
                letterSpacing: 3
            ),
        ]
    )
}

@Test
@MainActor
func customFontIsNotReinstalledForSizeOnlyChanges() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()
    let font = TerminalCustomFont(
        family: "My Mono",
        format: .woff2,
        data: Data("font-data".utf8)
    )

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    runtime.registeredFonts.removeAll()

    session.registerCustomFont(font)
    try await waitForAsyncBridge()

    #expect(runtime.registeredFonts == [font])
    #expect(
        runtime.commands == [
            .installFont(
                family: "My Mono",
                url: "swiftterminalfont://font/1",
                format: .woff2,
                variant: .regular
            ),
            expectedAppearanceCommand(
                fontFamily: "My Mono",
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )

    runtime.commands.removeAll()
    runtime.registeredFonts.removeAll()

    session.setFontSize(18)
    try await waitForAsyncBridge()

    #expect(runtime.registeredFonts.isEmpty)
    #expect(
        runtime.commands == [
            expectedAppearanceCommand(
                fontFamily: "My Mono",
                fontSize: 18,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )
}

@Test
@MainActor
func customFontSetRegistersAllFacesBeforeAppearanceCommand() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()
    let regular = TerminalCustomFont(
        family: "My Mono",
        format: .ttf,
        data: Data("regular-font-data".utf8)
    )
    let bold = TerminalCustomFont(
        family: "My Mono",
        format: .otf,
        data: Data("bold-font-data".utf8),
        variant: .bold
    )
    let italic = TerminalCustomFont(
        family: "My Mono",
        format: .woff2,
        data: Data("italic-font-data".utf8),
        variant: .italic
    )

    session.registerCustomFontSet([italic, regular, bold])
    session.setFontSize(15)
    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    #expect(runtime.registeredFonts == [regular, bold, italic])
    #expect(
        runtime.commands == [
            expectedConfigurationCommand(),
            .installFont(
                family: "My Mono",
                url: "swiftterminalfont://font/1",
                format: .ttf,
                variant: .regular
            ),
            .installFont(
                family: "My Mono",
                url: "swiftterminalfont://font/2",
                format: .otf,
                variant: .bold
            ),
            .installFont(
                family: "My Mono",
                url: "swiftterminalfont://font/3",
                format: .woff2,
                variant: .italic
            ),
            expectedAppearanceCommand(
                fontFamily: "My Mono",
                fontSize: 15,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )
}

@Test
@MainActor
func customFontSetIsNotReinstalledForSizeOnlyChanges() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()
    let regular = TerminalCustomFont(
        family: "My Mono",
        format: .woff2,
        data: Data("regular-font-data".utf8)
    )
    let bold = TerminalCustomFont(
        family: "My Mono",
        format: .woff2,
        data: Data("bold-font-data".utf8),
        variant: .bold
    )

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    runtime.registeredFonts.removeAll()

    session.registerCustomFontSet([regular, bold])
    try await waitForAsyncBridge()

    #expect(runtime.registeredFonts == [regular, bold])
    #expect(
        runtime.commands == [
            .installFont(
                family: "My Mono",
                url: "swiftterminalfont://font/1",
                format: .woff2,
                variant: .regular
            ),
            .installFont(
                family: "My Mono",
                url: "swiftterminalfont://font/2",
                format: .woff2,
                variant: .bold
            ),
            expectedAppearanceCommand(
                fontFamily: "My Mono",
                fontSize: 14,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )

    runtime.commands.removeAll()
    runtime.registeredFonts.removeAll()

    session.setFontSize(18)
    try await waitForAsyncBridge()

    #expect(runtime.registeredFonts.isEmpty)
    #expect(
        runtime.commands == [
            expectedAppearanceCommand(
                fontFamily: "My Mono",
                fontSize: 18,
                lineHeight: 1,
                letterSpacing: 0
            ),
        ]
    )
}

@Test
@MainActor
func richSearchOptionsEnqueueExtendedSearchCommand() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.searchNext(
        "terminal",
        options: SwiftTerminalSearchOptions(
            caseSensitive: true,
            usesRegex: true,
            matchesWholeWord: true
        )
    )
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            .searchNext(
                "terminal",
                options: SwiftTerminalSearchOptions(
                    caseSensitive: true,
                    usesRegex: true,
                    matchesWholeWord: true
                )
            ),
        ]
    )
}

@Test
@MainActor
func clearSearchEnqueuesClearSearchCommand() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.clearSearch()
    try await waitForAsyncBridge()

    #expect(runtime.commands == [.clearSearch])
}

@Test
@MainActor
func selectionTextTracksRuntimeSelectionEvents() {
    let session = SwiftTerminalSession()

    #expect(session.selectionText == nil)
    #expect(session.currentSelectionText() == nil)

    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .selectionChanged,
            text: "selected token"
        )
    )

    #expect(session.selectionText == "selected token")
    #expect(session.currentSelectionText() == "selected token")

    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .selectionChanged,
            text: ""
        )
    )

    #expect(session.selectionText == nil)
    #expect(session.currentSelectionText() == nil)
}

@Test
@MainActor
func searchStateTracksRuntimeSearchStateEvents() {
    let session = SwiftTerminalSession()

    #expect(session.searchState == .empty)
    #expect(session.currentSearchState() == .empty)

    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .searchStateChanged,
            query: "Terminal",
            visible: true,
            caseSensitive: true,
            regex: false,
            wholeWord: true,
            resultIndex: 2,
            resultCount: 5
        )
    )

    #expect(
        session.searchState == SwiftTerminalSearchState(
            isVisible: true,
            query: "Terminal",
            options: SwiftTerminalSearchOptions(
                caseSensitive: true,
                usesRegex: false,
                matchesWholeWord: true
            ),
            resultIndex: 2,
            resultCount: 5
        )
    )
    #expect(session.currentSearchState() == session.searchState)

    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .searchStateChanged,
            query: "Terminal(",
            visible: true,
            caseSensitive: true,
            regex: true,
            wholeWord: false,
            resultIndex: 0,
            resultCount: 0,
            errorMessage: "Invalid regex"
        )
    )

    #expect(session.searchState.errorMessage == "Invalid regex")

    session.runtimeDidTerminate()

    #expect(session.searchState == .empty)
    #expect(session.currentSearchState() == .empty)
}

@Test
@MainActor
func currentBufferSnapshotRequestsAndResolvesRuntimeSnapshot() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    let snapshotTask = Task { @MainActor in
        try await session.currentBufferSnapshot(maxLines: 2, trimRight: false)
    }
    try await waitForAsyncBridge()

    let requestCommand = try #require(runtime.commands.last)
    #expect(requestCommand.type == .requestBufferSnapshot)
    #expect(requestCommand.maxLines == 2)
    #expect(requestCommand.trimRight == false)

    let requestID = try #require(requestCommand.requestID)
    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .bufferSnapshot,
            cols: 120,
            rows: 40,
            requestID: requestID,
            bufferType: .normal,
            viewportY: 6,
            baseY: 12,
            totalLineCount: 14,
            startLine: 12,
            endLine: 14,
            isTruncated: true,
            lines: [
                SwiftTerminalBufferLine(
                    bufferLine: 12,
                    text: "first retained line",
                    isWrapped: false
                ),
                SwiftTerminalBufferLine(
                    bufferLine: 13,
                    text: "wrapped continuation",
                    isWrapped: true
                ),
            ]
        )
    )

    let snapshot = try await snapshotTask.value

    #expect(snapshot.bufferType == .normal)
    #expect(snapshot.cols == 120)
    #expect(snapshot.rows == 40)
    #expect(snapshot.viewportY == 6)
    #expect(snapshot.baseY == 12)
    #expect(snapshot.totalLineCount == 14)
    #expect(snapshot.startLine == 12)
    #expect(snapshot.endLine == 14)
    #expect(snapshot.isTruncated)
    #expect(snapshot.logicalLines == ["first retained linewrapped continuation"])
    #expect(snapshot.logicalText == "first retained linewrapped continuation")
    #expect(snapshot.visualText == "first retained line\nwrapped continuation")
    #expect(snapshot.text == snapshot.logicalText)
    #expect(
        snapshot.lines == [
            SwiftTerminalBufferLine(
                bufferLine: 12,
                text: "first retained line",
                isWrapped: false
            ),
            SwiftTerminalBufferLine(
                bufferLine: 13,
                text: "wrapped continuation",
                isWrapped: true
            ),
        ]
    )
}

@Test
func bufferSnapshotTextUsesOnlyRealLineBreaks() {
    let snapshot = SwiftTerminalBufferSnapshot(
        bufferType: .normal,
        cols: 10,
        rows: 4,
        viewportY: 0,
        baseY: 0,
        totalLineCount: 4,
        startLine: 0,
        endLine: 4,
        isTruncated: false,
        lines: [
            SwiftTerminalBufferLine(bufferLine: 0, text: "prompt long", isWrapped: false),
            SwiftTerminalBufferLine(bufferLine: 1, text: " command", isWrapped: true),
            SwiftTerminalBufferLine(bufferLine: 2, text: "actual next", isWrapped: false),
            SwiftTerminalBufferLine(bufferLine: 3, text: " line", isWrapped: true),
        ]
    )

    #expect(snapshot.logicalLines == ["prompt long command", "actual next line"])
    #expect(snapshot.text == "prompt long command\nactual next line")
    #expect(snapshot.logicalText == snapshot.text)
    #expect(snapshot.visualText == "prompt long\n command\nactual next\n line")
}

@Test
func bufferSnapshotLogicalTextDropsViewportTrailingBlankRows() {
    let snapshot = SwiftTerminalBufferSnapshot(
        bufferType: .normal,
        cols: 10,
        rows: 4,
        viewportY: 0,
        baseY: 0,
        totalLineCount: 4,
        startLine: 0,
        endLine: 4,
        isTruncated: false,
        lines: [
            SwiftTerminalBufferLine(bufferLine: 0, text: "prompt", isWrapped: false),
            SwiftTerminalBufferLine(bufferLine: 1, text: "", isWrapped: false),
            SwiftTerminalBufferLine(bufferLine: 2, text: "", isWrapped: false),
            SwiftTerminalBufferLine(bufferLine: 3, text: "", isWrapped: false),
        ]
    )

    #expect(snapshot.logicalLines == ["prompt"])
    #expect(snapshot.logicalText == "prompt")
    #expect(snapshot.text == snapshot.logicalText)
    #expect(snapshot.visualText == "prompt\n\n\n")
    #expect(snapshot.lines.count == 4)
}

@Test
@MainActor
func currentBufferSnapshotThrowsWhenRuntimeIsUnavailable() async {
    let session = SwiftTerminalSession()

    do {
        _ = try await session.currentBufferSnapshot()
        Issue.record("Expected currentBufferSnapshot to throw")
    } catch let error as SwiftTerminalBufferSnapshotError {
        #expect(error == .runtimeUnavailable)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
@MainActor
func windowTitleTracksRuntimeTitleEvents() {
    let session = SwiftTerminalSession()

    #expect(session.windowTitle == nil)
    #expect(session.currentWindowTitle() == nil)

    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .titleChanged,
            title: "remote-shell"
        )
    )

    #expect(session.windowTitle == "remote-shell")
    #expect(session.currentWindowTitle() == "remote-shell")

    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .titleChanged,
            title: ""
        )
    )

    #expect(session.windowTitle == "")
    #expect(session.currentWindowTitle() == "")

    session.runtimeDidTerminate()

    #expect(session.windowTitle == nil)
    #expect(session.currentWindowTitle() == nil)
}

@Test
@MainActor
func bellEventsAreForwardedToOnEvent() {
    let session = SwiftTerminalSession()
    var observedEventTypes: [TerminalRuntimeEventType] = []

    session.onEvent = { event in
        observedEventTypes.append(event.type)
    }

    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .bell))

    #expect(observedEventTypes == [.bell])
}

@Test
@MainActor
func linkActivatedEventOpensURLWhenEnabled() {
    let linkOpener = LinkOpenerSpy()
    let session = SwiftTerminalSession(
        configuration: SwiftTerminalConfiguration(opensLinksByDefault: true),
        clipboardProvider: ClipboardProviderSpy(),
        linkOpener: linkOpener
    )

    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .linkActivated,
            url: "https://example.com/docs"
        )
    )

    #expect(linkOpener.openedURLs == [URL(string: "https://example.com/docs")!])
}

@Test
@MainActor
func linkActivatedEventDoesNotOpenURLWhenDisabled() {
    let linkOpener = LinkOpenerSpy()
    let session = SwiftTerminalSession(
        configuration: SwiftTerminalConfiguration(opensLinksByDefault: false),
        clipboardProvider: ClipboardProviderSpy(),
        linkOpener: linkOpener
    )

    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .linkActivated,
            url: "https://example.com/docs"
        )
    )

    #expect(linkOpener.openedURLs.isEmpty)
}

@Test
@MainActor
func openExternalLinkUsesConfiguredLinkOpener() {
    let linkOpener = LinkOpenerSpy()
    let session = SwiftTerminalSession(
        clipboardProvider: ClipboardProviderSpy(),
        linkOpener: linkOpener
    )

    let url = URL(string: "https://example.com/docs")!
    session.openExternalLink(url)

    #expect(linkOpener.openedURLs == [url])
}

@Test
@MainActor
func pasteFromClipboardEnqueuesPasteCommand() async throws {
    let clipboard = ClipboardProviderSpy()
    clipboard.textToRead = "clipboard text"
    let session = SwiftTerminalSession(
        clipboardProvider: clipboard
    )
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.pasteFromClipboard()
    try await waitForAsyncBridge()

    #expect(runtime.commands == [.paste("clipboard text")])
}

@Test
@MainActor
func copySelectionEnqueuesCopyCommand() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.copySelection()
    try await waitForAsyncBridge()

    #expect(runtime.commands == [.copySelection])
}

@Test
@MainActor
func selectAllEnqueuesSelectAllCommand() async throws {
    let session = SwiftTerminalSession()
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.selectAll()
    try await waitForAsyncBridge()

    #expect(runtime.commands == [.selectAll])
}

@Test
@MainActor
func clipboardReadRequestRespondsWithClipboardContents() async throws {
    let clipboard = ClipboardProviderSpy()
    clipboard.textToRead = "copied from host"
    let session = SwiftTerminalSession(
        clipboardProvider: clipboard
    )
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .clipboardReadRequest,
            requestID: "clipboard-1"
        )
    )
    try await waitForAsyncBridge()

    #expect(
        runtime.commands == [
            .clipboardReadResult(requestID: "clipboard-1", text: "copied from host"),
        ]
    )
}

@Test
@MainActor
func clipboardWriteRequestWritesClipboardAndAcknowledges() async throws {
    let clipboard = ClipboardProviderSpy()
    let session = SwiftTerminalSession(
        clipboardProvider: clipboard
    )
    let runtime = RuntimeControllerSpy()

    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    try await waitForAsyncBridge()

    runtime.commands.removeAll()
    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .clipboardWriteRequest,
            text: "new clipboard text",
            requestID: "clipboard-2"
        )
    )
    try await waitForAsyncBridge()

    #expect(clipboard.writtenTexts == ["new clipboard text"])
    #expect(runtime.commands == [.clipboardWriteResult(requestID: "clipboard-2")])
}
