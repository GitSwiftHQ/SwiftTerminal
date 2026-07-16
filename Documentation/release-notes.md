# Release Notes

## Unreleased

No changes yet.

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
