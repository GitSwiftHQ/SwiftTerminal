import xtermPackage from '@xterm/xterm'
import { createUnicode11WithEmojiVariationProvider } from '../src/emojiVariationWidthProvider.js'

const { Terminal } = xtermPackage

type TerminalWithUnicodeCore = InstanceType<typeof Terminal> & {
  _core: {
    unicodeService: {
      getStringCellWidth(value: string): number
    }
  }
}

function assertEqual<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

function stringCellWidth(terminal: InstanceType<typeof Terminal>, value: string): number {
  return (terminal as TerminalWithUnicodeCore)._core.unicodeService.getStringCellWidth(value)
}

const terminal = new Terminal({ allowProposedApi: true })
terminal.unicode.register(createUnicode11WithEmojiVariationProvider())
terminal.unicode.activeVersion = '11-emoji-variation'

assertEqual(terminal.unicode.activeVersion, '11-emoji-variation', 'active Unicode version')

// Baseline Unicode 11 behavior must stay identical.
assertEqual(stringCellWidth(terminal, '🟢'), 2, 'green circle emoji width')
assertEqual(stringCellWidth(terminal, '🟢1'), 3, 'emoji followed by ASCII width')
assertEqual(stringCellWidth(terminal, '😀'), 2, 'smiling emoji width')
assertEqual(stringCellWidth(terminal, '中'), 2, 'CJK width')

// Narrow symbols measured against tmux 3.6 cursor-position ground truth.
for (const narrow of ['⏺', '✻', '✽', '✳', '●', '←', '—', '─', '│', '▸', '❯', '…']) {
  assertEqual(stringCellWidth(terminal, narrow), 1, `narrow symbol ${narrow} width`)
}
for (const wide of ['你', '，', '。']) {
  assertEqual(stringCellWidth(terminal, wide), 2, `wide CJK ${wide} width`)
}

// Emoji-presentation sequences (base + U+FE0F) are two columns, matching
// tmux 3.4+, iTerm2, and kitty.
assertEqual(stringCellWidth(terminal, '⏺️'), 2, 'record button emoji presentation width')
assertEqual(stringCellWidth(terminal, '✳️'), 2, 'eight-spoked asterisk emoji presentation width')
assertEqual(stringCellWidth(terminal, '❤️'), 2, 'red heart emoji presentation width')
assertEqual(stringCellWidth(terminal, '⏺️1'), 3, 'emoji presentation followed by ASCII width')
assertEqual(stringCellWidth(terminal, 'a️b'), 3, 'VS16 on ASCII base joins into a wide cell')

// VS16 must not stack on top of already-wide bases or stand alone.
assertEqual(stringCellWidth(terminal, '中️'), 2, 'VS16 after wide CJK keeps two columns')
assertEqual(stringCellWidth(terminal, '👍️'), 2, 'VS16 after wide emoji keeps two columns')
assertEqual(stringCellWidth(terminal, '️'), 0, 'lone VS16 stays zero width')
assertEqual(stringCellWidth(terminal, '⏺️️'), 2, 'doubled VS16 stays two columns')

// Emoji-presentation-by-default and combining behavior, per the same probe.
assertEqual(stringCellWidth(terminal, '👍'), 2, 'thumbs up width')
assertEqual(stringCellWidth(terminal, '🚀'), 2, 'rocket width')
assertEqual(stringCellWidth(terminal, '🇨🇳'), 2, 'regional indicator flag width')
assertEqual(stringCellWidth(terminal, 'é'), 1, 'combining acute width')

console.log('Unicode width checks passed')
