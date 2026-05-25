import Foundation

public enum SwiftTerminalBufferSnapshotError: Error, Equatable, Sendable {
    case runtimeUnavailable
    case missingSnapshotPayload(requestID: String?)
}

public enum SwiftTerminalBufferType: String, Codable, Sendable {
    case normal
    case alternate
}

public struct SwiftTerminalBufferLine: Codable, Equatable, Sendable {
    public var bufferLine: Int
    public var text: String
    public var isWrapped: Bool

    public init(
        bufferLine: Int,
        text: String,
        isWrapped: Bool
    ) {
        self.bufferLine = max(0, bufferLine)
        self.text = text
        self.isWrapped = isWrapped
    }
}

public struct SwiftTerminalBufferSnapshot: Codable, Equatable, Sendable {
    public var bufferType: SwiftTerminalBufferType
    public var cols: Int
    public var rows: Int
    public var viewportY: Int
    public var baseY: Int
    public var totalLineCount: Int
    public var startLine: Int
    public var endLine: Int
    public var isTruncated: Bool
    public var lines: [SwiftTerminalBufferLine]

    public init(
        bufferType: SwiftTerminalBufferType,
        cols: Int,
        rows: Int,
        viewportY: Int,
        baseY: Int,
        totalLineCount: Int,
        startLine: Int,
        endLine: Int,
        isTruncated: Bool,
        lines: [SwiftTerminalBufferLine]
    ) {
        self.bufferType = bufferType
        self.cols = max(0, cols)
        self.rows = max(0, rows)
        self.viewportY = max(0, viewportY)
        self.baseY = max(0, baseY)
        self.totalLineCount = max(0, totalLineCount)
        self.startLine = max(0, startLine)
        self.endLine = max(self.startLine, endLine)
        self.isTruncated = isTruncated
        self.lines = lines
    }

    public var logicalLines: [String] {
        var result: [String] = []

        for line in lines {
            if line.isWrapped, !result.isEmpty {
                result[result.count - 1] += line.text
            } else {
                result.append(line.text)
            }
        }

        while result.last?.isEmpty == true {
            result.removeLast()
        }

        return result
    }

    public var logicalText: String {
        logicalLines.joined(separator: "\n")
    }

    public var visualText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    public var text: String {
        logicalText
    }
}
