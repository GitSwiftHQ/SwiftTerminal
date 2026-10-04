//
//  TerminalKeyboardAccessorySizing.swift
//  SwiftTerminal
//
//  Created by GitSwift on 2026/10/04.
//

import CoreGraphics

/// The height one keyboard accessory instance keeps for its whole life.
///
/// UIKit records an input accessory's height when it presents it and keeps using that record for
/// `keyboardLayoutGuide` and the SwiftUI keyboard safe area, even after the same instance takes a
/// different height. The keyboard notifications report the right frame, but the guide and the
/// safe area stay off by the difference until the app restarts the presentation from scratch. The
/// terminal therefore never resizes an accessory instance: whenever a different height is needed,
/// it installs another instance with that height before it reloads the input views.
struct TerminalKeyboardAccessorySizing: Equatable, Sendable {
    /// Heights closer than this are the same height; they come from Auto Layout and safe areas,
    /// which can differ by rounding.
    static let tolerance: CGFloat = 0.5

    /// The host content's own height.
    var contentHeight: CGFloat
    /// Space below the content inside the bar, such as the gap between the glass bar and the
    /// keyboard on iOS 26 and later.
    var contentBottomInset: CGFloat
    /// Space below the bar for the home indicator, while the accessory sits at the bottom of the
    /// screen without a keyboard below it.
    var bottomReserve: CGFloat

    var height: CGFloat {
        contentHeight + contentBottomInset + bottomReserve
    }

    func matches(_ other: Self) -> Bool {
        Self.isSame(contentHeight, other.contentHeight)
            && Self.isSame(contentBottomInset, other.contentBottomInset)
            && Self.isSame(bottomReserve, other.bottomReserve)
    }

    /// The sizing a presented instance should have been given, from where UIKit placed it.
    ///
    /// The instance's bottom safe area is the home indicator space it overlaps: zero while a
    /// keyboard or a host input view lies below it, and the home indicator's height while it sits
    /// at the bottom of the screen, as it does with no keyboard or with a hardware keyboard. The
    /// content height is what the content takes in the instance as laid out. Returns `nil` while
    /// the instance already fits both, otherwise the sizing of the instance to install instead.
    /// An instance with the returned sizing, placed at the same spot, fits by construction, so a
    /// replacement never asks for another one.
    func replacement(laidOutContentHeight: CGFloat, bottomSafeAreaInset: CGFloat) -> Self? {
        let fitting = Self(
            contentHeight: max(0, laidOutContentHeight),
            contentBottomInset: contentBottomInset,
            bottomReserve: max(0, bottomSafeAreaInset)
        )
        return fitting.matches(self) ? nil : fitting
    }

    static func isSame(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < tolerance
    }
}

/// What lies below the keyboard accessory, as far as its height is concerned.
enum TerminalKeyboardAccessoryPresentation: Hashable, Sendable {
    /// The system keyboard, or with a hardware keyboard in use, nothing.
    case systemKeyboard
    /// A host input view, or with a hardware keyboard in use, possibly nothing.
    case hostInputView
    /// Nothing: the accessory sits at the bottom of the screen.
    case noKeyboard
}

/// Remembers where UIKit placed the accessory for each presentation, so the next time the
/// terminal shows it, the instance it installs already has the height that fits there.
///
/// The record only predicts; the instance UIKit actually presents is checked against its own
/// bottom safe area and replaced if the prediction was wrong. Predicting well avoids that second
/// step, which would show the bar once at the wrong height. A hardware keyboard, for example,
/// leaves the accessory at the bottom of the screen in every presentation, so once the record has
/// seen that, the next presentation starts with the docked height.
struct TerminalKeyboardAccessoryPlacementRecord: Sendable {
    private struct Observation: Sendable {
        /// The bottom safe area of the terminal's window when the placement was seen, which
        /// tells whether the observation still applies after a rotation.
        var windowBottomInset: CGFloat
        /// The accessory's own bottom safe area where UIKit placed it.
        var bottomSafeAreaInset: CGFloat
    }

    private var observations: [TerminalKeyboardAccessoryPresentation: Observation] = [:]

    /// The home indicator space an instance should reserve before UIKit presents it.
    ///
    /// Without a keyboard the accessory always sits at the bottom of the screen. With a keyboard
    /// it sits at the bottom only when the last presentation found it there. A docked accessory
    /// reserves what it found last time while the window's safe area is unchanged, and the
    /// window's bottom safe area otherwise.
    func predictedBottomReserve(
        for presentation: TerminalKeyboardAccessoryPresentation,
        windowBottomInset: CGFloat
    ) -> CGFloat {
        let observation = observations[presentation]
        let isDocked = presentation == .noKeyboard
            || (observation?.bottomSafeAreaInset ?? 0) >= TerminalKeyboardAccessorySizing.tolerance
        guard isDocked else {
            return 0
        }

        if let observation,
           TerminalKeyboardAccessorySizing.isSame(observation.windowBottomInset, windowBottomInset)
        {
            return observation.bottomSafeAreaInset
        }

        return max(0, windowBottomInset)
    }

    mutating func record(
        bottomSafeAreaInset: CGFloat,
        windowBottomInset: CGFloat,
        for presentation: TerminalKeyboardAccessoryPresentation
    ) {
        observations[presentation] = Observation(
            windowBottomInset: windowBottomInset,
            bottomSafeAreaInset: max(0, bottomSafeAreaInset)
        )
    }
}
