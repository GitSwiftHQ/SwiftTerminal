export type WebKitKeydownSuppressReason =
  | 'webkit-modifier-only-shift'
  | 'webkit-modifier-only-meta-229'
  | 'webkit-input-source-switch'
  | 'webkit-processed-ime'

export type WebKitKeydownSnapshot = {
  key: string
  code: string
  keyCode: number
  ctrlKey: boolean
  altKey: boolean
  metaKey: boolean
  shiftKey: boolean
  isComposing: boolean
  isSwiftTerminalWebKitHost: boolean
  isTerminalTextareaEvent: boolean
}

export type WebKitInsertInputSnapshot = {
  inputType: string
  data: string | null
  isComposing: boolean
  isSwiftTerminalWebKitHost: boolean
  isTerminalTextareaEvent: boolean
  textareaValue: string
}

export type WebKitInputBeforeInputDecision =
  | { action: 'ignore' }
  | { action: 'skip-fallback' }
  | { action: 'record-pending' }

export type WebKitScheduledTextareaInsert = {
  text: string
  xtermDataEventSerial: number
}

export type WebKitInputInputDecision =
  | { action: 'ignore' }
  | { action: 'schedule-forward'; insert: WebKitScheduledTextareaInsert }
  | {
      action: 'forward-diff'
      text: string
      deletedCharacterCount: number
      insertedCharacterCount: number
    }

export type WebKitInputDiagnosticState = {
  xtermDataEventSerial: number
  pendingWebKitInsert: boolean
  recentWebKitInsert: boolean
  forwardedTextareaTailLength: number
}

type WebKitInputCoordinatorConfiguration = {
  textareaKeydownInsertWindowMs: number
  processedInsertKeydownWindowMs: number
}

export class WebKitInputCoordinator {
  private xtermDataEventSerial = 0
  private terminalTextareaKeydownInputState:
    | { xtermDataEventSerial: number; timestamp: number }
    | undefined
  private pendingWebKitTextareaInsert:
    | { text: string; xtermDataEventSerial: number }
    | undefined
  private recentWebKitTextareaInsert:
    | { text: string; expiresAt: number }
    | undefined
  private insertTextareaValueBeforeInput: string | undefined
  private forwardedTextareaTail: string | undefined

  constructor(
    private readonly configuration: WebKitInputCoordinatorConfiguration,
  ) {}

  recordXtermData(): number {
    this.xtermDataEventSerial += 1
    return this.xtermDataEventSerial
  }

  recordTextareaKeydown(now: number): void {
    this.terminalTextareaKeydownInputState = {
      xtermDataEventSerial: this.xtermDataEventSerial,
      timestamp: now,
    }
    // A key event can change the host-side line state without a matching
    // textarea mutation, so the forwarded tail no longer mirrors the host.
    this.forwardedTextareaTail = undefined
  }

  handleBeforeInput(
    event: WebKitInsertInputSnapshot,
    now: number,
  ): WebKitInputBeforeInputDecision {
    if (
      !event.isSwiftTerminalWebKitHost ||
      !event.isTerminalTextareaEvent ||
      event.inputType !== 'insertText' ||
      !event.data
    ) {
      return { action: 'ignore' }
    }

    this.insertTextareaValueBeforeInput = event.textareaValue

    const keydownInputState = this.terminalTextareaKeydownInputState
    if (
      keydownInputState !== undefined &&
      now - keydownInputState.timestamp <=
        this.configuration.textareaKeydownInsertWindowMs &&
      this.xtermDataEventSerial !== keydownInputState.xtermDataEventSerial
    ) {
      this.pendingWebKitTextareaInsert = undefined
      return { action: 'skip-fallback' }
    }

    this.pendingWebKitTextareaInsert = {
      text: event.data,
      xtermDataEventSerial: this.xtermDataEventSerial,
    }
    return { action: 'record-pending' }
  }

  handleInput(
    event: WebKitInsertInputSnapshot,
    now: number,
  ): WebKitInputInputDecision {
    if (!event.isSwiftTerminalWebKitHost || !event.isTerminalTextareaEvent) {
      return { action: 'ignore' }
    }

    const pendingInsert = this.pendingWebKitTextareaInsert
    this.pendingWebKitTextareaInsert = undefined
    const textareaValueBeforeInput = this.insertTextareaValueBeforeInput
    this.insertTextareaValueBeforeInput = undefined

    if (event.inputType !== 'insertText' || !event.data) {
      // The textarea changed through a path this coordinator cannot mirror
      // (composition, deletion, paste), so the forwarded tail is stale.
      this.forwardedTextareaTail = undefined
      return { action: 'ignore' }
    }

    if (event.isComposing) {
      // Composition owns the textarea while it is active; the mirrored tail
      // cannot track those mutations. Legacy handling below stays unchanged.
      this.forwardedTextareaTail = undefined
    } else if (
      !this.hasRecentTextareaKeydown(now) &&
      textareaValueBeforeInput !== undefined
    ) {
      const diffDecision = this.resolveForwardedTailDiff(
        textareaValueBeforeInput,
        event.textareaValue,
        event.data,
      )
      if (diffDecision !== undefined) {
        this.recentWebKitTextareaInsert = {
          text: event.data,
          expiresAt: now + this.configuration.processedInsertKeydownWindowMs,
        }
        return diffDecision
      }
    }

    if (!pendingInsert || event.data !== pendingInsert.text) {
      return { action: 'ignore' }
    }

    this.recentWebKitTextareaInsert = {
      text: event.data,
      expiresAt: now + this.configuration.processedInsertKeydownWindowMs,
    }

    return { action: 'schedule-forward', insert: pendingInsert }
  }

  shouldForwardScheduledInsert(insert: WebKitScheduledTextareaInsert): boolean {
    return this.xtermDataEventSerial === insert.xtermDataEventSerial
  }

  recordFallbackForwardClearedTextarea(): void {
    this.forwardedTextareaTail = undefined
  }

  private hasRecentTextareaKeydown(now: number): boolean {
    const keydownInputState = this.terminalTextareaKeydownInputState
    return (
      keydownInputState !== undefined &&
      now - keydownInputState.timestamp <=
        this.configuration.textareaKeydownInsertWindowMs
    )
  }

  /**
   * Converts a keydown-less textarea `insertText` mutation into the exact
   * bytes the host still needs. Dictation and predictive text rewrite the
   * textarea by replacing an earlier hypothesis in place; replaying `data`
   * verbatim would resend the whole hypothesis on every update. While this
   * coordinator owns the textarea tail it forwards only the difference:
   * one delete per removed character followed by the appended suffix.
   *
   * Returns undefined when the mutation cannot be mirrored safely; the
   * caller must then leave the legacy fallback path untouched.
   */
  private resolveForwardedTailDiff(
    valueBeforeInput: string,
    valueAfterInput: string,
    data: string,
  ):
    | {
        action: 'forward-diff'
        text: string
        deletedCharacterCount: number
        insertedCharacterCount: number
      }
    | undefined {
    const forwardedTail = this.forwardedTextareaTail
    if (
      forwardedTail === undefined ||
      !valueBeforeInput.endsWith(forwardedTail)
    ) {
      if (valueAfterInput !== valueBeforeInput + data) {
        this.forwardedTextareaTail = undefined
        return undefined
      }

      this.forwardedTextareaTail = data
      return {
        action: 'forward-diff',
        text: data,
        deletedCharacterCount: 0,
        insertedCharacterCount: codePointCount(data),
      }
    }

    const stableBase = valueBeforeInput.slice(
      0,
      valueBeforeInput.length - forwardedTail.length,
    )
    if (!valueAfterInput.startsWith(stableBase)) {
      this.forwardedTextareaTail = undefined
      return undefined
    }

    const updatedTail = valueAfterInput.slice(stableBase.length)
    const commonUnits = commonCodePointPrefixUnits(forwardedTail, updatedTail)
    const deletedCharacterCount = codePointCount(forwardedTail.slice(commonUnits))
    const insertedText = updatedTail.slice(commonUnits)
    this.forwardedTextareaTail = updatedTail

    return {
      action: 'forward-diff',
      text: DELETE_CHARACTER.repeat(deletedCharacterCount) + insertedText,
      deletedCharacterCount,
      insertedCharacterCount: codePointCount(insertedText),
    }
  }

  getKeydownSuppressReason(
    event: WebKitKeydownSnapshot,
    now: number,
  ): WebKitKeydownSuppressReason | undefined {
    if (this.shouldSuppressModifierOnlyShift(event)) {
      return 'webkit-modifier-only-shift'
    }

    if (this.shouldSuppressModifierOnlyMeta229(event)) {
      return 'webkit-modifier-only-meta-229'
    }

    if (this.shouldSuppressInputSourceSwitchKeydown(event)) {
      return 'webkit-input-source-switch'
    }

    if (this.shouldSuppressProcessedIMEKeydown(event, now)) {
      return 'webkit-processed-ime'
    }

    return undefined
  }

  diagnosticState(now: number): WebKitInputDiagnosticState {
    return {
      xtermDataEventSerial: this.xtermDataEventSerial,
      pendingWebKitInsert: this.pendingWebKitTextareaInsert !== undefined,
      recentWebKitInsert:
        this.recentWebKitTextareaInsert !== undefined &&
        this.recentWebKitTextareaInsert.expiresAt >= now,
      forwardedTextareaTailLength:
        this.forwardedTextareaTail === undefined
          ? -1
          : codePointCount(this.forwardedTextareaTail),
    }
  }

  private shouldSuppressModifierOnlyShift(
    event: WebKitKeydownSnapshot,
  ): boolean {
    return (
      event.isSwiftTerminalWebKitHost &&
      event.isTerminalTextareaEvent &&
      event.key === 'Shift' &&
      event.shiftKey &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.metaKey
    )
  }

  private shouldSuppressModifierOnlyMeta229(
    event: WebKitKeydownSnapshot,
  ): boolean {
    return (
      event.isSwiftTerminalWebKitHost &&
      event.isTerminalTextareaEvent &&
      event.key === 'Meta' &&
      (event.code === 'MetaLeft' || event.code === 'MetaRight') &&
      event.keyCode === 229 &&
      event.metaKey &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.shiftKey
    )
  }

  /**
   * Switching the macOS input source while an IME composition is active makes
   * WebKit synthesize a keydown with key `Unidentified` and keyCode 0 before
   * the IME commits the composition. xterm's CompositionHelper treats any
   * keydown it does not recognize as composition-related as a request to
   * finalize immediately, so the preedit text would be sent once from that
   * keydown and a second time from the following compositionend. Suppressing
   * the synthesized keydown keeps compositionend as the single sender.
   */
  private shouldSuppressInputSourceSwitchKeydown(
    event: WebKitKeydownSnapshot,
  ): boolean {
    return (
      event.isSwiftTerminalWebKitHost &&
      event.isTerminalTextareaEvent &&
      event.isComposing &&
      event.key === 'Unidentified' &&
      event.keyCode === 0 &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.metaKey &&
      !event.shiftKey
    )
  }

  private shouldSuppressProcessedIMEKeydown(
    event: WebKitKeydownSnapshot,
    now: number,
  ): boolean {
    const shiftedPunctuationKeydown =
      event.isSwiftTerminalWebKitHost &&
      event.isTerminalTextareaEvent &&
      event.keyCode === 229 &&
      event.shiftKey &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.metaKey &&
      isSinglePrintableKey(event.key)

    if (shiftedPunctuationKeydown) {
      return true
    }

    return (
      event.isSwiftTerminalWebKitHost &&
      event.isTerminalTextareaEvent &&
      event.keyCode === 229 &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.metaKey &&
      isSinglePrintableKey(event.key) &&
      this.recentWebKitTextareaInsert?.text === event.key &&
      this.recentWebKitTextareaInsert.expiresAt >= now
    )
  }
}

function isSinglePrintableKey(key: string): boolean {
  return (
    key !== 'Process' &&
    key !== 'Unidentified' &&
    key !== 'Dead' &&
    Array.from(key).length === 1
  )
}

const DELETE_CHARACTER = '\u007F'

function codePointCount(text: string): number {
  let count = 0
  for (const _ of text) {
    count += 1
  }
  return count
}

function commonCodePointPrefixUnits(a: string, b: string): number {
  const limit = Math.min(a.length, b.length)
  let units = 0
  while (units < limit && a.charCodeAt(units) === b.charCodeAt(units)) {
    units += 1
  }
  // Never split a surrogate pair: when the strings diverge between a shared
  // high surrogate and differing low surrogates, back off to the pair start.
  if (
    units > 0 &&
    units < a.length &&
    units < b.length &&
    isHighSurrogate(a.charCodeAt(units - 1))
  ) {
    units -= 1
  }
  return units
}

function isHighSurrogate(unit: number): boolean {
  return unit >= 0xd800 && unit <= 0xdbff
}
