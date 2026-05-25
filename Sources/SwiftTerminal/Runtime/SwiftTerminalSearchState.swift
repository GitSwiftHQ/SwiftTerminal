import Foundation

public struct SwiftTerminalSearchState: Sendable, Equatable {
    public var isVisible: Bool
    public var query: String
    public var options: SwiftTerminalSearchOptions
    public var resultIndex: Int
    public var resultCount: Int
    public var errorMessage: String?

    public init(
        isVisible: Bool = false,
        query: String = "",
        options: SwiftTerminalSearchOptions = .default,
        resultIndex: Int = 0,
        resultCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.isVisible = isVisible
        self.query = query
        self.options = options
        self.resultCount = max(0, resultCount)

        if self.resultCount == 0 {
            self.resultIndex = 0
        } else {
            self.resultIndex = max(0, min(resultIndex, self.resultCount))
        }

        let trimmedError = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.errorMessage = trimmedError?.isEmpty == false ? trimmedError : nil
    }

    public static let empty = Self()
}
