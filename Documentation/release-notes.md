# Release Notes

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
