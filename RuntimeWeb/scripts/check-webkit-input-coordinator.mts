import {
  WebKitInputCoordinator,
  type WebKitInputInputDecision,
  type WebKitInsertInputSnapshot,
  type WebKitKeydownSnapshot,
  type WebKitScheduledTextareaInsert,
} from '../src/webkitInputCoordinator.js'

function assertEqual<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

function assert(condition: boolean, label: string): asserts condition {
  if (!condition) {
    throw new Error(label)
  }
}

function coordinator(): WebKitInputCoordinator {
  return new WebKitInputCoordinator({
    textareaKeydownInsertWindowMs: 100,
    processedInsertKeydownWindowMs: 250,
  })
}

function insert(
  data: string | null,
  isSwiftTerminalWebKitHost = true,
): WebKitInsertInputSnapshot {
  return {
    inputType: 'insertText',
    data,
    isSwiftTerminalWebKitHost,
  }
}

function keydown(
  overrides: Partial<WebKitKeydownSnapshot> = {},
): WebKitKeydownSnapshot {
  return {
    key: 'a',
    code: 'KeyA',
    keyCode: 65,
    ctrlKey: false,
    altKey: false,
    metaKey: false,
    shiftKey: false,
    isSwiftTerminalWebKitHost: true,
    isTerminalTextareaEvent: true,
    ...overrides,
  }
}

function requireScheduledInsert(
  decision: WebKitInputInputDecision,
  label: string,
): WebKitScheduledTextareaInsert {
  assert(decision.action === 'schedule-forward', label)
  return decision.insert
}

function checkNormalSpaceUsesXtermData(): void {
  const input = coordinator()
  input.recordTextareaKeydown(0)
  input.recordXtermData()

  assertEqual(
    input.handleBeforeInput(insert(' '), 10).action,
    'skip-fallback',
    'normal Space skips WebKit fallback after xterm data',
  )
  assertEqual(
    input.handleInput(insert(' '), 11).action,
    'ignore',
    'normal Space input has no pending fallback',
  )
}

function checkNormalShiftLetterUsesXtermData(): void {
  const input = coordinator()
  input.recordTextareaKeydown(0)
  input.recordXtermData()

  assertEqual(
    input.handleBeforeInput(insert('A'), 10).action,
    'skip-fallback',
    'normal Shift+A skips WebKit fallback after xterm data',
  )
  assertEqual(
    input.handleInput(insert('A'), 11).action,
    'ignore',
    'normal Shift+A input has no pending fallback',
  )
}

function checkSilentInsertTextForwardsOnce(): void {
  const input = coordinator()
  input.recordTextareaKeydown(0)

  assertEqual(
    input.handleBeforeInput(insert('あ'), 10).action,
    'record-pending',
    'silent insertText records pending fallback',
  )
  const scheduled = requireScheduledInsert(
    input.handleInput(insert('あ'), 11),
    'silent insertText schedules a fallback forward',
  )

  assertEqual(scheduled.text, 'あ', 'scheduled insert carries committed text')
  assertEqual(
    input.shouldForwardScheduledInsert(scheduled),
    true,
    'silent insertText forwards while xterm data serial is unchanged',
  )
}

function checkLateXtermDataCancelsScheduledForward(): void {
  const input = coordinator()
  input.recordTextareaKeydown(0)
  input.handleBeforeInput(insert('文'), 10)
  const scheduled = requireScheduledInsert(
    input.handleInput(insert('文'), 11),
    'insertText schedules before late xterm data',
  )

  input.recordXtermData()

  assertEqual(
    input.shouldForwardScheduledInsert(scheduled),
    false,
    'late xterm data cancels scheduled fallback',
  )
}

function checkProcessedKeydownAfterCommittedInsert(): void {
  const input = coordinator()
  input.handleBeforeInput(insert('あ'), 0)
  requireScheduledInsert(
    input.handleInput(insert('あ'), 1),
    'committed insert records recent text',
  )

  assertEqual(
    input.getKeydownSuppressReason(keydown({ key: 'あ', keyCode: 229 }), 10),
    'webkit-processed-ime',
    'processed keydown after committed insert is suppressed',
  )
  assertEqual(
    input.getKeydownSuppressReason(keydown({ key: 'あ', keyCode: 229 }), 252),
    undefined,
    'processed keydown after recent insert window passes through',
  )
}

function checkChineseIMEShiftedPunctuation(): void {
  const input = coordinator()

  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'Shift',
        code: 'ShiftLeft',
        keyCode: 16,
        shiftKey: true,
      }),
      0,
    ),
    'webkit-modifier-only-shift',
    'modifier-only Shift before IME insert is suppressed',
  )
  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: '！',
        code: 'Digit1',
        keyCode: 229,
        shiftKey: true,
      }),
      1,
    ),
    'webkit-processed-ime',
    'shifted printable processed keydown is suppressed',
  )
}

function checkStandaloneCommand229(): void {
  const input = coordinator()

  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'Meta',
        code: 'MetaLeft',
        keyCode: 229,
        metaKey: true,
      }),
      0,
    ),
    'webkit-modifier-only-meta-229',
    'standalone Command keyCode 229 is suppressed',
  )
}

function checkNormalCommandChordsPassThrough(): void {
  const input = coordinator()

  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'c',
        code: 'KeyC',
        keyCode: 67,
        metaKey: true,
      }),
      0,
    ),
    undefined,
    'Cmd-C passes through WebKit guards',
  )
  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'v',
        code: 'KeyV',
        keyCode: 86,
        metaKey: true,
      }),
      0,
    ),
    undefined,
    'Cmd-V passes through WebKit guards',
  )
  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'f',
        code: 'KeyF',
        keyCode: 70,
        metaKey: true,
      }),
      0,
    ),
    undefined,
    'Cmd-F passes through WebKit guards',
  )
  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'Meta',
        code: 'MetaLeft',
        keyCode: 91,
        metaKey: true,
      }),
      0,
    ),
    undefined,
    'normal standalone Command keydown passes through WebKit guards',
  )
}

checkNormalSpaceUsesXtermData()
checkNormalShiftLetterUsesXtermData()
checkSilentInsertTextForwardsOnce()
checkLateXtermDataCancelsScheduledForward()
checkProcessedKeydownAfterCommittedInsert()
checkChineseIMEShiftedPunctuation()
checkStandaloneCommand229()
checkNormalCommandChordsPassThrough()

console.log('WebKit input coordinator checks passed')
