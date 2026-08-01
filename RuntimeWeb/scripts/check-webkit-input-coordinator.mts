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
  textareaValue = '',
  inputType = 'insertText',
): WebKitInsertInputSnapshot {
  return {
    inputType,
    data,
    isComposing: false,
    isSwiftTerminalWebKitHost,
    isTerminalTextareaEvent: true,
    textareaValue,
  }
}

function requireForwardDiff(
  decision: WebKitInputInputDecision,
  label: string,
): Extract<WebKitInputInputDecision, { action: 'forward-diff' }> {
  assert(decision.action === 'forward-diff', label)
  return decision
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
    isComposing: false,
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

const DEL = '\u007F'

function checkDictationHypothesisUpdatesForwardDiffs(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('你好', true, ''), 1000)
  const first = requireForwardDiff(
    input.handleInput(insert('你好', true, '你好'), 1001),
    'keydown-less append onto an empty textarea forwards as a diff',
  )
  assertEqual(first.text, '你好', 'first hypothesis forwards its full text')
  assertEqual(first.deletedCharacterCount, 0, 'first hypothesis deletes nothing')
  assertEqual(
    input.diagnosticState(1001).pendingWebKitInsert,
    false,
    'forward-diff consumes the pending fallback insert',
  )

  input.handleBeforeInput(insert('你好吗', true, '你好'), 1400)
  const grown = requireForwardDiff(
    input.handleInput(insert('你好吗', true, '你好吗'), 1401),
    'wholesale hypothesis re-insert forwards as a diff',
  )
  assertEqual(grown.text, '吗', 'grown hypothesis forwards only the new suffix')
  assertEqual(grown.deletedCharacterCount, 0, 'grown hypothesis deletes nothing')

  input.handleBeforeInput(insert('你号码', true, '你好吗'), 1800)
  const corrected = requireForwardDiff(
    input.handleInput(insert('你号码', true, '你号码'), 1801),
    'hypothesis correction forwards as a diff',
  )
  assertEqual(
    corrected.text,
    `${DEL}${DEL}号码`,
    'correction deletes the changed suffix and retypes it',
  )
  assertEqual(corrected.deletedCharacterCount, 2, 'correction deletes two characters')
  assertEqual(corrected.insertedCharacterCount, 2, 'correction inserts two characters')
}

function checkIdenticalRetranscriptionForwardsNothing(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('你好', true, ''), 1000)
  requireForwardDiff(
    input.handleInput(insert('你好', true, '你好'), 1001),
    'hypothesis append forwards as a diff',
  )

  input.handleBeforeInput(insert('你好', true, '你好'), 1400)
  const retranscribed = requireForwardDiff(
    input.handleInput(insert('你好', true, '你好'), 1401),
    'identical retranscription is still intercepted',
  )
  assertEqual(retranscribed.text, '', 'identical retranscription sends no bytes')
  assertEqual(retranscribed.deletedCharacterCount, 0, 'identical retranscription deletes nothing')
  assertEqual(retranscribed.insertedCharacterCount, 0, 'identical retranscription inserts nothing')
}

function checkMidlineDictationAdoptsAppendedTail(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('你好', true, 'ls '), 1000)
  const adopted = requireForwardDiff(
    input.handleInput(insert('你好', true, 'ls 你好'), 1001),
    'append after unowned residue adopts only the appended tail',
  )
  assertEqual(adopted.text, '你好', 'adopted append forwards the appended text')

  input.handleBeforeInput(insert('你号', true, 'ls 你好'), 1400)
  const corrected = requireForwardDiff(
    input.handleInput(insert('你号', true, 'ls 你号'), 1401),
    'correction within the owned tail forwards as a diff',
  )
  assertEqual(corrected.text, `${DEL}号`, 'correction never reaches into the unowned base')
}

function checkCorrectionBeyondOwnedTailFallsBackToLegacy(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('好', true, 'ls '), 1000)
  requireForwardDiff(
    input.handleInput(insert('好', true, 'ls 好'), 1001),
    'append adopts the tail before the deep correction',
  )

  input.handleBeforeInput(insert('你', true, 'ls 好'), 1400)
  const decision = input.handleInput(insert('你', true, '你'), 1401)
  assertEqual(
    decision.action,
    'schedule-forward',
    'replacement reaching into unowned text falls back to the legacy path',
  )
  assertEqual(
    input.diagnosticState(1401).forwardedTextareaTailLength,
    -1,
    'deep replacement releases tail ownership',
  )
}

function checkRecentKeydownDisablesDiffForwarding(): void {
  const input = coordinator()

  input.recordTextareaKeydown(1000)
  input.handleBeforeInput(insert('你', true, ''), 1010)
  const decision = input.handleInput(insert('你', true, '你'), 1011)
  assertEqual(
    decision.action,
    'schedule-forward',
    'inserts within the keydown window keep the legacy fallback path',
  )
  assertEqual(
    input.diagnosticState(1011).forwardedTextareaTailLength,
    -1,
    'typed inserts never take tail ownership',
  )
}

function checkKeydownReleasesForwardedTail(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('你好', true, ''), 1000)
  requireForwardDiff(
    input.handleInput(insert('你好', true, '你好'), 1001),
    'append owns the tail before the keydown',
  )
  assertEqual(
    input.diagnosticState(1001).forwardedTextareaTailLength,
    2,
    'owned tail length is visible in diagnostics',
  )

  input.recordTextareaKeydown(2000)
  assertEqual(
    input.diagnosticState(2000).forwardedTextareaTailLength,
    -1,
    'a key event releases tail ownership',
  )
}

function checkNonInsertInputReleasesForwardedTail(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('你好', true, ''), 1000)
  requireForwardDiff(
    input.handleInput(insert('你好', true, '你好'), 1001),
    'append owns the tail before the deletion',
  )

  const decision = input.handleInput(
    insert(null, true, '你', 'deleteContentBackward'),
    1400,
  )
  assertEqual(decision.action, 'ignore', 'non-insert input stays on the legacy path')
  assertEqual(
    input.diagnosticState(1400).forwardedTextareaTailLength,
    -1,
    'non-insert input releases tail ownership',
  )
}

function checkSurrogatePairDiffDoesNotSplitPairs(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('😀😀', true, ''), 1000)
  requireForwardDiff(
    input.handleInput(insert('😀😀', true, '😀😀'), 1001),
    'emoji append owns the tail',
  )

  input.handleBeforeInput(insert('😀😁', true, '😀😀'), 1400)
  const corrected = requireForwardDiff(
    input.handleInput(insert('😀😁', true, '😀😁'), 1401),
    'emoji correction forwards as a diff',
  )
  assertEqual(corrected.deletedCharacterCount, 1, 'one emoji is deleted, not half a pair')
  assertEqual(corrected.text, `${DEL}😁`, 'the replacement emoji is retyped whole')
}

function checkComposingInsertReleasesForwardedTail(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('你好', true, ''), 1000)
  requireForwardDiff(
    input.handleInput(insert('你好', true, '你好'), 1001),
    'append owns the tail before composition starts',
  )

  const composing = insert('喵', true, '你好喵')
  composing.isComposing = true
  input.handleBeforeInput(composing, 1400)
  const decision = input.handleInput(composing, 1401)
  assertEqual(
    decision.action,
    'schedule-forward',
    'composing insertText keeps the legacy fallback path',
  )
  assertEqual(
    input.diagnosticState(1401).forwardedTextareaTailLength,
    -1,
    'composing insertText releases tail ownership',
  )
}

function checkInputSourceSwitchDuringCompositionSuppressed(): void {
  const input = coordinator()

  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'Unidentified',
        code: 'Unidentified',
        keyCode: 0,
        isComposing: true,
      }),
      0,
    ),
    'webkit-input-source-switch',
    'synthesized input-source-switch keydown during composition is suppressed',
  )
}

function checkInputSourceSwitchOutsideCompositionPassesThrough(): void {
  const input = coordinator()

  assertEqual(
    input.getKeydownSuppressReason(
      keydown({ key: 'Unidentified', code: 'Unidentified', keyCode: 0 }),
      0,
    ),
    undefined,
    'synthesized keydown without an active composition passes through',
  )
  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'Unidentified',
        code: 'Unidentified',
        keyCode: 0,
        isComposing: true,
        ctrlKey: true,
      }),
      0,
    ),
    undefined,
    'modified Unidentified keydown during composition passes through',
  )
  assertEqual(
    input.getKeydownSuppressReason(
      keydown({
        key: 'CapsLock',
        code: 'CapsLock',
        keyCode: 20,
        isComposing: true,
      }),
      0,
    ),
    undefined,
    'CapsLock keydown during composition passes through to xterm',
  )
}

function checkDiffForwardKeepsProcessedKeydownSuppression(): void {
  const input = coordinator()

  input.handleBeforeInput(insert('あ', true, ''), 1000)
  requireForwardDiff(
    input.handleInput(insert('あ', true, 'あ'), 1001),
    'keydown-less committed insert forwards as a diff',
  )

  assertEqual(
    input.getKeydownSuppressReason(keydown({ key: 'あ', keyCode: 229 }), 1010),
    'webkit-processed-ime',
    'processed keydown after a diff-forwarded insert is still suppressed',
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
checkDictationHypothesisUpdatesForwardDiffs()
checkIdenticalRetranscriptionForwardsNothing()
checkMidlineDictationAdoptsAppendedTail()
checkCorrectionBeyondOwnedTailFallsBackToLegacy()
checkRecentKeydownDisablesDiffForwarding()
checkKeydownReleasesForwardedTail()
checkNonInsertInputReleasesForwardedTail()
checkSurrogatePairDiffDoesNotSplitPairs()
checkComposingInsertReleasesForwardedTail()
checkInputSourceSwitchDuringCompositionSuppressed()
checkInputSourceSwitchOutsideCompositionPassesThrough()
checkDiffForwardKeepsProcessedKeydownSuppression()

console.log('WebKit input coordinator checks passed')
