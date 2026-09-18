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

## Link Activation

The runtime posts a `link_activated` event to the host when the user Command-clicks a link, and shows the `Follow link (cmd + click)` hint while a link is hovered. One shared interaction object in `RuntimeWeb/src/main.ts` serves both link sources xterm can produce:

- plaintext `https?://` runs matched by `WebLinksAddon`
- OSC 8 hyperlinks (`ESC ] 8 ; ; <uri> ST`) claimed by xterm's built-in link provider, which is passed the same closures through the `linkHandler` terminal option

Only `http` and `https` destinations are hoverable and activatable; xterm's default protocol filter drops every other OSC 8 destination, so a `file://` hyperlink or a bare path stays inert. Hosts receive the URL as a string and should still validate it before opening.

See [Shared Link Interaction](xterm-compatibility.md) for the provider-ordering rationale and the manual validation checklist.

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
- link handling, covering plaintext URLs and OSC 8 hyperlinks
- runtime diagnostic events

Compatibility changes around xterm.js should also follow the checks in [xterm.js Compatibility Layers](xterm-compatibility.md).
