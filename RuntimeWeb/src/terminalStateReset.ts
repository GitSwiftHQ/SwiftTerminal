import type { IBuffer, IBufferCell } from '@xterm/xterm'

/**
 * Written by `reset_terminal_state` before a host attaches a new remote
 * session to a terminal that still shows the previous session's output.
 *
 * The sequence clears modes only. It leaves the screen, the scrollback, and
 * the cursor position alone; `sessionBoundaryCursorSequence` then decides
 * where the new session starts.
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

/**
 * The cursor movement that starts a new session on a fresh line below the
 * previous session's output, or an empty string when the cursor already
 * starts one.
 *
 * A session can end with the cursor anywhere. A shell idling at its prompt
 * leaves it after the prompt, and a program that draws on the normal screen,
 * such as `top` or an inline TUI, leaves it wherever it last wrote, often
 * above lines it drew later. The new session would continue from that cell
 * and print over the old output, so the cursor moves to column one of the
 * line below the lowest row with content at or below the cursor. Rows above
 * the cursor are already behind it and do not count.
 *
 * Call it with the normal screen active, after `TERMINAL_STATE_RESET_SEQUENCE`
 * has been parsed: DECSTR has cleared origin mode and the scroll region, so
 * the cursor position is absolute and the line feed from the last row
 * scrolls the old output into the scrollback.
 */
export function sessionBoundaryCursorSequence(buffer: IBuffer, rows: number): string {
  const cell = buffer.getNullCell()
  let lastContentRow = -1
  for (let row = rows - 1; row >= buffer.cursorY; row -= 1) {
    if (rowHasContent(buffer, buffer.baseY + row, cell)) {
      lastContentRow = row
      break
    }
  }

  if (lastContentRow >= 0) {
    return `\x1b[${lastContentRow + 1};1H\r\n`
  }
  return buffer.cursorX > 0 ? '\r' : ''
}

// A blank cell still counts when it is painted, such as the space-filled
// inverse or colored status line a full-screen program draws.
function rowHasContent(buffer: IBuffer, absoluteRow: number, cell: IBufferCell): boolean {
  const line = buffer.getLine(absoluteRow)
  if (!line) {
    return false
  }
  for (let column = 0; column < line.length; column += 1) {
    if (!line.getCell(column, cell)) {
      continue
    }
    const chars = cell.getChars()
    if ((chars !== '' && chars !== ' ') || !cell.isBgDefault() || cell.isInverse() !== 0) {
      return true
    }
  }
  return false
}
