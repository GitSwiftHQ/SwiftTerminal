# Runtime and Build Notes

SwiftTerminal embeds a web runtime built from `RuntimeWeb/` into the Swift package resources.

## Rebuild the Runtime

Run this from the package root after changing `RuntimeWeb/`:

```bash
Scripts/build_runtime.sh
```

On a clean checkout, or after JavaScript dependency changes:

```bash
Scripts/build_runtime.sh --install
```

The script builds the runtime into:

```text
Sources/SwiftTerminal/Resources/TerminalRuntime/
```

Package users consume the generated resources through SwiftPM. Contributors should commit the TypeScript source change and the rebuilt generated assets together for runtime behavior changes.

## Type Checking

Run TypeScript validation from `RuntimeWeb/`:

```bash
npm run typecheck
```

Run the Swift package tests from the package root:

```bash
swift test
```

## Theme Catalog Generation

The built-in theme catalog is generated from the iTerm2 Color Schemes project.

```bash
python3 Scripts/generate_iterm2_theme_catalog.py /path/to/iTerm2-Color-Schemes
```

Generated theme resources live in:

```text
Sources/SwiftTerminal/Resources/TerminalThemes/
```

## macOS Sandbox Requirement

Sandboxed macOS host apps need outgoing network entitlement enabled so `WKWebView` can launch its WebKit subprocesses.

In Xcode:

```text
Signing & Capabilities > App Sandbox > Outgoing Connections (Client)
```

Equivalent build setting:

```text
ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES
```

The resulting entitlement is:

```text
com.apple.security.network.client = 1
```

The example app already includes this setting.

## Manual Validation App

Use `SwiftTerminalExample/` to validate runtime-facing features in a real host app:

- terminal rendering and resizing
- input and output
- built-in search
- copy, paste, and select-all
- themes and custom themes
- custom fonts
- cursor and scrollbar settings
- content insets
- scrollback and buffer snapshots
- link handling
- runtime diagnostic events

Compatibility changes around xterm.js should also follow the checks in [xterm.js Compatibility Layers](xterm-compatibility.md).
