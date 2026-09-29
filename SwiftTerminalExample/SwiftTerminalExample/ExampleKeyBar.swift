//
//  ExampleKeyBar.swift
//  SwiftTerminalExample
//
//  Created by GitSwift on 2026/09/29.
//

#if os(iOS)
import SwiftTerminal
import SwiftUI
import UIKit

/// A minimal terminal key bar that exercises `sendKey`, the sticky modifiers, and the keyboard
/// accessory. The same view is used above the system keyboard and, while the terminal has no
/// keyboard, pinned to the bottom of the terminal pane.
struct ExampleKeyBar: View {
    let session: SwiftTerminalSession
    let showsKeyboardToggle: Bool

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    keyButton("Esc") { session.sendKey(.escape) }
                    modifierButton("Ctrl", state: session.keyModifierStates.ctrl) { states, next in
                        states.ctrl = next
                    }
                    modifierButton("Alt", state: session.keyModifierStates.alt) { states, next in
                        states.alt = next
                    }
                    keyButton("Tab") { session.sendKey(.tab) }
                    keyButton("⇧Tab") { session.sendKey(.tab, modifiers: .shift) }
                    keyButton("^C") { session.sendKey(.character("c"), modifiers: .ctrl) }
                    keyButton("↑") { session.sendKey(.up) }
                    keyButton("↓") { session.sendKey(.down) }
                    keyButton("←") { session.sendKey(.left) }
                    keyButton("→") { session.sendKey(.right) }
                    keyButton("Home") { session.sendKey(.home) }
                    keyButton("End") { session.sendKey(.end) }
                    keyButton("PgUp") { session.sendKey(.pageUp) }
                    keyButton("PgDn") { session.sendKey(.pageDown) }
                    keyButton("Del") { session.sendKey(.delete) }
                    keyButton("F1") { session.sendKey(.function(1)) }
                    keyButton("F5") { session.sendKey(.function(5)) }
                    keyButton("F12") { session.sendKey(.function(12)) }
                    keyButton("⏎") { session.sendKey(.enter) }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.hidden)

            if showsKeyboardToggle {
                Button {
                    session.isSoftwareKeyboardSuppressed.toggle()
                } label: {
                    Image(
                        systemName: session.isSoftwareKeyboardSuppressed
                            ? "keyboard"
                            : "keyboard.chevron.compact.down"
                    )
                    .frame(minWidth: 36, minHeight: 32)
                }
                .buttonStyle(.bordered)

                Button {
                    session.resignKeyboardFocus()
                } label: {
                    Image(systemName: "xmark")
                        .frame(minWidth: 28, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .padding(.trailing, 8)
            }
        }
        .frame(height: 44)
    }

    private func keyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            session.playInputClick()
            action()
        } label: {
            Text(verbatim: title)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(minWidth: 28, minHeight: 32)
        }
        .buttonStyle(.bordered)
    }

    private func modifierButton(
        _ title: String,
        state: SwiftTerminalKeyModifierState,
        update: @escaping (inout SwiftTerminalKeyModifierStates, SwiftTerminalKeyModifierState) -> Void
    ) -> some View {
        Button {
            var states = session.keyModifierStates
            update(&states, state.next)
            session.setKeyModifiers(states)
        } label: {
            Text(verbatim: state == .sustained ? "\(title)•" : title)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(minWidth: 36, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .tint(state == .off ? nil : .accentColor)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(state == .off ? Color.clear : Color.accentColor.opacity(0.35))
        )
    }
}

private extension SwiftTerminalKeyModifierState {
    /// Tapping cycles off, one-shot, sustained, and back to off.
    var next: Self {
        switch self {
        case .off:
            .oneShot
        case .oneShot:
            .sustained
        case .sustained:
            .off
        }
    }
}

/// Owns the hosting controller whose view the session shows above the system keyboard.
@MainActor
final class ExampleKeyBarAccessoryHost {
    private let hostingController: UIHostingController<ExampleKeyBar>

    init(session: SwiftTerminalSession) {
        hostingController = UIHostingController(
            rootView: ExampleKeyBar(session: session, showsKeyboardToggle: true)
        )
        hostingController.sizingOptions = .intrinsicContentSize
        hostingController.view.backgroundColor = .clear
        session.keyboardAccessoryContentView = hostingController.view
    }
}
#endif
