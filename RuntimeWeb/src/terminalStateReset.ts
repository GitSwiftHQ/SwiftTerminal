/**
 * Written by `reset_terminal_state` before a host attaches a new remote
 * session to a terminal that still shows the previous session's output.
 *
 * The reset clears modes only. It leaves the screen, the scrollback, and the
 * cursor position alone, so the new session's first output continues on the
 * line the previous session ended on.
 *
 * Leaving the alternate screen: `CSI ? 1049 l` restores the cursor saved by
 * `CSI ? 1049 h`, and xterm.js performs that restore even when the normal
 * screen is already active. Sent on its own after a plain shell, it moves the
 * cursor to the saved position, which defaults to the top-left corner of the
 * viewport, and the new session then prints over the old lines. Entering the
 * alternate screen first makes the pair correct in both states: from the
 * normal screen, `?1049h` saves the current cursor and `?1049l` restores that
 * same position; from the alternate screen, `?1049h` is ignored and `?1049l`
 * restores the cursor the full-screen program saved when it started.
 *
 * DECSTR (`CSI ! p`) follows so the scroll region and saved cursor it resets
 * belong to the normal screen. DECSTR does not touch mouse tracking, which
 * xterm.js keeps in CoreMouseService and only a full terminal reset clears,
 * so every tracking and encoding mode is disabled explicitly. A dead remote
 * session that enabled mouse reporting would otherwise keep sending SGR mouse
 * sequences into the next shell.
 *
 * `scripts/check-terminal-state-reset.mts` runs these cases against the
 * bundled xterm.js; rerun it after upgrading `@xterm/xterm`.
 */
export const TERMINAL_STATE_RESET_SEQUENCE =
  '\x1b[?1049h\x1b[?1049l' +
  '\x1b[!p' +
  '\x1b[?9l\x1b[?1000l\x1b[?1001l\x1b[?1002l\x1b[?1003l' +
  '\x1b[?1005l\x1b[?1006l\x1b[?1015l\x1b[?1016l'
