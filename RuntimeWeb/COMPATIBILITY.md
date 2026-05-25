# Runtime Compatibility Notes

This file records host/runtime behavior that can look like an xterm.js bug or a SwiftTerminal bug depending on where it is observed. Keep it current when changing the runtime, updating `@xterm/xterm`, or changing `WKWebView` keyboard handling.

## macOS WKWebView Chinese IME Shift Punctuation

Status:

- A scoped SwiftTerminal runtime compatibility rule is active.
- The rule exists for macOS `WKWebView` hosting `@xterm/xterm` 6.0.0.
- The rule is scoped to the SwiftTerminal WebKit host and xterm's hidden textarea.

Observed behavior:

- A vanilla `@xterm/xterm` 6.0.0 browser page accepts shifted punctuation correctly with the active Chinese input source.
- The same vanilla xterm page inside a minimal macOS `WKWebView` can drop the first shifted punctuation in a held-Shift sequence.
- The failing WKWebView sequence is:
  1. `keydown` with `key="Shift"` and `shiftKey=true`
  2. `beforeinput` / `input` with `inputType="insertText"` and the resolved punctuation
  3. delayed `keydown` with `keyCode=229`, `shiftKey=true`, and a printable resolved `key`

Working hypothesis:

- xterm's hidden-textarea input path treats the standalone Shift keydown as active keydown state.
- The following `insertText` event can then look already handled from xterm's perspective.
- The delayed printable `keyCode=229` keydown can leave composition-related keydown state in a shape that affects subsequent input events.
- Browser-hosted xterm does not show this sequencing issue with the same xterm version and input source.

SwiftTerminal compatibility rule:

- Suppress modifier-only Shift `keydown` before xterm sees it.
- Suppress delayed printable Shift + `keyCode=229` `keydown` before xterm sees it.
- Do not call `terminal.input(...)` or synthesize terminal characters.
- Let terminal text continue to arrive through the normal WKWebView/xterm `insertText` path.

Implementation location:

- `RuntimeWeb/src/main.ts`
  - `shouldSuppressWebKitModifierOnlyShift(_:)`
  - `shouldSuppressWebKitProcessedIMEKeydown(_:)`
  - capture-phase `window.addEventListener('keydown', ...)`

Validation sequence:

1. Confirm the installed xterm version:

   ```bash
   cd RuntimeWeb
   npm ls @xterm/xterm --depth=0
   npm view @xterm/xterm version
   ```

2. Compare a vanilla xterm browser page with the same vanilla page inside a minimal macOS `WKWebView`.

3. With a Chinese input source active, hold Shift and press `1 2 3 4 5`.

4. Expected browser output:

   ```text
   !@#¥%
   ```

5. Expected fixed WKWebView output:

   ```text
   !@#¥%
   ```

6. Inspect the WKWebView event log for the three-event sequence listed above.

7. After modifying the compatibility rule, run:

   ```bash
   cd RuntimeWeb
   npm run typecheck
   cd ..
   Scripts/build_runtime.sh
   swift test
   ```

Upgrade rule:

- If a future xterm.js release consumes this WKWebView event sequence correctly on its own, remove or narrow the SwiftTerminal suppression in the same change that upgrades xterm.
- Keep the browser-vs-WKWebView comparison in the upgrade notes so future input regressions can be traced back to host event sequencing rather than surface-level shifted-punctuation symptoms.
