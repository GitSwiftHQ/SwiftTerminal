import Foundation

public struct SwiftTerminalAppearance: Sendable, Equatable {
    public static let defaultFontFamily = #"SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace"#
    public static let defaultFontSize = 14.0
    public static let defaultLineHeight = 1.0
    public static let defaultLetterSpacing = 0
    public static let defaultContentInsets = SwiftTerminalContentInsets.zero
    public static let defaultCursorStyle = SwiftTerminalCursorStyle.block
    public static let defaultCursorBlink = true
    public static let defaultInactiveCursorStyle = SwiftTerminalInactiveCursorStyle.outline
    public static let defaultScrollbarVisibility = SwiftTerminalScrollbarVisibility.automatic

    public var fontFamily: String
    public var fontSize: Double
    public var lineHeight: Double
    public var letterSpacing: Int
    public var contentInsets: SwiftTerminalContentInsets
    public var cursorStyle: SwiftTerminalCursorStyle
    public var cursorBlink: Bool
    public var inactiveCursorStyle: SwiftTerminalInactiveCursorStyle
    public var scrollbarVisibility: SwiftTerminalScrollbarVisibility
    public var theme: SwiftTerminalTheme

    public init(
        fontFamily: String = defaultFontFamily,
        fontSize: Double = defaultFontSize,
        lineHeight: Double = defaultLineHeight,
        letterSpacing: Int = defaultLetterSpacing,
        contentInsets: SwiftTerminalContentInsets = defaultContentInsets,
        cursorStyle: SwiftTerminalCursorStyle = defaultCursorStyle,
        cursorBlink: Bool = defaultCursorBlink,
        inactiveCursorStyle: SwiftTerminalInactiveCursorStyle = defaultInactiveCursorStyle,
        scrollbarVisibility: SwiftTerminalScrollbarVisibility = defaultScrollbarVisibility,
        theme: SwiftTerminalTheme = .default
    ) {
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
        self = self.normalized()
    }

    public init(
        fontFamily: String = defaultFontFamily,
        fontSize: Double = defaultFontSize,
        lineHeight: Double = defaultLineHeight,
        letterSpacing: Int = defaultLetterSpacing,
        contentPadding: Double,
        cursorStyle: SwiftTerminalCursorStyle = defaultCursorStyle,
        cursorBlink: Bool = defaultCursorBlink,
        inactiveCursorStyle: SwiftTerminalInactiveCursorStyle = defaultInactiveCursorStyle,
        scrollbarVisibility: SwiftTerminalScrollbarVisibility = defaultScrollbarVisibility,
        theme: SwiftTerminalTheme = .default
    ) {
        self.init(
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineHeight: lineHeight,
            letterSpacing: letterSpacing,
            contentInsets: .init(all: contentPadding),
            cursorStyle: cursorStyle,
            cursorBlink: cursorBlink,
            inactiveCursorStyle: inactiveCursorStyle,
            scrollbarVisibility: scrollbarVisibility,
            theme: theme
        )
    }

    public static let `default` = Self()

    func normalized() -> Self {
        let trimmedFamily = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)

        return Self(
            fontFamily: trimmedFamily.isEmpty ? Self.defaultFontFamily : trimmedFamily,
            fontSize: max(6, fontSize),
            lineHeight: max(Self.defaultLineHeight, lineHeight),
            letterSpacing: max(Self.defaultLetterSpacing, letterSpacing),
            contentInsets: contentInsets.normalized(),
            cursorStyle: cursorStyle,
            cursorBlink: cursorBlink,
            inactiveCursorStyle: inactiveCursorStyle,
            scrollbarVisibility: scrollbarVisibility,
            theme: theme.normalized(),
            isNormalized: true
        )
    }

    private init(
        fontFamily: String,
        fontSize: Double,
        lineHeight: Double,
        letterSpacing: Int,
        contentInsets: SwiftTerminalContentInsets,
        cursorStyle: SwiftTerminalCursorStyle,
        cursorBlink: Bool,
        inactiveCursorStyle: SwiftTerminalInactiveCursorStyle,
        scrollbarVisibility: SwiftTerminalScrollbarVisibility,
        theme: SwiftTerminalTheme,
        isNormalized: Bool
    ) {
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
    }
}
