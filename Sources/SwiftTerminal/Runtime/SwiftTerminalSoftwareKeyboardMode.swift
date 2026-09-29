//
//  SwiftTerminalSoftwareKeyboardMode.swift
//  SwiftTerminal
//
//  Created by GitSwift on 2026/09/30.
//

#if canImport(UIKit)
import UIKit

/// What the terminal shows in place of the software keyboard while it holds the keyboard focus
/// on iOS.
///
/// Every mode keeps the terminal's input focused, so the keyboard accessory stays on screen and
/// keys sent with ``SwiftTerminalSession/sendKey(_:modifiers:)`` or typed on a hardware keyboard
/// keep arriving.
public enum SwiftTerminalSoftwareKeyboardMode: Equatable {
    /// The system keyboard.
    case system
    /// No keyboard: only the keyboard accessory remains, at the bottom of the screen.
    case hidden
    /// A host view in place of the system keyboard, such as a panel of extra keys.
    ///
    /// UIKit sizes an input view from its frame or its Auto Layout height, so the view should
    /// have a fixed height, for example a `UIInputView` with a height constraint. The session keeps
    /// a strong reference to the view while the mode is set.
    case custom(UIView)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.system, .system), (.hidden, .hidden):
            true
        case let (.custom(lhsView), .custom(rhsView)):
            lhsView === rhsView
        default:
            false
        }
    }
}
#endif
