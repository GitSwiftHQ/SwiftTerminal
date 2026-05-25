import Testing
@testable import SwiftTerminal

@Test
func builtInThemeCatalogLoadsExpectedSnapshot() throws {
    #expect(SwiftTerminalThemes.builtIn.count == 485)

    let dracula = try #require(SwiftTerminalThemes.builtIn(named: "Dracula"))
    #expect(dracula.background == "#282A36")
    #expect(dracula.foreground == "#F8F8F2")

    let iTermDefault = try #require(SwiftTerminalThemes.builtIn(named: "iTerm2 Default"))
    #expect(iTermDefault.name == "iTerm2 Default")
    #expect(!iTermDefault.cursor.isEmpty)
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
