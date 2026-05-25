import Foundation

public struct SwiftTerminalContentInsets: Sendable, Equatable, Hashable, Codable {
    public static let defaultValue = 0.0

    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(
        top: Double = defaultValue,
        right: Double = defaultValue,
        bottom: Double = defaultValue,
        left: Double = defaultValue
    ) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        self = self.normalized()
    }

    public init(all value: Double) {
        self.init(top: value, right: value, bottom: value, left: value)
    }

    public static let zero = Self()

    public func normalized() -> Self {
        Self(
            top: max(Self.defaultValue, top),
            right: max(Self.defaultValue, right),
            bottom: max(Self.defaultValue, bottom),
            left: max(Self.defaultValue, left),
            isNormalized: true
        )
    }

    private init(
        top: Double,
        right: Double,
        bottom: Double,
        left: Double,
        isNormalized: Bool
    ) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }
}
