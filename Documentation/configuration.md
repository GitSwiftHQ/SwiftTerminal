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

## Key Input

`sendKey(_:modifiers:)` sends a key to the shell as if it were typed into the terminal. The runtime encodes it the way xterm does and delivers it through the terminal's input event, so the host's input handler receives it like any other keystroke and the terminal scrolls to the bottom.

```swift
session.sendKey(.escape)
session.sendKey(.up)                                   // ESC [ A, or ESC O A in application cursor mode
session.sendKey(.tab, modifiers: .shift)               // ESC [ Z
session.sendKey(.character("c"), modifiers: .ctrl)     // 0x03
session.sendKey(.function(5), modifiers: .ctrl)        // ESC [ 15 ; 5 ~
```

- Cursor keys, Home, and End follow the cursor-key mode the running program selected (DECCKM), with `ESC O` in application mode and `ESC [` otherwise. With modifiers they become `ESC [ 1 ; m X`, where `m` is `1 + Shift + 2·Alt + 4·Ctrl + 8·Meta`.
- Insert, Delete, Page Up, Page Down, and F5 through F12 are `ESC [ n ~`, or `ESC [ n ; m ~` with modifiers. F1 through F4 are `ESC O P` through `ESC O S`, or `ESC [ 1 ; m P` through `S` with modifiers.
- Enter is CR, Backspace is DEL (BS with Ctrl), Escape is ESC, and Shift+Tab is `ESC [ Z`. Alt adds an escape prefix to these keys and to characters. Ctrl has no Tab encoding, so Ctrl+Tab sends a plain Tab.
- Ctrl with a single character sends its control code: letters map to 0x01–0x1A, `@` `2` and Space to NUL, `[` and `3` to ESC, `\` and `4` to FS, `]` and `5` to GS, `^` and `6` to RS, `_` `7` and `/` to US, and `?` and `8` to DEL. Other characters are sent unchanged.
- Shift+Page Up and Shift+Page Down are sent to the shell rather than scrolling the terminal.
- A function key outside F1 through F12 and an empty character are ignored.

### Sticky Modifiers

`setKeyModifiers(_:)` sets modifiers that apply to the next keys. Each modifier is `.off`, `.oneShot`, or `.sustained`:

```swift
session.setKeyModifiers(SwiftTerminalKeyModifierStates(ctrl: .oneShot))
```

Sticky modifiers apply to keys sent with `sendKey(_:modifiers:)`, merged with the key's own modifiers, and to a single printable ASCII character typed on the system or a hardware keyboard, so a key bar's Ctrl followed by `c` on the keyboard sends 0x03. Pasted text, text committed by an input method, and anything longer than one character pass through unchanged and leave the modifiers as they are. A one-shot modifier turns off after the key that used it; the runtime then reports the new state with a `key_modifiers_changed` event and `keyModifierStates` reflects it. `keyModifierStates` is observable, and a reloaded runtime gets the last state back.

### Option as Meta

Set `optionIsMeta` to make the Option key send an escape prefix, the way a terminal's Meta key does, instead of the character from the keyboard's Option layer. xterm applies this where it detects a Mac platform, which includes an iPad web view reporting a desktop platform, so an iPad host with a hardware keyboard turns it on to make Option+B send `ESC b`.
