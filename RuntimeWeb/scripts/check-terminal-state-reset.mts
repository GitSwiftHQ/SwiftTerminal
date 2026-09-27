import xtermPackage from '@xterm/xterm'
import {
  sessionBoundaryCursorSequence,
  TERMINAL_STATE_RESET_SEQUENCE,
} from '../src/terminalStateReset.js'

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

// Every line from the top of the scrollback, independent of where the
// viewport is scrolled.
function bufferLines(terminal: HeadlessTerminal): string[] {
  const buffer = terminal.buffer.active
  return Array.from(
    { length: buffer.length },
    (_, row) => buffer.getLine(row)?.translateToString(true).trimEnd() ?? '',
  )
}

function lineIndex(lines: string[], text: string, label: string): number {
  const index = lines.indexOf(text)
  if (index < 0) {
    throw new Error(`${label}: missing line ${JSON.stringify(text)}`)
  }
  return index
}

// Mirrors the runtime's `reset_terminal_state` handler: the reset, then the
// cursor move computed from the buffer the reset left behind.
async function writeSessionBoundary(terminal: HeadlessTerminal): Promise<void> {
  await write(terminal, TERMINAL_STATE_RESET_SEQUENCE)
  const cursorSequence = sessionBoundaryCursorSequence(terminal.buffer.active, terminal.rows)
  await write(terminal, cursorSequence)
}

// The new session then writes its first output.
async function attachNewSession(terminal: HeadlessTerminal): Promise<void> {
  await writeSessionBoundary(terminal)
  await write(terminal, 'new session\r\n$')
}

function assertNewSessionFollows(
  terminal: HeadlessTerminal,
  previousLastLine: string,
  label: string,
): void {
  const lines = bufferLines(terminal)
  const previousIndex = lines.lastIndexOf(previousLastLine)
  if (previousIndex < 0) {
    throw new Error(`${label}: previous output ${JSON.stringify(previousLastLine)} was overwritten`)
  }
  assertEqual(lines[previousIndex + 1], 'new session', `${label}: new session starts on the next line`)
  assertEqual(lines[previousIndex + 2], '$', `${label}: new prompt follows`)
}

// A plain shell that has scrolled, cursor on the empty line after its output:
// the cursor stays, and the new session continues below the old lines.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 30))
  const cursorY = terminal.buffer.active.cursorY
  const scrollbackLength = terminal.buffer.active.length

  await writeSessionBoundary(terminal)
  assertEqual(terminal.buffer.active.type, 'normal', 'scrolled shell stays on the normal screen')
  assertEqual(terminal.buffer.active.cursorX, 0, 'scrolled shell keeps the cursor column')
  assertEqual(terminal.buffer.active.cursorY, cursorY, 'scrolled shell keeps the cursor row')
  assertEqual(terminal.buffer.active.length, scrollbackLength, 'scrolled shell keeps its scrollback')

  await write(terminal, 'new session\r\n$')
  const lines = bufferLines(terminal)
  for (let line = 1; line <= 30; line += 1) {
    assertEqual(lines[line - 1], `old line ${line}`, `scrolled shell keeps old line ${line}`)
  }
  assertNewSessionFollows(terminal, 'old line 30', 'scrolled shell')
}

// A plain shell that has not filled the viewport yet.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 3))
  await attachNewSession(terminal)
  const lines = bufferLines(terminal)
  assertEqual(lines[0], 'old line 1', 'short shell keeps the first old line')
  assertNewSessionFollows(terminal, 'old line 3', 'short shell')
  assertEqual(terminal.buffer.active.cursorY, 4, 'short shell leaves the cursor on the new prompt')
}

// A shell idling at its prompt: the new session must not continue on the
// prompt line.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 3) + 'user@host:~$ ')
  await attachNewSession(terminal)
  assertNewSessionFollows(terminal, 'user@host:~$', 'idle prompt')
}

// An empty terminal, as on the first connection: nothing moves.
{
  const terminal = makeTerminal()
  await writeSessionBoundary(terminal)
  assertEqual(terminal.buffer.active.cursorX, 0, 'empty terminal keeps the cursor column')
  assertEqual(terminal.buffer.active.cursorY, 0, 'empty terminal keeps the cursor row')
  await write(terminal, 'new session\r\n$')
  assertEqual(bufferLines(terminal)[0], 'new session', 'empty terminal starts at the top')
}

// Reconnecting twice: the DECSTR of the first reset must not become the
// cursor position the second reset restores.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 3))
  await attachNewSession(terminal)
  await write(terminal, '\r\n' + numberedLines('second line', 12))
  const cursorY = terminal.buffer.active.cursorY
  await writeSessionBoundary(terminal)
  assertEqual(terminal.buffer.active.cursorY, cursorY, 'second reset keeps the cursor row')
  assertEqual(terminal.buffer.active.cursorX, 0, 'second reset keeps the cursor column')
  await write(terminal, 'new session\r\n$')
  assertNewSessionFollows(terminal, 'second line 12', 'second reset')
}

// A full-screen program on the alternate screen: the reset returns to the
// normal screen and to the line the program was started from.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 3) + '$ vim')
  await write(terminal, '\x1b[?1049h\x1b[2J\x1b[H' + numberedLines('full screen', ROWS - 1) + '\x1b[8;12H')
  assertEqual(terminal.buffer.active.type, 'alternate', 'full-screen program uses the alternate screen')

  await attachNewSession(terminal)
  assertEqual(terminal.buffer.active.type, 'normal', 'reset leaves the alternate screen')
  const lines = bufferLines(terminal)
  assertEqual(lines[2], 'old line 3', 'alternate screen keeps the normal screen lines')
  assertEqual(lines.includes('full screen 1'), false, 'alternate screen content is gone')
  assertNewSessionFollows(terminal, '$ vim', 'alternate screen')
}

// A program that draws on the normal screen, such as procps `top`, with the
// cursor parked above the rows it drew last and an inverse status line made
// of spaces at the bottom.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 12) + '$ top\r\n')
  let frame = '\x1b[H\x1b[2J'
  for (let row = 1; row <= ROWS - 2; row += 1) {
    frame += `\x1b[${row};1Hframe row ${row}`
  }
  frame += `\x1b[${ROWS};1H\x1b[7m${' '.repeat(COLUMNS - 1)}\x1b[m`
  frame += '\x1b[5;20H'
  await write(terminal, frame)

  await attachNewSession(terminal)
  const lines = bufferLines(terminal)
  const lastFrameRow = lineIndex(lines, `frame row ${ROWS - 2}`, 'normal-screen program')
  for (let row = 1; row <= ROWS - 2; row += 1) {
    assertEqual(
      lines[lastFrameRow - (ROWS - 2 - row)],
      `frame row ${row}`,
      `normal-screen program keeps frame row ${row}`,
    )
  }
  // Row ROWS - 1 stays blank; the status line is the last row of the frame.
  const statusLine = terminal.buffer.active.getLine(lastFrameRow + 2)
  assertEqual(statusLine?.getCell(0)?.isInverse() !== 0, true, 'normal-screen program keeps its status line')
  assertEqual(lines[lastFrameRow + 3], 'new session', 'normal-screen program: new session starts below the status line')
  assertEqual(lines[lastFrameRow + 4], '$', 'normal-screen program: new prompt follows')
}

// The user has scrolled back through the history: rows are measured from the
// bottom of the buffer, not from the scrolled viewport.
{
  const terminal = makeTerminal()
  await write(terminal, numberedLines('old line', 30) + 'user@host:~$ ')
  terminal.scrollToTop()
  assertEqual(terminal.buffer.active.viewportY, 0, 'viewport is scrolled to the top')
  await attachNewSession(terminal)
  assertNewSessionFollows(terminal, 'user@host:~$', 'scrolled-back viewport')
}

// Mode state from the previous session is cleared.
{
  const terminal = makeTerminal()
  await write(terminal, '\x1b[?1000h\x1b[?1006h\x1b[?6h\x1b[3;6r\x1b[?25l')
  assertEqual(terminal.modes.mouseTrackingMode, 'vt200', 'previous session enables mouse tracking')
  assertEqual(terminal.modes.originMode, true, 'previous session enables origin mode')

  await writeSessionBoundary(terminal)
  assertEqual(terminal.modes.mouseTrackingMode, 'none', 'reset disables mouse tracking')
  assertEqual(terminal.modes.originMode, false, 'reset disables origin mode')
  await write(terminal, '\x1b[20;1H')
  assertEqual(terminal.buffer.active.cursorY, ROWS - 1, 'reset clears the scroll region')
}

console.log('Terminal state reset checks passed')
