import {
  controlCharacter,
  encodeKey,
  isStickyModifierTarget,
  keyModifiersFromNames,
  modifierParameter,
  NO_KEY_MODIFIERS,
  normalizedStickyKeyModifierStates,
  StickyKeyModifiers,
  STICKY_KEY_MODIFIERS_OFF,
  type KeyModifierFlags,
} from '../src/keyEncoder.js'

const ESC = '\u001b'

function visible(text: string | undefined): string {
  if (text === undefined) {
    return '<undefined>'
  }
  return Array.from(text)
    .map((character) => {
      const code = character.codePointAt(0) ?? 0
      if (code === 0x1b) {
        return 'ESC'
      }
      if (code < 0x20 || code === 0x7f) {
        return `\\x${code.toString(16).padStart(2, '0')}`
      }
      return character
    })
    .join(' ')
}

function assertEqual(actual: string | undefined, expected: string | undefined, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${visible(expected)}, got ${visible(actual)}`)
  }
}

function assert(condition: boolean, label: string): void {
  if (!condition) {
    throw new Error(label)
  }
}

function mods(...names: Array<keyof KeyModifierFlags>): KeyModifierFlags {
  return keyModifiersFromNames(names)
}

function key(
  name: string,
  modifiers: KeyModifierFlags = NO_KEY_MODIFIERS,
  applicationCursorKeys = false,
  text?: string,
): string | undefined {
  return encodeKey({ key: name, text, modifiers, applicationCursorKeys })
}

function checkModifierParameter(): void {
  assert(modifierParameter(NO_KEY_MODIFIERS) === 1, 'no modifiers is 1')
  assert(modifierParameter(mods('shift')) === 2, 'shift is 2')
  assert(modifierParameter(mods('alt')) === 3, 'alt is 3')
  assert(modifierParameter(mods('ctrl')) === 5, 'ctrl is 5')
  assert(modifierParameter(mods('ctrl', 'shift')) === 6, 'ctrl+shift is 6')
  assert(modifierParameter(mods('meta')) === 9, 'meta is 9')
  assert(modifierParameter(mods('ctrl', 'alt', 'shift', 'meta')) === 16, 'all is 16')
}

function checkCursorKeys(): void {
  const finals: Array<[string, string]> = [
    ['up', 'A'],
    ['down', 'B'],
    ['right', 'C'],
    ['left', 'D'],
    ['home', 'H'],
    ['end', 'F'],
  ]
  for (const [name, final] of finals) {
    assertEqual(key(name), `${ESC}[${final}`, `${name} normal mode`)
    assertEqual(key(name, NO_KEY_MODIFIERS, true), `${ESC}O${final}`, `${name} application mode`)
    assertEqual(key(name, mods('ctrl')), `${ESC}[1;5${final}`, `ctrl+${name}`)
    assertEqual(key(name, mods('ctrl'), true), `${ESC}[1;5${final}`, `ctrl+${name} application mode`)
    assertEqual(key(name, mods('alt')), `${ESC}[1;3${final}`, `alt+${name} uses the parameter, not a prefix`)
    assertEqual(key(name, mods('shift')), `${ESC}[1;2${final}`, `shift+${name}`)
  }
}

function checkTildeKeys(): void {
  const numbers: Array<[string, number]> = [
    ['insert', 2],
    ['delete', 3],
    ['page_up', 5],
    ['page_down', 6],
    ['f5', 15],
    ['f6', 17],
    ['f7', 18],
    ['f8', 19],
    ['f9', 20],
    ['f10', 21],
    ['f11', 23],
    ['f12', 24],
  ]
  for (const [name, number] of numbers) {
    assertEqual(key(name), `${ESC}[${number}~`, name)
    assertEqual(key(name, NO_KEY_MODIFIERS, true), `${ESC}[${number}~`, `${name} ignores DECCKM`)
    assertEqual(key(name, mods('ctrl')), `${ESC}[${number};5~`, `ctrl+${name}`)
  }
  // terminal.input bypasses xterm's own Shift+PgUp scrollback handling, so the
  // shifted sequence reaches the shell.
  assertEqual(key('page_up', mods('shift')), `${ESC}[5;2~`, 'shift+page_up')
  assertEqual(key('page_down', mods('shift')), `${ESC}[6;2~`, 'shift+page_down')
}

function checkF1ToF4(): void {
  const finals: Array<[string, string]> = [
    ['f1', 'P'],
    ['f2', 'Q'],
    ['f3', 'R'],
    ['f4', 'S'],
  ]
  for (const [name, final] of finals) {
    assertEqual(key(name), `${ESC}O${final}`, name)
    assertEqual(key(name, NO_KEY_MODIFIERS, true), `${ESC}O${final}`, `${name} application mode`)
    assertEqual(key(name, mods('shift')), `${ESC}[1;2${final}`, `shift+${name}`)
    assertEqual(key(name, mods('ctrl')), `${ESC}[1;5${final}`, `ctrl+${name}`)
  }
  assertEqual(key('f13'), undefined, 'f13 is unknown')
}

function checkSimpleKeys(): void {
  assertEqual(key('tab'), '\t', 'tab')
  assertEqual(key('tab', mods('shift')), `${ESC}[Z`, 'shift+tab is CBT')
  assertEqual(key('tab', mods('ctrl')), '\t', 'ctrl+tab stays a tab')
  assertEqual(key('tab', mods('alt')), `${ESC}\t`, 'alt+tab')
  assertEqual(key('escape'), ESC, 'escape')
  assertEqual(key('escape', mods('alt')), `${ESC}${ESC}`, 'alt+escape')
  assertEqual(key('enter'), '\r', 'enter is CR')
  assertEqual(key('enter', mods('alt')), `${ESC}\r`, 'alt+enter')
  assertEqual(key('backspace'), '\u007f', 'backspace is DEL')
  assertEqual(key('backspace', mods('ctrl')), '\b', 'ctrl+backspace is BS')
  assertEqual(key('backspace', mods('alt')), `${ESC}\u007f`, 'alt+backspace')
  assertEqual(key('unknown'), undefined, 'unknown key')
}

function checkControlCharacters(): void {
  for (let code = 0x61; code <= 0x7a; code += 1) {
    const lower = String.fromCharCode(code)
    const expected = String.fromCharCode(code - 0x60)
    assertEqual(controlCharacter(lower), expected, `ctrl+${lower}`)
    assertEqual(controlCharacter(lower.toUpperCase()), expected, `ctrl+${lower.toUpperCase()}`)
  }
  const table: Array<[string, string]> = [
    ['@', '\u0000'],
    ['2', '\u0000'],
    [' ', '\u0000'],
    ['[', ESC],
    ['3', ESC],
    ['\\', '\u001c'],
    ['4', '\u001c'],
    [']', '\u001d'],
    ['5', '\u001d'],
    ['^', '\u001e'],
    ['6', '\u001e'],
    ['_', '\u001f'],
    ['7', '\u001f'],
    ['/', '\u001f'],
    ['?', '\u007f'],
    ['8', '\u007f'],
  ]
  for (const [input, expected] of table) {
    assertEqual(controlCharacter(input), expected, `ctrl+${input}`)
    assertEqual(key('character', mods('ctrl'), false, input), expected, `send_key ctrl+${input}`)
  }
  assertEqual(controlCharacter('1'), undefined, 'ctrl+1 has no control character')
  assertEqual(key('character', mods('ctrl'), false, '1'), '1', 'ctrl+1 stays 1')
  assertEqual(key('character', mods('ctrl'), false, 'é'), 'é', 'ctrl+non-ASCII stays unchanged')
}

function checkCharacterKeys(): void {
  assertEqual(key('character', NO_KEY_MODIFIERS, false, 'x'), 'x', 'plain character')
  assertEqual(key('character', mods('alt'), false, 'b'), `${ESC}b`, 'alt+b')
  assertEqual(key('character', mods('alt', 'shift'), false, 'b'), `${ESC}B`, 'alt+shift+b')
  assertEqual(key('character', mods('alt', 'ctrl'), false, 'x'), `${ESC}\u0018`, 'alt+ctrl+x')
  assertEqual(key('character', mods('meta'), false, 'x'), `${ESC}x`, 'meta+x uses the escape prefix')
  assertEqual(key('character', mods('shift'), false, 'a'), 'A', 'shift+a')
  assertEqual(key('character', mods('ctrl'), false, 'hello'), 'hello', 'ctrl leaves text unchanged')
  assertEqual(key('character', mods('alt'), false, 'hi'), `${ESC}hi`, 'alt prefixes text')
  assertEqual(key('character', NO_KEY_MODIFIERS, false, ''), undefined, 'empty character')
  assertEqual(key('character'), undefined, 'missing character')
}

function checkBridgeParsing(): void {
  const parsed = keyModifiersFromNames(['ctrl', 'bogus', 'meta'])
  assert(parsed.ctrl && parsed.meta && !parsed.alt && !parsed.shift, 'modifier names')
  assert(!keyModifiersFromNames(undefined).ctrl, 'missing modifier list')
  const states = normalizedStickyKeyModifierStates({ ctrl: 'one_shot', alt: 'sustained', shift: 'bogus' })
  assert(
    states.ctrl === 'one_shot' && states.alt === 'sustained' && states.shift === 'off' && states.meta === 'off',
    'sticky state parsing',
  )
  assert(normalizedStickyKeyModifierStates(null).ctrl === 'off', 'null sticky state')
}

function checkStickyTargets(): void {
  assert(isStickyModifierTarget('a'), 'letter is a target')
  assert(isStickyModifierTarget(' '), 'space is a target')
  assert(isStickyModifierTarget('~'), 'tilde is a target')
  assert(!isStickyModifierTarget('\u007f'), 'DEL is not a target')
  assert(!isStickyModifierTarget('\r'), 'CR is not a target')
  assert(!isStickyModifierTarget('ab'), 'two characters are not a target')
  assert(!isStickyModifierTarget('é'), 'non-ASCII is not a target')
  assert(!isStickyModifierTarget('😀'), 'emoji is not a target')
  assert(!isStickyModifierTarget(`${ESC}[A`), 'a sequence is not a target')
}

function checkStickyMergeAndConsume(): void {
  const sticky = new StickyKeyModifiers()
  sticky.set({ ...STICKY_KEY_MODIFIERS_OFF, ctrl: 'one_shot' })

  const first = sticky.resolveTypedInput('c', 'keyboard')
  assertEqual(first.text, '\u0003', 'one-shot ctrl applies to a typed character')
  assert(first.didConsumeOneShot, 'typing consumes one-shot ctrl')
  assert(sticky.current().ctrl === 'off', 'one-shot ctrl is off afterwards')

  const second = sticky.resolveTypedInput('c', 'keyboard')
  assertEqual(second.text, 'c', 'the next character is plain')
  assert(!second.didConsumeOneShot, 'nothing left to consume')

  sticky.set({ ...STICKY_KEY_MODIFIERS_OFF, ctrl: 'sustained' })
  assertEqual(sticky.resolveTypedInput('a', 'keyboard').text, '\u0001', 'sustained ctrl first')
  const sustained = sticky.resolveTypedInput('b', 'keyboard')
  assertEqual(sustained.text, '\u0002', 'sustained ctrl stays on')
  assert(!sustained.didConsumeOneShot, 'sustained is not consumed')

  sticky.set({ ...STICKY_KEY_MODIFIERS_OFF, ctrl: 'sustained', alt: 'one_shot' })
  const mixed = sticky.resolveTypedInput('x', 'keyboard')
  assertEqual(mixed.text, `${ESC}\u0018`, 'sustained ctrl with one-shot alt')
  const afterMixed = sticky.current()
  assert(afterMixed.ctrl === 'sustained' && afterMixed.alt === 'off', 'only the one-shot alt is consumed')

  sticky.set({ ...STICKY_KEY_MODIFIERS_OFF, ctrl: 'one_shot' })
  const hostKey = sticky.resolveHostKey({
    key: 'up',
    modifiers: NO_KEY_MODIFIERS,
    applicationCursorKeys: true,
  })
  assertEqual(hostKey.sequence, `${ESC}[1;5A`, 'sticky ctrl merges into a host arrow key')
  assert(hostKey.didConsumeOneShot && sticky.current().ctrl === 'off', 'host key consumes one-shot ctrl')

  sticky.set({ ...STICKY_KEY_MODIFIERS_OFF, alt: 'one_shot' })
  const hostWithOwn = sticky.resolveHostKey({
    key: 'character',
    text: 'c',
    modifiers: mods('ctrl'),
    applicationCursorKeys: false,
  })
  assertEqual(hostWithOwn.sequence, `${ESC}\u0003`, 'command modifiers merge with sticky ones')

  const plainHostKey = sticky.resolveHostKey({
    key: 'up',
    modifiers: NO_KEY_MODIFIERS,
    applicationCursorKeys: true,
  })
  assertEqual(plainHostKey.sequence, `${ESC}OA`, 'DECCKM application up without modifiers')
  assert(!plainHostKey.didConsumeOneShot, 'no one-shot left to consume')

  sticky.set({ ...STICKY_KEY_MODIFIERS_OFF, ctrl: 'one_shot' })
  const unknownKey = sticky.resolveHostKey({
    key: 'f13',
    modifiers: NO_KEY_MODIFIERS,
    applicationCursorKeys: false,
  })
  assert(unknownKey.sequence === undefined, 'unknown host key is dropped')
  assert(sticky.current().ctrl === 'one_shot', 'an unknown key does not consume the modifier')
}

function checkStickySkipRules(): void {
  const sticky = new StickyKeyModifiers()
  sticky.set({ ...STICKY_KEY_MODIFIERS_OFF, ctrl: 'one_shot' })

  const cases: Array<[string, Parameters<StickyKeyModifiers['resolveTypedInput']>[1], string]> = [
    ['a', 'paste', 'pasted character'],
    ['a', 'composition', 'IME commit'],
    ['a', 'host-key', 'host key data'],
    ['ab', 'keyboard', 'multi-character input'],
    ['é', 'keyboard', 'non-ASCII input'],
    [`${ESC}[A`, 'keyboard', 'hardware arrow key'],
    ['\u007fab', 'keyboard', 'predictive text diff'],
    ['\r', 'keyboard', 'return key'],
  ]
  for (const [data, origin, label] of cases) {
    const resolution = sticky.resolveTypedInput(data, origin)
    assertEqual(resolution.text, data, `${label} passes through`)
    assert(!resolution.didConsumeOneShot, `${label} does not consume the modifier`)
    assert(sticky.current().ctrl === 'one_shot', `${label} keeps one-shot ctrl`)
  }

  sticky.set(STICKY_KEY_MODIFIERS_OFF)
  const off = sticky.resolveTypedInput('a', 'keyboard')
  assertEqual(off.text, 'a', 'no sticky modifiers leaves input unchanged')
}

const checks: Array<[string, () => void]> = [
  ['modifier parameter', checkModifierParameter],
  ['cursor keys and DECCKM', checkCursorKeys],
  ['tilde keys', checkTildeKeys],
  ['F1 to F4', checkF1ToF4],
  ['tab, escape, enter, backspace', checkSimpleKeys],
  ['control characters', checkControlCharacters],
  ['character keys', checkCharacterKeys],
  ['bridge parsing', checkBridgeParsing],
  ['sticky targets', checkStickyTargets],
  ['sticky merge and consume', checkStickyMergeAndConsume],
  ['sticky skip rules', checkStickySkipRules],
]

for (const [name, check] of checks) {
  check()
  console.log(`ok - ${name}`)
}
console.log(`key encoder checks passed (${checks.length})`)
