# Configuration and Appearance

SwiftTerminal separates behavior settings from visual settings:

- `SwiftTerminalConfiguration` controls runtime features such as search UI, keyboard shortcuts, clipboard integration, link opening, runtime diagnostics, scrollback, and initial text.
- `SwiftTerminalAppearance` controls terminal presentation such as font, spacing, content insets, cursor style, scrollbar visibility, and theme.

## Configuration

```swift
let configuration = SwiftTerminalConfiguration(
    enablesSearchUI: true,
    enablesKeyboardShortcuts: true,
    enablesClipboardIntegration: true,
    opensLinksByDefault: true,
    enablesRuntimeDiagnostics: false,
    scrollback: 5_000,
    initialText: "Ready\r\n"
)
```

`scrollback` controls the number of retained buffer lines. `terminalContentLimit` is an alias for the same setting for host apps that present the value as retained terminal content. A value of `0` disables retained scrollback.

`enablesRuntimeDiagnostics` emits structured runtime diagnostic events through the normal event stream. It is intended for app diagnostics and manual validation.

## Appearance

```swift
let appearance = SwiftTerminalAppearance(
    fontFamily: "SF Mono",
    fontSize: 14,
    lineHeight: 1.05,
    letterSpacing: 0,
    contentInsets: .init(top: 8, right: 12, bottom: 8, left: 12),
    cursorStyle: .block,
    cursorBlink: true,
    inactiveCursorStyle: .outline,
    scrollbarVisibility: .automatic,
    theme: SwiftTerminalTheme.default
)
```

`contentInsets` controls the space between terminal cells and the view edges. The inset area uses the active terminal background color.

`scrollbarVisibility` supports `.automatic`, `.visible`, and `.hidden`. Hidden scrollbars are accounted for during terminal fitting so the grid can use the recovered width.

## Themes

SwiftTerminal ships a generated built-in theme catalog based on the iTerm2 Color Schemes project:

```swift
let theme = SwiftTerminalThemes.builtIn(named: "Dracula") ?? .default
session.setTheme(theme)
```

`SwiftTerminalTheme` is a value type with foreground, background, cursor, selection, and ANSI color fields. Host apps can copy a built-in theme and override individual colors:

```swift
var theme = SwiftTerminalThemes.builtIn(named: "Dracula") ?? .default
theme.name = "Custom Dracula"
theme.cursor = "#FFB86C"
session.setTheme(theme)
```

The generated catalog and source notice are stored in `Sources/SwiftTerminal/Resources/TerminalThemes/`.

## Custom Fonts

Custom fonts are served to the bundled runtime through the `swiftterminalfont://` URL scheme. The app process keeps ownership of font data and exposes it through a `WKURLSchemeHandler`.

```swift
let font = TerminalCustomFont(
    family: "Example Mono",
    format: .ttf,
    data: fontData,
    variant: .regular
)

session.registerCustomFont(font)
```

Register related faces together when a family has regular, bold, italic, and bold italic files:

```swift
session.registerCustomFontSet([regular, bold, italic, boldItalic])
```

Each `TerminalCustomFont` should use the same family name and the appropriate `TerminalCustomFontVariant`.

## Search State

The built-in search UI emits `SwiftTerminalSearchState` updates. Host apps can read the latest value from `session.searchState` or `session.currentSearchState()`.

`SwiftTerminalSearchOptions` supports case sensitivity, regular expressions, and whole-word matching.

## Buffer Snapshots

`currentBufferSnapshot(maxLines:trimRight:)` returns the retained xterm active buffer as structured Swift data.

- `logicalText` joins wrapped terminal rows into logical lines.
- `visualText` preserves one newline per retained terminal row.
- `text` is an alias for `logicalText`.

Buffer snapshots are useful for host-owned copy or export flows, especially on touch platforms where the host may want to present terminal content in native UI.
