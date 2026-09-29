//
//  SwiftTerminalKey.swift
//  SwiftTerminal
//
//  Created by GitSwift on 2026/09/29.
//

import Foundation

/// A logical key a host sends to the terminal with `SwiftTerminalSession.sendKey(_:modifiers:)`.
///
/// The runtime encodes the key the way xterm does, including the cursor-key mode the running
/// program selected, and delivers it through the same input path as a key typed into the
/// terminal. A host never builds escape sequences itself.
public enum SwiftTerminalKey: Hashable, Sendable {
    case escape
    case tab
    case enter
    case backspace
    case delete
    case insert
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    /// A function key from F1 through F12. Other numbers are ignored.
    case function(Int)
    /// Text sent as typed. Control and Alt apply to a single character; longer text is sent
    /// unchanged apart from the Alt escape prefix.
    case character(String)

    /// The name the runtime bridge uses for the key, or `nil` for a key it cannot encode.
    var wireName: String? {
        switch self {
        case .escape:
            "escape"
        case .tab:
            "tab"
        case .enter:
            "enter"
        case .backspace:
            "backspace"
        case .delete:
            "delete"
        case .insert:
            "insert"
        case .up:
            "up"
        case .down:
            "down"
        case .left:
            "left"
        case .right:
            "right"
        case .home:
            "home"
        case .end:
            "end"
        case .pageUp:
            "page_up"
        case .pageDown:
            "page_down"
        case let .function(number):
            (1 ... 12).contains(number) ? "f\(number)" : nil
        case let .character(text):
            text.isEmpty ? nil : "character"
        }
    }

    var characterText: String? {
        guard case let .character(text) = self else {
            return nil
        }

        return text
    }
}

/// Modifiers applied to a single key sent with `SwiftTerminalSession.sendKey(_:modifiers:)`.
public struct SwiftTerminalKeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let alt = Self(rawValue: 1 << 1)
    public static let ctrl = Self(rawValue: 1 << 2)
    public static let meta = Self(rawValue: 1 << 3)

    static let wireNames: [(Self, String)] = [
        (.ctrl, "ctrl"),
        (.alt, "alt"),
        (.shift, "shift"),
        (.meta, "meta"),
    ]
}

extension SwiftTerminalKeyModifiers: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let names = try container.decode([String].self)
        var modifiers: Self = []
        for (modifier, name) in Self.wireNames where names.contains(name) {
            modifiers.insert(modifier)
        }
        self = modifiers
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.wireNames.filter { contains($0.0) }.map(\.1))
    }
}

/// How a sticky modifier applies to the keys that follow it.
public enum SwiftTerminalKeyModifierState: String, Codable, Hashable, Sendable {
    /// The modifier is not applied.
    case off
    /// The modifier applies to the next key only, then turns off.
    case oneShot = "one_shot"
    /// The modifier applies to every key until the host turns it off.
    case sustained
}

/// The sticky modifier state the runtime applies to keys sent with `sendKey(_:modifiers:)` and to
/// single printable characters typed on the system keyboard.
public struct SwiftTerminalKeyModifierStates: Codable, Hashable, Sendable {
    public var ctrl: SwiftTerminalKeyModifierState
    public var alt: SwiftTerminalKeyModifierState
    public var shift: SwiftTerminalKeyModifierState
    public var meta: SwiftTerminalKeyModifierState

    public init(
        ctrl: SwiftTerminalKeyModifierState = .off,
        alt: SwiftTerminalKeyModifierState = .off,
        shift: SwiftTerminalKeyModifierState = .off,
        meta: SwiftTerminalKeyModifierState = .off
    ) {
        self.ctrl = ctrl
        self.alt = alt
        self.shift = shift
        self.meta = meta
    }

    public static let off = Self()

    /// Whether every modifier is off.
    public var isOff: Bool {
        self == .off
    }

    private enum CodingKeys: String, CodingKey {
        case ctrl
        case alt
        case shift
        case meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ctrl = try container.decodeIfPresent(SwiftTerminalKeyModifierState.self, forKey: .ctrl) ?? .off
        alt = try container.decodeIfPresent(SwiftTerminalKeyModifierState.self, forKey: .alt) ?? .off
        shift = try container.decodeIfPresent(SwiftTerminalKeyModifierState.self, forKey: .shift) ?? .off
        meta = try container.decodeIfPresent(SwiftTerminalKeyModifierState.self, forKey: .meta) ?? .off
    }
}
