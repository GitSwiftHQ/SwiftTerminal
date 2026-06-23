# SwiftTerminal

SwiftTerminal is a Swift package for embedding a terminal surface in Apple-platform apps. It provides a SwiftUI view, a session object, a typed Swift-to-runtime bridge, built-in themes, search, clipboard integration, link handling, and appearance controls on top of a bundled xterm.js runtime.

## Platforms

- iOS 18+
- macOS 15+

## Installation

Add SwiftTerminal as a Swift Package dependency:

```swift
.package(url: "https://github.com/GitSwiftHQ/SwiftTerminal.git", from: "1.0.2")
```

Then add the `SwiftTerminal` product to your app target.

## Basic Usage

```swift
import SwiftTerminal
import SwiftUI

struct ContentView: View {
    @State private var session = SwiftTerminalSession(
        configuration: SwiftTerminalConfiguration(
            scrollback: 5_000,
            initialText: "SwiftTerminal ready\r\n"
        ),
        appearance: SwiftTerminalAppearance(
            fontSize: 14,
            contentInsets: .init(top: 10, right: 14, bottom: 10, left: 14),
            theme: SwiftTerminalThemes.builtIn(named: "Dracula") ?? .default
        )
    )

    var body: some View {
        SwiftTerminalView(session: session)
            .onAppear {
                session.write("$ echo hello\r\nhello\r\n")
            }
    }
}
```

Host apps own the terminal backend. Feed output with `session.write(_:)`, listen for input through `session.onEvent`, and connect those events to SSH, a local process, or another terminal backend.

## Documentation

- [Getting Started](Documentation/getting-started.md)
- [Configuration and Appearance](Documentation/configuration.md)
- [Runtime and Build Notes](Documentation/runtime.md)
- [xterm.js Compatibility Layers](Documentation/xterm-compatibility.md)

## Example App

`SwiftTerminalExample/` contains a macOS and iOS validation app for terminal rendering, search, copy and paste, themes, custom fonts, cursor settings, scrollback, buffer snapshots, and runtime diagnostics.
