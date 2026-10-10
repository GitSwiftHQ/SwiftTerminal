//
//  TerminalKeyboardAccessorySizing.swift
//  SwiftTerminal
//
//  Created by GitSwift on 2026/10/04.
//

import CoreGraphics

/// Where UIKit puts the keyboard accessory, as far as its height is concerned.
enum TerminalKeyboardAccessoryPlacement: Hashable, Sendable {
    /// The system keyboard or a host input view lies below the bar.
    case aboveInputView
    /// Nothing lies below the bar, which sits at the bottom of the screen over the home indicator's
    /// area, as it does while the keyboard is hidden or a hardware keyboard is in use.
    case bottomOfScreen

    /// The placement an instance's own bottom safe area shows: the home indicator space it
    /// overlaps, which is zero while an input view lies below it.
    init(bottomSafeAreaInset: CGFloat) {
        self = bottomSafeAreaInset >= TerminalKeyboardAccessorySizing.tolerance ? .bottomOfScreen : .aboveInputView
    }
}

/// How one keyboard accessory instance takes its height, for its whole life.
///
/// The iOS 26 keyboard records an input accessory's height when it presents the accessory, and
/// when the same instance comes back with another height after a change of input views, it keeps
/// using the old record for `keyboardLayoutGuide` and the SwiftUI keyboard safe area. The keyboard
/// notifications report the right frame, but the guide and the safe area stay off by the
/// difference. The keyboard does measure an instance again while it keeps presenting it through a
/// rotation. The terminal therefore never shows one instance at two placements:
///
/// - Above an input view, an instance has a fixed height, from the content height it was created
///   for, and keeps it even when the content is removed. A different content height gets another
///   instance.
/// - At the bottom of the screen, an instance reserves the home indicator space below the bar. It
///   starts with the window's home indicator space, the height the keyboard measures before it
///   places the instance, and then follows its own bottom safe area while that is not zero, so a
///   rotation gives the bar the landscape or portrait space. Such an instance is created whenever
///   the bar moves there and is not shown again once it has left its window.
struct TerminalKeyboardAccessorySizing: Equatable, Sendable {
    /// Heights closer than this are the same height; they come from Auto Layout and safe areas,
    /// which can differ by rounding.
    static let tolerance: CGFloat = 0.5

    /// Whether the instance takes its height from Auto Layout, from its content height and the
    /// home indicator space below the bar, rather than from its frame.
    var sizesItself: Bool
    /// The content height the instance is created for.
    var contentHeight: CGFloat
    /// The home indicator space an instance that sizes itself starts with.
    var bottomReserve: CGFloat

    init(sizesItself: Bool, contentHeight: CGFloat, bottomReserve: CGFloat = 0) {
        self.sizesItself = sizesItself
        self.contentHeight = contentHeight
        self.bottomReserve = sizesItself ? max(0, bottomReserve) : 0
    }

    /// The sizing of an instance for `placement`, which at the bottom of the screen starts with
    /// `bottomReserve`.
    init(placement: TerminalKeyboardAccessoryPlacement, contentHeight: CGFloat, bottomReserve: CGFloat) {
        self.init(sizesItself: placement == .bottomOfScreen, contentHeight: contentHeight, bottomReserve: bottomReserve)
    }

    /// The frame height of an instance with a fixed height, given the space below the content
    /// inside the bar.
    func fixedHeight(contentBottomInset: CGFloat) -> CGFloat {
        contentHeight + contentBottomInset
    }

    /// Whether an instance with this sizing can stand in for one with `other`. An instance that
    /// sizes itself follows its home indicator space, so that does not count.
    func matches(_ other: Self) -> Bool {
        sizesItself == other.sizesItself && Self.isSame(contentHeight, other.contentHeight)
    }

    /// The sizing a presented instance should have been given, from where UIKit placed it.
    ///
    /// `bottomSafeAreaInset` is the instance's own bottom safe area, which tells its placement,
    /// and `laidOutContentHeight` is the height the content takes in it as laid out. Returns `nil`
    /// while the instance fits both, otherwise the sizing of the instance to install instead. An
    /// instance with the returned sizing, placed at the same spot, fits by construction, so a
    /// replacement never asks for another one.
    func replacement(laidOutContentHeight: CGFloat, bottomSafeAreaInset: CGFloat) -> Self? {
        let fitting = Self(
            placement: TerminalKeyboardAccessoryPlacement(bottomSafeAreaInset: bottomSafeAreaInset),
            contentHeight: max(0, laidOutContentHeight),
            bottomReserve: bottomSafeAreaInset
        )
        return fitting.matches(self) ? nil : fitting
    }

    static func isSame(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < tolerance
    }
}

/// What lies below the keyboard accessory in each software keyboard mode, unless a hardware
/// keyboard is in use.
enum TerminalKeyboardAccessoryPresentation: Hashable, Sendable {
    /// The system keyboard, or with a hardware keyboard in use, nothing.
    case systemKeyboard
    /// A host input view, or with a hardware keyboard in use, possibly nothing.
    case hostInputView
    /// Nothing: the accessory sits at the bottom of the screen.
    case noKeyboard
}

/// Remembers where UIKit placed the accessory for each presentation, so the next time the
/// terminal shows it, the instance it installs already fits there.
///
/// The record only predicts; the instance UIKit actually presents is checked against its own
/// bottom safe area and replaced if the prediction was wrong. Predicting well avoids that second
/// step, which would show the bar once at the wrong height. A hardware keyboard, for example,
/// leaves the accessory at the bottom of the screen in every presentation, so once the record has
/// seen that, the next presentation starts with an instance for the bottom of the screen.
struct TerminalKeyboardAccessoryPlacementRecord: Sendable {
    private var placements: [TerminalKeyboardAccessoryPresentation: TerminalKeyboardAccessoryPlacement] = [:]

    func predictedPlacement(
        for presentation: TerminalKeyboardAccessoryPresentation
    ) -> TerminalKeyboardAccessoryPlacement {
        if presentation == .noKeyboard {
            return .bottomOfScreen
        }

        return placements[presentation] ?? .aboveInputView
    }

    mutating func record(
        _ placement: TerminalKeyboardAccessoryPlacement,
        for presentation: TerminalKeyboardAccessoryPresentation
    ) {
        placements[presentation] = placement
    }
}
