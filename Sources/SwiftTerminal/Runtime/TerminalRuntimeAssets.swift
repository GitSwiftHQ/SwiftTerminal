import Foundation

enum TerminalRuntimeAssets {
    static func entrypointURL(in bundle: Bundle = .module) throws -> URL {
        guard let url = bundle.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "TerminalRuntime"
        ) else {
            throw TerminalRuntimeAssetError.missingEntrypoint
        }
        return url
    }

    static func rootDirectoryURL(in bundle: Bundle = .module) throws -> URL {
        try entrypointURL(in: bundle).deletingLastPathComponent()
    }
}

enum TerminalRuntimeAssetError: Error {
    case missingEntrypoint
}
