import unicode11Package from '@xterm/addon-unicode11'
import xtermPackage from '@xterm/xterm'

const { Unicode11Addon } = unicode11Package
const { Terminal } = xtermPackage

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${expected}, got ${actual}`)
  }
}

function stringCellWidth(terminal, value) {
  return terminal._core.unicodeService.getStringCellWidth(value)
}

const terminal = new Terminal({ allowProposedApi: true })
terminal.loadAddon(new Unicode11Addon())
terminal.unicode.activeVersion = '11'

assertEqual(terminal.unicode.activeVersion, '11', 'active Unicode version')
assertEqual(stringCellWidth(terminal, '🟢'), 2, 'green circle emoji width')
assertEqual(stringCellWidth(terminal, '🟢1'), 3, 'emoji followed by ASCII width')
assertEqual(stringCellWidth(terminal, '😀'), 2, 'smiling emoji width')
assertEqual(stringCellWidth(terminal, '中'), 2, 'CJK width')

console.log('Unicode width checks passed')
