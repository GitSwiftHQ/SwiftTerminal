# Release Notes

## Unreleased

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
