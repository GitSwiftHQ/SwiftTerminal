import Foundation

public enum TerminalFontFormat: String, Codable, CaseIterable, Sendable {
    case ttf
    case otf
    case woff
    case woff2

    public init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "ttf":
            self = .ttf
        case "otf":
            self = .otf
        case "woff":
            self = .woff
        case "woff2":
            self = .woff2
        default:
            return nil
        }
    }

    var mimeType: String {
        switch self {
        case .ttf:
            return "font/ttf"
        case .otf:
            return "font/otf"
        case .woff:
            return "font/woff"
        case .woff2:
            return "font/woff2"
        }
    }

}

public struct TerminalCustomFont: Sendable, Equatable, Hashable {
    public var family: String
    public var format: TerminalFontFormat
    public var data: Data
    public var variant: TerminalCustomFontVariant

    public init(
        family: String,
        format: TerminalFontFormat,
        data: Data,
        variant: TerminalCustomFontVariant = .regular
    ) {
        self.family = family
        self.format = format
        self.data = data
        self.variant = variant
    }
}
