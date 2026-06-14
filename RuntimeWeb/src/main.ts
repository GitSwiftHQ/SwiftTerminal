import '@xterm/xterm/css/xterm.css'
import { ClipboardAddon, type IClipboardProvider } from '@xterm/addon-clipboard'
import { SearchAddon } from '@xterm/addon-search'
import { Unicode11Addon } from '@xterm/addon-unicode11'
import { WebLinksAddon } from '@xterm/addon-web-links'
import { Terminal, type IViewportRange } from '@xterm/xterm'
import {
  installHostCommandReceiver,
  postRuntimeEvent,
  type SwiftTerminalBufferSnapshotLine,
  type TerminalCustomFontVariant,
  type SwiftTerminalContentInsets,
  type SwiftTerminalHostCommand,
  type SwiftTerminalTheme,
} from './bridge'
import './styles.css'

function bootLog(message: string): void {
  postRuntimeEvent({ type: 'log', message: `boot ${message}` })
}

const DEFAULT_FONT_FAMILY =
  'SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace'
const DEFAULT_FONT_SIZE = 14
const DEFAULT_LINE_HEIGHT = 1
const DEFAULT_LETTER_SPACING = 0
const DEFAULT_SCROLLBACK = 1000
const DEFAULT_CONTENT_INSET = 0
const DEFAULT_FIT_SCROLLBAR_WIDTH = 14
const MIN_STABLE_FIT_COLS = 10
const MIN_STABLE_FIT_ROWS = 2
const DEFAULT_CURSOR_STYLE = 'block'
const DEFAULT_CURSOR_BLINK = true
const DEFAULT_INACTIVE_CURSOR_STYLE = 'outline'
const DEFAULT_SCROLLBAR_VISIBILITY = 'automatic'
const MAC_LINK_HOVER_HINT_DELAY_MS = 650
type RuntimeTheme = Required<SwiftTerminalTheme>
type RuntimeContentInsets = Required<SwiftTerminalContentInsets>
type RuntimeFontVariant = TerminalCustomFontVariant
type RuntimeCursorStyle = 'block' | 'underline' | 'bar'
type RuntimeInactiveCursorStyle = 'outline' | 'block' | 'bar' | 'underline' | 'none'
type RuntimeScrollbarVisibility = 'automatic' | 'visible' | 'hidden'
type TerminalWithCore = Terminal & {
  _core?: {
    _renderService?: {
      clear(): void
      dimensions?: {
        css: {
          cell: {
            width: number
            height: number
          }
        }
      }
    }
  }
}

type ResolvedColor = {
  red: number
  green: number
  blue: number
  alpha: number
}

type SearchDecorations = {
  activeMatchBackground: string
  activeMatchBorder: string
  activeMatchColorOverviewRuler: string
  matchBackground: string
  matchBorder: string
  matchOverviewRuler: string
}

type SearchQuerySource = 'empty' | 'selection' | 'manual' | 'host'
type SearchStateSignature = {
  query: string
  caseSensitive: boolean
  regex: boolean
  wholeWord: boolean
}
type HoveredLinkState = {
  url: string
  range: IViewportRange
  clientX: number
  clientY: number
}
type MutableFontFaceSet = FontFaceSet & {
  add(font: FontFace): FontFaceSet
  delete(font: FontFace): boolean
}

const DEFAULT_THEME: RuntimeTheme = {
  name: 'SwiftTerminal Default',
  foreground: '#e8ecf3',
  background: '#0f1115',
  cursor: '#7cc7ff',
  cursorAccent: '#0f1115',
  selectionBackground: '#2d4967',
  selectionForeground: '#f4fbff',
  selectionInactiveBackground: '#203246',
  black: '#2e3436',
  red: '#cc0000',
  green: '#4e9a06',
  yellow: '#c4a000',
  blue: '#3465a4',
  magenta: '#75507b',
  cyan: '#06989a',
  white: '#d3d7cf',
  brightBlack: '#555753',
  brightRed: '#ef2929',
  brightGreen: '#8ae234',
  brightYellow: '#fce94f',
  brightBlue: '#729fcf',
  brightMagenta: '#ad7fa8',
  brightCyan: '#34e2e2',
  brightWhite: '#eeeeec',
}

function normalizedText(value: string | undefined, fallback: string): string {
  const trimmed = value?.trim()
  return trimmed ? trimmed : fallback
}

function normalizedTheme(
  theme: SwiftTerminalTheme | undefined,
  fallback: RuntimeTheme = DEFAULT_THEME,
): RuntimeTheme {
  return {
    name: normalizedText(theme?.name, fallback.name),
    foreground: normalizedText(theme?.foreground, fallback.foreground),
    background: normalizedText(theme?.background, fallback.background),
    cursor: normalizedText(theme?.cursor, fallback.cursor),
    cursorAccent: normalizedText(theme?.cursorAccent, fallback.cursorAccent),
    selectionBackground: normalizedText(
      theme?.selectionBackground,
      fallback.selectionBackground,
    ),
    selectionForeground: normalizedText(
      theme?.selectionForeground,
      fallback.selectionForeground,
    ),
    selectionInactiveBackground: normalizedText(
      theme?.selectionInactiveBackground,
      theme?.selectionBackground ?? fallback.selectionInactiveBackground,
    ),
    black: normalizedText(theme?.black, fallback.black),
    red: normalizedText(theme?.red, fallback.red),
    green: normalizedText(theme?.green, fallback.green),
    yellow: normalizedText(theme?.yellow, fallback.yellow),
    blue: normalizedText(theme?.blue, fallback.blue),
    magenta: normalizedText(theme?.magenta, fallback.magenta),
    cyan: normalizedText(theme?.cyan, fallback.cyan),
    white: normalizedText(theme?.white, fallback.white),
    brightBlack: normalizedText(theme?.brightBlack, fallback.brightBlack),
    brightRed: normalizedText(theme?.brightRed, fallback.brightRed),
    brightGreen: normalizedText(theme?.brightGreen, fallback.brightGreen),
    brightYellow: normalizedText(theme?.brightYellow, fallback.brightYellow),
    brightBlue: normalizedText(theme?.brightBlue, fallback.brightBlue),
    brightMagenta: normalizedText(theme?.brightMagenta, fallback.brightMagenta),
    brightCyan: normalizedText(theme?.brightCyan, fallback.brightCyan),
    brightWhite: normalizedText(theme?.brightWhite, fallback.brightWhite),
  }
}

function themeForTerminal(theme: RuntimeTheme) {
  return {
    foreground: theme.foreground,
    background: theme.background,
    cursor: theme.cursor,
    cursorAccent: theme.cursorAccent,
    selectionBackground: theme.selectionBackground,
    selectionForeground: theme.selectionForeground,
    selectionInactiveBackground: theme.selectionInactiveBackground,
    black: theme.black,
    red: theme.red,
    green: theme.green,
    yellow: theme.yellow,
    blue: theme.blue,
    magenta: theme.magenta,
    cyan: theme.cyan,
    white: theme.white,
    brightBlack: theme.brightBlack,
    brightRed: theme.brightRed,
    brightGreen: theme.brightGreen,
    brightYellow: theme.brightYellow,
    brightBlue: theme.brightBlue,
    brightMagenta: theme.brightMagenta,
    brightCyan: theme.brightCyan,
    brightWhite: theme.brightWhite,
  }
}

function normalizedCursorStyle(value: string | undefined): RuntimeCursorStyle {
  switch (value) {
    case 'underline':
    case 'bar':
      return value
    default:
      return DEFAULT_CURSOR_STYLE
  }
}

function normalizedInactiveCursorStyle(
  value: string | undefined,
): RuntimeInactiveCursorStyle {
  switch (value) {
    case 'block':
    case 'bar':
    case 'underline':
    case 'none':
      return value
    default:
      return DEFAULT_INACTIVE_CURSOR_STYLE
  }
}

function normalizedScrollbarVisibility(
  value: string | undefined,
): RuntimeScrollbarVisibility {
  switch (value) {
    case 'visible':
    case 'hidden':
      return value
    default:
      return DEFAULT_SCROLLBAR_VISIBILITY
  }
}

function normalizedContentInset(value: number | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_CONTENT_INSET
  }

  return Math.max(DEFAULT_CONTENT_INSET, value)
}

function normalizedContentInsets(
  value: SwiftTerminalContentInsets | undefined,
): RuntimeContentInsets {
  return {
    top: normalizedContentInset(value?.top),
    right: normalizedContentInset(value?.right),
    bottom: normalizedContentInset(value?.bottom),
    left: normalizedContentInset(value?.left),
  }
}

function applyContentInsets(
  terminalRoot: HTMLElement,
  insets: RuntimeContentInsets,
): void {
  terminalRoot.style.setProperty('--st-terminal-content-padding-top', `${insets.top}px`)
  terminalRoot.style.setProperty('--st-terminal-content-padding-right', `${insets.right}px`)
  terminalRoot.style.setProperty('--st-terminal-content-padding-bottom', `${insets.bottom}px`)
  terminalRoot.style.setProperty('--st-terminal-content-padding-left', `${insets.left}px`)
}

function normalizedFontSize(value: number | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_FONT_SIZE
  }

  return Math.max(6, value)
}

function normalizedLineHeight(value: number | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_LINE_HEIGHT
  }

  return Math.max(DEFAULT_LINE_HEIGHT, value)
}

function normalizedLetterSpacing(value: number | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_LETTER_SPACING
  }

  return Math.max(DEFAULT_LETTER_SPACING, Math.round(value))
}

function cssFontFamilyValue(family: string | undefined): string {
  const trimmed = family?.trim()
  if (!trimmed) {
    return DEFAULT_FONT_FAMILY
  }

  if (trimmed.includes(',')) {
    return trimmed
  }

  const escaped = trimmed.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
  return `"${escaped}", monospace`
}

function initialAppearanceCommand():
  | Extract<SwiftTerminalHostCommand, { type: 'set_appearance' }>
  | undefined {
  const command = window.swiftTerminalInitialAppearance
  return command?.type === 'set_appearance' ? command : undefined
}

function normalizedFontVariant(
  value: TerminalCustomFontVariant | undefined,
): RuntimeFontVariant {
  switch (value) {
    case 'bold':
    case 'italic':
    case 'bold_italic':
      return value
    default:
      return 'regular'
  }
}

function fontFaceDescriptorsForVariant(
  variant: RuntimeFontVariant,
): FontFaceDescriptors {
  switch (variant) {
    case 'bold':
      return { weight: '700', style: 'normal' }
    case 'italic':
      return { weight: '400', style: 'italic' }
    case 'bold_italic':
      return { weight: '700', style: 'italic' }
    default:
      return { weight: '400', style: 'normal' }
  }
}

function installedFontKey(
  family: string,
  variant: RuntimeFontVariant,
): string {
  return `${family}::${variant}`
}

function resolveCssColor(color: string, fallback: string): string {
  const probe = document.createElement('div')
  probe.style.display = 'none'
  probe.style.color = fallback
  probe.style.color = color
  document.body.appendChild(probe)
  const resolvedColor = getComputedStyle(probe).color
  probe.remove()

  return resolvedColor || fallback
}

function parseResolvedColor(color: string): ResolvedColor | undefined {
  const matchedColor = color.match(/^rgba?\(([^)]+)\)$/i)
  if (!matchedColor) {
    return undefined
  }

  const components = matchedColor[1]
    .split(',')
    .map((component) => Number.parseFloat(component.trim()))

  if (components.length < 3 || components.some((component) => Number.isNaN(component))) {
    return undefined
  }

  return {
    red: Math.max(0, Math.min(255, components[0] ?? 0)),
    green: Math.max(0, Math.min(255, components[1] ?? 0)),
    blue: Math.max(0, Math.min(255, components[2] ?? 0)),
    alpha: Math.max(0, Math.min(1, components[3] ?? 1)),
  }
}

function rgbaString(color: ResolvedColor, alpha = color.alpha): string {
  return `rgba(${Math.round(color.red)}, ${Math.round(color.green)}, ${Math.round(
    color.blue,
  )}, ${Math.max(0, Math.min(1, alpha)).toFixed(3)})`
}

function mixColors(
  base: ResolvedColor,
  overlay: ResolvedColor,
  amount: number,
): ResolvedColor {
  const clampedAmount = Math.max(0, Math.min(1, amount))

  return {
    red: base.red + (overlay.red - base.red) * clampedAmount,
    green: base.green + (overlay.green - base.green) * clampedAmount,
    blue: base.blue + (overlay.blue - base.blue) * clampedAmount,
    alpha: base.alpha + (overlay.alpha - base.alpha) * clampedAmount,
  }
}

function relativeLuminance(color: ResolvedColor): number {
  const linearize = (component: number): number => {
    const value = component / 255
    return value <= 0.03928
      ? value / 12.92
      : ((value + 0.055) / 1.055) ** 2.4
  }

  return (
    0.2126 * linearize(color.red) +
    0.7152 * linearize(color.green) +
    0.0722 * linearize(color.blue)
  )
}

function resolvedThemeColors(theme: RuntimeTheme): Record<string, ResolvedColor> {
  const fallbackBackground = DEFAULT_THEME.background
  const fallbackForeground = DEFAULT_THEME.foreground
  const background =
    parseResolvedColor(resolveCssColor(theme.background, fallbackBackground)) ??
    parseResolvedColor(resolveCssColor(DEFAULT_THEME.background, fallbackBackground))!
  const foreground =
    parseResolvedColor(resolveCssColor(theme.foreground, fallbackForeground)) ??
    parseResolvedColor(resolveCssColor(DEFAULT_THEME.foreground, fallbackForeground))!
  const cursor =
    parseResolvedColor(resolveCssColor(theme.cursor, DEFAULT_THEME.cursor)) ??
    foreground
  const selection =
    parseResolvedColor(
      resolveCssColor(theme.selectionBackground, DEFAULT_THEME.selectionBackground),
    ) ?? mixColors(background, foreground, 0.3)
  const selectionForeground =
    parseResolvedColor(
      resolveCssColor(theme.selectionForeground, DEFAULT_THEME.selectionForeground),
    ) ?? foreground

  return {
    background,
    foreground,
    cursor,
    selection,
    selectionForeground,
  }
}

function buildSearchDecorations(theme: RuntimeTheme): SearchDecorations {
  const { background, foreground, cursor, selection } = resolvedThemeColors(theme)
  const activeMatch = mixColors(selection, cursor, 0.3)
  const passiveMatch = mixColors(background, selection, 0.55)

  return {
    activeMatchBackground: rgbaString(activeMatch, 0.92),
    activeMatchBorder: rgbaString(cursor, 0.88),
    activeMatchColorOverviewRuler: rgbaString(cursor, 0.88),
    matchBackground: rgbaString(passiveMatch, 0.78),
    matchBorder: rgbaString(foreground, 0.34),
    matchOverviewRuler: rgbaString(foreground, 0.5),
  }
}

function applyThemeStyles(theme: RuntimeTheme): void {
  const rootStyle = document.documentElement.style
  const { background, foreground, cursor, selection, selectionForeground } =
    resolvedThemeColors(theme)
  const isLightTheme = relativeLuminance(background) > 0.55
  const controlBackground = mixColors(background, foreground, isLightTheme ? 0.08 : 0.16)
  const activeBackground = mixColors(selection, cursor, 0.22)
  const surfaceAccent = mixColors(cursor, background, 0.28)

  rootStyle.setProperty('--st-body-background', rgbaString(background, 1))
  rootStyle.setProperty('--st-body-foreground', rgbaString(foreground, 1))
  rootStyle.setProperty('--st-surface-accent', rgbaString(surfaceAccent, 0.26))
  rootStyle.setProperty('--st-panel-background', rgbaString(controlBackground, 0.94))
  rootStyle.setProperty('--st-panel-border', rgbaString(cursor, isLightTheme ? 0.38 : 0.24))
  rootStyle.setProperty('--st-panel-shadow', rgbaString(background, isLightTheme ? 0.18 : 0.34))
  rootStyle.setProperty('--st-input-background', rgbaString(controlBackground, 0.97))
  rootStyle.setProperty('--st-input-foreground', rgbaString(foreground, 1))
  rootStyle.setProperty('--st-input-border', rgbaString(foreground, isLightTheme ? 0.2 : 0.16))
  rootStyle.setProperty('--st-input-border-focus', rgbaString(cursor, 0.64))
  rootStyle.setProperty('--st-input-error', theme.red)
  rootStyle.setProperty('--st-button-background', rgbaString(controlBackground, 0.97))
  rootStyle.setProperty('--st-button-foreground', rgbaString(foreground, 1))
  rootStyle.setProperty('--st-button-active-background', rgbaString(activeBackground, 0.98))
  rootStyle.setProperty('--st-button-active-foreground', rgbaString(selectionForeground, 1))
  rootStyle.setProperty('--st-results-color', rgbaString(foreground, 0.72))
}

function requiredElement<ElementType extends Element>(
  selector: string,
): ElementType {
  const element = document.querySelector<ElementType>(selector)
  if (!element) {
    throw new Error(`SwiftTerminal runtime DOM boot failed: missing ${selector}`)
  }

  return element
}

function main(): void {
  bootLog('script-start')

  const app = requiredElement<HTMLDivElement>('#app')
  const terminalRoot = requiredElement<HTMLDivElement>('#terminal-root')
  const linkHover = requiredElement<HTMLDivElement>('#link-hover')
  const searchPanel = requiredElement<HTMLDivElement>('#search-panel')
  const searchInputShell =
    requiredElement<HTMLDivElement>('.search-input-shell')
  const searchInput = requiredElement<HTMLInputElement>('#search-input')
  const searchPrevButton = requiredElement<HTMLButtonElement>('#search-prev')
  const searchNextButton = requiredElement<HTMLButtonElement>('#search-next')
  const searchRegexButton = requiredElement<HTMLButtonElement>('#search-regex')
  const searchWholeWordButton =
    requiredElement<HTMLButtonElement>('#search-whole-word')
  const searchCaseButton = requiredElement<HTMLButtonElement>('#search-case')
  const searchCloseButton = requiredElement<HTMLButtonElement>('#search-close')
  const searchResults = requiredElement<HTMLSpanElement>('#search-results')

  bootLog('dom-elements-found')
  app.dataset.linkFollowReady = 'false'
  const initialAppearance = initialAppearanceCommand()
  terminalRoot.dataset.scrollbarVisibility = normalizedScrollbarVisibility(
    initialAppearance?.scrollbarVisibility,
  )
  applyContentInsets(
    terminalRoot,
    normalizedContentInsets(initialAppearance?.contentInsets),
  )

  const searchAddon = new SearchAddon({ highlightLimit: 500 })
  let caseSensitive = false
  let regexEnabled = false
  let wholeWordEnabled = false
  let searchErrorMessage: string | undefined
  let lastSearchState: SearchStateSignature | undefined
  let searchQuerySource: SearchQuerySource = 'empty'
  let searchUIEnabled = true
  let keyboardShortcutsEnabled = true
  let clipboardIntegrationEnabled = true
  let nextClipboardRequestID = 0
  const pendingClipboardReads = new Map<string, (text: string) => void>()
  const pendingClipboardWrites = new Map<string, () => void>()
  const installedFonts = new Map<string, FontFace>()
  const documentFonts = document.fonts as MutableFontFaceSet
  let activeTheme = normalizedTheme(initialAppearance?.theme)
  let searchDecorations = buildSearchDecorations(activeTheme)
  let hoveredLink: HoveredLinkState | undefined
  let macLinkFollowModifierPressed = false
  let macLinkHoverHintVisible = false
  let macLinkHoverHintTimerID: number | undefined
  let deferredLargeShrinkFitTimerID: number | undefined

  bootLog('addons-created')
  applyThemeStyles(activeTheme)

  const terminal = new Terminal({
    allowProposedApi: true,
    allowTransparency: true,
    convertEol: true,
    cursorBlink:
      typeof initialAppearance?.cursorBlink === 'boolean'
        ? initialAppearance.cursorBlink
        : DEFAULT_CURSOR_BLINK,
    cursorStyle: normalizedCursorStyle(initialAppearance?.cursorStyle),
    cursorInactiveStyle: normalizedInactiveCursorStyle(
      initialAppearance?.inactiveCursorStyle,
    ),
    fontFamily: cssFontFamilyValue(initialAppearance?.fontFamily),
    fontSize: normalizedFontSize(initialAppearance?.fontSize),
    lineHeight: normalizedLineHeight(initialAppearance?.lineHeight),
    letterSpacing: normalizedLetterSpacing(initialAppearance?.letterSpacing),
    scrollback: DEFAULT_SCROLLBACK,
    theme: themeForTerminal(activeTheme),
  })
  const clipboardProvider: IClipboardProvider = {
    readText: async () => requestClipboardRead(),
    writeText: async (_selection, text) => requestClipboardWrite(text),
  }

  bootLog('terminal-created')

  terminal.loadAddon(new Unicode11Addon())
  terminal.unicode.activeVersion = '11'
  bootLog('unicode11-addon-loaded')

  terminal.loadAddon(searchAddon)
  bootLog('search-addon-loaded')
  terminal.loadAddon(new ClipboardAddon(undefined, clipboardProvider))
  bootLog('clipboard-addon-loaded')

  terminal.loadAddon(
    new WebLinksAddon(
      (event, uri) => {
        event.preventDefault()
        if (event.metaKey) {
          postRuntimeEvent({ type: 'link_activated', url: uri })
        }
      },
      {
        hover: (event, uri, range) => {
          const isSameLink =
            hoveredLink?.url === uri &&
            hoveredLink.range.start.x === range.start.x &&
            hoveredLink.range.start.y === range.start.y &&
            hoveredLink.range.end.x === range.end.x &&
            hoveredLink.range.end.y === range.end.y
          macLinkFollowModifierPressed = event.metaKey
          hoveredLink = {
            url: uri,
            range,
            clientX: event.clientX,
            clientY: event.clientY,
          }

          if (!isSameLink) {
            macLinkHoverHintVisible = false
            cancelMacLinkHoverHintTimer()
            armMacLinkHoverHint()
          }

          updateMacLinkHoverPresentation()
        },
        leave: (event) => {
          macLinkFollowModifierPressed = event.metaKey
          hoveredLink = undefined
          macLinkHoverHintVisible = false
          cancelMacLinkHoverHintTimer()
          updateMacLinkHoverPresentation()
        },
      },
    ),
  )
  bootLog('weblinks-addon-loaded')

  bootLog('before-open')
  terminal.open(terminalRoot)
  bootLog('after-open')
  fitTerminal(true)
  bootLog('after-fit')

  function focusTerminal(): void {
    terminal.focus()
  }

  focusTerminal()
  bootLog('after-focus')

  terminal.onData((text) => {
    postRuntimeEvent({ type: 'input', text })
  })

  terminal.onBell(() => {
    postRuntimeEvent({ type: 'bell' })
  })

  terminal.onTitleChange((title) => {
    postRuntimeEvent({ type: 'title_changed', title })
  })

  terminal.onSelectionChange(() => {
    const selectionText = terminal.getSelection()
    postRuntimeEvent({ type: 'selection_changed', text: selectionText })

    if (
      searchQuerySource === 'selection' &&
      searchPanel.classList.contains('hidden') &&
      !selectionText
    ) {
      setSearchQuery('', 'empty')
      updateSearchResults(0, 0, false)
    }
  })

  terminal.onResize(({ cols, rows }) => {
    postRuntimeEvent({ type: 'resize', cols, rows })
  })

  function applyScrollbarVisibility(visibility: RuntimeScrollbarVisibility): void {
    terminalRoot.dataset.scrollbarVisibility = visibility
  }

  function normalizedScrollback(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return DEFAULT_SCROLLBACK
    }

    return Math.max(0, Math.round(value))
  }

  function normalizedSnapshotLineLimit(value: number | undefined): number | undefined {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return undefined
    }

    return Math.max(0, Math.floor(value))
  }

  function cssPixelValue(style: CSSStyleDeclaration, propertyName: string): number {
    const value = Number.parseFloat(style.getPropertyValue(propertyName))
    return Number.isFinite(value) ? value : 0
  }

  function currentFitScrollbarWidth(): number {
    if (terminal.options.scrollback === 0) {
      return 0
    }

    return terminalRoot.dataset.scrollbarVisibility === 'hidden'
      ? 0
      : terminal.options.overviewRuler?.width ?? DEFAULT_FIT_SCROLLBAR_WIDTH
  }

  function cancelDeferredLargeShrinkFit(): void {
    if (deferredLargeShrinkFitTimerID === undefined) {
      return
    }

    window.clearTimeout(deferredLargeShrinkFitTimerID)
    deferredLargeShrinkFitTimerID = undefined
  }

  function fitTerminal(allowLargeShrink = false): boolean {
    if (!terminal.element || !terminal.element.parentElement) {
      return false
    }

    const core = terminal as TerminalWithCore
    const dimensions = core._core?._renderService?.dimensions
    if (!dimensions) {
      return false
    }

    const cellWidth = dimensions.css.cell.width
    const cellHeight = dimensions.css.cell.height
    if (cellWidth === 0 || cellHeight === 0) {
      return false
    }

    const parentElement = terminal.element.parentElement
    const parentBounds = parentElement.getBoundingClientRect()
    const parentElementStyle = window.getComputedStyle(parentElement)
    const parentPaddingVertical =
      cssPixelValue(parentElementStyle, 'padding-top') +
      cssPixelValue(parentElementStyle, 'padding-bottom')
    const parentPaddingHorizontal =
      cssPixelValue(parentElementStyle, 'padding-left') +
      cssPixelValue(parentElementStyle, 'padding-right')
    const elementStyle = window.getComputedStyle(terminal.element)
    const elementPaddingVertical =
      cssPixelValue(elementStyle, 'padding-top') +
      cssPixelValue(elementStyle, 'padding-bottom')
    const elementPaddingHorizontal =
      cssPixelValue(elementStyle, 'padding-left') +
      cssPixelValue(elementStyle, 'padding-right')
    const availableHeight =
      parentBounds.height - parentPaddingVertical - elementPaddingVertical
    const availableWidth =
      parentBounds.width -
      parentPaddingHorizontal -
      elementPaddingHorizontal -
      currentFitScrollbarWidth()
    const measuredCols = Math.floor(availableWidth / cellWidth)
    const measuredRows = Math.floor(availableHeight / cellHeight)

    if (measuredCols < MIN_STABLE_FIT_COLS || measuredRows < MIN_STABLE_FIT_ROWS) {
      return false
    }

    const cols = Math.max(MIN_STABLE_FIT_COLS, measuredCols)
    const rows = Math.max(MIN_STABLE_FIT_ROWS, measuredRows)
    const isLargeShrink =
      (terminal.cols > MIN_STABLE_FIT_COLS && cols < terminal.cols * 0.6) ||
      (terminal.rows > MIN_STABLE_FIT_ROWS && rows < terminal.rows * 0.6)

    if (isLargeShrink && !allowLargeShrink) {
      if (deferredLargeShrinkFitTimerID === undefined) {
        deferredLargeShrinkFitTimerID = window.setTimeout(() => {
          deferredLargeShrinkFitTimerID = undefined
          fitTerminal(true)
        }, 120)
      }
      return false
    }

    cancelDeferredLargeShrinkFit()

    if (terminal.rows !== rows || terminal.cols !== cols) {
      core._core?._renderService?.clear()
      terminal.resize(cols, rows)
      return true
    }

    return false
  }

  function currentCellMetrics():
    | { cellWidth: number; cellHeight: number }
    | undefined {
    const core = terminal as TerminalWithCore
    const dimensions = core._core?._renderService?.dimensions
    const cellWidth = dimensions?.css.cell.width ?? 0
    const cellHeight = dimensions?.css.cell.height ?? 0
    if (cellWidth <= 0 || cellHeight <= 0) {
      return undefined
    }

    return { cellWidth, cellHeight }
  }

  function cancelMacLinkHoverHintTimer(): void {
    if (macLinkHoverHintTimerID === undefined) {
      return
    }

    window.clearTimeout(macLinkHoverHintTimerID)
    macLinkHoverHintTimerID = undefined
  }

  function armMacLinkHoverHint(): void {
    if (!hoveredLink || macLinkHoverHintVisible) {
      return
    }

    if (macLinkHoverHintTimerID !== undefined) {
      return
    }

    macLinkHoverHintTimerID = window.setTimeout(() => {
      macLinkHoverHintTimerID = undefined
      if (!hoveredLink) {
        return
      }

      macLinkHoverHintVisible = true
      updateMacLinkHoverPresentation()
    }, MAC_LINK_HOVER_HINT_DELAY_MS)
  }

  function setMacLinkFollowModifierPressed(nextValue: boolean): void {
    if (macLinkFollowModifierPressed === nextValue) {
      return
    }

    macLinkFollowModifierPressed = nextValue
    updateMacLinkHoverPresentation()
  }

  function updateMacLinkFollowCursorState(): void {
    app.dataset.linkFollowReady = macLinkFollowModifierPressed ? 'true' : 'false'
  }

  function updateMacLinkHoverPresentation(): void {
    updateMacLinkFollowCursorState()

    if (!hoveredLink || !macLinkHoverHintVisible) {
      linkHover.classList.add('hidden')
      linkHover.setAttribute('aria-hidden', 'true')
      return
    }

    const appRect = app.getBoundingClientRect()
    const cellDimensions = currentCellMetrics()
    const topRowIndex = hoveredLink.range.start.y - 1
    const leftColumnIndex = hoveredLink.range.start.x - 1
    const anchorX =
      appRect.left +
      leftColumnIndex * (cellDimensions?.cellWidth ?? 0) +
      8
    const anchorY =
      appRect.top +
      topRowIndex * (cellDimensions?.cellHeight ?? 0) -
      10
    linkHover.classList.remove('hidden')
    linkHover.setAttribute('aria-hidden', 'false')
    const bubbleWidth = Math.min(linkHover.offsetWidth || 0, appRect.width - 24)
    const bubbleHeight = linkHover.offsetHeight || 0
    const clampedLeft = Math.min(
      Math.max(12, anchorX - appRect.left),
      Math.max(12, appRect.width - bubbleWidth - 12),
    )
    const top = anchorY - appRect.top
    const displayTop =
      top > bubbleHeight + 12
        ? top - bubbleHeight
        : Math.min(
            appRect.height - bubbleHeight - 12,
            hoveredLink.clientY - appRect.top + 18,
          )

    linkHover.style.left = `${clampedLeft}px`
    linkHover.style.top = `${Math.max(12, displayTop)}px`
  }

  applyScrollbarVisibility(DEFAULT_SCROLLBAR_VISIBILITY)

  searchAddon.onDidChangeResults(({ resultIndex, resultCount }) => {
    updateSearchResults(resultIndex, resultCount)
  })

  function updateSearchResults(
    resultIndex: number,
    resultCount: number,
    emitEvent = true,
  ): void {
    const normalizedResultCount = Math.max(0, resultCount)
    const normalizedResultIndex =
      normalizedResultCount > 0 && resultIndex >= 0 ? resultIndex + 1 : 0
    const hasQuery = searchInput.value.length > 0
    const hasNoResults =
      hasQuery &&
      !searchErrorMessage &&
      normalizedResultCount === 0

    if (!hasQuery && !searchErrorMessage) {
      searchResults.textContent = ''
      searchResults.title = ''
    } else if (searchErrorMessage) {
      searchResults.textContent = searchErrorMessage
      searchResults.title = searchErrorMessage
    } else {
      const label = `${normalizedResultIndex} / ${normalizedResultCount}`
      searchResults.textContent = label
      searchResults.title = label
    }

    searchResults.classList.toggle('is-empty', hasNoResults)
    searchResults.classList.toggle('has-error', Boolean(searchErrorMessage))
    searchInputShell.classList.toggle('has-error', Boolean(searchErrorMessage))
    syncSearchActionAvailability()
    if (emitEvent && !searchErrorMessage) {
      postRuntimeEvent({
        type: 'search_results',
        resultIndex: normalizedResultIndex,
        resultCount: normalizedResultCount,
      })
    }

    postRuntimeEvent({
      type: 'search_state_changed',
      visible: !searchPanel.classList.contains('hidden'),
      query: searchInput.value,
      caseSensitive,
      regex: regexEnabled,
      wholeWord: wholeWordEnabled,
      resultIndex: normalizedResultIndex,
      resultCount: normalizedResultCount,
      errorMessage: searchErrorMessage ?? null,
    })
  }

  function syncSearchButtons(): void {
    searchRegexButton.classList.toggle('is-enabled', regexEnabled)
    searchWholeWordButton.classList.toggle('is-enabled', wholeWordEnabled)
    searchCaseButton.classList.toggle('is-enabled', caseSensitive)
    searchRegexButton.setAttribute('aria-pressed', String(regexEnabled))
    searchWholeWordButton.setAttribute('aria-pressed', String(wholeWordEnabled))
    searchCaseButton.setAttribute('aria-pressed', String(caseSensitive))
  }

  function syncSearchActionAvailability(): void {
    const hasActiveQuery =
      searchInput.value.length > 0 && !searchErrorMessage

    searchPrevButton.disabled = !hasActiveQuery
    searchNextButton.disabled = !hasActiveQuery
  }

  function setSearchError(message?: string): void {
    searchErrorMessage = message?.trim() || undefined
    updateSearchResults(0, 0, false)
  }

  function currentSearchState(query: string): SearchStateSignature {
    return {
      query,
      caseSensitive,
      regex: regexEnabled,
      wholeWord: wholeWordEnabled,
    }
  }

  function hasSearchStateChanged(nextState: SearchStateSignature): boolean {
    return (
      !lastSearchState ||
      lastSearchState.query !== nextState.query ||
      lastSearchState.caseSensitive !== nextState.caseSensitive ||
      lastSearchState.regex !== nextState.regex ||
      lastSearchState.wholeWord !== nextState.wholeWord
    )
  }

  function setSearchQuery(value: string, source: SearchQuerySource): void {
    searchInput.value = value
    searchQuerySource = value.length > 0 ? source : 'empty'
  }

  function selectedSearchText(): string | undefined {
    if (!terminal.hasSelection()) {
      return undefined
    }

    const selection = terminal.getSelection().replace(/\r/g, '')
    if (!selection || selection.includes('\n')) {
      return undefined
    }

    return selection
  }

  function focusSearchInput(): void {
    searchInput.focus()
    searchInput.select()
  }

  function isSearchVisible(): boolean {
    return !searchPanel.classList.contains('hidden')
  }

  function refreshSearchFromSelection(): boolean {
    const preferredQuery = selectedSearchText()
    if (!preferredQuery) {
      return false
    }

    setSearchQuery(preferredQuery, 'selection')
    focusSearchInput()
    runSearch('previous', true, true)
    return true
  }

  function handleFindShortcut(): void {
    if (!isSearchVisible()) {
      setSearchVisible(true)
      return
    }

    if (!refreshSearchFromSelection()) {
      focusSearchInput()
    }
  }

  function hasCommandShortcutModifier(event: KeyboardEvent): boolean {
    return event.metaKey && !event.ctrlKey && !event.altKey
  }

  function shortcutMatchesCode(
    event: KeyboardEvent,
    code: string,
    fallbackKey: string,
  ): boolean {
    return (
      event.code === code ||
      (!event.altKey && event.key.toLowerCase() === fallbackKey)
    )
  }

  function toggleCaseSensitiveSearch(): void {
    caseSensitive = !caseSensitive
    syncSearchButtons()
    rerunSearchIncrementally()
  }

  function toggleWholeWordSearch(): void {
    wholeWordEnabled = !wholeWordEnabled
    syncSearchButtons()
    rerunSearchIncrementally()
  }

  function toggleRegexSearch(): void {
    regexEnabled = !regexEnabled
    syncSearchButtons()
    rerunSearchIncrementally()
  }

  function handleSearchShortcutKeydown(event: KeyboardEvent): boolean {
    if (!keyboardShortcutsEnabled) {
      return false
    }

    if (
      searchUIEnabled &&
      hasCommandShortcutModifier(event) &&
      shortcutMatchesCode(event, 'KeyF', 'f')
    ) {
      handleFindShortcut()
      return true
    }

    if (!searchUIEnabled) {
      return false
    }

    return false
  }

  function isSwiftTerminalWebKitHost(): boolean {
    return (
      typeof window.webkit?.messageHandlers?.swiftTerminal?.postMessage ===
      'function'
    )
  }

  function isTerminalTextareaEvent(event: Event): boolean {
    const textarea = terminal.textarea
    if (!textarea) {
      return false
    }

    if (event.target === textarea) {
      return true
    }

    if (event.composedPath().includes(textarea)) {
      return true
    }

    return document.activeElement === textarea
  }

  function isSinglePrintableKey(key: string): boolean {
    return (
      key !== 'Process' &&
      key !== 'Unidentified' &&
      key !== 'Dead' &&
      Array.from(key).length === 1
    )
  }

  function shouldSuppressWebKitModifierOnlyShift(
    event: KeyboardEvent,
  ): boolean {
    // macOS WKWebView can send a standalone Shift keydown before IME
    // insertText. xterm treats that keydown as active input state, which can
    // make the following composed insertText event look already handled.
    return (
      isSwiftTerminalWebKitHost() &&
      isTerminalTextareaEvent(event) &&
      event.key === 'Shift' &&
      event.shiftKey &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.metaKey
    )
  }

  function shouldSuppressWebKitProcessedIMEKeydown(
    event: KeyboardEvent,
  ): boolean {
    // After WKWebView sends IME insertText for Shift punctuation, it can emit a
    // late keyCode=229 keydown for the same printable character. The input
    // event has already supplied the text, so this keydown should not reach
    // xterm's composition state.
    return (
      isSwiftTerminalWebKitHost() &&
      isTerminalTextareaEvent(event) &&
      event.keyCode === 229 &&
      event.shiftKey &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.metaKey &&
      isSinglePrintableKey(event.key)
    )
  }

  function preserveSearchInputFocus(button: HTMLButtonElement): void {
    button.addEventListener('mousedown', (event) => {
      event.preventDefault()
    })
  }

  function applySearchCommandState(
    command: Extract<
      SwiftTerminalHostCommand,
      { type: 'search_next' | 'search_previous' }
    >,
  ): void {
    caseSensitive = Boolean(command.caseSensitive)
    regexEnabled = Boolean(command.regex)
    wholeWordEnabled = Boolean(command.wholeWord)
    syncSearchButtons()
  }

  function runSearch(
    direction: 'next' | 'previous',
    incremental = false,
    forceRefresh = false,
  ): boolean {
    const query = searchInput.value
    setSearchError()
    if (!query) {
      searchAddon.clearDecorations()
      terminal.clearSelection()
      lastSearchState = undefined
      updateSearchResults(0, 0)
      return false
    }

    const searchState = currentSearchState(query)
    if (forceRefresh || hasSearchStateChanged(searchState)) {
      searchAddon.clearDecorations()
      terminal.clearSelection()
    }

    const options = {
      caseSensitive,
      regex: regexEnabled,
      wholeWord: wholeWordEnabled,
      incremental,
      decorations: searchDecorations,
    }

    try {
      const didFind =
        direction === 'next'
          ? searchAddon.findNext(query, options)
          : searchAddon.findPrevious(query, options)

      lastSearchState = searchState
      return didFind
    } catch (error) {
      const uiMessage = regexEnabled ? 'Invalid regex' : 'Search failed'
      const logMessage =
        error instanceof Error && error.message
          ? `${uiMessage}: ${error.message}`
          : uiMessage

      searchAddon.clearDecorations()
      terminal.clearSelection()
      lastSearchState = undefined
      setSearchError(uiMessage)
      postRuntimeEvent({ type: 'log', message: `search.error ${logMessage}` })
      return false
    }
  }

  function setSearchVisible(visible: boolean): void {
    if (visible && !searchUIEnabled) {
      return
    }

    searchPanel.classList.toggle('hidden', !visible)
    if (visible) {
      const preferredQuery = selectedSearchText()
      if (preferredQuery) {
        setSearchQuery(preferredQuery, 'selection')
      } else if (searchQuerySource === 'selection') {
        setSearchQuery('', 'empty')
      }
      focusSearchInput()
      if (searchInput.value.length > 0) {
        runSearch('previous', true, true)
      } else {
        updateSearchResults(0, 0, false)
      }
      return
    }

    searchAddon.clearDecorations()
    setSearchError()
    updateSearchResults(0, 0, false)
    focusTerminal()
  }

  function clearSearchState(clearQuery = true): void {
    if (clearQuery) {
      setSearchQuery('', 'empty')
    }

    searchAddon.clearDecorations()
    terminal.clearSelection()
    lastSearchState = undefined
    setSearchError()
    updateSearchResults(0, 0, false)
  }

  function rerunSearchIncrementally(): void {
    if (searchInput.value.length > 0) {
      runSearch('next', true, true)
      return
    }

    clearSearchState(false)
  }

  function toggleSearchOption(
    button: HTMLButtonElement,
    updateState: () => void,
  ): void {
    preserveSearchInputFocus(button)
    button.addEventListener('click', () => {
      updateState()
    })
  }

  function focusSearchToggle(offset: number): void {
    const toggleButtons = [searchCaseButton, searchWholeWordButton, searchRegexButton]
    const activeIndex = toggleButtons.indexOf(
      document.activeElement as HTMLButtonElement,
    )

    if (activeIndex < 0) {
      return
    }

    const nextIndex =
      (activeIndex + offset + toggleButtons.length) % toggleButtons.length
    toggleButtons[nextIndex].focus()
  }

  function isSearchToggleFocused(): boolean {
    return (
      document.activeElement === searchCaseButton ||
      document.activeElement === searchWholeWordButton ||
      document.activeElement === searchRegexButton
    )
  }

  function cssFontSourceFormat(
    format: 'ttf' | 'otf' | 'woff' | 'woff2',
  ): string {
    switch (format) {
      case 'ttf':
        return 'truetype'
      case 'otf':
        return 'opentype'
      case 'woff':
        return 'woff'
      case 'woff2':
        return 'woff2'
    }
  }

  function applyAppearance(
    command: Extract<SwiftTerminalHostCommand, { type: 'set_appearance' }>,
  ): void {
    if (typeof command.fontFamily === 'string') {
      terminal.options.fontFamily = cssFontFamilyValue(command.fontFamily)
    }

    if (typeof command.fontSize === 'number') {
      terminal.options.fontSize = normalizedFontSize(command.fontSize)
    }

    if (typeof command.lineHeight === 'number') {
      terminal.options.lineHeight = normalizedLineHeight(command.lineHeight)
    }

    if (typeof command.letterSpacing === 'number') {
      terminal.options.letterSpacing = normalizedLetterSpacing(command.letterSpacing)
    }

    if (command.contentInsets) {
      applyContentInsets(
        terminalRoot,
        normalizedContentInsets(command.contentInsets),
      )
    }

    if (typeof command.cursorBlink === 'boolean') {
      terminal.options.cursorBlink = command.cursorBlink
    }

    if (typeof command.cursorStyle === 'string') {
      terminal.options.cursorStyle = normalizedCursorStyle(command.cursorStyle)
    }

    if (typeof command.inactiveCursorStyle === 'string') {
      terminal.options.cursorInactiveStyle = normalizedInactiveCursorStyle(
        command.inactiveCursorStyle,
      )
    }

    if (typeof command.scrollbarVisibility === 'string') {
      applyScrollbarVisibility(
        normalizedScrollbarVisibility(command.scrollbarVisibility),
      )
    }

    if (command.theme) {
      activeTheme = normalizedTheme(command.theme, activeTheme)
      terminal.options.theme = themeForTerminal(activeTheme)
      searchDecorations = buildSearchDecorations(activeTheme)
      applyThemeStyles(activeTheme)
      if (searchInput.value) {
        runSearch('next', true, true)
      }
    }

    fitTerminal(true)
  }

  async function installFont(
    command: Extract<SwiftTerminalHostCommand, { type: 'install_font' }>,
  ): Promise<void> {
    if (!command.fontFamily || !command.fontURL || !command.fontFormat) {
      return
    }

    const fontVariant = normalizedFontVariant(command.fontVariant)
    const fontKey = installedFontKey(command.fontFamily, fontVariant)
    const previousFont = installedFonts.get(fontKey)
    const fontFace = new FontFace(
      command.fontFamily,
      `url("${command.fontURL}") format("${cssFontSourceFormat(command.fontFormat)}")`,
      fontFaceDescriptorsForVariant(fontVariant),
    )

    try {
      await fontFace.load()
      if (previousFont) {
        documentFonts.delete(previousFont)
      }
      documentFonts.add(fontFace)
      installedFonts.set(fontKey, fontFace)
      postRuntimeEvent({
        type: 'log',
        message: `font.loaded ${command.fontFamily} ${fontVariant}`,
      })
      fitTerminal(true)
    } catch (error) {
      postRuntimeEvent({
        type: 'log',
        message: `font.failed ${command.fontFamily} ${fontVariant} ${
          error instanceof Error ? error.message : String(error)
        }`,
      })
    }
  }

  function applyFeatureFlags(
    command: Extract<SwiftTerminalHostCommand, { type: 'set_feature_flags' }>,
  ): void {
    searchUIEnabled = command.enablesSearchUI ?? searchUIEnabled
    keyboardShortcutsEnabled =
      command.enablesKeyboardShortcuts ?? keyboardShortcutsEnabled
    clipboardIntegrationEnabled =
      command.enablesClipboardIntegration ?? clipboardIntegrationEnabled
    if (typeof command.scrollback === 'number' && Number.isFinite(command.scrollback)) {
      const resolvedScrollback = normalizedScrollback(command.scrollback)
      if (terminal.options.scrollback !== resolvedScrollback) {
        terminal.options.scrollback = resolvedScrollback
        fitTerminal(true)
      }
    }

    if (!clipboardIntegrationEnabled) {
      for (const resolve of pendingClipboardReads.values()) {
        resolve('')
      }
      pendingClipboardReads.clear()

      for (const resolve of pendingClipboardWrites.values()) {
        resolve()
      }
      pendingClipboardWrites.clear()
    }

    if (!searchUIEnabled) {
      setSearchVisible(false)
    }
  }

  function postBufferSnapshot(
    command: Extract<SwiftTerminalHostCommand, { type: 'request_buffer_snapshot' }>,
  ): void {
    if (!command.requestID) {
      postRuntimeEvent({ type: 'log', message: 'buffer_snapshot missing requestID' })
      return
    }

    const buffer = terminal.buffer.active
    const totalLineCount = buffer.length
    const maxLines = normalizedSnapshotLineLimit(command.maxLines)
    const startLine =
      maxLines === undefined ? 0 : Math.max(0, totalLineCount - maxLines)
    const lines: SwiftTerminalBufferSnapshotLine[] = []
    const trimRight = command.trimRight !== false

    for (let bufferLine = startLine; bufferLine < totalLineCount; bufferLine += 1) {
      const line = buffer.getLine(bufferLine)
      lines.push({
        bufferLine,
        text: line?.translateToString(trimRight, 0, terminal.cols) ?? '',
        isWrapped: line?.isWrapped ?? false,
      })
    }

    postRuntimeEvent({
      type: 'buffer_snapshot',
      requestID: command.requestID,
      bufferType: buffer.type,
      cols: terminal.cols,
      rows: terminal.rows,
      viewportY: buffer.viewportY,
      baseY: buffer.baseY,
      totalLineCount,
      startLine,
      endLine: totalLineCount,
      isTruncated: startLine > 0,
      lines,
    })
  }

  function nextClipboardRequest(): string {
    nextClipboardRequestID += 1
    return `clipboard-${nextClipboardRequestID}`
  }

  function requestClipboardRead(): Promise<string> {
    if (!clipboardIntegrationEnabled) {
      return Promise.resolve('')
    }

    return new Promise((resolve) => {
      const requestID = nextClipboardRequest()
      pendingClipboardReads.set(requestID, resolve)
      postRuntimeEvent({ type: 'clipboard_read_request', requestID })
    })
  }

  function requestClipboardWrite(text: string): Promise<void> {
    if (!clipboardIntegrationEnabled) {
      return Promise.resolve()
    }

    return new Promise((resolve) => {
      const requestID = nextClipboardRequest()
      pendingClipboardWrites.set(requestID, resolve)
      postRuntimeEvent({ type: 'clipboard_write_request', requestID, text })
    })
  }

  function resolveClipboardRead(requestID: string, text: string): void {
    const resolve = pendingClipboardReads.get(requestID)
    if (!resolve) {
      return
    }

    pendingClipboardReads.delete(requestID)
    resolve(text)
  }

  function resolveClipboardWrite(requestID: string): void {
    const resolve = pendingClipboardWrites.get(requestID)
    if (!resolve) {
      return
    }

    pendingClipboardWrites.delete(requestID)
    resolve()
  }

  async function copySelectionToHost(): Promise<void> {
    if (!clipboardIntegrationEnabled) {
      return
    }

    const text = terminal.getSelection()
    if (!text) {
      return
    }

    await requestClipboardWrite(text)
  }

  async function pasteFromHost(): Promise<void> {
    if (!clipboardIntegrationEnabled) {
      return
    }

    const text = await requestClipboardRead()
    if (!text) {
      return
    }

    terminal.paste(text)
  }

  async function handleHostCommand(
    command: SwiftTerminalHostCommand,
  ): Promise<void> {
    switch (command.type) {
      case 'write':
        if (command.text) {
          terminal.write(command.text)
        }
        return
      case 'clear':
        terminal.clear()
        return
      case 'focus':
        focusTerminal()
        return
      case 'paste':
        if (command.text) {
          terminal.paste(command.text)
        }
        return
      case 'select_all':
        terminal.selectAll()
        return
      case 'copy_selection':
        void copySelectionToHost()
        return
      case 'install_font':
        await installFont(command)
        return
      case 'set_appearance':
        applyAppearance(command)
        return
      case 'set_search_visible':
        setSearchVisible(Boolean(command.visible))
        return
      case 'clear_search':
        clearSearchState()
        return
      case 'search_next':
        if (command.query) {
          setSearchQuery(command.query, 'host')
          applySearchCommandState(command)
          runSearch('next')
        }
        return
      case 'search_previous':
        if (command.query) {
          setSearchQuery(command.query, 'host')
          applySearchCommandState(command)
          runSearch('previous')
        }
        return
      case 'set_feature_flags':
        applyFeatureFlags(command)
        return
      case 'request_buffer_snapshot':
        postBufferSnapshot(command)
        return
      case 'clipboard_read_result':
        if (command.requestID) {
          resolveClipboardRead(command.requestID, command.text ?? '')
        }
        return
      case 'clipboard_write_result':
        if (command.requestID) {
          resolveClipboardWrite(command.requestID)
        }
        return
    }
  }

  searchInput.addEventListener('input', () => {
    searchQuerySource = searchInput.value.length === 0 ? 'empty' : 'manual'
    rerunSearchIncrementally()
  })

  searchInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault()
      runSearch(event.shiftKey ? 'next' : 'previous')
      return
    }

    if (event.key === 'Escape') {
      event.preventDefault()
      setSearchVisible(false)
    }
  })

  searchPanel.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      if (isSearchToggleFocused()) {
        searchInput.focus()
        return
      }
      setSearchVisible(false)
      return
    }

    if (event.key === 'ArrowLeft' && isSearchToggleFocused()) {
      event.preventDefault()
      focusSearchToggle(-1)
      return
    }

    if (event.key === 'ArrowRight' && isSearchToggleFocused()) {
      event.preventDefault()
      focusSearchToggle(1)
      return
    }

    if (event.key === 'F3') {
      event.preventDefault()
      runSearch(event.shiftKey ? 'previous' : 'next')
      return
    }

    if (handleSearchShortcutKeydown(event)) {
      event.preventDefault()
      event.stopPropagation()
    }
  })

  preserveSearchInputFocus(searchPrevButton)
  preserveSearchInputFocus(searchNextButton)
  preserveSearchInputFocus(searchCloseButton)
  searchPrevButton.addEventListener('click', () => runSearch('previous'))
  searchNextButton.addEventListener('click', () => runSearch('next'))
  searchCloseButton.addEventListener('click', () => setSearchVisible(false))
  toggleSearchOption(searchRegexButton, () => {
    toggleRegexSearch()
  })
  toggleSearchOption(searchWholeWordButton, () => {
    toggleWholeWordSearch()
  })
  toggleSearchOption(searchCaseButton, () => {
    toggleCaseSensitiveSearch()
  })

  window.addEventListener(
    'keydown',
    (event) => {
      if (
        shouldSuppressWebKitModifierOnlyShift(event) ||
        shouldSuppressWebKitProcessedIMEKeydown(event)
      ) {
        event.stopPropagation()
        return
      }

      setMacLinkFollowModifierPressed(event.metaKey)

      if (!handleSearchShortcutKeydown(event)) {
        return
      }

      event.preventDefault()
      event.stopPropagation()
    },
    { capture: true },
  )
  window.addEventListener(
    'keyup',
    (event) => {
      setMacLinkFollowModifierPressed(event.metaKey)
    },
    { capture: true },
  )
  window.addEventListener('blur', () => {
    hoveredLink = undefined
    macLinkHoverHintVisible = false
    cancelMacLinkHoverHintTimer()
    setMacLinkFollowModifierPressed(false)
  })
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) {
      return
    }

    hoveredLink = undefined
    macLinkHoverHintVisible = false
    cancelMacLinkHoverHintTimer()
    setMacLinkFollowModifierPressed(false)
  })

  const resizeObserver = new ResizeObserver(() => {
    fitTerminal()
    updateMacLinkHoverPresentation()
    postRuntimeEvent({
      type: 'resize',
      cols: terminal.cols,
      rows: terminal.rows,
    })
  })

  resizeObserver.observe(terminalRoot)
  syncSearchButtons()
  syncSearchActionAvailability()
  updateSearchResults(0, 0, false)
  installHostCommandReceiver(handleHostCommand)
  bootLog('bridge-installed')
  postRuntimeEvent({ type: 'ready' })
}

try {
  main()
} catch (error) {
  const message =
    error instanceof Error
      ? error.stack || error.message
      : `Unknown runtime error: ${String(error)}`

  postRuntimeEvent({ type: 'log', message: `fatal ${message}` })
  throw error
}
