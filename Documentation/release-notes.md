# Release Notes

## Unreleased

### Changes

- Stopped forwarding transient macOS host geometry to WebKit during live window resizes, removing the blank terminal frame that appeared on every drag step under a SwiftUI inspector split.

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
