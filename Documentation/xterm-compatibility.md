# xterm.js Compatibility Layers

SwiftTerminal uses xterm.js for terminal parsing, buffering, rendering, input handling, search, links, and Unicode width support. The runtime also contains a small set of compatibility layers for Apple `WKWebView` behavior and host-facing appearance requirements.

These layers live in `RuntimeWeb/src/main.ts`, `RuntimeWeb/src/webkitInputCoordinator.ts`, and the generated runtime asset under `Sources/SwiftTerminal/Resources/TerminalRuntime/`. `main.ts` adapts DOM and xterm.js events, while `WebKitInputCoordinator` owns the WebKit input compatibility state machine. Keep this document current when changing input handling, fitting behavior, `WKWebView` integration, or xterm.js versions.

## Compatibility Layer 1: WebKit `insertText` Fallback

Purpose:

- Support `WKWebView` input paths where text is committed through xterm's hidden textarea as `beforeinput` / `input` with `inputType="insertText"`, while xterm.js emits no `onData` event for that text.

Affected behavior:

- Some iOS third-party keyboards and IME paths commit text through the browser textarea input event path.
- The terminal should receive the committed text once.
- The runtime sends each committed text sequence once, including paths where xterm.js already emitted `onData`.

Implementation:

- `RuntimeWeb/src/webkitInputCoordinator.ts`
- `WebKitInputCoordinator.recordXtermData()`
- `WebKitInputCoordinator.recordTextareaKeydown(now)`
- `WebKitInputCoordinator.handleBeforeInput(event, now)`
- `WebKitInputCoordinator.handleInput(event, now)`
- `WebKitInputCoordinator.shouldForwardScheduledInsert(insert)`
- `RuntimeWeb/src/main.ts` capture-phase `beforeinput` / `input` listeners on the terminal root element, filtered to xterm's hidden textarea

Invariant:

- Forward a textarea `insertText` event to Swift only when xterm.js stayed silent for that same input sequence.
- Treat an `insertText` event as already handled when xterm's data-event serial advanced during the same short keydown window.
- The listeners run on the terminal root in the capture phase so the diff-forwarding layer below can stop propagation before xterm's own textarea listeners; fallback and pass-through decisions do not stop propagation and leave xterm's handling unchanged.

Validation:

1. Use a normal hardware keyboard and type printable text, including Space. Each key should generate one terminal input.
2. Use an IME or third-party keyboard path that commits through `insertText`. Committed text should appear once in the terminal.
3. With runtime diagnostics enabled, compare `xterm.data`, `textarea.beforeinput.capture`, `textarea.input.capture`, and `host.write` events.
4. Run `npm run check:webkit-input` from `RuntimeWeb/` to validate the coordinator event-sequence rules.

Upgrade check:

- Re-test this fallback after xterm.js input, composition, or textarea handling changes. Remove the fallback only after a default xterm.js runtime inside `WKWebView` handles the same committed-text paths reliably.

## Compatibility Layer 2: WebKit Keydown Guards

Purpose:

- Prevent `WKWebView` keydown events that represent host input bookkeeping from reaching xterm.js when the text path has already carried the actual terminal input, or when a modifier-only event would trigger xterm's user-input scroll behavior.

Active guards:

- `webkit-modifier-only-shift`
- `webkit-processed-ime`
- `webkit-modifier-only-meta-229`
- `webkit-input-source-switch`

Implementation:

- `RuntimeWeb/src/webkitInputCoordinator.ts`
- `WebKitInputCoordinator.getKeydownSuppressReason(event, now)`
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

Guard: input-source switch during composition

- Scope: SwiftTerminal `WKWebView` host, xterm hidden textarea.
- Match: `key="Unidentified"`, `keyCode=0`, `isComposing=true`, and no modifiers.
- Reason: macOS WebKit synthesizes this keydown while switching input sources during an active composition. If it reaches xterm, xterm finalizes and sends the preedit text before the following `compositionend` sends the same text again.

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
5. Input-source switch during composition: enter Latin letters as active Chinese IME preedit text, switch to the Latin input source with Caps Lock, and confirm the text is sent once.
6. Diagnostics: confirm suppressed events include the expected `suppressReason`.
7. Run `npm run check:webkit-input` from `RuntimeWeb/` to validate guard signatures and normal Command pass-through.

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

## Compatibility Layer 4: Remote Session Boundary Reset

Purpose:

- Prevent local xterm modes from leaking from one backend PTY into the next when a host app reuses the same `SwiftTerminalSession`.

Affected behavior:

- Shells such as bash/readline may enable bracketed paste by sending `ESC[?2004h`.
- If the SSH connection is forcibly replaced or a remote system is reinstalled, the old shell may never send the matching `ESC[?2004l`.
- xterm.js then still believes bracketed paste is enabled and wraps future paste input as `ESC[200~...ESC[201~`, even if the new remote shell does not understand that mode.

Implementation:

- `try await SwiftTerminalSession.resetStateForNewRemoteSessionAcknowledged()`
- `SwiftTerminalSession.resetStateForNewRemoteSession()` for fire-and-forget compatibility
- typed host command `reset_terminal_state`
- runtime handler writes a session-boundary sequence into the local xterm parser: leave the alternate screen (`ESC[?1049l ESC[?1047l ESC[?47l`), soft reset (`ESC[!p`), then disable every mouse tracking mode and encoding (`ESC[?9l ?1000l ?1001l ?1002l ?1003l ?1005l ?1006l ?1015l ?1016l`)
- the acknowledged method returns after WebKit has run the host command and xterm's write callback has completed for the whole boundary sequence
- the acknowledged method throws `SwiftTerminalLifecycleError.runtimeUnavailable` when there is no runtime available to execute the reset
- the acknowledged method throws `CancellationError` when the caller task is canceled before the barrier completes

Invariant:

- The reset is local to the embedded terminal runtime. Backend PTYs receive later host input and output only through the normal session flow.
- Host code that needs a backend boundary awaits the async reset before opening the new remote PTY.
- The reset preserves primary-screen scrollback. It resets the modes handled by xterm's DECSTR path plus the two classes DECSTR leaves behind in xterm.js: the active alternate screen, and mouse tracking, which lives in `CoreMouseService` and is otherwise cleared only by a full terminal reset. Without the explicit mouse disables, a dead remote session that enabled mouse reporting keeps emitting SGR mouse sequences (`ESC[<...M`) into the next shell, which echoes them as visible `35;56;24M`-style garbage on every pointer movement.

Stronger boundary:

- `SwiftTerminalSession.reloadRuntime()` rebuilds the embedded runtime and creates a fresh xterm instance.
- Use a runtime reload when the host has evidence that the remote identity changed, such as an SSH host-key fingerprint change after a reinstall.
- Reloading the runtime clears current xterm buffer state, so it is intentionally stronger than the soft reset.

Validation:

1. Connect to a bash/readline shell that enables bracketed paste.
2. Force-close the connection without allowing the shell to exit cleanly.
3. Reconnect the same terminal session to a shell that does not understand bracketed paste.
4. Paste `abcdefghijklmnopqrstuvwxyz`.
5. Confirm the new shell receives the full text instead of a suffix such as `klmnopqrstuvwxyz`.

## Compatibility Layer 5: Keydown-less Insert Diff Forwarding

Purpose:

- Deliver iOS/macOS dictation and other keydown-less `insertText` streams to the host once, as incremental edits, instead of replaying the whole hypothesis text on every update.

Affected behavior:

- Dictation commits no key events. WebKit repeatedly rewrites the textarea by replacing the current hypothesis in place, and each rewrite arrives as `beforeinput` / `input` with `inputType="insertText"` whose `data` holds the entire updated hypothesis.
- Without this layer, xterm's `_inputEvent` forwards each full hypothesis verbatim (`_keyDownSeen` stays false), so the host receives the growing prefix over and over.

Implementation:

- `WebKitInputCoordinator.handleInput(event, now)` `forward-diff` decision
- `WebKitInputCoordinator` forwarded-tail state: the textarea suffix whose bytes were already forwarded to the host
- `RuntimeWeb/src/main.ts` capture-phase `input` listener: a `forward-diff` decision stops propagation before xterm's textarea listener and posts the diff bytes directly

Invariant:

- The layer activates only for host textarea `insertText` events with data, outside composition (`isComposing=false`), and with no textarea keydown inside the keydown window. Every keyboard-driven path keeps its existing behavior.
- When it activates it is the single writer for that event: propagation is stopped so xterm cannot forward, and the pending fallback insert is consumed so the scheduled forward cannot fire.
- A pure append onto text it does not own adopts only the appended tail. A replacement is converted to one `DEL` (`0x7F`) per removed character, counted in code points, followed by the retyped suffix. Surrogate pairs are never split.
- Ownership is released on any textarea keydown, composition activity, non-`insertText` input, a fallback forward that clears the textarea, or any mutation that does not match the mirrored tail. After release the legacy fallback path runs exactly as before, even when that reintroduces duplicated hypothesis text for that stream.

Diagnostics:

- `webkit.insert.diff_forward` reports `deletedCharacterCount`, `insertedCharacterCount`, and `forwardedTextLength` for each intercepted insert.
- Baseline diagnostic metadata includes `forwardedWebKitTailLength` (`-1` when the coordinator owns no tail).

Validation:

1. iOS dictation into a shell prompt: speak a phrase with a mid-phrase correction. The prompt should track the dictation live and contain the final phrase exactly once.
2. iOS keyboard typing, including Space and QuickType candidates, still produces each character once.
3. Chinese IME composition on macOS and iOS still commits text once.
4. Hardware-keyboard typing, Enter, Ctrl-C, and arrow keys behave unchanged after a dictation session.
5. Run `npm run check:webkit-input` from `RuntimeWeb/` to validate the diff, adoption, release, and regression rules.

Upgrade check:

- Re-test dictation after xterm.js changes to `_inputEvent`, `_keyDownSeen`, or textarea clearing, since this layer relies on running before xterm's textarea `input` listener in the capture phase.

## Compatibility Layer 6: Emoji Variation Selector Width

Purpose:

- Measure emoji-presentation sequences (`<base char> U+FE0F`, e.g. `✳️` `❤️` `⏺️`) as two columns, matching tmux 3.4+, iTerm2, and kitty.

Affected behavior:

- The Unicode 11 tables measure per codepoint: U+FE0F is zero width, so the sequence stays one column. tmux measures it as two columns.
- Any width disagreement between SwiftTerminal and tmux desynchronizes tmux's model of the client screen. tmux then skips "unchanged" prefix cells during incremental redraws (scrolling, pane updates), which leaves stale characters in the leading columns until a full repaint (`refresh-client`, resize). Verified against tmux 3.6 with cursor-position-report probes run inside and outside tmux.

Implementation:

- `RuntimeWeb/src/emojiVariationWidthProvider.ts`
- provider version `11-emoji-variation`, registered instead of activating `@xterm/addon-unicode11` directly; all lookups delegate to the Unicode 11 provider except the one added rule
- the rule: U+FE0F joining a single-width base character returns a joined two-column property value; xterm's print path supports width-growing joins natively

Invariant:

- Every width other than `<single-width base> U+FE0F` is identical to the plain Unicode 11 addon.
- U+FE0F after an already-wide cell keeps two columns, a lone U+FE0F stays zero width, and repeated U+FE0F does not widen further.

Validation:

1. Run `npm run check:unicode` from `RuntimeWeb/`; it asserts the tmux 3.6 ground-truth battery, the VS16 rules, and the unchanged baseline widths.
2. On a device, print `⏺️ ✳️ ❤️` followed by `ESC[6n` inside tmux and directly in SwiftTerminal; both must report the same cursor column.
3. Scroll a tmux pane whose content contains emoji-presentation sequences; leading columns must stay clean without resizing.

Upgrade check:

- Re-run the inside/outside tmux probe after tmux or xterm.js upgrades; tmux's width model is the reference this layer must agree with.
- If tmux narrows the rule (for example only for emoji-capable bases), scope the provider rule to match.

## Terminal Option Invariants

- `convertEol` must stay disabled (the default). A PTY stream uses a bare LF as "index down, keep the column" — terminfo advertises `cud1=\n` — and tmux's incremental redraws position the cursor at a mid-line column and then emit LF expecting the column to survive. With `convertEol: true`, every such LF resets the column to 1: redrawn lines shear left by their indent, and the next repaint's `CUP(row,3)` + `EL` leaves the sheared line's first character orphaned in columns 1-2. The failure was reproduced character-for-character by replaying a captured tmux byte stream (`script -qf` on the remote) into a terminal with `convertEol: true`, and disappears with the default. Full repaints (resize, `refresh-client`) mask the bug because they use absolute positioning with complete line text.

## Related xterm.js Addons

SwiftTerminal also loads xterm.js addons for Unicode width, search, clipboard, and web links. These are normal xterm.js extension points.

- The Unicode 11 tables from `@xterm/addon-unicode11` are active through the Compatibility Layer 6 wrapper, so wide Emoji and CJK width accounting match modern terminal behavior.
- Search and web-link behavior are exposed through SwiftTerminal's public session and runtime UI.
- Clipboard behavior is bridged to the host app through typed runtime events.

Changes to these addons should follow the same rebuild and manual validation process described in [Runtime and Build Notes](runtime.md).
