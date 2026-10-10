//
//  SwiftTerminalKeyboardAccessoryView.swift
//  SwiftTerminal
//
//  Created by GitSwift on 2026/10/04.
//

#if canImport(UIKit)
import UIKit

/// The keyboard-styled container for a host's accessory content.
///
/// It uses the keyboard's own input view style, takes its height as its
/// ``TerminalKeyboardAccessorySizing`` says, enables system keyboard clicks while visible, and
/// reports when it enters or leaves a window, which is the only reliable signal for whether the
/// bar is on screen. On iOS 26 and later the content sits in a glass rounded rectangle that lines
/// up with the system's own bar above the keyboard: 16 pt from the screen edges, about 10 pt above
/// the keyboard's panel, and a 14 pt corner radius that host keys inset by 6 pt can follow
/// concentrically. An instance that sizes itself keeps the content clear of the home indicator
/// while the bar sits at the bottom of the screen.
@MainActor
final class SwiftTerminalKeyboardAccessoryView: UIInputView, UIInputViewAudioFeedback {
    var onWindowAttachmentChange: (@MainActor (Bool) -> Void)?
    /// Called just before UIKit puts this instance in a window.
    var onWillEnterWindow: (@MainActor (SwiftTerminalKeyboardAccessoryView) -> Void)?
    /// Called after each layout pass, when the instance's safe area or its content's height may
    /// have changed.
    var onLayout: (@MainActor (SwiftTerminalKeyboardAccessoryView) -> Void)?

    /// Whether the keyboard keeps using the height it recorded for an accessory instance that
    /// comes back with another height, which the keyboard of iOS 26 and later does.
    ///
    /// The two keyboards need opposite handling. The iOS 18 keyboard measures the accessory again
    /// on every presentation, so one instance that sizes itself from its own safe area serves
    /// every placement there, while installing another instance as the input view changes makes
    /// it hide the whole input area before it shows the new instance, and a reload it receives
    /// as a rotation ends can leave the new instance out of the window. The iOS 26 keyboard keeps
    /// the old height of an instance that comes back resized, which leaves `keyboardLayoutGuide`
    /// and the SwiftUI keyboard safe area off by the difference, so there each placement and
    /// content height gets an instance of its own. Neither behavior can be observed before the
    /// keyboard presents the accessory, and the iOS 26 one only shows in the layout guide after
    /// it has gone wrong, so the choice follows the keyboard generation, which arrived with the
    /// glass appearance of iOS 26. A later keyboard that measures resized instances again still
    /// gets a layout guide that matches the bar from these instances, each shown at one height,
    /// though it might present a change of instance in two steps as the iOS 18 keyboard does.
    nonisolated static var keyboardKeepsRecordedHeight: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
    }

    /// The glass container's corner radius on iOS 26 and later.
    static let glassCornerRadius: CGFloat = 14

    /// Space between the content and the bar's bottom edge, which on iOS 26 and later keeps the
    /// glass bar about 10 pt above the keyboard's panel.
    static var contentBottomInset: CGFloat {
        if #available(iOS 26.0, *) {
            10
        } else {
            0
        }
    }

    /// Space between the content and each side of the safe area.
    static var contentHorizontalInset: CGFloat {
        if #available(iOS 26.0, *) {
            16
        } else {
            0
        }
    }

    let sizing: TerminalKeyboardAccessorySizing

    private let contentSlot = SwiftTerminalKeyboardAccessoryContentSlot()
    private var isAttachedToWindow = false
    /// Keep the home indicator space below the bar of an instance that sizes itself on iOS 26 and
    /// later: the bar's bottom edge, and the instance's height.
    private var bottomReserveConstraints: (containerBottom: NSLayoutConstraint, height: NSLayoutConstraint)?

    init(sizing: TerminalKeyboardAccessorySizing) {
        self.sizing = sizing
        let horizontalInset = Self.contentHorizontalInset
        let bottomInset = Self.contentBottomInset
        // An instance that sizes itself starts with the height it is expected to take, so it
        // never has an empty frame while UIKit puts it in a window.
        super.init(
            frame: CGRect(
                x: 0,
                y: 0,
                width: 0,
                height: sizing.fixedHeight(contentBottomInset: bottomInset) + sizing.bottomReserve
            ),
            inputViewStyle: .keyboard
        )

        let contentContainer: UIView
        let containerView: UIView
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            // The host's keys draw their own pressed state; an interactive glass would animate
            // the whole bar on every key press as well.
            glassEffect.isInteractive = false
            let glassView = UIVisualEffectView(effect: glassEffect)
            glassView.cornerConfiguration = .corners(radius: .fixed(Self.glassCornerRadius))
            contentContainer = glassView.contentView
            containerView = glassView
        } else {
            contentContainer = UIView()
            containerView = contentContainer
        }
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        contentSlot.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentSlot)
        contentSlot.onLayout = { [weak self] in
            self?.contentDidLayout()
        }

        let slotBottom = contentSlot.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        let containerBottom: NSLayoutConstraint
        if sizing.sizesItself, !Self.keyboardKeepsRecordedHeight {
            containerBottom = containerView.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor,
                constant: -bottomInset
            )
        } else if sizing.sizesItself {
            // The height constraint carries the content height the instance was created for and
            // the home indicator space, so the keyboard measures that height even before the
            // content arrives and before the instance has a window and a safe area of its own.
            // The keyboard measures the instance again when the space changes while it presents
            // the instance, as in a rotation. The content takes its own height, so a change to it
            // shows up in the slot's frame.
            let bottomReserve = bottomInset + sizing.bottomReserve
            containerBottom = containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomReserve)
            let height = heightAnchor.constraint(equalToConstant: sizing.contentHeight + bottomReserve)
            height.isActive = true
            slotBottom.priority = .fittingSizeLevel
            bottomReserveConstraints = (containerBottom, height)
        } else {
            // The frame fixes the bar's bottom edge, never this view's own safe area, so its
            // position cannot change while UIKit presents it. The content takes its own height,
            // so a change to it shows up in the slot's frame; only content without a height of
            // its own fills the bar.
            containerBottom = containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset)
            slotBottom.priority = .fittingSizeLevel
        }
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: horizontalInset
            ),
            containerView.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -horizontalInset
            ),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerBottom,
            contentSlot.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentSlot.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentSlot.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            slotBottom,
        ])

        allowsSelfSizing = sizing.sizesItself
        if sizing.sizesItself {
            translatesAutoresizingMaskIntoConstraints = false
        } else {
            // The frame carries the height; UIKit only adjusts the width.
            autoresizingMask = [.flexibleWidth]
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var enableInputClicksWhenVisible: Bool {
        true
    }

    /// The height the content takes in this instance as laid out, or `nil` without content, once
    /// the content has moved to another instance, or before it has been laid out at the bar's
    /// width.
    var laidOutContentHeight: CGFloat? {
        guard contentSlot.contentView?.superview === contentSlot, contentSlot.hasLaidOutContent else {
            return nil
        }

        return contentSlot.bounds.height
    }

    /// Moves `contentView` into this instance, or removes the current content. An instance with a
    /// fixed height keeps it either way.
    func setContentView(_ contentView: UIView?) {
        contentSlot.setContentView(contentView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        reserveBottomSafeArea()
        onLayout?(self)
    }

    /// Makes the home indicator space of an instance that sizes itself its own bottom safe area,
    /// while it sits at the bottom of the screen. Above an input view that safe area is zero and
    /// the space stays as it was, until the terminal installs an instance for that placement.
    private func reserveBottomSafeArea() {
        guard let bottomReserveConstraints, window != nil else {
            return
        }

        let bottomSafeAreaInset = safeAreaInsets.bottom
        let bottomReserve = Self.contentBottomInset + bottomSafeAreaInset
        guard bottomSafeAreaInset >= TerminalKeyboardAccessorySizing.tolerance,
              !TerminalKeyboardAccessorySizing.isSame(-bottomReserveConstraints.containerBottom.constant, bottomReserve)
        else {
            return
        }

        bottomReserveConstraints.containerBottom.constant = -bottomReserve
        bottomReserveConstraints.height.constant = sizing.contentHeight + bottomReserve
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow != nil, window == nil {
            onWillEnterWindow?(self)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let isAttached = window != nil
        guard isAttached != isAttachedToWindow else {
            return
        }

        isAttachedToWindow = isAttached
        onWindowAttachmentChange?(isAttached)
    }

    private func contentDidLayout() {
        onLayout?(self)
    }
}

/// Holds the host's content at the content's own height, so the accessory sees a change to that
/// height in the slot's layout.
@MainActor
private final class SwiftTerminalKeyboardAccessoryContentSlot: UIView {
    var onLayout: (@MainActor () -> Void)?

    private(set) weak var contentView: UIView?
    /// Whether the current content has been laid out at a nonzero width since it arrived.
    private(set) var hasLaidOutContent = false

    func setContentView(_ newContentView: UIView?) {
        if let contentView, contentView !== newContentView, contentView.superview === self {
            contentView.removeFromSuperview()
        }
        contentView = newContentView
        guard let newContentView, newContentView.superview !== self else {
            return
        }

        hasLaidOutContent = false

        // The same content moves between instances of different heights.
        newContentView.removeFromSuperview()
        newContentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newContentView)
        NSLayoutConstraint.activate([
            newContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            newContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            newContentView.topAnchor.constraint(equalTo: topAnchor),
            newContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if contentView?.superview === self, bounds.width > 0 {
            hasLaidOutContent = true
        }
        onLayout?()
    }
}
#endif
