// Encodes host key presses the way xterm does, and applies the host's sticky
// modifiers to typed input. Pure functions only: no DOM, no xterm imports, so
// scripts/check-key-encoder.mts can exercise every rule under Node.

export type TerminalKeyName =
  | 'escape'
  | 'tab'
  | 'enter'
  | 'backspace'
  | 'delete'
  | 'insert'
  | 'up'
  | 'down'
  | 'left'
  | 'right'
  | 'home'
  | 'end'
  | 'page_up'
  | 'page_down'
  | 'f1'
  | 'f2'
  | 'f3'
  | 'f4'
  | 'f5'
  | 'f6'
  | 'f7'
  | 'f8'
  | 'f9'
  | 'f10'
  | 'f11'
  | 'f12'
  | 'character'

export type KeyModifierName = 'ctrl' | 'alt' | 'shift' | 'meta'

export type KeyModifierFlags = {
  ctrl: boolean
  alt: boolean
  shift: boolean
  meta: boolean
}

export type StickyKeyModifierState = 'off' | 'one_shot' | 'sustained'

export type StickyKeyModifierStates = Record<KeyModifierName, StickyKeyModifierState>

export type KeyEncodingInput = {
  key: string
  text?: string
  modifiers: KeyModifierFlags
  applicationCursorKeys: boolean
}

const ESC = '\u001b'
const CSI = `${ESC}[`
const SS3 = `${ESC}O`

export const NO_KEY_MODIFIERS: KeyModifierFlags = {
  ctrl: false,
  alt: false,
  shift: false,
  meta: false,
}

export const STICKY_KEY_MODIFIERS_OFF: StickyKeyModifierStates = {
  ctrl: 'off',
  alt: 'off',
  shift: 'off',
  meta: 'off',
}

const KEY_MODIFIER_NAMES: readonly KeyModifierName[] = ['ctrl', 'alt', 'shift', 'meta']

// Cursor and editing keys whose final byte follows CSI (normal mode) or SS3
// (DECCKM application mode); with modifiers they become CSI 1 ; m <final>.
const CURSOR_KEY_FINALS: Readonly<Record<string, string>> = {
  up: 'A',
  down: 'B',
  right: 'C',
  left: 'D',
  home: 'H',
  end: 'F',
}

// Keys sent as CSI <number> ~, or CSI <number> ; m ~ with modifiers.
const TILDE_KEY_NUMBERS: Readonly<Record<string, number>> = {
  insert: 2,
  delete: 3,
  page_up: 5,
  page_down: 6,
  f5: 15,
  f6: 17,
  f7: 18,
  f8: 19,
  f9: 20,
  f10: 21,
  f11: 23,
  f12: 24,
}

// F1 through F4 are SS3 P..S, or CSI 1 ; m P..S with modifiers.
const SS3_FUNCTION_FINALS: Readonly<Record<string, string>> = {
  f1: 'P',
  f2: 'Q',
  f3: 'R',
  f4: 'S',
}

// Control characters for Ctrl plus a non-letter, following xterm's C0 rules.
const CONTROL_CHARACTERS: Readonly<Record<string, string>> = {
  '@': '\u0000',
  '2': '\u0000',
  ' ': '\u0000',
  '[': '\u001b',
  '3': '\u001b',
  '\\': '\u001c',
  '4': '\u001c',
  ']': '\u001d',
  '5': '\u001d',
  '^': '\u001e',
  '6': '\u001e',
  _: '\u001f',
  '7': '\u001f',
  '/': '\u001f',
  '?': '\u007f',
  '8': '\u007f',
}

/** The xterm modifier parameter: 1 + Shift(1) + Alt(2) + Ctrl(4) + Meta(8). */
export function modifierParameter(modifiers: KeyModifierFlags): number {
  return (
    1 +
    (modifiers.shift ? 1 : 0) +
    (modifiers.alt ? 2 : 0) +
    (modifiers.ctrl ? 4 : 0) +
    (modifiers.meta ? 8 : 0)
  )
}

/** The control character for Ctrl plus `character`, or undefined when Ctrl leaves it unchanged. */
export function controlCharacter(character: string): string | undefined {
  if (character.length !== 1) {
    return undefined
  }

  const code = character.charCodeAt(0)
  const isLetter =
    (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a)
  if (isLetter) {
    return String.fromCharCode(code & 0x1f)
  }

  return CONTROL_CHARACTERS[character]
}

/**
 * Encodes a key the way xterm sends it for the current cursor-key mode.
 * Returns undefined for a key it does not know or an empty character.
 */
export function encodeKey(input: KeyEncodingInput): string | undefined {
  const { key, modifiers } = input
  const parameter = modifierParameter(modifiers)
  const hasModifiers = parameter > 1
  const escapePrefix = modifiers.alt || modifiers.meta ? ESC : ''

  const cursorFinal = CURSOR_KEY_FINALS[key]
  if (cursorFinal !== undefined) {
    if (hasModifiers) {
      return `${CSI}1;${parameter}${cursorFinal}`
    }
    return `${input.applicationCursorKeys ? SS3 : CSI}${cursorFinal}`
  }

  const tildeNumber = TILDE_KEY_NUMBERS[key]
  if (tildeNumber !== undefined) {
    return hasModifiers
      ? `${CSI}${tildeNumber};${parameter}~`
      : `${CSI}${tildeNumber}~`
  }

  const functionFinal = SS3_FUNCTION_FINALS[key]
  if (functionFinal !== undefined) {
    return hasModifiers
      ? `${CSI}1;${parameter}${functionFinal}`
      : `${SS3}${functionFinal}`
  }

  switch (key) {
    case 'escape':
      return `${escapePrefix}${ESC}`
    case 'tab':
      // Shift+Tab is back-tab (CBT). Ctrl has no Tab encoding in xterm, so
      // Ctrl+Tab stays a plain Tab; Alt adds the escape prefix.
      return modifiers.shift ? `${escapePrefix}${CSI}Z` : `${escapePrefix}\t`
    case 'enter':
      return `${escapePrefix}\r`
    case 'backspace':
      return `${escapePrefix}${modifiers.ctrl ? '\b' : '\u007f'}`
    case 'character':
      return encodeCharacterText(input.text ?? '', modifiers)
    default:
      return undefined
  }
}

function encodeCharacterText(
  text: string,
  modifiers: KeyModifierFlags,
): string | undefined {
  if (text.length === 0) {
    return undefined
  }

  const escapePrefix = modifiers.alt || modifiers.meta ? ESC : ''
  if (Array.from(text).length !== 1) {
    return `${escapePrefix}${text}`
  }

  let character = text
  if (modifiers.shift && /^[a-z]$/.test(character)) {
    character = character.toUpperCase()
  }
  if (modifiers.ctrl) {
    character = controlCharacter(character) ?? character
  }
  return `${escapePrefix}${character}`
}

export function mergeKeyModifiers(
  first: KeyModifierFlags,
  second: KeyModifierFlags,
): KeyModifierFlags {
  return {
    ctrl: first.ctrl || second.ctrl,
    alt: first.alt || second.alt,
    shift: first.shift || second.shift,
    meta: first.meta || second.meta,
  }
}

/** Reads the bridge's modifier list, ignoring names it does not know. */
export function keyModifiersFromNames(names: unknown): KeyModifierFlags {
  const list = Array.isArray(names) ? names : []
  return {
    ctrl: list.includes('ctrl'),
    alt: list.includes('alt'),
    shift: list.includes('shift'),
    meta: list.includes('meta'),
  }
}

/** Reads the bridge's sticky state, treating anything missing or unknown as off. */
export function normalizedStickyKeyModifierStates(
  value: unknown,
): StickyKeyModifierStates {
  const record =
    typeof value === 'object' && value !== null
      ? (value as Record<string, unknown>)
      : {}
  const states = { ...STICKY_KEY_MODIFIERS_OFF }
  for (const name of KEY_MODIFIER_NAMES) {
    const state = record[name]
    if (state === 'one_shot' || state === 'sustained') {
      states[name] = state
    }
  }
  return states
}

/**
 * Whether sticky modifiers may change typed data: exactly one printable ASCII
 * character (0x20-0x7E). Pasted text, IME commits, multi-character sequences,
 * and non-ASCII text pass through unchanged.
 */
export function isStickyModifierTarget(data: string): boolean {
  if (data.length !== 1) {
    return false
  }

  const code = data.charCodeAt(0)
  return code >= 0x20 && code <= 0x7e
}

/** Where typed input came from, which decides whether sticky modifiers apply. */
export type TypedInputOrigin =
  | 'keyboard'
  | 'paste'
  | 'composition'
  | 'host-key'

export type TypedInputResolution = {
  text: string
  didConsumeOneShot: boolean
}

/**
 * The host's sticky modifier state. The runtime owns it so that keys sent by
 * the host and characters typed on the system or hardware keyboard are
 * modified in one place.
 */
export class StickyKeyModifiers {
  private states: StickyKeyModifierStates = { ...STICKY_KEY_MODIFIERS_OFF }

  current(): StickyKeyModifierStates {
    return { ...this.states }
  }

  set(states: StickyKeyModifierStates): void {
    this.states = { ...states }
  }

  activeFlags(): KeyModifierFlags {
    return {
      ctrl: this.states.ctrl !== 'off',
      alt: this.states.alt !== 'off',
      shift: this.states.shift !== 'off',
      meta: this.states.meta !== 'off',
    }
  }

  hasActiveModifier(): boolean {
    return KEY_MODIFIER_NAMES.some((name) => this.states[name] !== 'off')
  }

  /** Turns every one-shot modifier off. Returns whether anything changed. */
  consumeOneShot(): boolean {
    let didChange = false
    for (const name of KEY_MODIFIER_NAMES) {
      if (this.states[name] === 'one_shot') {
        this.states[name] = 'off'
        didChange = true
      }
    }
    return didChange
  }

  /**
   * Applies the sticky modifiers to typed data when it is a single printable
   * ASCII character from the keyboard, consuming one-shot modifiers.
   */
  resolveTypedInput(
    data: string,
    origin: TypedInputOrigin,
  ): TypedInputResolution {
    if (
      origin !== 'keyboard' ||
      !this.hasActiveModifier() ||
      !isStickyModifierTarget(data)
    ) {
      return { text: data, didConsumeOneShot: false }
    }

    const text =
      encodeKey({
        key: 'character',
        text: data,
        modifiers: this.activeFlags(),
        applicationCursorKeys: false,
      }) ?? data
    return { text, didConsumeOneShot: this.consumeOneShot() }
  }

  /**
   * Encodes a host key with its own modifiers merged with the sticky ones,
   * consuming one-shot modifiers when the key is sent.
   */
  resolveHostKey(
    input: KeyEncodingInput,
  ): { sequence: string | undefined; didConsumeOneShot: boolean } {
    const sequence = encodeKey({
      ...input,
      modifiers: mergeKeyModifiers(input.modifiers, this.activeFlags()),
    })
    if (sequence === undefined) {
      return { sequence, didConsumeOneShot: false }
    }
    return { sequence, didConsumeOneShot: this.consumeOneShot() }
  }
}
