# Keyboard Focus

A terminal is only useful while key presses reach it. On both platforms the system decides where a key press goes, and on macOS 27 and iPadOS 27 that decision can leave the terminal out even though it looks focused. This guide explains what changed on each platform, the invariant a host should keep, how `takeKeyboardFocus()` and `holdsKeyboardFocus` work, when to call them, what the package deliberately leaves alone, and how to verify the result.

## The Invariant

While the terminal is the view the person types into, key presses reach it.

What "the view the person types into" means is the host's decision: the terminal the person selected, opened, or tapped. The package never takes the keyboard focus on its own. It gives the host a way to see where key presses would go and a way to hand them to the terminal, and it leaves the decision of when to do that to the host.

Keep the check condition driven. Look at where key presses would go and repair only when they would miss the terminal. Where the system already keeps the invariant, as macOS 26, iPadOS 26, and earlier versions do, the check then finds nothing to do, and it keeps finding nothing once the system behavior is fixed. A check keyed to a system version would have to be revisited for every release.

## macOS

### Where key presses go

AppKit delivers a key press to the window's first responder. Inside the terminal that is the web view; SwiftUI's own focus state does not move it.

### What macOS 27 changed

When a host moves SwiftUI's focus to a terminal, for example with `@FocusState` after a sidebar selection, SwiftUI reports the terminal focused but leaves the window's first responder on the key view placeholder it keeps for hosted content. The placeholder is a sibling of the terminal's view, not an ancestor, so key presses stop there and never reach the shell. A terminal created without a selection change, such as one opened from a menu, does get the first responder, which is why switching between terminals is the case that fails. A click inside the terminal fixes it.

### The API

- `takeKeyboardFocus()` makes the web view the window's first responder. A terminal that already holds it is left alone, and a terminal whose view is not in a window returns `false`.
- `holdsKeyboardFocus` is `true` while the web view is the window's first responder. On macOS that is exactly the question of where key presses go.
- `keyboardFocusWindow` is the window the terminal is in, for hosts that need a window to inspect when the application has no key window.

### When to call it

Call `takeKeyboardFocus()` while the host considers the terminal focused, after SwiftUI has finished the layout pass in which it assigns the responder. A run loop observer at the end of the pass works well. Check `holdsKeyboardFocus` first, leave the first responder alone when it is a text field or text view the person moved to, cap the number of attempts, and drop a pending request when the person clicks or types.

## iOS and iPadOS

### Where key presses go

Without a hardware keyboard, key presses come from the software keyboard and go to the first responder: in a terminal, WebKit's content view inside the web view.

With a hardware keyboard, iPadOS also runs a focus system. A hardware key press is first offered to the focus system's focused item and its responder chain, and only then to the first responder. When no item is focused, the first responder gets it directly.

### What iPadOS 27 changed

On iPadOS 27 a sidebar row stays the focused item in situations where earlier versions left no item focused. UIKit does move focus to a new first responder, but only when that responder, or something in its focus environment, can be focused. WebKit's content view cannot, so tapping the terminal makes the content view the first responder and leaves focus on the row. Return and the arrow keys then go to the sidebar, which can even change the selection; printable characters still arrive through the text input path, which makes the problem look partial.

Three ways into a terminal behave differently:

- **A. A new terminal selected by the host.** Starting a terminal from a context menu or a button inserts a sidebar row and selects it from code. Selecting a row asks the collection view to update focus, and its preferred focus is the selected row, so the new row becomes the focused item. Tapping the terminal afterwards does not move it.
- **B. Selecting another row.** When the person selects a different row, the terminal's view appears as a new focus environment, and the focus system defers focus to it: no item is focused, and key presses reach the terminal once it is tapped. This path works.
- **C. Tapping the selected row again.** The row becomes the focused item, nothing new appears, and tapping the terminal leaves the focus on the row.

### The API

- `keyboardFocusHostView` is the view that hosts the terminal. Read the focused item from its focus system with `UIFocusSystem.focusSystem(for: hostView)?.focusedItem` and check it with `hostView.contains(_:)`. A focused item outside the host means key presses will miss the terminal.
- `holdsKeyboardFocus` is `true` while the web content holds the first responder. This is where the platforms differ: on iOS it does not by itself mean key presses arrive, because a focused item outside the terminal still comes first. Combine it with the focused item check above.
- `takeKeyboardFocus()` hands the first responder to the web content through the host view. The host view is focusable, draws no focus effect, and accepts the first responder only for the length of the hand-off. The call makes the host the first responder, which UIKit follows by moving focus toward the host, and then gives the first responder to the web view, which passes it to WebKit's content view. Because the content view cannot be focused, UIKit then leaves no item focused, and key presses reach the shell. If the web content declines, the host gives the responder up again rather than keep it. A terminal whose web content already holds the first responder with nothing outside it focused is left alone, and a terminal whose view is not in a window returns `false`.

### When to call it

Repair, do not take over. Call `takeKeyboardFocus()` when the web content holds the first responder and the focused item is outside the terminal; leave every other state alone. In particular:

- Check after the events that can produce the broken state, and only after UIKit has applied the focus update they cause, for example at the end of the run loop pass:
  - the terminal's keyboard accessory entering a window (`isKeyboardAccessoryAttached` turning `true`), which follows the content view becoming the first responder and covers paths A and C;
  - the terminal appearing, and the host's own selection of the terminal, including selecting it again;
  - `UIFocusSystem.didUpdateNotification`, as a fallback for focus pulled back to a row without any first responder change.
- Cap the attempts for each request and stop, rather than trade the focus back and forth with the system.
- Only repair while a hardware keyboard is connected. Without one there is no focus system to repair, and taking the first responder shows the software keyboard.
- Give way to the host's own keyboard shortcuts. While the terminal holds the first responder it receives Return before a SwiftUI `.keyboardShortcut(.defaultAction)` elsewhere in the window. A host that shows a dialog over the terminal, such as one offering to reconnect, should not repair while the dialog is up, and can call `resignKeyboardFocus()` so the dialog's shortcut receives Return.

`UIScreen.focusedItem` is deprecated and raises an exception on iPadOS 27; use the focus system read above.

## What the Package Does Not Do

- It uses public API only. It does not swizzle or subclass WebKit's content view, does not name private classes, and does not make the content view focusable.
- It does not intercept key presses with `UIKeyCommand` or replay them into the terminal.
- It does not change whether other views, such as a sidebar, can be focused.
- It does not branch on the system version.
- It never takes the keyboard focus on its own. A host decides when the terminal should be typed into.

## Verifying Key Delivery

Check what the shell receives, not what the views report. A first responder that reads as the web view, or a terminal cursor drawn as focused, does not prove that key presses arrive.

1. Run a raw byte dump in the shell, for example:

   ```sh
   stty raw -echo; dd bs=1 count=6 2>/dev/null | od -An -tx1; stty sane
   ```

   Then press y, Return, Down, and Tab. The expected output is `79 0d 1b 5b 42 09`. Test Return and the arrow keys in particular: printable characters can arrive through the text input path even when Return does not.
2. Use real input. On macOS, use a real keyboard and mouse; synthetic clicks can follow a different event path and produce focus states a person never sees. On an iPad simulator, turn on the simulator's hardware keyboard connection before launching the app, and confirm the focus system is active, for example from the debugger with `po UIFocusDebugger.status()`. Key presses injected by automation tools only take the hardware key path once the simulator reports a hardware keyboard.
3. Cover every way into a terminal: on iPad the paths A, B, and C above, on macOS a sidebar switch and a menu-created terminal. Repeat the check after sidebar and window changes that do not change the selection, such as collapsing the sidebar or opening an inspector.
4. Run the same checks on the previous major system version, where the repair should never act, and without a hardware keyboard, where tapping the terminal shows the software keyboard as before.
