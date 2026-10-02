# Release Notes

## 1.0.12

SwiftTerminal 1.0.12 lets a host send keys and sticky modifiers through the terminal's own input path, puts a host key bar above the iOS system keyboard, hands hardware key presses back to the terminal on iPadOS, inserts file paths for files pasted or dropped on the macOS terminal, copies the terminal selection from the macOS Edit menu, and starts each new session on a fresh line below the previous output.

### Changes

- Added `SwiftTerminalSession.sendKey(_:modifiers:)` with `SwiftTerminalKey` and `SwiftTerminalKeyModifiers`. The runtime encodes each key the way xterm does, including application cursor-key mode (DECCKM), the xterm modifier parameter for cursor, editing, and function keys, the C0 control characters for Ctrl with a character, and the escape prefix for Alt, then delivers it through the terminal's input event, so the host's input handler receives it like a typed key and the terminal scrolls to the bottom.
- Added sticky modifiers: `setKeyModifiers(_:)` with `SwiftTerminalKeyModifierStates` sets Ctrl, Alt, Shift, and Meta to off, one-shot, or sustained. They apply to keys sent with `sendKey(_:modifiers:)` and to a single printable ASCII character typed on the system or a hardware keyboard; pasted text and input-method commits pass through unchanged. A consumed one-shot modifier is reported with the new `key_modifiers_changed` runtime event and mirrored by the observable `keyModifierStates`.
- Added `SwiftTerminalSession.optionIsMeta`, which makes the Option key send an escape prefix, the way a terminal's Meta key does.
- Added the iOS keyboard accessory API: `keyboardAccessoryContentView` shows a host view above the system keyboard in a keyboard-styled input view, drawn in a glass rounded rectangle on iOS 26 and later, and replaces WebKit's form assistant bar; `isKeyboardAccessoryAttached` reports whether that bar is on screen; `softwareKeyboardMode` shows the system keyboard, no keyboard, or a host view such as a panel of extra keys while the terminal keeps the keyboard focus and the bar, with `isSoftwareKeyboardSuppressed` as a shorthand for hiding the keyboard; `resignKeyboardFocus()` takes the keyboard focus away; `playInputClick()` plays the system keyboard click.
- The iOS terminal now uses a `WKWebView` subclass that supplies these input views. Without a `keyboardAccessoryContentView` the input views stay WebKit's defaults.
- Added `takeKeyboardFocus()` and `holdsKeyboardFocus` on iOS with the macOS names, plus `keyboardFocusHostView`. With a hardware keyboard, iPadOS 27 delivers key presses to the focus system's focused item ahead of the first responder, so a sidebar row that took focus kept Return, Tab, and the arrow keys after the person tapped the terminal. `takeKeyboardFocus()` hands the first responder to the terminal's web content and leaves no item focused, so key presses reach the shell; a host checks the focused item against `keyboardFocusHostView` to decide when to call it.
- `SwiftTerminalSession` now conforms to `Observable`. Observation tracks `keyModifierStates`, `isKeyboardAccessoryAttached`, and `softwareKeyboardMode` (with `isSoftwareKeyboardSuppressed`).
- Files and folders pasted or dropped on the macOS terminal now insert their full paths, the way Terminal.app does: Command-V, the Edit and context menus, `pasteFromClipboard()`, and drops from Finder insert each path escaped for the shell and followed by a space. The text goes through `paste(_:)`, so bracketed paste applies and nothing runs on its own. `pastesFileURLsAsPaths` controls this on macOS and defaults to `true`; pasteboards and drags without file URLs keep their previous behavior.
- The macOS Edit menu's Copy, and Command-C, now copies the terminal selection, or the find bar's selected text while the find bar has focus. With clipboard integration turned off, Copy stays with WebKit.
- Kept the cursor in place when the terminal state reset leaves the alternate screen, so the next session prints its first lines below the previous session's output.
- Started the next session on a fresh line below the previous session's output after a terminal state reset, wherever the previous session left the cursor, including an idle prompt and programs such as `top` that draw on the normal screen. Output queued with `write(_:)` during the reset lands after the new line, and `resetStateForNewRemoteSessionAcknowledged()` returns once the cursor has moved.
- Added the [Keyboard Focus](keyboard-focus.md) guide for macOS and iPadOS hosts, and documented key input, the iOS keyboard accessory, iOS keyboard focus, and file paths on macOS in the configuration guide.
- Updated the example app with a key bar that uses the new API above the keyboard and at the bottom of the terminal pane, and made it keep its `SwiftTerminalView` in the model that owns the session.

### Source Compatibility

- `TerminalHostCommandType` gains `copy_focused_control`, `send_key`, `set_key_modifiers`, and `set_option_is_meta`, and `TerminalRuntimeEventType` gains `key_modifiers_changed`. A `switch` over either enum without a `default` case needs the new cases.
- A macOS host that handles file drops or file pastes itself sets `pastesFileURLsAsPaths` to `false` to keep its own handling.

### Validation

- `swift build`
- `swift test` with 167 Swift Testing tests
- `SwiftTerminal` package tests on iPadOS 27.0 and iOS 18.6 simulators, 125 tests each
- `npm run typecheck`, `npm run check:key-encoder`, `npm run check:webkit-input`, `npm run check:terminal-state-reset`, and `npm run check:unicode`
- `./Scripts/build_runtime.sh` reproduces the bundled runtime byte for byte
- `SwiftTerminalExample` macOS Debug build
- `SwiftTerminalExample` iOS Simulator Debug build, run on iOS 27.0, iOS 26.5, and iPadOS 18.6 simulators: the accessory replaces WebKit's form bar, the keyboard hides and returns with the bar and focus kept, typing continues afterwards, and exactly one bar is on screen
- iOS Simulator Debug build of a host app connected over SSH to a local server, with a raw-mode byte dump on the remote side: every key, Ctrl and Alt one-shot modifiers, Ctrl with a character typed on the system keyboard, and both cursor-key modes produced the documented sequences
- iPadOS 27.0 simulator with a hardware keyboard in the same host app: after the hand-off, Return, Down, Tab, and `y` reach the shell as `0d`, `1b 5b 42`, `09`, and `79`
- iOS Simulator host app after a server-side SSH disconnect and Reconnect: the new session starts below the old output after plain output, at an idle prompt, with `top` running, and with an alternate-screen program
- macOS 27 Debug build of the same host app: files and folders dragged from Finder or pasted with Command-V insert their escaped paths, and Edit ▸ Copy is enabled with a terminal selection and copies it

## 1.0.11

SwiftTerminal 1.0.11 lets a macOS host give the terminal the window's first responder, and keeps the terminal painted when the host swaps the view around it.

### Changes

- Added `SwiftTerminalSession.takeKeyboardFocus()` on macOS, which gives the terminal's web view the window's first responder so key presses reach the shell without a click inside the terminal.
- Added `SwiftTerminalSession.holdsKeyboardFocus` and `SwiftTerminalSession.keyboardFocusWindow` on macOS, so a host driving focus for several terminals can tell its own terminal apart from another view that holds the first responder.
- Left a terminal that already holds the first responder untouched and reported `false` for a terminal whose view is not in a window, so a host can call these whenever it decides the terminal should be typed into.
- Kept the terminal's view inside its window on macOS while SwiftUI rebuilds the views around it, removing the blank terminal that appeared for several frames whenever a host swapped which session it showed. The view the representable hands SwiftUI is now a slot; the terminal itself waits in the window it is already in until a slot claims it.

### Validation

- `swift build`
- `swift test` with 102 Swift Testing tests
- `SwiftTerminalExample` macOS Debug build
- `SwiftTerminalExample` iOS Simulator Debug build
- macOS Debug build of a host app that gives the terminal keyboard focus when a session is selected, typing into it after each switch
- 120 fps screen recordings of that host app switching between two terminals and between a terminal and another screen: no blank frames, against runs of 4 to 7 blank frames before the change
- iOS Simulator Debug build of the same host app

## 1.0.10

SwiftTerminal 1.0.10 makes OSC 8 hyperlinks behave like plaintext links on macOS and removes a blank frame during live window resizes.

### Changes

- Fixed Command-click activation and the `Follow link (cmd + click)` hint for OSC 8 hyperlinks, the form Codex CLI and other modern tools print, so they behave like plaintext URLs.
- Kept the `Follow link (cmd + click)` hint on screen while the pointer holds still over a link on a line that keeps repainting, such as a CLI status line.
- Placed the link hint next to its link while the terminal is scrolled back through scrollback, and hid it once the link's row leaves the viewport.
- Stopped forwarding transient macOS host geometry to WebKit during live window resizes, removing the blank terminal frame that appeared on every drag step under a SwiftUI inspector split.

### Validation

- `npm run check:webkit-input`
- `npm run check:unicode`
- `npm run typecheck`
- `./Scripts/build_runtime.sh`
- `swift test` with 85 Swift Testing tests
- `SwiftTerminalExample` macOS Debug build
- `SwiftTerminalExample` iOS Simulator Debug build
- Browser harness against the bundled runtime for OSC 8 and plaintext link hover, Command-click activation, repaint stability, and scrollback placement

## 1.0.9

SwiftTerminal 1.0.9 fixes macOS WebKit input-source switching and Edit-menu selection behavior.

### Changes

- Prevented active IME preedit text from being sent twice when macOS WebKit switches input sources.
- Routed the macOS Edit menu's Select All action to the focused terminal buffer or search query.
- Preserved terminal-only selection for the public `SwiftTerminalSession.selectAll()` API and WebKit fallback behavior while the runtime is unavailable.

### Validation

- `npm run check:webkit-input`
- `npm run check:unicode`
- `npm run typecheck`
- `./Scripts/build_runtime.sh`
- `swift test` with 78 Swift Testing tests
- `SwiftTerminalExample` macOS Debug build
- `SwiftTerminalExample` iOS Simulator Debug build
- Manual macOS Chinese Pinyin preedit to Caps Lock input-source switch
- Manual macOS Edit -> Select All with terminal and search-field focus
- `git diff --check`

## 1.0.8

SwiftTerminal 1.0.8 aligns terminal input, redraw, and session-boundary state with PTY, WebKit, tmux, and emoji-presentation semantics.

### Changes

- Kept bare line feeds column-preserving so tmux incremental redraws retain their intended horizontal position.
- Added forward-diff handling for keydown-less dictation hypothesis updates, including corrections without replaying the full phrase.
- Completed reused-session reset boundaries by leaving alternate screens and disabling retained mouse tracking modes.
- Matched tmux-style two-column widths for VS16 emoji-presentation sequences while retaining the Unicode 11 width tables for all other text.

### Validation

- `npm run check:webkit-input`
- `npm run check:unicode`
- `npm run typecheck`
- `./Scripts/build_runtime.sh`
- `swift test` with 76 Swift Testing tests
- `SwiftTerminalExample` macOS Debug build
- `SwiftTerminalExample` iOS Simulator Debug build
- `git diff --check`

## 1.0.7

SwiftTerminal 1.0.7 refreshes the built-in theme catalog and hardens theme generation for schemes with optional text colors.

### Changes

- Refreshed the bundled iTerm2 theme snapshot from `7335c0a` to the latest stable upstream release at `97e244c`.
- Expanded the catalog from 516 to 591 themes with 75 additions and zero removals.
- Adopted upstream palette corrections for Adwaita, Adwaita Dark, the four Catppuccin variants, and Electron Highlighter.
- Added semantic fallbacks for omitted cursor-text and selected-text colors, covering the new Sandstone themes.
- Added generator and catalog regression coverage for fallback priority, theme names, and color payloads.

### Validation

- `python3 -m unittest discover -s Scripts/Tests -v`
- Deterministic catalog regeneration after excluding the generated timestamp
- `swift test` with 76 Swift Testing tests
- `SwiftTerminalExample` macOS Debug build
- `SwiftTerminalExample` iOS Simulator Debug build

## 1.0.6

SwiftTerminal 1.0.6 hardens WebKit input coordination and iOS keyboard-driven layout behavior.

### Changes

- Extracted WebKit input compatibility state into a focused `WebKitInputCoordinator` with event-sequence coverage for xterm-owned input, silent `insertText`, processed `keyCode=229`, and normal Command chords.
- Added `npm run check:webkit-input` as the focused runtime compatibility check.
- Locked the outer iOS `WKWebView` scroll view so keyboard focus and inset restoration cannot drag the complete terminal page away from its SwiftUI layout.
- Kept terminal buffer scrolling under the runtime-owned xterm viewport.

### Validation

- The WebKit input coordinator commit previously passed `npm run check:webkit-input`, `npm run typecheck`, `./Scripts/build_runtime.sh`, and `swift test` with 74 Swift Testing tests.
- Final release-tree validation was not rerun for this release.

## 1.0.5

SwiftTerminal 1.0.5 adds an acknowledged reset barrier for hosts that reuse a terminal session across backend PTY boundaries.

### Changes

- Added `resetStateForNewRemoteSessionAcknowledged()` as an awaitable lifecycle barrier for hosts that reuse a `SwiftTerminalSession` across backend PTY boundaries.
- Runtime `reset_terminal_state` now resolves after xterm processes the DECSTR soft reset.
- Acknowledged resets now fail with `SwiftTerminalLifecycleError.runtimeUnavailable` when the runtime is unavailable, detaches, or terminates before the reset barrier completes.
- Acknowledged resets now fail with `CancellationError` when the caller task is canceled before the reset barrier completes.

### Validation

- `npm run typecheck`
- `./Scripts/build_runtime.sh`
- `swift test`

## 1.0.4

SwiftTerminal 1.0.4 focuses on WKWebView input correctness and public documentation.

### Changes

- Fixed duplicate Space input on macOS by tightening the WebKit `insertText` fallback so it only forwards text when xterm.js stayed silent for the same key sequence.
- Added a narrow guard for `WKWebView` environments that report standalone Command as `keyCode=229`, preventing xterm.js from scrolling a terminal in history back to the bottom.
- Added a public `Documentation/` library and moved detailed runtime compatibility notes out of the top-level README.

### Validation

- `npm run typecheck`
- `./Scripts/build_runtime.sh`
- `swift test`
- `SwiftTerminalExample` macOS Debug build
