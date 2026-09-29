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

Run the runtime logic checks from `RuntimeWeb/`. Each compiles one DOM-free module with its script and runs it under Node:

```bash
npm run check:key-encoder         # send_key encoding and sticky modifier rules
npm run check:webkit-input        # WebKit textarea input coordination, including host keys
npm run check:terminal-state-reset
npm run check:unicode
```

Run the Swift package tests from the package root:

```bash
swift test
```

## Key Input

Every byte the runtime sends to the host as an `input` event leaves through one function in `main.ts`, whichever path produced it: xterm's `onData`, or the WebKit textarea paths that forward predictive text and dictation. That single exit is where the host's sticky modifiers apply, and it knows where each piece of input came from:

- `send_key` encodes the key with `src/keyEncoder.ts` and injects it with `terminal.input(sequence, true)`. The data it produces is marked as host input, so the sticky modifiers are not applied a second time, and it does not advance the xterm data serial the WebKit input coordinator uses to tell whether xterm already delivered a pending textarea insert. Counting it would drop a character typed on the system keyboard just before the key.
- Pasted text, from a `paste` host command or a paste event, and text committed by an input method are marked as well and pass through unchanged.
- Anything else is keyboard input. A single printable ASCII character gets the sticky modifiers and consumes the one-shot ones, which the runtime reports with `key_modifiers_changed`.

`src/keyEncoder.ts` holds the encoding table and the sticky modifier rules as pure functions, so `npm run check:key-encoder` covers every row without a browser.

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

The hint is positioned from the link's buffer row converted to a viewport row through `terminal.buffer.active.viewportY`, and anchored on the rendered screen so terminal content insets do not shift it. It hides when the link's row scrolls out of the viewport.

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
