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
/// The keyboard accessory follows the rule ``TerminalKeyboardAccessorySizing`` describes on iOS 26
/// and later, whose keyboard keeps the height it recorded for a presented accessory instance:
/// whenever the bar needs to take its height another way, because it moves between the bottom of
/// the screen and the top of an input view or the host content takes another height above an
/// input view, the web view moves the content into another instance and reloads the input views.
/// The iOS 18 keyboard measures the accessory again on every presentation, and it hides the whole
/// input area before it shows another instance that arrives with an empty input view, so there one
/// instance that sizes itself serves every placement.
@MainActor
final class SwiftTerminalUIKitWebView: WKWebView, TerminalKeyboardInputControlling {
    var onKeyboardAccessoryAttachmentChange: (@MainActor (Bool) -> Void)?

    private static var keyboardKeepsRecordedAccessoryHeight: Bool {
        SwiftTerminalKeyboardAccessoryView.keyboardKeepsRecordedHeight
    }

    /// The instance `inputAccessoryView` returns while there is content.
    private var keyboardAccessoryView: SwiftTerminalKeyboardAccessoryView?
    /// Instances with a fixed height kept for reuse; each keeps the height it was created with.
    private var fixedHeightKeyboardAccessoryViews: [SwiftTerminalKeyboardAccessoryView] = []
    private var keyboardAccessoryContentView: UIView?
    private var keyboardAccessoryPlacementRecord = TerminalKeyboardAccessoryPlacementRecord()
    /// The instance the terminal swapped in on its own, until UIKit has placed it where it fits.
    private weak var swappedKeyboardAccessoryView: SwiftTerminalKeyboardAccessoryView?
    /// An instance that replaced another one on screen, until the input views are reloaded with
    /// it at rest.
    private weak var unsettledKeyboardAccessoryView: SwiftTerminalKeyboardAccessoryView?
    /// How many instances are in a window. While UIKit swaps one instance for another, both can
    /// be, so the bar counts as attached until the last one leaves.
    private var attachedKeyboardAccessoryCount = 0
    private var isKeyboardAccessoryAttached = false
    private var isKeyboardAccessoryDetachmentPending = false
    private var windowGeometryObservation: NSKeyValueObservation?
    /// Waits for the presented instance to come to rest.
    private var restingPlacementCheck: Task<Void, Never>?
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
        guard Self.keyboardKeepsRecordedAccessoryHeight else {
            return
        }

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
                predictedKeyboardAccessorySizing(
                    contentHeight: Self.fittingHeight(of: contentView, width: estimatedAccessoryContentWidth)
                )
            )
        } else {
            // An instance with a fixed height keeps it; UIKit replaces the instance with WebKit's
            // own accessory.
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
            installKeyboardAccessoryView(
                predictedKeyboardAccessorySizing(contentHeight: Self.contentHeight(in: keyboardAccessoryView))
            )
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

    /// The sizing for the current mode, from where the bar went the last time in that mode.
    private func predictedKeyboardAccessorySizing(contentHeight: CGFloat) -> TerminalKeyboardAccessorySizing {
        guard Self.keyboardKeepsRecordedAccessoryHeight else {
            return TerminalKeyboardAccessorySizing(sizesItself: true, contentHeight: contentHeight)
        }

        return TerminalKeyboardAccessorySizing(
            placement: keyboardAccessoryPlacementRecord.predictedPlacement(for: keyboardAccessoryPresentation),
            contentHeight: contentHeight,
            bottomReserve: window?.safeAreaInsets.bottom ?? 0
        )
    }

    /// Makes the instance `inputAccessoryView` returns one with `sizing` and moves the content
    /// into it. Called before a reload, never while UIKit presents an instance.
    private func installKeyboardAccessoryView(_ sizing: TerminalKeyboardAccessorySizing) {
        guard let contentView = keyboardAccessoryContentView else {
            return
        }

        let accessory = reusableKeyboardAccessoryView(for: sizing) ?? makeKeyboardAccessoryView(sizing)
        // UIKit replaces the instance on screen only once it puts the new one in a window, which
        // can be a whole keyboard animation after the reload. Until then the content stays in the
        // instance on screen, so the bar keeps its keys and a host that finds the bar from its
        // content still finds it on screen; it moves as UIKit puts the new instance in a window.
        // Without an instance on screen, the content moves at once.
        let presentedAccessory = sequence(first: contentView, next: \.superview)
            .lazy
            .compactMap { $0 as? SwiftTerminalKeyboardAccessoryView }
            .first { $0.window != nil }
        if presentedAccessory == nil || presentedAccessory === accessory {
            if accessory !== keyboardAccessoryView {
                keyboardAccessoryView?.setContentView(nil)
            }
            accessory.setContentView(contentView)
        }
        keyboardAccessoryView = accessory
    }

    /// An existing instance that can take `sizing`, if any.
    ///
    /// Before iOS 26 the one instance serves every placement. An instance that sizes itself is
    /// reused only while UIKit still presents it, for example when a hardware keyboard keeps the
    /// bar at the bottom of the screen in another mode, so it never comes back with a height from
    /// an earlier presentation. Instances with a fixed height are kept for their content height.
    private func reusableKeyboardAccessoryView(
        for sizing: TerminalKeyboardAccessorySizing
    ) -> SwiftTerminalKeyboardAccessoryView? {
        guard Self.keyboardKeepsRecordedAccessoryHeight else {
            return keyboardAccessoryView
        }

        if sizing.sizesItself {
            guard let keyboardAccessoryView, keyboardAccessoryView.sizing.matches(sizing), keyboardAccessoryView.window != nil else {
                return nil
            }

            return keyboardAccessoryView
        }

        // Instances for an earlier content height are no longer useful. One may still be on
        // screen while UIKit animates it away; UIKit keeps it until then.
        fixedHeightKeyboardAccessoryViews.removeAll {
            !TerminalKeyboardAccessorySizing.isSame($0.sizing.contentHeight, sizing.contentHeight)
        }
        return fixedHeightKeyboardAccessoryViews.first { $0.sizing.matches(sizing) }
    }

    private func makeKeyboardAccessoryView(_ sizing: TerminalKeyboardAccessorySizing) -> SwiftTerminalKeyboardAccessoryView {
        let accessory = SwiftTerminalKeyboardAccessoryView(sizing: sizing)
        // UIKit gives the bar the screen's width when it lays it out; until then a host that
        // finds the bar from its content sees that width rather than none.
        accessory.frame.size.width = window?.bounds.width ?? 0
        accessory.onWindowAttachmentChange = { [weak self, weak accessory] isAttached in
            guard let accessory else {
                return
            }

            self?.keyboardAccessoryWindowAttachmentDidChange(accessory, isAttached: isAttached)
        }
        accessory.onWillEnterWindow = { [weak self] accessory in
            self?.keyboardAccessoryWillEnterWindow(accessory)
        }
        accessory.onLayout = { [weak self] accessory in
            self?.keyboardAccessoryDidLayout(accessory)
        }
        if !sizing.sizesItself {
            fixedHeightKeyboardAccessoryViews.append(accessory)
        }
        return accessory
    }

    /// The height the content takes in `accessory`, or the height it was created for while the
    /// content has not been laid out there.
    private static func contentHeight(in accessory: SwiftTerminalKeyboardAccessoryView) -> CGFloat {
        accessory.laidOutContentHeight ?? accessory.sizing.contentHeight
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
        guard Self.keyboardKeepsRecordedAccessoryHeight,
              isPresentedKeyboardAccessoryView(accessory),
              let laidOutContentHeight = accessory.laidOutContentHeight,
              !TerminalKeyboardAccessorySizing.isSame(laidOutContentHeight, accessory.sizing.contentHeight)
        else {
            return
        }

        swapKeyboardAccessoryView(
            to: TerminalKeyboardAccessorySizing(
                sizesItself: accessory.sizing.sizesItself,
                contentHeight: laidOutContentHeight,
                bottomReserve: accessory.safeAreaInsets.bottom
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
        checkKeyboardAccessoryPlacement()
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
    /// stays on screen; that is not a keyboard leaving.
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

        checkKeyboardAccessoryPlacement(isResting: true)
    }

    /// Whether the interface is between two orientations.
    ///
    /// UIKit announces the keyboard frames of a rotation before the scene reports its new
    /// geometry. By then either the scene's interface orientation differs from the one it last
    /// reported, or, as at the start of some rotations, the screen's bounds already have the
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
    /// They are skipped. A rotation itself never needs another instance: it keeps the bar above
    /// the input view or at the bottom of the screen, and an instance at the bottom of the screen
    /// takes the new home indicator space as UIKit measures it again.
    private func checkKeyboardAccessoryPlacement(isResting: Bool = false) {
        guard Self.keyboardKeepsRecordedAccessoryHeight,
              let accessory = keyboardAccessoryView,
              isPresentedKeyboardAccessoryView(accessory),
              !isInterfaceRotating
        else {
            return
        }

        let bottomSafeAreaInset = accessory.safeAreaInsets.bottom
        let replacement = accessory.sizing.replacement(
            laidOutContentHeight: Self.contentHeight(in: accessory),
            bottomSafeAreaInset: bottomSafeAreaInset
        )
        if swappedKeyboardAccessoryView != nil {
            guard swappedKeyboardAccessoryView === accessory, replacement == nil else {
                return
            }

            swappedKeyboardAccessoryView = nil
        }

        keyboardAccessoryPlacementRecord.record(
            TerminalKeyboardAccessoryPlacement(bottomSafeAreaInset: bottomSafeAreaInset),
            for: keyboardAccessoryPresentation
        )
        if let replacement {
            swapKeyboardAccessoryView(to: replacement)
        } else if isResting, unsettledKeyboardAccessoryView === accessory {
            settleKeyboardAccessoryView(accessory)
        }
    }

    /// Reloads the input views once more with an instance that replaced another one, now that it
    /// rests where it fits.
    ///
    /// When one instance replaces another, the keyboard keeps the frame of the one it replaced on
    /// record, although it lays out the new one where it belongs. The keyboard layout guide and
    /// the SwiftUI keyboard safe area follow that record the next time the keyboard changes on its
    /// own, as in a rotation, or, on iOS 26, as soon as the replacement is shorter. A reload with
    /// the instance already in place changes nothing on screen and makes the keyboard record it.
    ///
    /// The reload waits for the main actor's next turn: one made while UIKit is still announcing
    /// the frame change does not update the record.
    private func settleKeyboardAccessoryView(_ accessory: SwiftTerminalKeyboardAccessoryView) {
        unsettledKeyboardAccessoryView = nil
        Task { @MainActor [weak self, weak accessory] in
            guard let self, let accessory, self.isPresentedKeyboardAccessoryView(accessory), !Self.isAnimating(accessory) else {
                return
            }

            self.reloadTerminalInputViews()
        }
    }

    /// Installs an instance with `sizing` in place of the presented one and reloads, then waits
    /// for UIKit to place it before judging placements again.
    private func swapKeyboardAccessoryView(to sizing: TerminalKeyboardAccessorySizing) {
        installKeyboardAccessoryView(sizing)
        swappedKeyboardAccessoryView = keyboardAccessoryView
        reloadTerminalInputViews()
    }

    /// Has the input views reloaded once a rotation has moved a bar at the bottom of the screen.
    ///
    /// The instance there takes the new home indicator space as the keyboard measures it again,
    /// but the keyboard announces the rotation as a hidden keyboard with frames it recorded
    /// before, and its layout guide follows that record, as after an instance replaced another
    /// one. UIKit announces nothing once the input views have rotated, and a reload while it still
    /// animates them leaves the bar or the keyboard layout guide above an empty keyboard area, so
    /// the reload waits until the animations moving the bar have ended.
    private func windowGeometryDidChange() {
        guard Self.keyboardKeepsRecordedAccessoryHeight,
              let accessory = keyboardAccessoryView,
              accessory.window != nil,
              accessory.sizing.sizesItself
        else {
            return
        }

        unsettledKeyboardAccessoryView = accessory
        checkKeyboardAccessoryPlacementAtRest()
    }

    /// Checks the placement of the presented instance once the animations moving it have ended,
    /// or on the main actor's next turn if none is running.
    ///
    /// UIKit can put an instance in place without announcing a keyboard frame afterwards, for
    /// example when a hardware keyboard is connected and the system keyboard is selected again
    /// while the keyboard is hidden, and it announces some changes, such as hiding the keyboard,
    /// only as they start. It adds the instance and starts its animations in the layout pass that
    /// follows a change, so once the main actor's current job is over, the animations to wait for
    /// are attached.
    private func checkKeyboardAccessoryPlacementAtRest() {
        restingPlacementCheck?.cancel()
        restingPlacementCheck = Task { @MainActor [weak self] in
            await Task.yield()
            // Each pass waits for the animations attached at that moment; UIKit can chain one more.
            for _ in 0 ..< 3 {
                guard let accessory = self?.keyboardAccessoryView,
                      let remaining = Self.remainingAnimationDuration(of: accessory)
                else {
                    break
                }

                try? await Task.sleep(for: .seconds(remaining))
            }
            guard let self, !Task.isCancelled else {
                return
            }

            self.restingPlacementCheck = nil
            self.checkRestingKeyboardAccessoryPlacement()
        }
    }

    /// How long the animations that move `view` or a view it sits in still run, or `nil` once
    /// none does.
    private static func remainingAnimationDuration(of view: UIView) -> TimeInterval? {
        let now = CACurrentMediaTime()
        var end: CFTimeInterval?
        for layer in sequence(first: view, next: \.superview).map(\.layer) {
            for key in layer.animationKeys() ?? [] {
                guard let animation = layer.animation(forKey: key), animation.repeatCount.isFinite else {
                    continue
                }

                let animationEnd = layer.convertTime(animation.beginTime + animation.duration, to: nil)
                end = max(end ?? animationEnd, animationEnd)
            }
        }
        guard let end else {
            return nil
        }

        // An animation that has run its course but is still attached ends within a frame.
        return max(end - now, 1.0 / 60)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportedInterfaceOrientation = window?.windowScene?.effectiveGeometry.interfaceOrientation
        windowGeometryObservation = window?.windowScene?.observe(\.effectiveGeometry) { [weak self] scene, _ in
            MainActor.assumeIsolated {
                self?.reportedInterfaceOrientation = scene.effectiveGeometry.interfaceOrientation
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

    private func keyboardAccessoryWindowAttachmentDidChange(
        _ accessory: SwiftTerminalKeyboardAccessoryView,
        isAttached: Bool
    ) {
        attachedKeyboardAccessoryCount = max(0, attachedKeyboardAccessoryCount + (isAttached ? 1 : -1))
        if isAttached {
            // The bar still counts as attached while UIKit replaces one instance with another.
            if isKeyboardAccessoryAttached {
                unsettledKeyboardAccessoryView = accessory
            }
            checkKeyboardAccessoryPlacementAtRest()
        }
        updateKeyboardAccessoryAttachment()
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
