import Foundation

public struct SwiftTerminalTheme: Sendable, Equatable, Hashable, Codable, Identifiable {
    public static let defaultName = "SwiftTerminal Default"

    private static let defaultForegroundValue = "#e8ecf3"
    private static let defaultBackgroundValue = "#0f1115"
    private static let defaultCursorValue = "#7cc7ff"
    private static let defaultCursorAccentValue = "#0f1115"
    private static let defaultSelectionBackgroundValue = "#2d4967"
    private static let defaultSelectionForegroundValue = "#f4fbff"
    private static let defaultSelectionInactiveBackgroundValue = "#203246"
    private static let defaultBlackValue = "#2e3436"
    private static let defaultRedValue = "#cc0000"
    private static let defaultGreenValue = "#4e9a06"
    private static let defaultYellowValue = "#c4a000"
    private static let defaultBlueValue = "#3465a4"
    private static let defaultMagentaValue = "#75507b"
    private static let defaultCyanValue = "#06989a"
    private static let defaultWhiteValue = "#d3d7cf"
    private static let defaultBrightBlackValue = "#555753"
    private static let defaultBrightRedValue = "#ef2929"
    private static let defaultBrightGreenValue = "#8ae234"
    private static let defaultBrightYellowValue = "#fce94f"
    private static let defaultBrightBlueValue = "#729fcf"
    private static let defaultBrightMagentaValue = "#ad7fa8"
    private static let defaultBrightCyanValue = "#34e2e2"
    private static let defaultBrightWhiteValue = "#eeeeec"

    public var id: String {
        name
    }

    public var name: String
    public var foreground: String
    public var background: String
    public var cursor: String
    public var cursorAccent: String
    public var selectionBackground: String
    public var selectionForeground: String
    public var selectionInactiveBackground: String
    public var black: String
    public var red: String
    public var green: String
    public var yellow: String
    public var blue: String
    public var magenta: String
    public var cyan: String
    public var white: String
    public var brightBlack: String
    public var brightRed: String
    public var brightGreen: String
    public var brightYellow: String
    public var brightBlue: String
    public var brightMagenta: String
    public var brightCyan: String
    public var brightWhite: String

    public init(
        name: String = Self.defaultName,
        foreground: String = "#e8ecf3",
        background: String = "#0f1115",
        cursor: String = "#7cc7ff",
        cursorAccent: String = "#0f1115",
        selectionBackground: String = "#2d4967",
        selectionForeground: String = "#f4fbff",
        selectionInactiveBackground: String = "#203246",
        black: String = "#2e3436",
        red: String = "#cc0000",
        green: String = "#4e9a06",
        yellow: String = "#c4a000",
        blue: String = "#3465a4",
        magenta: String = "#75507b",
        cyan: String = "#06989a",
        white: String = "#d3d7cf",
        brightBlack: String = "#555753",
        brightRed: String = "#ef2929",
        brightGreen: String = "#8ae234",
        brightYellow: String = "#fce94f",
        brightBlue: String = "#729fcf",
        brightMagenta: String = "#ad7fa8",
        brightCyan: String = "#34e2e2",
        brightWhite: String = "#eeeeec"
    ) {
        self.name = name
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.cursorAccent = cursorAccent
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.selectionInactiveBackground = selectionInactiveBackground
        self.black = black
        self.red = red
        self.green = green
        self.yellow = yellow
        self.blue = blue
        self.magenta = magenta
        self.cyan = cyan
        self.white = white
        self.brightBlack = brightBlack
        self.brightRed = brightRed
        self.brightGreen = brightGreen
        self.brightYellow = brightYellow
        self.brightBlue = brightBlue
        self.brightMagenta = brightMagenta
        self.brightCyan = brightCyan
        self.brightWhite = brightWhite
        self = self.normalized()
    }

    public static let `default` = Self()

    public func normalized() -> Self {
        let normalizedName = Self.normalizedText(name, fallback: Self.defaultName)
        let normalizedSelectionBackground = Self.normalizedText(
            selectionBackground,
            fallback: Self.defaultSelectionBackgroundValue
        )

        return Self(
            name: normalizedName,
            foreground: Self.normalizedText(foreground, fallback: Self.defaultForegroundValue),
            background: Self.normalizedText(background, fallback: Self.defaultBackgroundValue),
            cursor: Self.normalizedText(cursor, fallback: Self.defaultCursorValue),
            cursorAccent: Self.normalizedText(cursorAccent, fallback: Self.defaultCursorAccentValue),
            selectionBackground: normalizedSelectionBackground,
            selectionForeground: Self.normalizedText(
                selectionForeground,
                fallback: Self.defaultSelectionForegroundValue
            ),
            selectionInactiveBackground: Self.normalizedText(
                selectionInactiveBackground,
                fallback: normalizedSelectionBackground
            ),
            black: Self.normalizedText(black, fallback: Self.defaultBlackValue),
            red: Self.normalizedText(red, fallback: Self.defaultRedValue),
            green: Self.normalizedText(green, fallback: Self.defaultGreenValue),
            yellow: Self.normalizedText(yellow, fallback: Self.defaultYellowValue),
            blue: Self.normalizedText(blue, fallback: Self.defaultBlueValue),
            magenta: Self.normalizedText(magenta, fallback: Self.defaultMagentaValue),
            cyan: Self.normalizedText(cyan, fallback: Self.defaultCyanValue),
            white: Self.normalizedText(white, fallback: Self.defaultWhiteValue),
            brightBlack: Self.normalizedText(brightBlack, fallback: Self.defaultBrightBlackValue),
            brightRed: Self.normalizedText(brightRed, fallback: Self.defaultBrightRedValue),
            brightGreen: Self.normalizedText(brightGreen, fallback: Self.defaultBrightGreenValue),
            brightYellow: Self.normalizedText(brightYellow, fallback: Self.defaultBrightYellowValue),
            brightBlue: Self.normalizedText(brightBlue, fallback: Self.defaultBrightBlueValue),
            brightMagenta: Self.normalizedText(
                brightMagenta,
                fallback: Self.defaultBrightMagentaValue
            ),
            brightCyan: Self.normalizedText(brightCyan, fallback: Self.defaultBrightCyanValue),
            brightWhite: Self.normalizedText(brightWhite, fallback: Self.defaultBrightWhiteValue),
            isNormalized: true
        )
    }

    private static func normalizedText(_ value: String, fallback: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? fallback : trimmedValue
    }

    private init(
        name: String,
        foreground: String,
        background: String,
        cursor: String,
        cursorAccent: String,
        selectionBackground: String,
        selectionForeground: String,
        selectionInactiveBackground: String,
        black: String,
        red: String,
        green: String,
        yellow: String,
        blue: String,
        magenta: String,
        cyan: String,
        white: String,
        brightBlack: String,
        brightRed: String,
        brightGreen: String,
        brightYellow: String,
        brightBlue: String,
        brightMagenta: String,
        brightCyan: String,
        brightWhite: String,
        isNormalized: Bool
    ) {
        self.name = name
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.cursorAccent = cursorAccent
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.selectionInactiveBackground = selectionInactiveBackground
        self.black = black
        self.red = red
        self.green = green
        self.yellow = yellow
        self.blue = blue
        self.magenta = magenta
        self.cyan = cyan
        self.white = white
        self.brightBlack = brightBlack
        self.brightRed = brightRed
        self.brightGreen = brightGreen
        self.brightYellow = brightYellow
        self.brightBlue = brightBlue
        self.brightMagenta = brightMagenta
        self.brightCyan = brightCyan
        self.brightWhite = brightWhite
    }
}
