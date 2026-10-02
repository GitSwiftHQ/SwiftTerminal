//
//  SwiftTerminalSessionKeyInputTests.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/09/29.
//

import Foundation
import Observation
import Synchronization
import Testing
@testable import SwiftTerminal

@MainActor
private final class KeyInputRuntimeSpy: TerminalRuntimeControlling {
    var commands: [TerminalHostCommandEnvelope] = []

    func send(_ command: TerminalHostCommandEnvelope) async throws {
        commands.append(command)
    }

    func reloadRuntime() {}

    func registerFontResource(_: TerminalCustomFont) async throws -> String {
        "swiftterminalfont://font/unused"
    }

    var keyCommands: [TerminalHostCommandEnvelope] {
        commands.filter {
            [.sendKey, .setKeyModifiers, .setOptionIsMeta].contains($0.type)
        }
    }
}

@MainActor
private func readySession() async throws -> (SwiftTerminalSession, KeyInputRuntimeSpy) {
    let session = SwiftTerminalSession()
    let runtime = KeyInputRuntimeSpy()
    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    await waitForAsyncBridge()
    runtime.commands.removeAll()
    return (session, runtime)
}

@Test
@MainActor
func sendKeyForwardsTheKeyToTheRuntime() async throws {
    let (session, runtime) = try await readySession()

    session.sendKey(.pageDown, modifiers: .ctrl)
    session.sendKey(.character("x"))
    await waitForAsyncBridge()

    #expect(
        runtime.keyCommands == [
            try #require(.sendKey(.pageDown, modifiers: .ctrl)),
            try #require(.sendKey(.character("x"))),
        ]
    )
}

@Test
@MainActor
func sendKeyIgnoresKeysTheRuntimeCannotEncode() async throws {
    let (session, runtime) = try await readySession()

    session.sendKey(.function(13))
    session.sendKey(.character(""))
    await waitForAsyncBridge()

    #expect(runtime.keyCommands.isEmpty)
}

@Test
@MainActor
func sendKeyQueuesUntilTheRuntimeIsReady() async throws {
    let session = SwiftTerminalSession()
    let runtime = KeyInputRuntimeSpy()
    session.attachRuntime(runtime)

    session.sendKey(.escape)
    #expect(runtime.commands.isEmpty)

    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    await waitForAsyncBridge()

    #expect(runtime.keyCommands == [try #require(.sendKey(.escape))])
}

@Test
@MainActor
func setKeyModifiersUpdatesStateAndTheRuntime() async throws {
    let (session, runtime) = try await readySession()
    let states = SwiftTerminalKeyModifierStates(ctrl: .oneShot)

    session.setKeyModifiers(states)
    await waitForAsyncBridge()

    #expect(session.keyModifierStates == states)
    #expect(runtime.keyCommands == [.setKeyModifiers(states)])
}

@Test
@MainActor
func keyModifiersChangedEventMirrorsTheRuntimeState() async throws {
    let (session, _) = try await readySession()
    var forwardedEvents: [TerminalRuntimeEventEnvelope] = []
    session.onEvent = { forwardedEvents.append($0) }
    session.setKeyModifiers(SwiftTerminalKeyModifierStates(ctrl: .oneShot, alt: .sustained))

    let event = TerminalRuntimeEventEnvelope(
        type: .keyModifiersChanged,
        keyModifierStates: SwiftTerminalKeyModifierStates(alt: .sustained)
    )
    session.handleRuntimeEvent(event)

    #expect(session.keyModifierStates == SwiftTerminalKeyModifierStates(alt: .sustained))
    #expect(forwardedEvents == [event])
}

@Test
@MainActor
func keyModifierStatesAreObservable() async throws {
    let (session, _) = try await readySession()
    let didChange = Mutex(false)

    withObservationTracking {
        _ = session.keyModifierStates
    } onChange: {
        didChange.withLock { $0 = true }
    }
    session.handleRuntimeEvent(
        TerminalRuntimeEventEnvelope(
            type: .keyModifiersChanged,
            keyModifierStates: SwiftTerminalKeyModifierStates(ctrl: .sustained)
        )
    )

    #expect(didChange.withLock { $0 })
}

@Test
@MainActor
func optionIsMetaIsSentOnlyWhenItChanges() async throws {
    let (session, runtime) = try await readySession()

    session.optionIsMeta = true
    session.optionIsMeta = true
    session.optionIsMeta = false
    await waitForAsyncBridge()

    #expect(runtime.keyCommands == [.setOptionIsMeta(true), .setOptionIsMeta(false)])
}

@Test
@MainActor
func reloadedRuntimeGetsTheHostKeyStateBack() async throws {
    let (session, runtime) = try await readySession()
    let states = SwiftTerminalKeyModifierStates(ctrl: .sustained)
    session.optionIsMeta = true
    session.setKeyModifiers(states)
    await waitForAsyncBridge()
    runtime.commands.removeAll()

    session.runtimeDidTerminate()
    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    await waitForAsyncBridge()

    #expect(runtime.keyCommands == [.setOptionIsMeta(true), .setKeyModifiers(states)])
}

@Test
@MainActor
func freshRuntimeGetsNoKeyStateByDefault() async throws {
    let session = SwiftTerminalSession()
    let runtime = KeyInputRuntimeSpy()
    session.attachRuntime(runtime)
    session.handleRuntimeEvent(TerminalRuntimeEventEnvelope(type: .ready))
    await waitForAsyncBridge()

    #expect(runtime.keyCommands.isEmpty)
}
