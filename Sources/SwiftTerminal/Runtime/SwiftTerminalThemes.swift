import Foundation

public enum SwiftTerminalThemes {
    public static let builtInSourceName = "iTerm2 Color Schemes"
    public static let builtInSourceRepositoryURL = URL(
        string: "https://github.com/mbadolato/iTerm2-Color-Schemes"
    )!
    public static let builtInSourceLicenseURL = URL(
        string: "https://github.com/mbadolato/iTerm2-Color-Schemes/blob/master/LICENSE"
    )!

    public static var builtIn: [SwiftTerminalTheme] {
        ThemeCatalogStore.catalog.themes
    }

    public static func builtIn(named name: String) -> SwiftTerminalTheme? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        return builtIn.first(where: { $0.name == trimmedName })
            ?? builtIn.first(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame })
    }
}

private struct BuiltInThemeCatalog: Codable {
    var sourceRepositoryURL: String
    var sourceCommit: String
    var generatedAt: String
    var themeCount: Int
    var themes: [SwiftTerminalTheme]

    static let empty = Self(
        sourceRepositoryURL: SwiftTerminalThemes.builtInSourceRepositoryURL.absoluteString,
        sourceCommit: "",
        generatedAt: "",
        themeCount: 0,
        themes: []
    )
}

private enum ThemeCatalogStore {
    static let catalog = loadCatalog()

    private static func loadCatalog() -> BuiltInThemeCatalog {
        guard let resourceURL = themeCatalogResourceURL() else {
            assertionFailure("Missing iTerm2 theme catalog resource")
            return .empty
        }

        do {
            let data = try Data(contentsOf: resourceURL)
            return try JSONDecoder().decode(BuiltInThemeCatalog.self, from: data)
        } catch {
            assertionFailure("Failed to decode iTerm2 theme catalog: \(error.localizedDescription)")
            return .empty
        }
    }

    private static func themeCatalogResourceURL() -> URL? {
        if let directoryURL = Bundle.module.url(forResource: "TerminalThemes", withExtension: nil) {
            return directoryURL.appendingPathComponent("iTerm2Themes.json")
        }

        return Bundle.module.url(forResource: "iTerm2Themes", withExtension: "json")
    }
}
