# Getting Started

## Add the Package

Add SwiftTerminal as a Swift Package dependency:

```swift
    .package(url: "https://github.com/GitSwiftHQ/SwiftTerminal.git", from: "1.0.11")
```

Then add the `SwiftTerminal` product to your app target and import it from SwiftUI code:

```swift
import SwiftTerminal
```

SwiftTerminal supports iOS 18 and macOS 15 or newer.

## Create a Terminal View

```swift
import SwiftTerminal
import SwiftUI

struct TerminalScreen: View {
    @State private var session = SwiftTerminalSession(
        configuration: SwiftTerminalConfiguration(
            scrollback: 5_000,
            initialText: "Connecting...\r\n"
        ),
        appearance: SwiftTerminalAppearance(
            fontSize: 14,
            lineHeight: 1.05,
            contentInsets: .init(top: 8, right: 12, bottom: 8, left: 12),
            theme: SwiftTerminalThemes.builtIn(named: "iTerm2 Default") ?? .default
        )
    )

    var body: some View {
        SwiftTerminalView(session: session)
            .onAppear {
                session.focus()
            }
    }
}
```

`SwiftTerminalView` hosts the runtime. `SwiftTerminalSession` owns the bridge state and exposes the methods a host app uses to write output, paste text, search, copy selection, update appearance, and request buffer snapshots.

## Keyboard Focus on macOS

`session.focus()` focuses the terminal inside the runtime. On macOS, key presses go to the window's first responder, which that call does not change, so a host that decides the terminal should be typed into also calls `session.takeKeyboardFocus()`.

```swift
struct TerminalScreen: View {
    @State private var session = SwiftTerminalSession()

    var body: some View {
        SwiftTerminalView(session: session)
            .onAppear {
                session.takeKeyboardFocus()
            }
    }
}
```

The call returns `true` when the terminal holds the window's first responder afterwards. A terminal that already holds it is left alone, and a terminal whose view is not in a window reports `false`. `session.holdsKeyboardFocus` reports whether the terminal holds it right now, and `session.keyboardFocusWindow` is the window the terminal is in; a host that drives focus for several terminals uses both to tell its own terminal apart from another one. The terminal never takes focus on its own, so a text field or sheet the person moved to keeps it. On iOS the same calls repair hardware keyboard focus; [Keyboard Focus](keyboard-focus.md) covers both platforms.

## Hosting on macOS

`SwiftTerminalView` keeps a terminal's view inside its window even while the host has nowhere to show it. On macOS the view the representable gives SwiftUI is a lightweight slot; the view that holds the page moves between slots, and waits in a fully transparent container inside the window whenever no slot wants it. The container is transparent rather than hidden because a hidden view is not visible to WebKit, which releases what a non-visible page has painted — the blank this hosting exists to avoid — so it is instead taken out of hit testing, the key view loop, and the accessibility tree explicitly.

This matters when a host rebuilds its view tree to switch sessions — a `NavigationSplitView` detail keyed by the selected session, for example. Taking a `WKWebView` out of its window makes WebKit release what it has painted, so a terminal that was unmounted and remounted came back blank for several frames. Keeping it in the window means a switch shows the terminal's existing content immediately.

The consequence to budget for: every terminal a host has created keeps its page resident for as long as its session is alive, rather than only while it is on screen. Releasing a session releases its view and its memory. Nothing about this is visible in the API — it is how `SwiftTerminalView` hosts itself.

## Connect Input and Output

SwiftTerminal is a terminal view component. The host app owns the process or network connection behind the terminal.

```swift
session.onEvent = { event in
    switch event.type {
    case .input:
        if let text = event.text {
            sendToBackend(text)
        }
    case .resize:
        if let cols = event.cols, let rows = event.rows {
            resizeBackend(cols: cols, rows: rows)
        }
    case .titleChanged:
        updateWindowTitle(event.title)
    default:
        break
    }
}

session.write(remoteOutput)
```

The runtime parses terminal escape sequences through xterm.js. Hosts should pass terminal output as received from the backend; xterm.js handles row parsing and rendering.

## Common Session Methods

Use `write(_:)` for backend output, `clear()` for clearing the terminal, and `focus()` when the host wants keyboard focus to return to the terminal.

Use `try await resetStateForNewRemoteSessionAcknowledged()` before attaching a new backend PTY to an existing terminal session. This performs a local xterm soft reset so modes left by the previous shell, such as bracketed paste, do not leak into the next shell, and moves the cursor to a fresh line below the previous shell's output so the next shell does not print over it. The method returns after the runtime has executed the reset and xterm's write callback has completed. When the runtime is unavailable, the method throws `SwiftTerminalLifecycleError.runtimeUnavailable`. When the caller task is canceled before completion, the method throws `CancellationError`.

The synchronous `resetStateForNewRemoteSession()` method preserves fire-and-forget command queue behavior for existing integrations. Host code that opens a new PTY immediately after reset should use the acknowledged method.

Use `reloadRuntime()` only when the existing terminal runtime should be rebuilt completely, such as after a host app detects that the remote identity behind the same connection target has changed. Reloading creates a fresh xterm instance and clears the current runtime buffer.

Use `paste(_:)`, `pasteFromClipboard()`, `copySelection()`, and `selectAll()` for clipboard-related commands. `selectAll()` selects retained terminal content from the start of the active buffer through the current cursor position.

Use `showSearch()`, `hideSearch()`, `clearSearch()`, `searchNext(_:options:)`, and `searchPrevious(_:options:)` for the built-in search UI.

Use `currentBufferSnapshot(maxLines:trimRight:)` when the host needs a plain-text view of retained terminal content. The snapshot is built from xterm's parsed active buffer, so escape sequences and styling control bytes are already resolved before Swift receives the data.
