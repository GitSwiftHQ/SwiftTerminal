//
//  TerminalKeyboardAccessorySizingTests.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/10/04.
//

import CoreGraphics
import Testing
@testable import SwiftTerminal

/// Covers which instance the keyboard accessory gets for each placement. The iOS 26 keyboard
/// keeps the height it recorded for a presented accessory, so the terminal installs another
/// instance instead of showing one at two placements; these tests pin down when an instance is
/// asked for and that a replacement never asks for another.
@Suite("Keyboard accessory sizing")
struct TerminalKeyboardAccessorySizingTests {
    private let barAboveKeyboard = TerminalKeyboardAccessorySizing(sizesItself: false, contentHeight: 46)
    private let dockedBar = TerminalKeyboardAccessorySizing(sizesItself: true, contentHeight: 46, bottomReserve: 34)

    @Test(arguments: [
        (CGFloat(0), TerminalKeyboardAccessoryPlacement.aboveInputView),
        (0.3, .aboveInputView),
        (0.5, .bottomOfScreen),
        (20, .bottomOfScreen),
        (34, .bottomOfScreen),
    ])
    func placementFollowsTheInstancesBottomSafeArea(
        bottomSafeAreaInset: CGFloat,
        placement: TerminalKeyboardAccessoryPlacement
    ) {
        #expect(TerminalKeyboardAccessoryPlacement(bottomSafeAreaInset: bottomSafeAreaInset) == placement)
    }

    @Test
    func onlyABarAtTheBottomOfTheScreenSizesItself() {
        let above = TerminalKeyboardAccessorySizing(placement: .aboveInputView, contentHeight: 46, bottomReserve: 34)
        let docked = TerminalKeyboardAccessorySizing(placement: .bottomOfScreen, contentHeight: 46, bottomReserve: 34)

        #expect(!above.sizesItself)
        #expect(above.bottomReserve == 0)
        #expect(docked.sizesItself)
        #expect(docked.bottomReserve == 34)
    }

    @Test
    func fixedHeightAddsTheContentInset() {
        #expect(barAboveKeyboard.fixedHeight(contentBottomInset: 10) == 56)
        #expect(barAboveKeyboard.fixedHeight(contentBottomInset: 0) == 46)
    }

    @Test
    func negativeReservesAreTreatedAsZero() {
        let sizing = TerminalKeyboardAccessorySizing(sizesItself: true, contentHeight: 46, bottomReserve: -5)

        #expect(sizing.bottomReserve == 0)
    }

    @Test
    func instancesMatchOnHowTheyTakeTheirHeightAndTheirContentHeight() {
        #expect(barAboveKeyboard.matches(TerminalKeyboardAccessorySizing(sizesItself: false, contentHeight: 46.3)))
        #expect(!barAboveKeyboard.matches(TerminalKeyboardAccessorySizing(sizesItself: false, contentHeight: 60)))
        #expect(!barAboveKeyboard.matches(dockedBar))
        // A docked bar follows its own home indicator space, so the space it started with does
        // not tell two of them apart.
        let landscapeDockedBar = TerminalKeyboardAccessorySizing(sizesItself: true, contentHeight: 46, bottomReserve: 20)
        #expect(dockedBar.matches(landscapeDockedBar))
    }

    @Test
    func barAboveAKeyboardKeepsItsInstance() {
        #expect(barAboveKeyboard.replacement(laidOutContentHeight: 46, bottomSafeAreaInset: 0) == nil)
    }

    @Test
    func barFoundAtTheBottomOfTheScreenAsksForAnInstanceThatSizesItself() throws {
        let replacement = try #require(
            barAboveKeyboard.replacement(laidOutContentHeight: 46, bottomSafeAreaInset: 34)
        )

        #expect(replacement.sizesItself)
        #expect(replacement.contentHeight == 46)
        #expect(replacement.bottomReserve == 34)
    }

    @Test
    func dockedBarFoundAboveAKeyboardAsksForAFixedHeight() throws {
        let replacement = try #require(dockedBar.replacement(laidOutContentHeight: 46, bottomSafeAreaInset: 0))

        #expect(!replacement.sizesItself)
        #expect(replacement.contentHeight == 46)
        #expect(replacement.bottomReserve == 0)
    }

    @Test
    func rotatedDockedBarKeepsItsInstance() {
        // The instance takes the landscape home indicator space itself.
        #expect(dockedBar.replacement(laidOutContentHeight: 46, bottomSafeAreaInset: 20) == nil)
    }

    @Test(arguments: [false, true])
    func contentThatChangedHeightAsksForANewInstanceAtTheSamePlacement(isDocked: Bool) throws {
        let sizing = isDocked ? dockedBar : barAboveKeyboard
        let bottomSafeAreaInset: CGFloat = isDocked ? 34 : 0

        let replacement = try #require(
            sizing.replacement(laidOutContentHeight: 60, bottomSafeAreaInset: bottomSafeAreaInset)
        )

        #expect(replacement.sizesItself == isDocked)
        #expect(replacement.contentHeight == 60)
        #expect(replacement.bottomReserve == sizing.bottomReserve)
    }

    @Test(arguments: [
        (CGFloat(46), CGFloat(0)),
        (46, 34),
        (46, 20),
        (60, 34),
        (60, 0),
        (0, 0),
        (0, 34),
    ])
    func replacementFitsWhereItWasAskedFor(contentHeight: CGFloat, bottomSafeAreaInset: CGFloat) {
        for sizing in [barAboveKeyboard, dockedBar] {
            let replacement = sizing.replacement(
                laidOutContentHeight: contentHeight,
                bottomSafeAreaInset: bottomSafeAreaInset
            ) ?? sizing

            #expect(
                replacement.replacement(
                    laidOutContentHeight: contentHeight,
                    bottomSafeAreaInset: bottomSafeAreaInset
                ) == nil
            )
        }
    }

    @Test
    func roundingDifferencesKeepTheInstance() {
        #expect(barAboveKeyboard.replacement(laidOutContentHeight: 46.3, bottomSafeAreaInset: 0.2) == nil)
    }

    @Test
    func negativeMeasurementsAreTreatedAsZero() throws {
        let replacement = try #require(dockedBar.replacement(laidOutContentHeight: -1, bottomSafeAreaInset: -5))

        #expect(!replacement.sizesItself)
        #expect(replacement.contentHeight == 0)
        #expect(replacement.bottomReserve == 0)
    }

    @Test
    func emptyContentKeepsOnlyTheInset() {
        let empty = TerminalKeyboardAccessorySizing(sizesItself: false, contentHeight: 0)

        #expect(empty.fixedHeight(contentBottomInset: 10) == 10)
        #expect(empty.replacement(laidOutContentHeight: 0, bottomSafeAreaInset: 0) == nil)
    }
}

@Suite("Keyboard accessory placement record")
struct TerminalKeyboardAccessoryPlacementRecordTests {
    @Test
    func withoutObservationsOnlyTheHiddenKeyboardPutsTheBarAtTheBottomOfTheScreen() {
        let record = TerminalKeyboardAccessoryPlacementRecord()

        #expect(record.predictedPlacement(for: .systemKeyboard) == .aboveInputView)
        #expect(record.predictedPlacement(for: .hostInputView) == .aboveInputView)
        #expect(record.predictedPlacement(for: .noKeyboard) == .bottomOfScreen)
    }

    @Test
    func hardwareKeyboardPlacementIsRememberedForTheNextPresentation() {
        var record = TerminalKeyboardAccessoryPlacementRecord()

        record.record(.bottomOfScreen, for: .systemKeyboard)

        #expect(record.predictedPlacement(for: .systemKeyboard) == .bottomOfScreen)
        // Each presentation keeps its own observation: a host panel still lies below the bar.
        #expect(record.predictedPlacement(for: .hostInputView) == .aboveInputView)
    }

    @Test
    func softwareKeyboardReturningClearsTheDockedPrediction() {
        var record = TerminalKeyboardAccessoryPlacementRecord()
        record.record(.bottomOfScreen, for: .systemKeyboard)

        record.record(.aboveInputView, for: .systemKeyboard)

        #expect(record.predictedPlacement(for: .systemKeyboard) == .aboveInputView)
    }

    @Test
    func hiddenKeyboardAlwaysPredictsTheBottomOfTheScreen() {
        var record = TerminalKeyboardAccessoryPlacementRecord()

        // Nothing lies below the bar with the keyboard hidden, whatever an instance reported.
        record.record(.aboveInputView, for: .noKeyboard)

        #expect(record.predictedPlacement(for: .noKeyboard) == .bottomOfScreen)
    }
}
