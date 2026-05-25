# SwiftTerminal

`SwiftTerminal` is a Swift package for embedding a richer terminal surface on Apple platforms.

Current baseline:

- `SwiftUI`-first public API
- internal `WKWebView` runtime built from `RuntimeWeb/`
- typed Swift/runtime bridge
- built-in theme catalog generated from `iTerm2 Color Schemes`
- custom theme support through `SwiftTerminalTheme`
- built-in search UI
- platform-aware link handling
- runtime bell and title-change events
- built-in copy, paste, and select-all handling
- built-in font family, size, line-height, and letter-spacing control
- custom font loading from Swift-owned font data, including multi-face family sets

Target platforms:

- `iOS 18+`
- `macOS 15+`

## Usage

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
            fontFamily: "SF Mono",
            fontSize: 14,
            lineHeight: 1.1,
            letterSpacing: 1,
            contentInsets: .init(top: 10, right: 16, bottom: 14, left: 16),
            cursorStyle: .underline,
            cursorBlink: false,
            inactiveCursorStyle: .outline,
            scrollbarVisibility: .visible,
            theme: SwiftTerminalThemes.builtIn(named: "Dracula") ?? .default
        )
    )

    var body: some View {
        SwiftTerminalView(session: session)
    }
}
```

Useful session actions:

- `appearance`
- `searchState`
- `selectionText`
- `currentSearchState()`
- `currentSelectionText()`
- `windowTitle`
- `currentWindowTitle()`
- `currentBufferSnapshot(maxLines:trimRight:)`
- `configuration`
- `setAppearance(_:)`
- `setTheme(_:)`
- `write(_:)`
- `clear()`
- `focus()`
- `showSearch()`
- `clearSearch()`
- `searchNext(_:caseSensitive:)`
- `searchNext(_:options:)`
- `searchPrevious(_:caseSensitive:)`
- `searchPrevious(_:options:)`
- `paste(_:)`
- `pasteFromClipboard()`
- `copySelection()`
- `selectAll()`
- `setScrollback(_:)`
- `setTerminalContentLimit(_:)`
- `setFontFamily(_:)`
- `setFontSize(_:)`
- `setLineHeight(_:)`
- `setLetterSpacing(_:)`
- `setContentInsets(_:)`
- `setContentPadding(_:)`
- `setContentPadding(top:right:bottom:left:)`
- `setCursorStyle(_:)`
- `setCursorBlink(_:)`
- `setInactiveCursorStyle(_:)`
- `setScrollbarVisibility(_:)`
- `registerCustomFont(_:)`
- `registerCustomFontSet(_:)`

`selectAll()` selects terminal content from buffer start through the current cursor position, which avoids trailing blank cells and blank rows after the live prompt.

`SwiftTerminalConfiguration.scrollback` controls the maximum number of lines kept in the running terminal buffer. `terminalContentLimit` is a public alias for the same value when the host app wants to present this as retained terminal content. The default is `1000`, matching xterm.js and VS Code's current running-terminal scrollback default, and `0` disables scrollback entirely.

`currentBufferSnapshot(maxLines:trimRight:)` returns the currently retained xterm active buffer after xterm has parsed escape sequences into cells. The snapshot includes normal or alternate buffer identity, terminal dimensions, viewport and base line positions, wrap markers, and one plain-text entry per retained buffer row. `snapshot.text` and `snapshot.logicalText` join wrapped xterm rows back into logical lines, so terminal-width soft wraps do not become copied newlines, and omit trailing empty viewport rows after the last visible text. `snapshot.visualText` preserves one newline per retained buffer row for hosts that need terminal-grid layout. This is the preferred data source for host-owned iOS selection sheets because it avoids reading raw terminal streams with ANSI styling and cursor-control sequences.

`contentInsets` controls the inset between terminal text and the view edges. You can set top, right, bottom, and left independently, or keep using `setContentPadding(_:)` when all four sides should match. The padded area stays on the same terminal background color as the active theme instead of revealing the host view behind it.

Link interaction is platform-specific: on macOS, hovering a URL underlines it immediately, a short dwell shows a `Follow link (cmd + click)` hint while keeping the text cursor, and `Cmd`-hover switches to the pointing-hand cursor before `Cmd`-click opens the URL. Touch-host link actions should stay host-owned until a later mobile selection and copy flow is designed.

Theme types:

- `SwiftTerminalTheme`
- `SwiftTerminalThemes.builtIn`
- `SwiftTerminalThemes.builtIn(named:)`
- `SwiftTerminalCursorStyle`
- `SwiftTerminalInactiveCursorStyle`
- `SwiftTerminalScrollbarVisibility`
- `SwiftTerminalSearchOptions`
- `SwiftTerminalSearchState`

`SwiftTerminalTheme` is a plain value type. You can start from a built-in theme, copy it, and override individual colors for a custom theme:

```swift
var theme = SwiftTerminalThemes.builtIn(named: "Dracula") ?? .default
theme.name = "My Dracula Variant"
theme.cursor = "#FFB86C"
theme.selectionBackground = "#44475ACC"

session.setTheme(theme)
```

If a host app wants a Swift-side search panel, `searchState` and `currentSearchState()` expose the runtime widget's current query, options, visibility, match counts, and regex error state.

Custom fonts are served to the bundled runtime through `WKURLSchemeHandler` with the `swiftterminalfont://` scheme. This keeps the font-loading path inside the app process and avoids starting a local web server just to expose user-selected font files.

If a family needs matching `regular`, `bold`, `italic`, and `bold italic` faces, register them together with `registerCustomFontSet(_:)` and set each `TerminalCustomFont.variant` appropriately. The legacy `registerCustomFont(_:)` path still works for the single-file case and defaults that file to `regular`.

## Built-In Theme Source

The built-in theme catalog is generated from [mbadolato/iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes).

- The upstream repository license is MIT.
- The upstream repository also notes that each individual theme remains under that theme author's copyright and license.
- The generated catalog and a short source notice are stored under `Sources/SwiftTerminal/Resources/TerminalThemes/`.

## macOS Sandbox Requirement

If a macOS host app enables App Sandbox, it also needs outgoing network entitlement enabled. Without it, `WKWebView` cannot launch the WebKit subprocesses that `SwiftTerminal` depends on, and the terminal surface may stay blank.

In Xcode, enable:

- `Signing & Capabilities > App Sandbox > Outgoing Connections (Client)`

Equivalent build setting:

```text
ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES
```

That produces:

```text
com.apple.security.network.client = 1
```

The example app at [SwiftTerminalExample](./SwiftTerminalExample) already includes this setting.

## Runtime Compatibility Notes

Runtime compatibility notes live in [RuntimeWeb/COMPATIBILITY.md](./RuntimeWeb/COMPATIBILITY.md).

The current important case is macOS `WKWebView` with `@xterm/xterm` 6.0.0 and Chinese IME shifted punctuation. A vanilla xterm page works correctly in a browser, while the same page inside a minimal macOS `WKWebView` can drop the first shifted punctuation because WebKit sends standalone `keydown Shift`, then resolved `insertText`, then a delayed printable `keydown keyCode=229`. SwiftTerminal scopes its compatibility layer to the SwiftTerminal WebKit host and xterm hidden textarea, and suppresses only those host-noise keydown events.

When upgrading `@xterm/xterm` or changing WKWebView keyboard handling, re-run the compatibility checks in that file before keeping, removing, or widening this runtime rule.

## Runtime Build

The bundled runtime lives in `RuntimeWeb/` and is built into `Sources/SwiftTerminal/Resources/TerminalRuntime/`.

To rebuild it from the package root:

```bash
Scripts/build_runtime.sh
```

On a clean checkout, or after JavaScript dependency changes:

```bash
Scripts/build_runtime.sh --install
```

Manual fallback:

```bash
cd RuntimeWeb
npm ci
npm run build:swiftterminal
```

What ships to Swift package users:

- `RuntimeWeb/` stays in the repository as contributor-facing source.
- `RuntimeWeb/node_modules/` is local build state, ignored by git, and is not packaged into the SwiftPM product bundle.
- The built app or library only embeds the generated runtime resources under `Sources/SwiftTerminal/Resources/TerminalRuntime/`.

To refresh the built-in iTerm2 theme catalog from an upstream checkout:

```bash
python3 Scripts/generate_iterm2_theme_catalog.py /path/to/iTerm2-Color-Schemes
```

## Manual Validation

Use the example app in [SwiftTerminalExample](./SwiftTerminalExample) to verify:

- terminal rendering
- built-in theme selection from the iTerm2 catalog
- custom theme editing and application
- built-in search with `case sensitive`, `whole word`, and `regex` toggles
- copy and paste
- select all
- full active-buffer snapshots
- bell and title-change events
- font family, size, line-height, and letter-spacing changes
- cursor style, cursor blink, inactive cursor style, and scrollbar visibility changes
- running terminal content limit changes
- per-edge content inset changes while keeping the padded area on the terminal background
- custom font import from a local file or multi-face family set
- link interaction
- runtime event logging
