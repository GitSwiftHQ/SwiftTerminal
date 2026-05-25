import Foundation
import Testing
@testable import SwiftTerminal

@Test
func runtimeAssetsResolveCopiedDirectoryStructure() throws {
    let entrypointURL = try TerminalRuntimeAssets.entrypointURL()
    let rootDirectoryURL = try TerminalRuntimeAssets.rootDirectoryURL()

    #expect(entrypointURL.lastPathComponent == "index.html")
    #expect(rootDirectoryURL.lastPathComponent == "TerminalRuntime")
    #expect(FileManager.default.fileExists(atPath: entrypointURL.path))
    #expect(
        FileManager.default.fileExists(
            atPath: rootDirectoryURL.appendingPathComponent("assets").path
        )
    )
}
