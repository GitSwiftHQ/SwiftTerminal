import xtermPackage from '@xterm/xterm'
import { TERMINAL_STATE_RESET_SEQUENCE } from '../src/terminalStateReset.js'

const { Terminal } = xtermPackage

type HeadlessTerminal = InstanceType<typeof Terminal>

const ROWS = 10
const COLUMNS = 40

function assertEqual<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

function makeTerminal(): HeadlessTerminal {
  return new Terminal({ rows: ROWS, cols: COLUMNS, allowProposedApi: true })
}

function write(terminal: HeadlessTerminal, data: string): Promise<void> {
  return new Promise((resolve) => terminal.write(data, resolve))
}

function numberedLines(prefix: string, count: number): string {
  return Array.from({ length: count }, (_, index) => `${prefix} ${index + 1}\r\n`).join('')
}

function viewportLine(terminal: HeadlessTerminal, row: number): string {
  const buffer = terminal.buffer.active
  return buffer.getLine(buffer.viewportY + row)?.translateToString(true) ?? ''
}

function viewportLines(terminal: HeadlessTerminal): string[] {
  return Array.from({ length: ROWS }, (_, row) => viewportLine(terminal, row))
}

// The runtime writes the reset, then the new session writes its first output.
async function attachNewSession(terminal: HeadlessTerminal): Promise<void> {
  await write(terminal, TERMINAL_STATE_RESET_SEQUENCE)
  await write(terminal, 'new session\r\n$')
}

// A plain shell that has scrolled: the new session must continue on the
// cursor line instead of jumping to the top of the viewport.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 30))
  const before = viewportLines(terminal)
  const cursorY = terminal.buffer.active.cursorY
  const scrollbackLength = terminal.buffer.active.length

  await write(terminal, TERMINAL_STATE_RESET_SEQUENCE)
  assertEqual(terminal.buffer.active.type, 'normal', 'scrolled shell stays on the normal screen')
  assertEqual(terminal.buffer.active.cursorX, 0, 'scrolled shell keeps the cursor column')
  assertEqual(terminal.buffer.active.cursorY, cursorY, 'scrolled shell keeps the cursor row')
  assertEqual(terminal.buffer.active.length, scrollbackLength, 'scrolled shell keeps its scrollback')

  await write(terminal, 'new session\r\n$')
  const after = viewportLines(terminal)
  // The new output pushed the old lines up by one row; none were overwritten.
  for (let row = 0; row < ROWS - 2; row += 1) {
    assertEqual(after[row], before[row + 1], `scrolled shell keeps old viewport row ${row + 1}`)
  }
  assertEqual(after[ROWS - 2], 'new session', 'scrolled shell prints the new session after the old lines')
  assertEqual(after[ROWS - 1], '$', 'scrolled shell puts the new prompt last')
}

// A plain shell that has not filled the viewport yet.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 3))
  await attachNewSession(terminal)
  const lines = viewportLines(terminal)
  assertEqual(lines[0], 'old line 1', 'short shell keeps the first old line')
  assertEqual(lines[2], 'old line 3', 'short shell keeps the last old line')
  assertEqual(lines[3], 'new session', 'short shell prints the new session below the old lines')
  assertEqual(terminal.buffer.active.cursorY, 4, 'short shell leaves the cursor on the new prompt')
}

// Reconnecting twice: the DECSTR of the first reset must not become the
// cursor position the second reset restores.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 3))
  await attachNewSession(terminal)
  await write(terminal, numberedLines('second line', 12))
  const cursorY = terminal.buffer.active.cursorY
  await write(terminal, TERMINAL_STATE_RESET_SEQUENCE)
  assertEqual(terminal.buffer.active.cursorY, cursorY, 'second reset keeps the cursor row')
  assertEqual(terminal.buffer.active.cursorX, 0, 'second reset keeps the cursor column')
}

// A full-screen program on the alternate screen: the reset returns to the
// normal screen and to the cursor the program saved when it started.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 3) + '$ top')
  await write(terminal, '\x1b[?1049h\x1b[2J\x1b[H' + numberedLines('full screen', ROWS - 1) + '\x1b[8;12H')
  assertEqual(terminal.buffer.active.type, 'alternate', 'full-screen program uses the alternate screen')

  await attachNewSession(terminal)
  assertEqual(terminal.buffer.active.type, 'normal', 'reset leaves the alternate screen')
  const lines = viewportLines(terminal)
  assertEqual(lines[2], 'old line 3', 'alternate screen keeps the normal screen lines')
  assertEqual(lines[3], '$ topnew session', 'alternate screen resumes at the cursor saved on entry')
  assertEqual(lines[4], '$', 'alternate screen puts the new prompt below')
}

// Mode state from the previous session is cleared.
{
  const terminal = makeTerminal()
  await write(terminal, '\x1b[?1000h\x1b[?1006h\x1b[?6h\x1b[3;6r\x1b[?25l')
  assertEqual(terminal.modes.mouseTrackingMode, 'vt200', 'previous session enables mouse tracking')
  assertEqual(terminal.modes.originMode, true, 'previous session enables origin mode')

  await write(terminal, TERMINAL_STATE_RESET_SEQUENCE)
  assertEqual(terminal.modes.mouseTrackingMode, 'none', 'reset disables mouse tracking')
  assertEqual(terminal.modes.originMode, false, 'reset disables origin mode')
  await write(terminal, '\x1b[20;1H')
  assertEqual(terminal.buffer.active.cursorY, ROWS - 1, 'reset clears the scroll region')
}

console.log('Terminal state reset checks passed')
