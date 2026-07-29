import { Unicode11Addon } from '@xterm/addon-unicode11'
import type { IUnicodeVersionProvider, Terminal } from '@xterm/xterm'

const EMOJI_VARIATION_SELECTOR_16 = 0xfe0f

// Mirrors the packed layout xterm's UnicodeService uses for charProperties
// values: bit 0 shouldJoin, bits 1-2 width, remaining bits provider state.
function extractWidth(properties: number): number {
  return (properties >> 1) & 0x3
}

const JOINED_WIDE_PROPERTIES = (2 << 1) | 1

/**
 * The Unicode 11 tables measure emoji-presentation sequences such as
 * U+2733 U+FE0F per codepoint, so the variation selector contributes zero
 * columns and the sequence stays one column wide. tmux 3.4+, iTerm2, and
 * kitty measure the same sequence two columns wide. When SwiftTerminal
 * disagrees with tmux about a width, every incremental tmux redraw after
 * the sequence lands one column off and leaves stale cells behind.
 *
 * This provider keeps the Unicode 11 tables for everything else and adds
 * the single modern rule: U+FE0F joining a single-width base character
 * upgrades the joined cell to two columns.
 */
export function createUnicode11WithEmojiVariationProvider(): IUnicodeVersionProvider {
  let unicode11: IUnicodeVersionProvider | undefined
  const registrationCaptor = {
    unicode: {
      register(provider: IUnicodeVersionProvider): void {
        unicode11 = provider
      },
    },
  }
  new Unicode11Addon().activate(registrationCaptor as unknown as Terminal)
  if (!unicode11) {
    throw new Error('Unicode11Addon did not register a version provider')
  }
  const base = unicode11

  return {
    version: '11-emoji-variation',
    wcwidth: (codepoint) => base.wcwidth(codepoint),
    charProperties(codepoint, preceding) {
      if (
        codepoint === EMOJI_VARIATION_SELECTOR_16 &&
        extractWidth(preceding) === 1
      ) {
        return JOINED_WIDE_PROPERTIES
      }
      return base.charProperties(codepoint, preceding)
    },
  }
}
