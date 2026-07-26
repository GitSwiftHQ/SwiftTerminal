import Testing
@testable import SwiftTerminal

@Test
func builtInThemeCatalogLoadsExpectedSnapshot() throws {
    #expect(SwiftTerminalThemes.builtIn.count == 591)

    let dracula = try #require(SwiftTerminalThemes.builtIn(named: "Dracula"))
    #expect(dracula.background == "#282A36")
    #expect(dracula.foreground == "#F8F8F2")

    let iTermDefault = try #require(SwiftTerminalThemes.builtIn(named: "iTerm2 Default"))
    #expect(iTermDefault.name == "iTerm2 Default")
    #expect(!iTermDefault.cursor.isEmpty)
}

@Test
func builtInThemeCatalogHasUniqueNamesAndValidColors() {
    let themes = SwiftTerminalThemes.builtIn
    let names = themes.map(\.name)
    let normalizedNames = names.map { $0.lowercased() }
    let blankName = names.first { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let invalidTheme = themes.first { theme in
        themeColors(theme).contains { !isValidHexColor($0) }
    }

    #expect(blankName == nil)
    #expect(Set(names).count == themes.count)
    #expect(Set(normalizedNames).count == themes.count)
    #expect(invalidTheme == nil)
}

@Test(
    "Themes with omitted text colors use semantic fallbacks",
    arguments: [
        ("Sandstone Classic", "#3D5259", "#E4DCC8"),
        ("Sandstone Ink", "#2B3D45", "#DDD8C0"),
        ("Sandstone Warm", "#3E3220", "#E8DFC4"),
    ]
)
func themesWithOmittedTextColorsUseSemanticFallbacks(
    name: String,
    foreground: String,
    selectionBackground: String
) throws {
    let theme = try #require(SwiftTerminalThemes.builtIn(named: name))

    #expect(theme.foreground == foreground)
    #expect(theme.background == "#FDF6E3")
    #expect(theme.cursor == foreground)
    #expect(theme.cursorAccent == "#FDF6E3")
    #expect(theme.selectionBackground == selectionBackground)
    #expect(theme.selectionForeground == foreground)
    #expect(theme.selectionInactiveBackground == selectionBackground)
}

@Test
func themeInitializerNormalizesEmptyFields() {
    let theme = SwiftTerminalTheme(
        name: "   ",
        foreground: "   ",
        background: "   ",
        cursor: "   ",
        selectionBackground: "   "
    )

    #expect(theme == .default)
}

private func themeColors(_ theme: SwiftTerminalTheme) -> [String] {
    [
        theme.foreground,
        theme.background,
        theme.cursor,
        theme.cursorAccent,
        theme.selectionBackground,
        theme.selectionForeground,
        theme.selectionInactiveBackground,
        theme.black,
        theme.red,
        theme.green,
        theme.yellow,
        theme.blue,
        theme.magenta,
        theme.cyan,
        theme.white,
        theme.brightBlack,
        theme.brightRed,
        theme.brightGreen,
        theme.brightYellow,
        theme.brightBlue,
        theme.brightMagenta,
        theme.brightCyan,
        theme.brightWhite,
    ]
}

private func isValidHexColor(_ value: String) -> Bool {
    guard value.first == "#", value.count == 7 || value.count == 9 else {
        return false
    }

    return UInt64(value.dropFirst(), radix: 16) != nil
}
