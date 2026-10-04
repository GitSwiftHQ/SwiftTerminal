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
///
/// The keyboard accessory follows one rule: an instance never changes its height once created.
/// UIKit keeps the height it recorded when it presented an instance, and an instance that later
/// takes another height leaves `keyboardLayoutGuide` and the SwiftUI keyboard safe area off by
/// the difference. Whenever the accessory needs a different height, because the keyboard is
/// hidden or a hardware keyboard leaves the bar at the bottom of the screen, the safe area below
/// it changes, or the host content takes another height, the web view moves the content into an
/// instance with that height and reloads the input views.
@MainActor
final class SwiftTerminalUIKitWebView: WKWebView, TerminalKeyboardInputControlling {
    var onKeyboardAccessoryAttachmentChange: (@MainActor (Bool) -> Void)?

    /// The instance `inputAccessoryView` returns while there is content.
    private var keyboardAccessoryView: SwiftTerminalKeyboardAccessoryView?
    /// Instances kept for reuse, one per sizing; each keeps the height it was created with.
    private var keyboardAccessoryViews: [SwiftTerminalKeyboardAccessoryView] = []
    private var keyboardAccessoryContentView: UIView?
    private var keyboardAccessoryPlacementRecord = TerminalKeyboardAccessoryPlacementRecord()
    /// The instance the terminal swapped in on its own, until UIKit has placed it where it fits.
    private weak var swappedKeyboardAccessoryView: SwiftTerminalKeyboardAccessoryView?
    /// How many instances are in a window. While UIKit swaps one instance for another, both can
    /// be, so the bar counts as attached until the last one leaves.
    private var attachedKeyboardAccessoryCount = 0
    private var isKeyboardAccessoryAttached = false
    private var isKeyboardAccessoryDetachmentPending = false
    private var windowGeometryObservation: NSKeyValueObservation?
    /// The interface orientation the window scene last reported with its geometry.
    private var reportedInterfaceOrientation: UIInterfaceOrientation?
    private let emptyInputView = UIView(frame: .zero)
    private var softwareKeyboardMode = SwiftTerminalSoftwareKeyboardMode.system
    private var clearedAssistantGroups: (
        leading: [UIBarButtonItemGroup],
        trailing: [UIBarButtonItemGroup]
    )?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameDidChange(_:)),
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var inputAccessoryView: UIView? {
        if keyboardAccessoryContentView != nil, let keyboardAccessoryView {
            return keyboardAccessoryView
        }

        return super.inputAccessoryView
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
        if keyboardAccessoryContentView != nil {
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

    /// Replacing one content view with another also reloads, so UIKit shows an accessory measured
    /// for the new view, for example when a host swaps its bar for a view with no height.
    func setKeyboardAccessoryContentView(_ contentView: UIView?) {
        guard contentView !== keyboardAccessoryContentView else {
            return
        }

        keyboardAccessoryContentView = contentView
        swappedKeyboardAccessoryView = nil
        if let contentView {
            installKeyboardAccessoryView(
                contentHeight: Self.fittingHeight(of: contentView, width: estimatedAccessoryContentWidth)
            )
        } else {
            // The instance keeps its height; UIKit replaces it with WebKit's own accessory.
            keyboardAccessoryView?.setContentView(nil)
        }
        reloadTerminalInputViews()
    }

    func setSoftwareKeyboardMode(_ mode: SwiftTerminalSoftwareKeyboardMode) {
        guard mode != softwareKeyboardMode else {
            return
        }

        softwareKeyboardMode = mode
        swappedKeyboardAccessoryView = nil
        if let keyboardAccessoryView, keyboardAccessoryContentView != nil {
            installKeyboardAccessoryView(contentHeight: keyboardAccessoryView.sizing.contentHeight)
        }
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

    private var keyboardAccessoryPresentation: TerminalKeyboardAccessoryPresentation {
        switch softwareKeyboardMode {
        case .system:
            .systemKeyboard
        case .hidden:
            .noKeyboard
        case .custom:
            .hostInputView
        }
    }

    private var windowBottomInset: CGFloat {
        window?.safeAreaInsets.bottom ?? 0
    }

    /// The width the content gets in the bar above the keyboard, which spans the screen.
    private var estimatedAccessoryContentWidth: CGFloat {
        guard let window else {
            return 0
        }

        let insets = window.safeAreaInsets
        let width = window.bounds.width - insets.left - insets.right
            - SwiftTerminalKeyboardAccessoryView.contentHorizontalInset * 2
        return max(0, width)
    }

    /// Makes the instance `inputAccessoryView` returns one with `contentHeight` and, unless given,
    /// the home indicator space predicted for the current mode, and moves the content into it.
    /// Called before a reload, never while UIKit presents an instance.
    private func installKeyboardAccessoryView(
        contentHeight: CGFloat,
        bottomReserve: CGFloat? = nil,
        keepsContentOnScreen: Bool = false
    ) {
        guard let contentView = keyboardAccessoryContentView else {
            return
        }

        let sizing = TerminalKeyboardAccessorySizing(
            contentHeight: contentHeight,
            contentBottomInset: SwiftTerminalKeyboardAccessoryView.contentBottomInset,
            bottomReserve: bottomReserve ?? keyboardAccessoryPlacementRecord.predictedBottomReserve(
                for: keyboardAccessoryPresentation,
                windowBottomInset: windowBottomInset
            )
        )
        // Instances for an earlier content height are no longer useful. One may still be on
        // screen while UIKit animates it away; UIKit keeps it until then.
        keyboardAccessoryViews.removeAll {
            !TerminalKeyboardAccessorySizing.isSame($0.sizing.contentHeight, contentHeight)
        }
        let accessory = keyboardAccessoryViews.first { $0.sizing.matches(sizing) } ?? {
            let accessory = SwiftTerminalKeyboardAccessoryView(sizing: sizing)
            accessory.onWindowAttachmentChange = { [weak self] isAttached in
                self?.keyboardAccessoryWindowAttachmentDidChange(isAttached)
            }
            accessory.onWillEnterWindow = { [weak self] accessory in
                self?.keyboardAccessoryWillEnterWindow(accessory)
            }
            accessory.onLayout = { [weak self] accessory in
                self?.keyboardAccessoryDidLayout(accessory)
            }
            keyboardAccessoryViews.append(accessory)
            return accessory
        }()
        // A swap made while UIKit animates the keyboard takes effect only once that animation
        // ends. Until then the content stays in the instance on screen, so the bar keeps its keys
        // and a host that finds the bar from its content still finds it; it moves as UIKit puts
        // the new instance in a window. Every other swap takes effect with the reload, and the
        // content moves at once.
        let presentedAccessory = sequence(first: contentView, next: \.superview)
            .lazy
            .compactMap { $0 as? SwiftTerminalKeyboardAccessoryView }
            .first { $0.window != nil }
        if !keepsContentOnScreen || presentedAccessory == nil || presentedAccessory === accessory {
            if accessory !== keyboardAccessoryView {
                keyboardAccessoryView?.setContentView(nil)
            }
            accessory.setContentView(contentView)
        }
        keyboardAccessoryView = accessory
    }

    /// Moves the content into the installed instance as UIKit puts it in a window.
    private func keyboardAccessoryWillEnterWindow(_ accessory: SwiftTerminalKeyboardAccessoryView) {
        guard accessory === keyboardAccessoryView, let contentView = keyboardAccessoryContentView else {
            return
        }

        accessory.setContentView(contentView)
    }

    /// Checks the presented instance's content height after a layout pass, and installs an
    /// instance with the new height if the content changed it.
    ///
    /// Only the content height is judged here, since it does not depend on where UIKit puts the
    /// instance. While UIKit brings the accessory in, it first lays the instance out at the bottom
    /// of the screen, where its bottom safe area briefly covers the home indicator although a
    /// keyboard will lie below it, so the placement is judged only at the moments described in
    /// ``keyboardFrameWillChange(_:)`` and ``keyboardFrameDidChange(_:)``.
    private func keyboardAccessoryDidLayout(_ accessory: SwiftTerminalKeyboardAccessoryView) {
        guard isPresentedKeyboardAccessoryView(accessory),
              let laidOutContentHeight = accessory.laidOutContentHeight,
              !TerminalKeyboardAccessorySizing.isSame(laidOutContentHeight, accessory.sizing.contentHeight)
        else {
            return
        }

        swapKeyboardAccessoryView(
            to: TerminalKeyboardAccessorySizing(
                contentHeight: laidOutContentHeight,
                contentBottomInset: accessory.sizing.contentBottomInset,
                bottomReserve: accessory.sizing.bottomReserve
            )
        )
    }

    /// Checks the presented instance against where UIKit placed it once UIKit announces an
    /// animated keyboard frame change.
    ///
    /// UIKit sets the accessory's final frame before it announces the frame it animates to, so
    /// the instance's bottom safe area then tells whether a keyboard or a host input view lies
    /// below it or the bar sits at the bottom of the screen, as it does with no keyboard and with
    /// a hardware keyboard. Judging here swaps the instance before the animation starts.
    ///
    /// A keyboard on its way off the screen is skipped, here and in ``keyboardFrameDidChange(_:)``:
    /// the instance leaving with it says nothing about where the next one goes, and a reload then
    /// would bring back the keyboard the person is dismissing, since the content view still holds
    /// the first responder when UIKit announces the frame. Frame changes without an animation are
    /// left to ``keyboardFrameDidChange(_:)``.
    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              duration > 0,
              !isKeyboardLeavingScreen(notification)
        else {
            return
        }

        // A new animated change starts from where UIKit puts the accessory now.
        swappedKeyboardAccessoryView = nil
        checkKeyboardAccessoryPlacement(duringKeyboardAnimation: true)
    }

    /// Checks the presented instance against where UIKit placed it once a keyboard frame change
    /// is done.
    ///
    /// With a hardware keyboard, UIKit presents the accessory at the bottom of the screen and only
    /// announces that afterwards, with a frame that does not describe the accessory, so the
    /// instance itself is checked. An accessory that left its window with a dismissed keyboard
    /// is not presented any more and is left alone.
    ///
    /// UIKit also announces frames while it is still animating the keyboard into place, with the
    /// accessory shown where it was before; those are skipped until nothing above the accessory
    /// is animating. After the terminal swapped instances on its own, UIKit first shows the new
    /// one where the old one was as well, so placements are not judged again until the new
    /// instance fits where it sits.
    @objc private func keyboardFrameDidChange(_ notification: Notification) {
        guard !isKeyboardLeavingScreen(notification) else {
            return
        }

        checkRestingKeyboardAccessoryPlacement()
    }

    /// Whether the announced frame takes the keyboard below the screen.
    ///
    /// With a hardware keyboard, UIKit announces an empty frame at the bottom edge while the bar
    /// stays on screen; that is not a keyboard leaving. On iOS 18 a rotation starts with such a
    /// departure before the interface orientation changes, with the bar at the bottom of the
    /// screen on its way out.
    private func isKeyboardLeavingScreen(_ notification: Notification) -> Bool {
        guard let screenBounds = window?.windowScene?.screen.bounds,
              let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return false
        }

        return endFrame.height > 0 && endFrame.minY >= screenBounds.maxY
    }

    /// Checks the placement of an accessory that UIKit has stopped moving.
    private func checkRestingKeyboardAccessoryPlacement() {
        guard let accessory = keyboardAccessoryView, !Self.isAnimating(accessory) else {
            return
        }

        checkKeyboardAccessoryPlacement()
    }

    /// Whether the interface is between two orientations.
    ///
    /// UIKit announces the keyboard frames of a rotation before the scene reports its new
    /// geometry. By then either the scene's interface orientation differs from the one it last
    /// reported, or, as on iOS 18 at the start of a rotation, the screen's bounds already have the
    /// new aspect while the interface orientation is still the old one.
    private var isInterfaceRotating: Bool {
        guard let windowScene = window?.windowScene else {
            return false
        }

        let orientation = windowScene.effectiveGeometry.interfaceOrientation
        let screenBounds = windowScene.screen.bounds
        let isScreenLandscape = screenBounds.width > screenBounds.height
        return orientation != reportedInterfaceOrientation
            || (orientation != .unknown && orientation.isLandscape != isScreenLandscape)
    }

    private static func isAnimating(_ view: UIView) -> Bool {
        sequence(first: view, next: \.superview).contains { $0.layer.animationKeys()?.isEmpty == false }
    }

    /// Installs an instance that fits where UIKit placed the presented one, if it does not fit.
    ///
    /// While the interface rotates, UIKit announces a series of keyboard frames, some of which
    /// briefly place the accessory at the bottom of the screen above where the keyboard returns.
    /// They are skipped; ``windowGeometryDidChange()`` handles the rotation itself.
    private func checkKeyboardAccessoryPlacement(duringKeyboardAnimation: Bool = false) {
        guard let accessory = keyboardAccessoryView,
              isPresentedKeyboardAccessoryView(accessory),
              !isInterfaceRotating
        else {
            return
        }

        let bottomSafeAreaInset = accessory.safeAreaInsets.bottom
        let replacement = accessory.sizing.replacement(
            laidOutContentHeight: accessory.laidOutContentHeight ?? accessory.sizing.contentHeight,
            bottomSafeAreaInset: bottomSafeAreaInset
        )
        if swappedKeyboardAccessoryView != nil {
            guard swappedKeyboardAccessoryView === accessory, replacement == nil else {
                return
            }

            swappedKeyboardAccessoryView = nil
        }

        keyboardAccessoryPlacementRecord.record(
            bottomSafeAreaInset: bottomSafeAreaInset,
            windowBottomInset: windowBottomInset,
            for: keyboardAccessoryPresentation
        )
        guard let replacement else {
            return
        }

        swapKeyboardAccessoryView(to: replacement, duringKeyboardAnimation: duringKeyboardAnimation)
    }

    /// Installs an instance with `sizing` in place of the presented one and reloads, then waits
    /// for UIKit to place it before judging placements again.
    private func swapKeyboardAccessoryView(
        to sizing: TerminalKeyboardAccessorySizing,
        duringKeyboardAnimation: Bool = false
    ) {
        installKeyboardAccessoryView(
            contentHeight: sizing.contentHeight,
            bottomReserve: sizing.bottomReserve,
            keepsContentOnScreen: duringKeyboardAnimation
        )
        swappedKeyboardAccessoryView = keyboardAccessoryView
        reloadTerminalInputViews()
    }

    /// Gives a docked accessory the home indicator space of the geometry a rotation ends in, while
    /// the keyboard is hidden.
    ///
    /// A rotation keeps the accessory where it was relative to the keyboard, at the bottom of the
    /// screen or above a keyboard; only the home indicator space of a docked accessory changes,
    /// for example from 34 to 20 points on an iPhone turned to landscape. With the keyboard
    /// hidden, the window's bottom safe area and the accessory's own have the new value when the
    /// scene reports its geometry, nothing else follows, and a reload then swaps the instance
    /// cleanly.
    ///
    /// While the system keyboard or a host input view is selected and a hardware keyboard keeps
    /// the bar at the bottom of the screen, UIKit is still animating the input views into the new
    /// orientation at that moment and announces nothing once it is done. A reload during that
    /// animation, or an instance installed before it, leaves the bar or the keyboard layout guide
    /// above an empty keyboard area after a turn back to portrait, so that bar keeps its instance
    /// until the next keyboard change checks it.
    private func windowGeometryDidChange() {
        reportedInterfaceOrientation = window?.windowScene?.effectiveGeometry.interfaceOrientation
        guard keyboardAccessoryPresentation == .noKeyboard,
              let accessory = keyboardAccessoryView,
              accessory.window != nil,
              TerminalKeyboardAccessorySizing.isSame(accessory.safeAreaInsets.bottom, windowBottomInset)
        else {
            return
        }

        swapToWindowDockedReserveIfNeeded()
    }

    /// Swaps a presented docked instance for one that reserves the window's current home
    /// indicator space.
    private func swapToWindowDockedReserveIfNeeded() {
        guard let accessory = keyboardAccessoryView,
              isPresentedKeyboardAccessoryView(accessory),
              accessory.sizing.bottomReserve >= TerminalKeyboardAccessorySizing.tolerance,
              !TerminalKeyboardAccessorySizing.isSame(accessory.sizing.bottomReserve, windowBottomInset)
        else {
            return
        }

        let sizing = TerminalKeyboardAccessorySizing(
            contentHeight: accessory.sizing.contentHeight,
            contentBottomInset: accessory.sizing.contentBottomInset,
            bottomReserve: windowBottomInset
        )
        keyboardAccessoryPlacementRecord.record(
            bottomSafeAreaInset: sizing.bottomReserve,
            windowBottomInset: windowBottomInset,
            for: keyboardAccessoryPresentation
        )
        swapKeyboardAccessoryView(to: sizing)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportedInterfaceOrientation = window?.windowScene?.effectiveGeometry.interfaceOrientation
        windowGeometryObservation = window?.windowScene?.observe(\.effectiveGeometry) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.windowGeometryDidChange()
            }
        }
    }

    private func isPresentedKeyboardAccessoryView(_ accessory: SwiftTerminalKeyboardAccessoryView) -> Bool {
        accessory === keyboardAccessoryView
            && keyboardAccessoryContentView != nil
            && accessory.window != nil
            && accessory.bounds.width > 0
            && firstResponderView() != nil
    }

    private func keyboardAccessoryWindowAttachmentDidChange(_ isAttached: Bool) {
        attachedKeyboardAccessoryCount = max(0, attachedKeyboardAccessoryCount + (isAttached ? 1 : -1))
        if isAttached {
            checkKeyboardAccessoryPlacementAfterLayoutPass()
        }
        updateKeyboardAccessoryAttachment()
    }

    /// Checks the placement of an instance that just entered a window once the current layout
    /// pass is over.
    ///
    /// UIKit can put an instance in place without announcing a keyboard frame afterwards, for
    /// example when a hardware keyboard is connected and the system keyboard is selected again
    /// while the keyboard is hidden. It adds the instance in the same layout pass in which it
    /// announces and starts any keyboard animation, so on the main actor's next turn the instance
    /// is either moving, and a later announcement covers it, or resting where it stays.
    private func checkKeyboardAccessoryPlacementAfterLayoutPass() {
        Task { @MainActor [weak self] in
            self?.checkRestingKeyboardAccessoryPlacement()
        }
    }

    /// Reports the bar entering a window at once, and leaving only after the main actor's next
    /// turn.
    ///
    /// When the terminal swaps instances, UIKit takes the old one out of its window and puts the
    /// new one in during the layout pass that follows the reload, outside the reload call, with
    /// the old one leaving first. Both happen before the main actor runs its next job, so
    /// waiting for that job turns the swap into no change, and the host only hears about the bar
    /// really entering or leaving the screen.
    private func updateKeyboardAccessoryAttachment() {
        guard attachedKeyboardAccessoryCount == 0 else {
            reportKeyboardAccessoryAttachment()
            return
        }

        guard !isKeyboardAccessoryDetachmentPending else {
            return
        }

        isKeyboardAccessoryDetachmentPending = true
        Task { @MainActor [weak self] in
            self?.isKeyboardAccessoryDetachmentPending = false
            self?.reportKeyboardAccessoryAttachment()
        }
    }

    private func reportKeyboardAccessoryAttachment() {
        let isAnyAttached = attachedKeyboardAccessoryCount > 0
        guard isAnyAttached != isKeyboardAccessoryAttached else {
            return
        }

        isKeyboardAccessoryAttached = isAnyAttached
        onKeyboardAccessoryAttachmentChange?(isAnyAttached)
    }

    private static func fittingHeight(of contentView: UIView, width: CGFloat) -> CGFloat {
        let size = if width > 0 {
            contentView.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
        } else {
            contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        }
        return max(0, size.height)
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
#endif
