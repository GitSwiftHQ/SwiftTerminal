//
//  TerminalKeyboardAccessorySizingTests.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/10/04.
//

import CoreGraphics
import Testing
@testable import SwiftTerminal

/// Covers which height the keyboard accessory gets for each placement. UIKit keeps the height it
/// recorded for a presented accessory, so the terminal swaps instances instead of resizing one;
/// these tests pin down when a swap is asked for and that a swap never asks for another.
@Suite("Keyboard accessory sizing")
struct TerminalKeyboardAccessorySizingTests {
    private let barAboveKeyboard = TerminalKeyboardAccessorySizing(
        contentHeight: 46,
        contentBottomInset: 10,
        bottomReserve: 0
    )

    @Test
    func heightAddsContentInsetAndReserve() {
        #expect(barAboveKeyboard.height == 56)

        var docked = barAboveKeyboard
        docked.bottomReserve = 34
        #expect(docked.height == 90)
    }

    @Test
    func barAboveAKeyboardKeepsItsInstance() {
        #expect(barAboveKeyboard.replacement(laidOutContentHeight: 46, bottomSafeAreaInset: 0) == nil)
    }

    @Test
    func barFoundAtTheBottomOfTheScreenAsksForTheHomeIndicatorSpace() throws {
        let replacement = try #require(
            barAboveKeyboard.replacement(laidOutContentHeight: 46, bottomSafeAreaInset: 34)
        )

        #expect(replacement.contentHeight == 46)
        #expect(replacement.contentBottomInset == 10)
        #expect(replacement.bottomReserve == 34)
        #expect(replacement.height == 90)
    }

    @Test
    func dockedBarFoundAboveAKeyboardDropsTheHomeIndicatorSpace() throws {
        var docked = barAboveKeyboard
        docked.bottomReserve = 34

        let replacement = try #require(docked.replacement(laidOutContentHeight: 46, bottomSafeAreaInset: 0))

        #expect(replacement.bottomReserve == 0)
        #expect(replacement.height == 56)
    }

    @Test
    func rotatedDockedBarTakesTheLandscapeHomeIndicatorSpace() throws {
        var docked = barAboveKeyboard
        docked.bottomReserve = 34

        let replacement = try #require(docked.replacement(laidOutContentHeight: 46, bottomSafeAreaInset: 21))

        #expect(replacement.bottomReserve == 21)
        #expect(replacement.height == 77)
    }

    @Test
    func contentThatChangedHeightAsksForANewInstanceAtTheSamePlacement() throws {
        var docked = barAboveKeyboard
        docked.bottomReserve = 34

        let replacement = try #require(docked.replacement(laidOutContentHeight: 60, bottomSafeAreaInset: 34))

        #expect(replacement.contentHeight == 60)
        #expect(replacement.bottomReserve == 34)
        #expect(replacement.height == 104)
    }

    @Test(arguments: [
        (CGFloat(46), CGFloat(0)),
        (46, 34),
        (46, 21),
        (60, 34),
        (0, 0),
        (0, 34),
    ])
    func replacementFitsWhereItWasAskedFor(contentHeight: CGFloat, bottomSafeAreaInset: CGFloat) {
        let replacement = barAboveKeyboard.replacement(
            laidOutContentHeight: contentHeight,
            bottomSafeAreaInset: bottomSafeAreaInset
        ) ?? barAboveKeyboard

        #expect(
            replacement.replacement(
                laidOutContentHeight: contentHeight,
                bottomSafeAreaInset: bottomSafeAreaInset
            ) == nil
        )
    }

    @Test
    func roundingDifferencesKeepTheInstance() {
        #expect(barAboveKeyboard.replacement(laidOutContentHeight: 46.3, bottomSafeAreaInset: 0.2) == nil)
    }

    @Test
    func negativeMeasurementsAreTreatedAsZero() throws {
        var docked = barAboveKeyboard
        docked.bottomReserve = 34

        let replacement = try #require(docked.replacement(laidOutContentHeight: -1, bottomSafeAreaInset: -5))

        #expect(replacement.contentHeight == 0)
        #expect(replacement.bottomReserve == 0)
    }

    @Test
    func emptyContentKeepsOnlyTheInset() {
        let empty = TerminalKeyboardAccessorySizing(contentHeight: 0, contentBottomInset: 10, bottomReserve: 0)

        #expect(empty.height == 10)
        #expect(empty.replacement(laidOutContentHeight: 0, bottomSafeAreaInset: 0) == nil)
    }
}

@Suite("Keyboard accessory placement record")
struct TerminalKeyboardAccessoryPlacementRecordTests {
    @Test
    func withoutObservationsOnlyTheHiddenKeyboardReservesTheHomeIndicator() {
        let record = TerminalKeyboardAccessoryPlacementRecord()

        #expect(record.predictedBottomReserve(for: .systemKeyboard, windowBottomInset: 34) == 0)
        #expect(record.predictedBottomReserve(for: .hostInputView, windowBottomInset: 34) == 0)
        #expect(record.predictedBottomReserve(for: .noKeyboard, windowBottomInset: 34) == 34)
    }

    @Test
    func hardwareKeyboardPlacementIsRememberedForTheNextPresentation() {
        var record = TerminalKeyboardAccessoryPlacementRecord()

        record.record(bottomSafeAreaInset: 34, windowBottomInset: 34, for: .systemKeyboard)

        #expect(record.predictedBottomReserve(for: .systemKeyboard, windowBottomInset: 34) == 34)
        // Each presentation keeps its own observation: a host panel still lies below the bar.
        #expect(record.predictedBottomReserve(for: .hostInputView, windowBottomInset: 34) == 0)
    }

    @Test
    func softwareKeyboardReturningClearsTheDockedPrediction() {
        var record = TerminalKeyboardAccessoryPlacementRecord()
        record.record(bottomSafeAreaInset: 34, windowBottomInset: 34, for: .systemKeyboard)

        record.record(bottomSafeAreaInset: 0, windowBottomInset: 34, for: .systemKeyboard)

        #expect(record.predictedBottomReserve(for: .systemKeyboard, windowBottomInset: 34) == 0)
    }

    @Test
    func dockedPredictionFollowsTheWindowAfterARotation() {
        var record = TerminalKeyboardAccessoryPlacementRecord()
        record.record(bottomSafeAreaInset: 34, windowBottomInset: 34, for: .systemKeyboard)
        record.record(bottomSafeAreaInset: 34, windowBottomInset: 34, for: .noKeyboard)

        #expect(record.predictedBottomReserve(for: .systemKeyboard, windowBottomInset: 21) == 21)
        #expect(record.predictedBottomReserve(for: .noKeyboard, windowBottomInset: 21) == 21)
    }

    @Test
    func observedDockedReserveWinsWhileTheWindowIsUnchanged() {
        var record = TerminalKeyboardAccessoryPlacementRecord()

        // The keyboard can sit lower than the app's window, for example in a window that does
        // not reach the bottom of the screen.
        record.record(bottomSafeAreaInset: 20, windowBottomInset: 0, for: .noKeyboard)

        #expect(record.predictedBottomReserve(for: .noKeyboard, windowBottomInset: 0) == 20)
        #expect(record.predictedBottomReserve(for: .noKeyboard, windowBottomInset: 34) == 34)
    }

    @Test
    func screenWithoutHomeIndicatorReservesNothing() {
        var record = TerminalKeyboardAccessoryPlacementRecord()
        record.record(bottomSafeAreaInset: 0, windowBottomInset: 0, for: .noKeyboard)

        #expect(record.predictedBottomReserve(for: .noKeyboard, windowBottomInset: 0) == 0)
        #expect(record.predictedBottomReserve(for: .systemKeyboard, windowBottomInset: 0) == 0)
    }
}
