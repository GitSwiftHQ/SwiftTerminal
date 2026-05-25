import Foundation

public enum SwiftTerminalInactiveCursorStyle: String, Codable, Sendable, CaseIterable {
    case outline
    case block
    case bar
    case underline
    case hidden = "none"
}
