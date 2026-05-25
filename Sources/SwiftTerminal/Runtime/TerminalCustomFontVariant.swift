import Foundation

public enum TerminalCustomFontVariant: String, Codable, Sendable, CaseIterable {
    case regular
    case bold
    case italic
    case boldItalic = "bold_italic"

    var cssFontWeight: String {
        switch self {
        case .regular, .italic:
            return "400"
        case .bold, .boldItalic:
            return "700"
        }
    }

    var cssFontStyle: String {
        switch self {
        case .regular, .bold:
            return "normal"
        case .italic, .boldItalic:
            return "italic"
        }
    }

    var sortOrder: Int {
        switch self {
        case .regular:
            return 0
        case .bold:
            return 1
        case .italic:
            return 2
        case .boldItalic:
            return 3
        }
    }

    public var displayName: String {
        switch self {
        case .regular:
            return "Regular"
        case .bold:
            return "Bold"
        case .italic:
            return "Italic"
        case .boldItalic:
            return "Bold Italic"
        }
    }
}
