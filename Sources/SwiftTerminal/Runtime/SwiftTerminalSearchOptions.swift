import Foundation

public struct SwiftTerminalSearchOptions: Sendable, Equatable {
    public var caseSensitive: Bool
    public var usesRegex: Bool
    public var matchesWholeWord: Bool

    public init(
        caseSensitive: Bool = false,
        usesRegex: Bool = false,
        matchesWholeWord: Bool = false
    ) {
        self.caseSensitive = caseSensitive
        self.usesRegex = usesRegex
        self.matchesWholeWord = matchesWholeWord
    }

    public static let `default` = Self()
}
