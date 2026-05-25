import Foundation
import Testing
@testable import SwiftTerminal

@Test
func hostWriteCommandEncodesExpectedShape() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(TerminalHostCommandEnvelope.write("echo test"))
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["type"] as? String == "write")
    #expect(jsonObject?["text"] as? String == "echo test")
}

@Test
func selectAllCommandEncodesExpectedShape() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(TerminalHostCommandEnvelope.selectAll)
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["type"] as? String == "select_all")
}

@Test
func runtimeResizeEventDecodesExpectedShape() throws {
    let json = """
    {
      "type": "resize",
      "cols": 120,
      "rows": 40
    }
    """

    let decoder = JSONDecoder()
    let event = try decoder.decode(TerminalRuntimeEventEnvelope.self, from: Data(json.utf8))

    #expect(event.type == .resize)
    #expect(event.cols == 120)
    #expect(event.rows == 40)
}

@Test
func selectionChangedEventDecodesExpectedShape() throws {
    let json = """
    {
      "type": "selection_changed",
      "text": "selected text"
    }
    """

    let decoder = JSONDecoder()
    let event = try decoder.decode(TerminalRuntimeEventEnvelope.self, from: Data(json.utf8))

    #expect(event.type == .selectionChanged)
    #expect(event.text == "selected text")
}

@Test
func featureFlagCommandEncodesExpectedShape() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(
        TerminalHostCommandEnvelope.setFeatureFlags(
            enablesSearchUI: false,
            enablesKeyboardShortcuts: true,
            enablesClipboardIntegration: false,
            scrollback: 5000
        )
    )
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["type"] as? String == "set_feature_flags")
    #expect(jsonObject?["enablesSearchUI"] as? Bool == false)
    #expect(jsonObject?["enablesKeyboardShortcuts"] as? Bool == true)
    #expect(jsonObject?["enablesClipboardIntegration"] as? Bool == false)
    #expect(jsonObject?["scrollback"] as? Int == 5000)
}

@Test
func requestBufferSnapshotCommandEncodesExpectedShape() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(
        TerminalHostCommandEnvelope.requestBufferSnapshot(
            requestID: "buffer-snapshot-4",
            maxLines: 250,
            trimRight: false
        )
    )
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["type"] as? String == "request_buffer_snapshot")
    #expect(jsonObject?["requestID"] as? String == "buffer-snapshot-4")
    #expect(jsonObject?["maxLines"] as? Int == 250)
    #expect(jsonObject?["trimRight"] as? Bool == false)
}

@Test
func appearanceCommandEncodesExpectedShape() throws {
    let encoder = JSONEncoder()
    let theme = SwiftTerminalTheme(
        name: "Dracula",
        foreground: "#F8F8F2",
        background: "#282A36",
        cursor: "#F8F8F2"
    )
    let data = try encoder.encode(
        TerminalHostCommandEnvelope.setAppearance(
            fontFamily: "Fira Code",
            fontSize: 15,
            lineHeight: 1.2,
            letterSpacing: 2,
            contentInsets: .init(top: 18, right: 16, bottom: 14, left: 12),
            cursorStyle: .underline,
            cursorBlink: false,
            inactiveCursorStyle: .bar,
            scrollbarVisibility: .hidden,
            theme: theme
        )
    )
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let contentInsets = jsonObject?["contentInsets"] as? [String: Any]
    let themeObject = jsonObject?["theme"] as? [String: Any]

    #expect(jsonObject?["type"] as? String == "set_appearance")
    #expect(jsonObject?["fontFamily"] as? String == "Fira Code")
    #expect(jsonObject?["fontSize"] as? Double == 15)
    #expect(jsonObject?["lineHeight"] as? Double == 1.2)
    #expect(jsonObject?["letterSpacing"] as? Int == 2)
    #expect(contentInsets?["top"] as? Double == 18)
    #expect(contentInsets?["right"] as? Double == 16)
    #expect(contentInsets?["bottom"] as? Double == 14)
    #expect(contentInsets?["left"] as? Double == 12)
    #expect(jsonObject?["cursorStyle"] as? String == "underline")
    #expect(jsonObject?["cursorBlink"] as? Bool == false)
    #expect(jsonObject?["inactiveCursorStyle"] as? String == "bar")
    #expect(jsonObject?["scrollbarVisibility"] as? String == "hidden")
    #expect(themeObject?["name"] as? String == "Dracula")
    #expect(themeObject?["background"] as? String == "#282A36")
    #expect(themeObject?["foreground"] as? String == "#F8F8F2")
}

@Test
func searchCommandEncodesExtendedOptions() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(
        TerminalHostCommandEnvelope.searchNext(
            "terminal",
            options: SwiftTerminalSearchOptions(
                caseSensitive: true,
                usesRegex: true,
                matchesWholeWord: true
            )
        )
    )
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["type"] as? String == "search_next")
    #expect(jsonObject?["query"] as? String == "terminal")
    #expect(jsonObject?["caseSensitive"] as? Bool == true)
    #expect(jsonObject?["regex"] as? Bool == true)
    #expect(jsonObject?["wholeWord"] as? Bool == true)
}

@Test
func clearSearchCommandEncodesExpectedShape() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(TerminalHostCommandEnvelope.clearSearch)
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["type"] as? String == "clear_search")
}

@Test
func searchStateChangedEventDecodesExpectedShape() throws {
    let json = """
    {
      "type": "search_state_changed",
      "visible": true,
      "query": "terminal",
      "caseSensitive": true,
      "regex": false,
      "wholeWord": true,
      "resultIndex": 2,
      "resultCount": 5,
      "errorMessage": null
    }
    """

    let decoder = JSONDecoder()
    let event = try decoder.decode(TerminalRuntimeEventEnvelope.self, from: Data(json.utf8))

    #expect(event.type == .searchStateChanged)
    #expect(event.visible == true)
    #expect(event.query == "terminal")
    #expect(event.caseSensitive == true)
    #expect(event.regex == false)
    #expect(event.wholeWord == true)
    #expect(event.resultIndex == 2)
    #expect(event.resultCount == 5)
    #expect(event.errorMessage == nil)
}

@Test
func bufferSnapshotEventDecodesExpectedShape() throws {
    let json = """
    {
      "type": "buffer_snapshot",
      "requestID": "buffer-snapshot-2",
      "bufferType": "normal",
      "cols": 120,
      "rows": 40,
      "viewportY": 20,
      "baseY": 80,
      "totalLineCount": 120,
      "startLine": 0,
      "endLine": 120,
      "isTruncated": false,
      "lines": [
        {
          "bufferLine": 0,
          "text": "first",
          "isWrapped": false
        },
        {
          "bufferLine": 1,
          "text": "wrapped",
          "isWrapped": true
        }
      ]
    }
    """

    let decoder = JSONDecoder()
    let event = try decoder.decode(TerminalRuntimeEventEnvelope.self, from: Data(json.utf8))

    #expect(event.type == .bufferSnapshot)
    #expect(event.requestID == "buffer-snapshot-2")
    #expect(event.bufferType == .normal)
    #expect(event.cols == 120)
    #expect(event.rows == 40)
    #expect(event.viewportY == 20)
    #expect(event.baseY == 80)
    #expect(event.totalLineCount == 120)
    #expect(event.startLine == 0)
    #expect(event.endLine == 120)
    #expect(event.isTruncated == false)
    #expect(
        event.lines == [
            SwiftTerminalBufferLine(bufferLine: 0, text: "first", isWrapped: false),
            SwiftTerminalBufferLine(bufferLine: 1, text: "wrapped", isWrapped: true),
        ]
    )
}

@Test
func titleChangedEventDecodesExpectedShape() throws {
    let json = """
    {
      "type": "title_changed",
      "title": "remote-shell"
    }
    """

    let decoder = JSONDecoder()
    let event = try decoder.decode(TerminalRuntimeEventEnvelope.self, from: Data(json.utf8))

    #expect(event.type == .titleChanged)
    #expect(event.title == "remote-shell")
}

@Test
func bellEventDecodesExpectedShape() throws {
    let json = """
    {
      "type": "bell"
    }
    """

    let decoder = JSONDecoder()
    let event = try decoder.decode(TerminalRuntimeEventEnvelope.self, from: Data(json.utf8))

    #expect(event.type == .bell)
}

@Test
func installFontCommandEncodesExpectedShape() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(
        TerminalHostCommandEnvelope.installFont(
            family: "My Mono",
            url: "swiftterminalfont://font/123",
            format: .woff2,
            variant: .boldItalic
        )
    )
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(jsonObject?["type"] as? String == "install_font")
    #expect(jsonObject?["fontFamily"] as? String == "My Mono")
    #expect(jsonObject?["fontURL"] as? String == "swiftterminalfont://font/123")
    #expect(jsonObject?["fontFormat"] as? String == "woff2")
    #expect(jsonObject?["fontVariant"] as? String == "bold_italic")
}

@Test
func clipboardWriteRequestDecodesExpectedShape() throws {
    let json = """
    {
      "type": "clipboard_write_request",
      "requestID": "clipboard-3",
      "text": "copied"
    }
    """

    let decoder = JSONDecoder()
    let event = try decoder.decode(TerminalRuntimeEventEnvelope.self, from: Data(json.utf8))

    #expect(event.type == .clipboardWriteRequest)
    #expect(event.requestID == "clipboard-3")
    #expect(event.text == "copied")
}

@Test
func fontFormatDetectsKnownExtensions() {
    #expect(TerminalFontFormat(pathExtension: "ttf") == .ttf)
    #expect(TerminalFontFormat(pathExtension: "otf") == .otf)
    #expect(TerminalFontFormat(pathExtension: "woff") == .woff)
    #expect(TerminalFontFormat(pathExtension: "woff2") == .woff2)
    #expect(TerminalFontFormat(pathExtension: "ttc") == nil)
}

@Test
func configurationDefaultsRemainRichByDefault() {
    let configuration = SwiftTerminalConfiguration.default

    #expect(configuration.enablesSearchUI)
    #expect(configuration.enablesKeyboardShortcuts)
    #expect(configuration.enablesClipboardIntegration)
    #expect(configuration.opensLinksByDefault)
    #expect(configuration.scrollback == SwiftTerminalConfiguration.defaultScrollback)
    #expect(configuration.initialText == nil)
}

@Test
func configurationInitializerNormalizesNegativeScrollback() {
    let configuration = SwiftTerminalConfiguration(scrollback: -250)

    #expect(configuration.scrollback == 0)
}

@Test
func appearanceDefaultsRemainRichByDefault() {
    let appearance = SwiftTerminalAppearance.default

    #expect(appearance.fontFamily == SwiftTerminalAppearance.defaultFontFamily)
    #expect(appearance.fontSize == SwiftTerminalAppearance.defaultFontSize)
    #expect(appearance.lineHeight == SwiftTerminalAppearance.defaultLineHeight)
    #expect(appearance.letterSpacing == SwiftTerminalAppearance.defaultLetterSpacing)
    #expect(appearance.contentInsets == SwiftTerminalAppearance.defaultContentInsets)
    #expect(appearance.cursorStyle == SwiftTerminalAppearance.defaultCursorStyle)
    #expect(appearance.cursorBlink == SwiftTerminalAppearance.defaultCursorBlink)
    #expect(appearance.inactiveCursorStyle == SwiftTerminalAppearance.defaultInactiveCursorStyle)
    #expect(appearance.scrollbarVisibility == SwiftTerminalAppearance.defaultScrollbarVisibility)
    #expect(appearance.theme == .default)
}

@Test
func appearanceConvenienceInitializerAppliesUniformContentPadding() {
    let appearance = SwiftTerminalAppearance(contentPadding: 12)

    #expect(appearance.contentInsets == .init(all: 12))
}

@Test
func searchOptionsDefaultRemainSearchFriendly() {
    let options = SwiftTerminalSearchOptions.default

    #expect(options.caseSensitive == false)
    #expect(options.usesRegex == false)
    #expect(options.matchesWholeWord == false)
}

@Test
func appearanceInitializerNormalizesInvalidValues() {
    let appearance = SwiftTerminalAppearance(
        fontFamily: "   ",
        fontSize: 4,
        lineHeight: 0.5,
        letterSpacing: -2,
        contentInsets: .init(top: -10, right: 6, bottom: -4, left: 8),
        theme: SwiftTerminalTheme(
            name: "   ",
            foreground: "   ",
            background: "   "
        )
    )

    #expect(appearance.fontFamily == SwiftTerminalAppearance.defaultFontFamily)
    #expect(appearance.fontSize == 6)
    #expect(appearance.lineHeight == 1)
    #expect(appearance.letterSpacing == 0)
    #expect(
        appearance.contentInsets == SwiftTerminalContentInsets(
            top: 0,
            right: 6,
            bottom: 0,
            left: 8
        )
    )
    #expect(appearance.cursorStyle == .block)
    #expect(appearance.cursorBlink == true)
    #expect(appearance.inactiveCursorStyle == .outline)
    #expect(appearance.scrollbarVisibility == .automatic)
    #expect(appearance.theme == .default)
}
