import Foundation

public enum TerminalHostCommandType: String, Codable, Sendable {
    case write
    case clear
    case focus
    case paste
    case selectAll = "select_all"
    case copySelection = "copy_selection"
    case installFont = "install_font"
    case setAppearance = "set_appearance"
    case setSearchVisible = "set_search_visible"
    case clearSearch = "clear_search"
    case searchNext = "search_next"
    case searchPrevious = "search_previous"
    case setFeatureFlags = "set_feature_flags"
    case requestBufferSnapshot = "request_buffer_snapshot"
    case clipboardReadResult = "clipboard_read_result"
    case clipboardWriteResult = "clipboard_write_result"
}

public struct TerminalHostCommandEnvelope: Codable, Equatable, Sendable {
    public var type: TerminalHostCommandType
    public var text: String?
    public var visible: Bool?
    public var query: String?
    public var caseSensitive: Bool?
    public var regex: Bool?
    public var wholeWord: Bool?
    public var requestID: String?
    public var maxLines: Int?
    public var trimRight: Bool?
    public var enablesSearchUI: Bool?
    public var enablesKeyboardShortcuts: Bool?
    public var enablesClipboardIntegration: Bool?
    public var enablesRuntimeDiagnostics: Bool?
    public var scrollback: Int?
    public var fontFamily: String?
    public var fontSize: Double?
    public var lineHeight: Double?
    public var letterSpacing: Int?
    public var contentInsets: SwiftTerminalContentInsets?
    public var cursorStyle: SwiftTerminalCursorStyle?
    public var cursorBlink: Bool?
    public var inactiveCursorStyle: SwiftTerminalInactiveCursorStyle?
    public var scrollbarVisibility: SwiftTerminalScrollbarVisibility?
    public var theme: SwiftTerminalTheme?
    public var fontURL: String?
    public var fontFormat: TerminalFontFormat?
    public var fontVariant: TerminalCustomFontVariant?

    public init(
        type: TerminalHostCommandType,
        text: String? = nil,
        visible: Bool? = nil,
        query: String? = nil,
        caseSensitive: Bool? = nil,
        regex: Bool? = nil,
        wholeWord: Bool? = nil,
        requestID: String? = nil,
        maxLines: Int? = nil,
        trimRight: Bool? = nil,
        enablesSearchUI: Bool? = nil,
        enablesKeyboardShortcuts: Bool? = nil,
        enablesClipboardIntegration: Bool? = nil,
        enablesRuntimeDiagnostics: Bool? = nil,
        scrollback: Int? = nil,
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        letterSpacing: Int? = nil,
        contentInsets: SwiftTerminalContentInsets? = nil,
        cursorStyle: SwiftTerminalCursorStyle? = nil,
        cursorBlink: Bool? = nil,
        inactiveCursorStyle: SwiftTerminalInactiveCursorStyle? = nil,
        scrollbarVisibility: SwiftTerminalScrollbarVisibility? = nil,
        theme: SwiftTerminalTheme? = nil,
        fontURL: String? = nil,
        fontFormat: TerminalFontFormat? = nil,
        fontVariant: TerminalCustomFontVariant? = nil
    ) {
        self.type = type
        self.text = text
        self.visible = visible
        self.query = query
        self.caseSensitive = caseSensitive
        self.regex = regex
        self.wholeWord = wholeWord
        self.requestID = requestID
        self.maxLines = maxLines
        self.trimRight = trimRight
        self.enablesSearchUI = enablesSearchUI
        self.enablesKeyboardShortcuts = enablesKeyboardShortcuts
        self.enablesClipboardIntegration = enablesClipboardIntegration
        self.enablesRuntimeDiagnostics = enablesRuntimeDiagnostics
        self.scrollback = scrollback
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.contentInsets = contentInsets
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.inactiveCursorStyle = inactiveCursorStyle
        self.scrollbarVisibility = scrollbarVisibility
        self.theme = theme
        self.fontURL = fontURL
        self.fontFormat = fontFormat
        self.fontVariant = fontVariant
    }

    public static func write(_ text: String) -> Self {
        Self(type: .write, text: text)
    }

    public static func paste(_ text: String) -> Self {
        Self(type: .paste, text: text)
    }

    public static let clear = Self(type: .clear)
    public static let focus = Self(type: .focus)
    public static let selectAll = Self(type: .selectAll)
    public static let copySelection = Self(type: .copySelection)

    public static func setSearchVisible(_ visible: Bool) -> Self {
        Self(type: .setSearchVisible, visible: visible)
    }

    public static let clearSearch = Self(type: .clearSearch)

    public static func installFont(
        family: String,
        url: String,
        format: TerminalFontFormat,
        variant: TerminalCustomFontVariant
    ) -> Self {
        Self(
            type: .installFont,
            fontFamily: family,
            fontURL: url,
            fontFormat: format,
            fontVariant: variant
        )
    }

    public static func setAppearance(
        fontFamily: String,
        fontSize: Double,
        lineHeight: Double? = nil,
        letterSpacing: Int? = nil,
        contentInsets: SwiftTerminalContentInsets? = nil,
        cursorStyle: SwiftTerminalCursorStyle? = nil,
        cursorBlink: Bool? = nil,
        inactiveCursorStyle: SwiftTerminalInactiveCursorStyle? = nil,
        scrollbarVisibility: SwiftTerminalScrollbarVisibility? = nil,
        theme: SwiftTerminalTheme? = nil
    ) -> Self {
        Self(
            type: .setAppearance,
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

    public static func searchNext(
        _ query: String,
        options: SwiftTerminalSearchOptions
    ) -> Self {
        Self(
            type: .searchNext,
            query: query,
            caseSensitive: options.caseSensitive,
            regex: options.usesRegex,
            wholeWord: options.matchesWholeWord
        )
    }

    public static func searchNext(_ query: String, caseSensitive: Bool) -> Self {
        searchNext(query, options: SwiftTerminalSearchOptions(caseSensitive: caseSensitive))
    }

    public static func searchPrevious(
        _ query: String,
        options: SwiftTerminalSearchOptions
    ) -> Self {
        Self(
            type: .searchPrevious,
            query: query,
            caseSensitive: options.caseSensitive,
            regex: options.usesRegex,
            wholeWord: options.matchesWholeWord
        )
    }

    public static func searchPrevious(_ query: String, caseSensitive: Bool) -> Self {
        searchPrevious(
            query,
            options: SwiftTerminalSearchOptions(caseSensitive: caseSensitive)
        )
    }

    public static func setFeatureFlags(
        enablesSearchUI: Bool,
        enablesKeyboardShortcuts: Bool,
        enablesClipboardIntegration: Bool,
        enablesRuntimeDiagnostics: Bool = false,
        scrollback: Int
    ) -> Self {
        Self(
            type: .setFeatureFlags,
            enablesSearchUI: enablesSearchUI,
            enablesKeyboardShortcuts: enablesKeyboardShortcuts,
            enablesClipboardIntegration: enablesClipboardIntegration,
            enablesRuntimeDiagnostics: enablesRuntimeDiagnostics,
            scrollback: scrollback
        )
    }

    public static func requestBufferSnapshot(
        requestID: String,
        maxLines: Int? = nil,
        trimRight: Bool = true
    ) -> Self {
        Self(
            type: .requestBufferSnapshot,
            requestID: requestID,
            maxLines: maxLines.map { max(0, $0) },
            trimRight: trimRight
        )
    }

    public static func clipboardReadResult(requestID: String, text: String) -> Self {
        Self(
            type: .clipboardReadResult,
            text: text,
            requestID: requestID
        )
    }

    public static func clipboardWriteResult(requestID: String) -> Self {
        Self(
            type: .clipboardWriteResult,
            requestID: requestID
        )
    }
}

public enum TerminalRuntimeEventType: String, Codable, Sendable {
    case ready
    case input
    case selectionChanged = "selection_changed"
    case resize
    case searchResults = "search_results"
    case searchStateChanged = "search_state_changed"
    case bufferSnapshot = "buffer_snapshot"
    case titleChanged = "title_changed"
    case bell
    case linkActivated = "link_activated"
    case clipboardReadRequest = "clipboard_read_request"
    case clipboardWriteRequest = "clipboard_write_request"
    case log
}

public struct TerminalRuntimeEventEnvelope: Codable, Equatable, Sendable {
    private static let runtimeDiagnosticWireType = "runtime_diagnostic"

    public var type: TerminalRuntimeEventType
    public var text: String?
    public var query: String?
    public var cols: Int?
    public var rows: Int?
    public var visible: Bool?
    public var caseSensitive: Bool?
    public var regex: Bool?
    public var wholeWord: Bool?
    public var resultIndex: Int?
    public var resultCount: Int?
    public var title: String?
    public var url: String?
    public var message: String?
    public var errorMessage: String?
    public var requestID: String?
    public var bufferType: SwiftTerminalBufferType?
    public var viewportY: Int?
    public var baseY: Int?
    public var totalLineCount: Int?
    public var startLine: Int?
    public var endLine: Int?
    public var isTruncated: Bool?
    public var lines: [SwiftTerminalBufferLine]?
    public var name: String?
    public var sequence: Int?
    public var timestamp: Double?
    public var metadata: [String: String]?

    public var isRuntimeDiagnostic: Bool {
        name != nil && sequence != nil && timestamp != nil && metadata != nil
    }

    public init(
        type: TerminalRuntimeEventType,
        text: String? = nil,
        query: String? = nil,
        cols: Int? = nil,
        rows: Int? = nil,
        visible: Bool? = nil,
        caseSensitive: Bool? = nil,
        regex: Bool? = nil,
        wholeWord: Bool? = nil,
        resultIndex: Int? = nil,
        resultCount: Int? = nil,
        title: String? = nil,
        url: String? = nil,
        message: String? = nil,
        errorMessage: String? = nil,
        requestID: String? = nil,
        bufferType: SwiftTerminalBufferType? = nil,
        viewportY: Int? = nil,
        baseY: Int? = nil,
        totalLineCount: Int? = nil,
        startLine: Int? = nil,
        endLine: Int? = nil,
        isTruncated: Bool? = nil,
        lines: [SwiftTerminalBufferLine]? = nil,
        name: String? = nil,
        sequence: Int? = nil,
        timestamp: Double? = nil,
        metadata: [String: String]? = nil
    ) {
        self.type = type
        self.text = text
        self.query = query
        self.cols = cols
        self.rows = rows
        self.visible = visible
        self.caseSensitive = caseSensitive
        self.regex = regex
        self.wholeWord = wholeWord
        self.resultIndex = resultIndex
        self.resultCount = resultCount
        self.title = title
        self.url = url
        self.message = message
        self.errorMessage = errorMessage
        self.requestID = requestID
        self.bufferType = bufferType
        self.viewportY = viewportY
        self.baseY = baseY
        self.totalLineCount = totalLineCount
        self.startLine = startLine
        self.endLine = endLine
        self.isTruncated = isTruncated
        self.lines = lines
        self.name = name
        self.sequence = sequence
        self.timestamp = timestamp
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        if rawType == Self.runtimeDiagnosticWireType {
            self.type = .log
        } else if let type = TerminalRuntimeEventType(rawValue: rawType) {
            self.type = type
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown terminal runtime event type: \(rawType)"
            )
        }

        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.query = try container.decodeIfPresent(String.self, forKey: .query)
        self.cols = try container.decodeIfPresent(Int.self, forKey: .cols)
        self.rows = try container.decodeIfPresent(Int.self, forKey: .rows)
        self.visible = try container.decodeIfPresent(Bool.self, forKey: .visible)
        self.caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive)
        self.regex = try container.decodeIfPresent(Bool.self, forKey: .regex)
        self.wholeWord = try container.decodeIfPresent(Bool.self, forKey: .wholeWord)
        self.resultIndex = try container.decodeIfPresent(Int.self, forKey: .resultIndex)
        self.resultCount = try container.decodeIfPresent(Int.self, forKey: .resultCount)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        self.requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
        self.bufferType = try container.decodeIfPresent(SwiftTerminalBufferType.self, forKey: .bufferType)
        self.viewportY = try container.decodeIfPresent(Int.self, forKey: .viewportY)
        self.baseY = try container.decodeIfPresent(Int.self, forKey: .baseY)
        self.totalLineCount = try container.decodeIfPresent(Int.self, forKey: .totalLineCount)
        self.startLine = try container.decodeIfPresent(Int.self, forKey: .startLine)
        self.endLine = try container.decodeIfPresent(Int.self, forKey: .endLine)
        self.isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated)
        self.lines = try container.decodeIfPresent([SwiftTerminalBufferLine].self, forKey: .lines)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.sequence = try container.decodeIfPresent(Int.self, forKey: .sequence)
        self.timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
    }
}
