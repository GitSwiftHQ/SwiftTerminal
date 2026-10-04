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
/// It uses the keyboard's own input view style, keeps the height it was created with, enables
/// system keyboard clicks while visible, and reports when it enters or leaves a window, which is
/// the only reliable signal for whether the bar is on screen. On iOS 26 and later the content sits
/// in a glass rounded rectangle that lines up with the system's own bar above the keyboard: 16 pt
/// from the screen edges, about 10 pt above the keyboard's panel, and a 14 pt corner radius that
/// host keys inset by 6 pt can follow concentrically. While the bar sits at the bottom of the
/// screen, its ``TerminalKeyboardAccessorySizing/bottomReserve`` keeps the content clear of the
/// home indicator.
@MainActor
final class SwiftTerminalKeyboardAccessoryView: UIInputView, UIInputViewAudioFeedback {
    var onWindowAttachmentChange: (@MainActor (Bool) -> Void)?
    /// Called just before UIKit puts this instance in a window.
    var onWillEnterWindow: (@MainActor (SwiftTerminalKeyboardAccessoryView) -> Void)?
    /// Called after each layout pass, when the instance's safe area or its content's height may
    /// have changed.
    var onLayout: (@MainActor (SwiftTerminalKeyboardAccessoryView) -> Void)?

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

    init(sizing: TerminalKeyboardAccessorySizing) {
        self.sizing = sizing
        let horizontalInset = Self.contentHorizontalInset
        let bottomInset = sizing.contentBottomInset + sizing.bottomReserve
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: sizing.height),
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

        // The bar's bottom edge is fixed by the sizing, never by this view's own safe area, so
        // its position cannot change while UIKit presents it.
        let slotBottom = contentSlot.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        // The content takes its own height, so a change to it shows up in the slot's frame;
        // only content without a height of its own fills the bar.
        slotBottom.priority = .fittingSizeLevel
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
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset),
            contentSlot.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentSlot.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentSlot.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            slotBottom,
        ])

        // The frame carries the height; UIKit only adjusts the width.
        allowsSelfSizing = false
        autoresizingMask = [.flexibleWidth]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var enableInputClicksWhenVisible: Bool {
        true
    }

    /// The height the content takes in this instance as laid out, or `nil` without content or
    /// before the content has been laid out at the bar's width.
    var laidOutContentHeight: CGFloat? {
        guard contentSlot.contentView != nil, contentSlot.hasLaidOutContent else {
            return nil
        }

        return contentSlot.bounds.height
    }

    /// Moves `contentView` into this instance, or removes the current content. The instance's
    /// height stays the same either way.
    func setContentView(_ contentView: UIView?) {
        contentSlot.setContentView(contentView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onLayout?(self)
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
