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

Changing `scrollback` on a running session, through `configuration` or `setScrollback(_:)`, takes effect at once. Lowering it discards the oldest retained lines beyond the new limit; raising it lets later output build up to the new limit, and lines that were already discarded do not come back.

`enablesRuntimeDiagnostics` emits structured runtime diagnostic events through the normal event stream. It is intended for app diagnostics and manual validation.

### Copy and Select All on macOS

The terminal draws its own selection, so the page's selection is only the caret in the runtime's hidden input, and WebKit's own Copy and Select All would act on that input. The terminal's web view routes both through the session instead. The Edit menu's Select All, and Command-A, selects the retained terminal content, or the text in the search field while that field has focus. The Edit menu's Copy, and Command-C, is enabled while the terminal has selected text and copies it through the clipboard integration; while the search field has focus with text selected in it, Copy copies that text. With clipboard integration turned off, Copy is left to WebKit. `copySelection()` and `selectAll()` are the same actions for host menus of their own.

### Pasting and Dropping Files on macOS

Finder copies a file or folder to the pasteboard as a file URL whose plain-text form is only the item's name, and WebKit refuses file drops on the terminal page. The terminal inserts the items' paths instead, the way Terminal.app does. Pasting a pasteboard that holds file URLs, with Command-V, the Edit menu, the context menu, or `pasteFromClipboard()`, and dropping files on the terminal insert each item's full path. Every shell metacharacter Terminal.app escapes, ``\!|&;<>()$'` `` and space, tab, newline, carriage return, and `*?[]#~=%{},:"`, gets a backslash in front of it, other control characters such as ESC are written as ANSI-C quoted escapes like `$'\033'` so they cannot act as keys in the shell's line editor, other characters, non-ASCII ones included, stay as they are, and each path is followed by a space, so `My Folder (1)` and `a&b.txt` become `/Users/me/My\ Folder\ \(1\) /Users/me/a\&b.txt `. The text goes through `paste(_:)`, so bracketed paste applies and nothing runs on its own. Pasteboards and drags without file URLs keep their usual behavior, and text that merely looks like a path is pasted as text.

To leave file URLs to WebKit, for example when the host handles dropped files itself, turn it off:

```swift
session.pastesFileURLsAsPaths = false
```

It defaults to `true`, and the property exists only on macOS.

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

## Keyboard Accessory on iOS

On iOS a host can show its own bar above the system keyboard in place of WebKit's form assistant bar (previous, next, and Done):

```swift
let host = UIHostingController(rootView: KeyBar(session: session))
host.sizingOptions = .intrinsicContentSize
host.view.backgroundColor = .clear
session.keyboardAccessoryContentView = host.view
```

- The terminal wraps the view in a keyboard-styled `UIInputView` that sizes itself from the view's Auto Layout height and plays system keyboard clicks through `playInputClick()`. On iOS 26 and later the view sits in a non-interactive glass rounded rectangle that lines up with the system's own bar above the keyboard: 16 pt from the screen edges, about 10 pt above the keyboard's panel, and a 14 pt corner radius, so keys inset by 6 pt with an 8 pt radius stay concentric. The host view draws its own pressed states. The iPad shortcuts bar's default buttons are removed while a view is set.
- The session keeps a strong reference to the view; the host keeps the controller that owns it. Set the property to `nil` to restore WebKit's default accessory. To keep WebKit's bar away without showing a bar of your own, for example while a hardware keyboard is in use, set a view with no height instead of `nil`. Replacing one view with another reloads the input views, so the accessory is measured again.
- `isKeyboardAccessoryAttached` is `true` while the bar is in a window, which is while the terminal holds the keyboard focus. It becomes `true` just before the keyboard starts to appear and `false` once the keyboard has finished disappearing, so a host that shows the same bar inside its own layout while the terminal has no keyboard never shows two. It is observable.
- `softwareKeyboardMode` chooses what takes the software keyboard's place while the terminal keeps the keyboard focus: `.system` is the system keyboard, `.hidden` leaves only the bar at the bottom of the screen, and `.custom(view)` shows a host view, such as a panel of extra keys, with the bar above it. In every mode keys keep arriving, and changing the mode takes effect without a tap on the terminal. WebKit does not show the keyboard for a terminal that was never tapped, so this does not replace that first tap. It is observable.
- Give a `.custom` view a fixed height, for example a `UIInputView` with the `.keyboard` style and a required height constraint. To keep the terminal from resizing when switching between the system keyboard and the panel, use the height of the system keyboard you last saw in `keyboardWillChangeFrameNotification`, minus the accessory's height.
- `isSoftwareKeyboardSuppressed` is a shorthand for `softwareKeyboardMode == .hidden`; setting it to `false` selects `.system`.
- `resignKeyboardFocus()` takes the keyboard focus away from the terminal. Call it when the terminal leaves the screen, so WebKit does not keep a focused input behind the host's other text fields.

Keep the `SwiftTerminalView` value in the object that owns the session, as with a view model, rather than building it inside a `body` that reads these observable properties. Each `body` pass would otherwise build a new view value, and releasing an earlier one detaches the runtime the terminal on screen is using.

## Keyboard Focus on iOS

With a hardware keyboard, iPadOS 27 delivers key presses to the focus system's focused item ahead of the first responder, and a sidebar row can keep that focus after the person taps the terminal. The session gives a host what it needs to notice and repair that, with the same names as on macOS:

- `keyboardFocusHostView` is the view that hosts the terminal. Ask its focus system for the focused item with `UIFocusSystem.focusSystem(for:)` and check `keyboardFocusHostView.contains(_:)`; a focused item outside the terminal receives Return and the arrow keys instead of the shell. It is `nil` until the terminal's view is built.
- `holdsKeyboardFocus` is `true` while the terminal's web content holds the first responder. On iOS that is not the whole answer: the focused item above can still take hardware key presses first.
- `takeKeyboardFocus()` hands the first responder to the web content through the terminal's host view, which is focusable without a focus effect and accepts the first responder only for the length of that hand-off. Afterwards no item is focused, so key presses reach the shell. A terminal whose web content already holds the first responder with nothing outside it focused stays as it is, and a terminal whose view is not in a window returns `false`. Without a hardware keyboard the call shows the software keyboard, so call it only when the terminal should be typed into.

The terminal never takes the focus on its own. [Keyboard Focus](keyboard-focus.md) explains the behavior on both platforms, when a host should call these, and how to verify key delivery.
