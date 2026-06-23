# SwiftTerminal Documentation

This directory contains the public SwiftTerminal documentation for app developers and contributors.

## Guides

- [Getting Started](getting-started.md): add the package, create a session, and connect terminal input/output.
- [Configuration and Appearance](configuration.md): configure scrollback, search, clipboard behavior, themes, fonts, cursor style, and buffer snapshots.
- [Runtime and Build Notes](runtime.md): rebuild the bundled web runtime, refresh theme resources, and configure macOS sandboxed hosts.
- [xterm.js Compatibility Layers](xterm-compatibility.md): understand the small runtime compatibility layers around xterm.js and the validation required when changing them.

## Project Shape

SwiftTerminal ships a Swift package and a bundled web runtime:

- `Sources/SwiftTerminal/`: Swift API, runtime bridge, resource loading, and platform host views.
- `RuntimeWeb/`: TypeScript source for the bundled terminal runtime.
- `Sources/SwiftTerminal/Resources/TerminalRuntime/`: built runtime assets embedded in the SwiftPM product.
- `Sources/SwiftTerminal/Resources/TerminalThemes/`: generated built-in theme catalog resources.
- `SwiftTerminalExample/`: local app for manual validation.

Package users consume the Swift target and the generated resources. Contributors edit Swift source and `RuntimeWeb/`, then rebuild the runtime assets before committing runtime changes.
