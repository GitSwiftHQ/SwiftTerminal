export type SwiftTerminalTheme = {
  name?: string
  foreground?: string
  background?: string
  cursor?: string
  cursorAccent?: string
  selectionBackground?: string
  selectionForeground?: string
  selectionInactiveBackground?: string
  black?: string
  red?: string
  green?: string
  yellow?: string
  blue?: string
  magenta?: string
  cyan?: string
  white?: string
  brightBlack?: string
  brightRed?: string
  brightGreen?: string
  brightYellow?: string
  brightBlue?: string
  brightMagenta?: string
  brightCyan?: string
  brightWhite?: string
}

export type SwiftTerminalContentInsets = {
  top?: number
  right?: number
  bottom?: number
  left?: number
}

export type TerminalCustomFontVariant =
  | 'regular'
  | 'bold'
  | 'italic'
  | 'bold_italic'

export type SwiftTerminalBufferType = 'normal' | 'alternate'

export type SwiftTerminalBufferSnapshotLine = {
  bufferLine: number
  text: string
  isWrapped: boolean
}

export type SwiftTerminalHostCommand =
  | { type: 'write'; text?: string }
  | { type: 'clear' }
  | { type: 'focus' }
  | { type: 'paste'; text?: string }
  | { type: 'select_all' }
  | { type: 'copy_selection' }
  | {
      type: 'install_font'
      fontFamily?: string
      fontURL?: string
      fontFormat?: 'ttf' | 'otf' | 'woff' | 'woff2'
      fontVariant?: TerminalCustomFontVariant
    }
  | {
      type: 'set_appearance'
      fontFamily?: string
      fontSize?: number
      lineHeight?: number
      letterSpacing?: number
      contentInsets?: SwiftTerminalContentInsets
      cursorStyle?: 'block' | 'underline' | 'bar'
      cursorBlink?: boolean
      inactiveCursorStyle?: 'outline' | 'block' | 'bar' | 'underline' | 'none'
      scrollbarVisibility?: 'automatic' | 'visible' | 'hidden'
      theme?: SwiftTerminalTheme
    }
  | { type: 'set_search_visible'; visible?: boolean }
  | { type: 'clear_search' }
  | {
      type: 'search_next'
      query?: string
      caseSensitive?: boolean
      regex?: boolean
      wholeWord?: boolean
    }
  | {
      type: 'search_previous'
      query?: string
      caseSensitive?: boolean
      regex?: boolean
      wholeWord?: boolean
    }
  | {
      type: 'set_feature_flags'
      enablesSearchUI?: boolean
      enablesKeyboardShortcuts?: boolean
      enablesClipboardIntegration?: boolean
      enablesRuntimeDiagnostics?: boolean
      scrollback?: number
    }
  | {
      type: 'request_buffer_snapshot'
      requestID?: string
      maxLines?: number
      trimRight?: boolean
    }
  | { type: 'clipboard_read_result'; requestID?: string; text?: string }
  | { type: 'clipboard_write_result'; requestID?: string }

export type SwiftTerminalRuntimeEvent =
  | { type: 'ready' }
  | { type: 'input'; text: string }
  | { type: 'selection_changed'; text: string }
  | { type: 'resize'; cols: number; rows: number }
  | { type: 'search_results'; resultIndex: number; resultCount: number }
  | {
      type: 'search_state_changed'
      visible: boolean
      query: string
      caseSensitive: boolean
      regex: boolean
      wholeWord: boolean
      resultIndex: number
      resultCount: number
      errorMessage: string | null
    }
  | {
      type: 'buffer_snapshot'
      requestID: string
      bufferType: SwiftTerminalBufferType
      cols: number
      rows: number
      viewportY: number
      baseY: number
      totalLineCount: number
      startLine: number
      endLine: number
      isTruncated: boolean
      lines: SwiftTerminalBufferSnapshotLine[]
    }
  | { type: 'title_changed'; title: string }
  | { type: 'bell' }
  | { type: 'link_activated'; url: string }
  | { type: 'clipboard_read_request'; requestID: string }
  | { type: 'clipboard_write_request'; requestID: string; text: string }
  | {
      type: 'runtime_diagnostic'
      name: string
      sequence: number
      timestamp: number
      metadata: Record<string, string>
    }
  | { type: 'log'; message: string }

declare global {
  interface Window {
    swiftTerminal: {
      receive(commandJSON: string): Promise<void>
    }
    swiftTerminalInitialAppearance?: Extract<
      SwiftTerminalHostCommand,
      { type: 'set_appearance' }
    >
    webkit?: {
      messageHandlers?: {
        swiftTerminal?: {
          postMessage(message: string): void
        }
      }
    }
  }
}

export function postRuntimeEvent(event: SwiftTerminalRuntimeEvent): void {
  window.webkit?.messageHandlers?.swiftTerminal?.postMessage(
    JSON.stringify(event),
  )
}

export function installHostCommandReceiver(
  handler: (command: SwiftTerminalHostCommand) => void | Promise<void>,
): void {
  window.swiftTerminal = {
    async receive(commandJSON: string): Promise<void> {
      try {
        const command = JSON.parse(commandJSON) as SwiftTerminalHostCommand
        await handler(command)
      } catch (error) {
        const message =
          error instanceof Error ? error.message : 'Unknown bridge error'
        postRuntimeEvent({ type: 'log', message })
      }
    },
  }
}
