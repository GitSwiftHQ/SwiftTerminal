# xterm.js Compatibility Layers

SwiftTerminal uses xterm.js for terminal parsing, buffering, rendering, input handling, search, links, and Unicode width support. The runtime also contains a small set of compatibility layers for Apple `WKWebView` behavior and host-facing appearance requirements.

These layers live in `RuntimeWeb/src/main.ts` and the generated runtime asset under `Sources/SwiftTerminal/Resources/TerminalRuntime/`. Keep this document current when changing input handling, fitting behavior, `WKWebView` integration, or xterm.js versions.

## Compatibility Layer 1: WebKit `insertText` Fallback

Purpose:

- Support `WKWebView` input paths where text is committed through xterm's hidden textarea as `beforeinput` / `input` with `inputType="insertText"`, while xterm.js emits no `onData` event for that text.

Affected behavior:

- Some iOS third-party keyboards and IME paths commit text through the browser textarea input event path.
- The terminal should receive the committed text once.
- The runtime sends each committed text sequence once, including paths where xterm.js already emitted `onData`.

Implementation:

- `installWebKitTextareaInputFallback()`
- `pendingWebKitTextareaInsert`
- `recentWebKitTextareaInsert`
- `xtermDataEventSerial`
- `terminalTextareaKeydownInputState`

Invariant:

- Forward a textarea `insertText` event to Swift only when xterm.js stayed silent for that same input sequence.
- Treat an `insertText` event as already handled when xterm's data-event serial advanced during the same short keydown window.

Validation:

1. Use a normal hardware keyboard and type printable text, including Space. Each key should generate one terminal input.
2. Use an IME or third-party keyboard path that commits through `insertText`. Committed text should appear once in the terminal.
3. With runtime diagnostics enabled, compare `xterm.data`, `textarea.beforeinput.capture`, `textarea.input.capture`, and `host.write` events.

Upgrade check:

- Re-test this fallback after xterm.js input, composition, or textarea handling changes. Remove the fallback only after a default xterm.js runtime inside `WKWebView` handles the same committed-text paths reliably.

## Compatibility Layer 2: WebKit Keydown Guards

Purpose:

- Prevent `WKWebView` keydown events that represent host input bookkeeping from reaching xterm.js when the text path has already carried the actual terminal input, or when a modifier-only event would trigger xterm's user-input scroll behavior.

Active guards:

- `webkit-modifier-only-shift`
- `webkit-processed-ime`
- `webkit-modifier-only-meta-229`

Implementation:

- `shouldSuppressWebKitModifierOnlyShift(_:)`
- `shouldSuppressWebKitProcessedIMEKeydown(_:)`
- `shouldSuppressWebKitModifierOnlyMeta229(_:)`
- `getWebKitKeydownSuppressReason(_:)`
- capture-phase `window.addEventListener("keydown", ...)`

Guard: modifier-only Shift

- Scope: SwiftTerminal `WKWebView` host, xterm hidden textarea.
- Match: standalone Shift keydown with `shiftKey=true` and no other modifiers.
- Reason: macOS `WKWebView` can send standalone Shift before resolved IME `insertText`; xterm can treat that keydown as active input state before the committed text arrives.

Guard: processed IME keydown

- Scope: SwiftTerminal `WKWebView` host, xterm hidden textarea.
- Match: printable `keyCode=229` keydown after committed text, or shifted printable `keyCode=229` in the known WebKit shifted-punctuation sequence.
- Reason: the character has already arrived through `insertText`; the later keydown is browser/xterm bookkeeping for that committed text.

Guard: standalone Command `keyCode=229`

- Scope: SwiftTerminal `WKWebView` host, xterm hidden textarea.
- Match: `key="Meta"`, `code="MetaLeft"` or `code="MetaRight"`, `keyCode=229`, `metaKey=true`, and `ctrlKey/altKey/shiftKey=false`.
- Reason: xterm.js treats `keyCode=229` as a composition keydown. When `scrollOnUserInput` is enabled and the user is viewing scrollback, that path can move the terminal to the bottom even though the user only pressed the Command modifier.

Normal Command behavior:

- Command chords such as Copy and Paste arrive as concrete key events like `KeyC` or `KeyV` with `metaKey=true`, so they fall through these guards.
- Normal standalone Command keydown events with platform key codes such as `91` or `93` fall through these guards.
- Link-hover modifier state is updated before the standalone Command guard returns, so Command-click link affordances remain synchronized.

Diagnostics:

- Runtime diagnostics include `suppressReason` on `window.keydown.capture` and `window.keydown.after` events.
- The reason string should identify the exact guard that would run for the event.

Validation:

1. Chinese IME shifted punctuation: press `Shift+1` through `Shift+0` and confirm the expected punctuation appears once.
2. Third-party or IME committed text: confirm text committed through `insertText` appears once.
3. Scrollback with standalone Command: scroll into history, press Command by itself, and confirm the viewport remains in history.
4. Command chords: confirm `Cmd-C`, `Cmd-V`, `Cmd-F`, and Command-click links keep their expected behavior.
5. Diagnostics: confirm suppressed events include the expected `suppressReason`.

Upgrade check:

- Compare the current xterm.js `CompositionHelper` and keydown flow before changing these guards.
- Run a default xterm.js page in a browser and inside a minimal `WKWebView` host when investigating input behavior.
- Keep each guard scoped to a concrete event signature and validation case.

## Compatibility Layer 3: Hidden-Scrollbar Fit Path

Purpose:

- Let `SwiftTerminalScrollbarVisibility.hidden` recover terminal grid width while hiding scrollbar chrome.

Affected behavior:

- xterm's fit addon accounts for scrollbar width when scrollback is enabled.
- SwiftTerminal exposes a hidden-scrollbar appearance mode where the terminal grid should use the width normally reserved for the scrollbar.

Implementation:

- `fitTerminal(...)`
- `runtimeScrollbarWidth()`
- `terminal._core?._renderService?.dimensions`
- `terminal._core?._renderService?.clear()`

Invariant:

- `.automatic` and `.visible` follow normal scrollbar sizing.
- `.hidden` treats runtime scrollbar width as zero during fit calculations.
- Terminal fitting remains stable after open, resize, font load, appearance changes, and content inset changes.

Validation:

1. Toggle `.automatic`, `.visible`, and `.hidden` in `SwiftTerminalExample`.
2. Confirm `.hidden` increases usable terminal columns when a scrollbar would otherwise reserve width.
3. Confirm wheel and trackpad scrolling still work with hidden scrollbars.
4. Resize the host view repeatedly and confirm terminal content stays aligned to the grid.
5. Change font size, line height, letter spacing, and content insets, then confirm fitting remains correct.

Upgrade check:

- Compare SwiftTerminal's fit path with the installed `@xterm/addon-fit` implementation.
- Inspect xterm.js render-service and viewport internals for renamed or changed private fields.
- Rebuild the runtime and run Swift package tests plus a manual host-app fit pass after every xterm.js upgrade.

## Related xterm.js Addons

SwiftTerminal also loads xterm.js addons for Unicode width, search, clipboard, and web links. These are normal xterm.js extension points.

- `@xterm/addon-unicode11` is active so wide Emoji and CJK width accounting match modern terminal behavior.
- Search and web-link behavior are exposed through SwiftTerminal's public session and runtime UI.
- Clipboard behavior is bridged to the host app through typed runtime events.

Changes to these addons should follow the same rebuild and manual validation process described in [Runtime and Build Notes](runtime.md).
