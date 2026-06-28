export type WebKitKeydownSuppressReason =
  | 'webkit-modifier-only-shift'
  | 'webkit-modifier-only-meta-229'
  | 'webkit-processed-ime'

export type WebKitKeydownSnapshot = {
  key: string
  code: string
  keyCode: number
  ctrlKey: boolean
  altKey: boolean
  metaKey: boolean
  shiftKey: boolean
  isSwiftTerminalWebKitHost: boolean
  isTerminalTextareaEvent: boolean
}

export type WebKitInsertInputSnapshot = {
  inputType: string
  data: string | null
  isSwiftTerminalWebKitHost: boolean
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

export type WebKitInputDiagnosticState = {
  xtermDataEventSerial: number
  pendingWebKitInsert: boolean
  recentWebKitInsert: boolean
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
  }

  handleBeforeInput(
    event: WebKitInsertInputSnapshot,
    now: number,
  ): WebKitInputBeforeInputDecision {
    if (
      !event.isSwiftTerminalWebKitHost ||
      event.inputType !== 'insertText' ||
      !event.data
    ) {
      return { action: 'ignore' }
    }

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
    if (!event.isSwiftTerminalWebKitHost) {
      return { action: 'ignore' }
    }

    const pendingInsert = this.pendingWebKitTextareaInsert
    this.pendingWebKitTextareaInsert = undefined

    if (
      event.inputType !== 'insertText' ||
      !event.data ||
      !pendingInsert ||
      event.data !== pendingInsert.text
    ) {
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
