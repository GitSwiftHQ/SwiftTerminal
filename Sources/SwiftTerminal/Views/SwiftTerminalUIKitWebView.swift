//
//  SwiftTerminalUIKitWebView.swift
//  SwiftTerminal
//
//  Created by GitSwift on 2026/09/29.
//

#if canImport(UIKit)
import UIKit
import WebKit

/// The terminal's web view on iOS, which owns the input views UIKit shows while the terminal
/// holds the keyboard focus.
///
/// WebKit's content view, the actual first responder, asks the web view for its
/// `inputAccessoryView`, `inputView`, and `inputAssistantItem`, so overriding them here is the
/// supported way to replace WebKit's form assistant bar and to hide or replace the software
/// keyboard while the terminal's input stays focused.
@MainActor
final class SwiftTerminalUIKitWebView: WKWebView, TerminalKeyboardInputControlling {
    var onKeyboardAccessoryAttachmentChange: (@MainActor (Bool) -> Void)? {
        didSet {
            keyboardAccessoryView.onWindowAttachmentChange = onKeyboardAccessoryAttachmentChange
        }
    }

    private let keyboardAccessoryView = SwiftTerminalKeyboardAccessoryView()
    private let emptyInputView = UIView(frame: .zero)
    private var hasKeyboardAccessoryContent = false
    private var softwareKeyboardMode = SwiftTerminalSoftwareKeyboardMode.system
    private var clearedAssistantGroups: (
        leading: [UIBarButtonItemGroup],
        trailing: [UIBarButtonItemGroup]
    )?

    override var inputAccessoryView: UIView? {
        hasKeyboardAccessoryContent ? keyboardAccessoryView : super.inputAccessoryView
    }

    override var inputView: UIView? {
        switch softwareKeyboardMode {
        case .system:
            super.inputView
        case .hidden:
            emptyInputView
        case let .custom(view):
            view
        }
    }

    override var inputAssistantItem: UITextInputAssistantItem {
        let item = super.inputAssistantItem
        if hasKeyboardAccessoryContent {
            // The iPad shortcuts bar would otherwise show undo, redo, and paste beside the
            // host's own bar. Only its default groups are cleared; nothing is added to it.
            // The item persists across reads, so its groups are kept to restore them once
            // the host removes its bar.
            if clearedAssistantGroups == nil {
                clearedAssistantGroups = (item.leadingBarButtonGroups, item.trailingBarButtonGroups)
            }
            item.leadingBarButtonGroups = []
            item.trailingBarButtonGroups = []
        } else if let clearedAssistantGroups {
            item.leadingBarButtonGroups = clearedAssistantGroups.leading
            item.trailingBarButtonGroups = clearedAssistantGroups.trailing
            self.clearedAssistantGroups = nil
        }
        return item
    }

    /// Replacing one content view with another also reloads, so UIKit measures the accessory
    /// again, for example when a host swaps its bar for a view with no height.
    func setKeyboardAccessoryContentView(_ contentView: UIView?) {
        guard keyboardAccessoryView.setContentView(contentView) else {
            return
        }

        hasKeyboardAccessoryContent = contentView != nil
        reloadTerminalInputViews()
    }

    func setSoftwareKeyboardMode(_ mode: SwiftTerminalSoftwareKeyboardMode) {
        guard mode != softwareKeyboardMode else {
            return
        }

        softwareKeyboardMode = mode
        reloadTerminalInputViews()
    }

    /// Asks UIKit to fetch the input views again from the view that holds the first responder.
    ///
    /// UIKit reads input views from the first responder, which is WebKit's content view inside
    /// the scroll view, so the reload must be sent to that view; sending it to the web view
    /// itself has no effect. A web view that does not hold the focus has nothing to reload.
    func reloadTerminalInputViews() {
        firstResponderView()?.reloadInputViews()
    }

    func resignKeyboardFocus() {
        firstResponderView()?.resignFirstResponder()
    }

    private func firstResponderView() -> UIView? {
        if isFirstResponder {
            return self
        }

        return Self.firstResponderDescendant(of: scrollView)
    }

    private static func firstResponderDescendant(of view: UIView) -> UIView? {
        var pendingViews = [view]
        while !pendingViews.isEmpty {
            let candidate = pendingViews.removeFirst()
            if candidate.isFirstResponder {
                return candidate
            }
            pendingViews.append(contentsOf: candidate.subviews)
        }

        return nil
    }
}

/// The keyboard-styled container for a host's accessory content.
///
/// It uses the keyboard's own input view style, sizes itself from the content's Auto Layout
/// height, enables system keyboard clicks while visible, and reports when it enters or leaves a
/// window, which is the only reliable signal for whether the bar is on screen. On iOS 26 and later
/// the content sits in a glass rounded rectangle that lines up with the system's own bar above the
/// keyboard: 16 pt from the screen edges, about 10 pt above the keyboard's panel, and a 14 pt
/// corner radius that host keys inset by 6 pt can follow concentrically.
@MainActor
final class SwiftTerminalKeyboardAccessoryView: UIInputView, UIInputViewAudioFeedback {
    var onWindowAttachmentChange: (@MainActor (Bool) -> Void)?

    /// The glass container's corner radius on iOS 26 and later.
    static let glassCornerRadius: CGFloat = 14

    private let contentContainer: UIView
    private weak var hostedContentView: UIView?
    private var isAttachedToWindow = false

    init() {
        let glassInset = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16)
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            // The host's keys draw their own pressed state; an interactive glass would animate
            // the whole bar on every key press as well.
            glassEffect.isInteractive = false
            let glassView = UIVisualEffectView(effect: glassEffect)
            glassView.cornerConfiguration = .corners(radius: .fixed(Self.glassCornerRadius))
            glassView.translatesAutoresizingMaskIntoConstraints = false
            contentContainer = glassView.contentView
            super.init(frame: .zero, inputViewStyle: .keyboard)
            addSubview(glassView)
            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(
                    equalTo: safeAreaLayoutGuide.leadingAnchor,
                    constant: glassInset.leading
                ),
                glassView.trailingAnchor.constraint(
                    equalTo: safeAreaLayoutGuide.trailingAnchor,
                    constant: -glassInset.trailing
                ),
                glassView.topAnchor.constraint(equalTo: topAnchor, constant: glassInset.top),
                glassView.bottomAnchor.constraint(
                    equalTo: safeAreaLayoutGuide.bottomAnchor,
                    constant: -glassInset.bottom
                ),
            ])
        } else {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            contentContainer = container
            super.init(frame: .zero, inputViewStyle: .keyboard)
            addSubview(container)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
                container.topAnchor.constraint(equalTo: topAnchor),
                container.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            ])
        }

        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var enableInputClicksWhenVisible: Bool {
        true
    }

    /// Returns whether the content changed.
    @discardableResult
    func setContentView(_ contentView: UIView?) -> Bool {
        guard contentView !== hostedContentView else {
            return false
        }

        hostedContentView?.removeFromSuperview()
        hostedContentView = contentView
        guard let contentView else {
            return true
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        return true
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
}
#endif
