//
//  TerminalFilePathTextTests.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/10/01.
//

import Foundation
import Testing
@testable import SwiftTerminal

#if canImport(AppKit)
import AppKit
#endif

@Suite("Shell-escaped file paths")
struct TerminalFilePathTextTests {
    @Test
    func plainPathIsUnchanged() {
        #expect(TerminalFilePathText.shellEscapedPath("/Users/me/Documents/report.txt") == "/Users/me/Documents/report.txt")
    }

    @Test
    func spacesAreEscaped() {
        #expect(TerminalFilePathText.shellEscapedPath("/Users/me/My Folder/a b.txt") == #"/Users/me/My\ Folder/a\ b.txt"#)
    }

    @Test
    func quotesAreEscaped() {
        #expect(TerminalFilePathText.shellEscapedPath(#"/tmp/it's "quoted""#) == #"/tmp/it\'s\ \"quoted\""#)
    }

    @Test
    func dollarAndBacktickAreEscaped() {
        #expect(TerminalFilePathText.shellEscapedPath("/tmp/$HOME `id`") == #"/tmp/\$HOME\ \`id\`"#)
    }

    @Test
    func bracketsAndBracesAreEscaped() {
        #expect(TerminalFilePathText.shellEscapedPath("/tmp/(1)[2]{3}") == #"/tmp/\(1\)\[2\]\{3\}"#)
    }

    @Test(arguments: Array("&;|<>*?!#~"))
    func shellOperatorIsEscaped(_ character: Character) {
        #expect(TerminalFilePathText.shellEscapedPath("/tmp/a\(character)b") == "/tmp/a\\\(character)b")
    }

    @Test
    func backslashIsEscaped() {
        #expect(TerminalFilePathText.shellEscapedPath(#"/tmp/a\b"#) == #"/tmp/a\\b"#)
    }

    /// Terminal.app also escapes `=`, `%`, `,` and `:`, which some shells treat specially in
    /// assignments and completions.
    @Test
    func terminalAppExtraCharactersAreEscaped() {
        #expect(TerminalFilePathText.shellEscapedPath("/tmp/a=b%c,d:e") == #"/tmp/a\=b\%c\,d\:e"#)
    }

    @Test
    func leadingTildeIsEscaped() {
        #expect(TerminalFilePathText.shellEscapedPath("~/notes") == #"\~/notes"#)
    }

    @Test
    func whitespaceControlCharactersAreEscaped() {
        #expect(TerminalFilePathText.shellEscapedPath("/tmp/a\tb\nc\rd") == "/tmp/a\\\tb\\\nc\\\rd")
    }

    /// A raw ESC could end a bracketed paste early and raw Control-O runs the line in bash and
    /// zsh, so other control characters are ANSI-C quoted instead of passed through.
    @Test
    func otherControlCharactersAreANSICQuoted() {
        #expect(
            TerminalFilePathText.shellEscapedPath("/tmp/a\u{1B}[201~b\u{0F}c\u{7F}d\u{08}")
                == #"/tmp/a$'\033'\[201\~b$'\017'c$'\177'd$'\010'"#
        )
    }

    @Test
    func escapedPathContainsNoKeyActingControlCharacters() {
        var everyControl = String.UnicodeScalarView()
        everyControl.append(contentsOf: (0x01 ..< 0x20).compactMap(Unicode.Scalar.init))
        everyControl.append("\u{7F}")
        let escaped = TerminalFilePathText.shellEscapedPath("/tmp/" + String(everyControl))
        let allowedControls: Set<UInt32> = [0x09, 0x0A, 0x0D]

        #expect(
            escaped.unicodeScalars.allSatisfy { scalar in
                (scalar.value >= 0x20 && scalar.value != 0x7F) || allowedControls.contains(scalar.value)
            }
        )
    }

    @Test
    func nonASCIINamesAreKept() {
        #expect(TerminalFilePathText.shellEscapedPath("/Users/me/文档/Résumé 📄.pdf") == #"/Users/me/文档/Résumé\ 📄.pdf"#)
    }

    @Test
    func decomposedNonASCIINamesAreKept() {
        let decomposed = "/tmp/Re\u{301}sume\u{301}"
        let escaped = TerminalFilePathText.shellEscapedPath(decomposed)

        #expect(Array(escaped.unicodeScalars) == Array(decomposed.unicodeScalars))
    }

    @Test
    func metacharacterSetMatchesTerminalApp() {
        #expect(TerminalFilePathText.shellMetacharacters.count == 29)
    }

    @Test
    func insertionTextFollowsEachPathWithASpace() {
        #expect(TerminalFilePathText.insertionText(forPaths: ["/tmp/folder"]) == "/tmp/folder ")
    }

    @Test
    func insertionTextSeparatesSeveralPaths() {
        let text = TerminalFilePathText.insertionText(
            forPaths: ["/Users/me/My Folder", "/tmp/a&b.txt", "/Users/me/文档"]
        )

        #expect(text == #"/Users/me/My\ Folder /tmp/a\&b.txt /Users/me/文档 "#)
    }

    @Test
    func insertionTextNeverEndsWithANewline() {
        let text = TerminalFilePathText.insertionText(forPaths: ["/tmp/a", "/tmp/b"])

        #expect(text?.hasSuffix("\n") == false)
        #expect(text?.hasSuffix("\r") == false)
    }

    @Test
    func insertionTextIsNilWithoutPaths() {
        #expect(TerminalFilePathText.insertionText(forPaths: []) == nil)
        #expect(TerminalFilePathText.insertionText(forPaths: [""]) == nil)
    }
}

#if canImport(AppKit)
/// Reads file URLs from private pasteboards, so the tests never touch the user's clipboard.
@MainActor
@Suite("File paths on a pasteboard")
struct TerminalFilePathPasteboardTests {
    @Test
    func fileURLsBecomePathsInOrder() {
        withPrivatePasteboard { pasteboard in
            let folder = URL(fileURLWithPath: "/Users/me/My Folder (1)", isDirectory: true)
            let file = URL(fileURLWithPath: "/Users/me/文档/it's $HOME & ok.txt")
            pasteboard.writeObjects([folder as NSURL, file as NSURL])

            #expect(
                TerminalFilePathText.filePaths(on: pasteboard) == [
                    "/Users/me/My Folder (1)",
                    "/Users/me/文档/it's $HOME & ok.txt",
                ]
            )
        }
    }

    @Test
    func directoryPathHasNoTrailingSlash() throws {
        try withPrivatePasteboard { pasteboard in
            let folder = try #require(URL(string: "file:///Users/me/Downloads/"))
            pasteboard.writeObjects([folder as NSURL])

            #expect(TerminalFilePathText.filePaths(on: pasteboard) == ["/Users/me/Downloads"])
        }
    }

    @Test
    func fileReferenceURLResolvesToItsPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalFilePathTextTests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("referenced file.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try Data().write(to: file)

        let referenceURL = try #require((file as NSURL).fileReferenceURL() as NSURL?)
        #expect(referenceURL.isFileReferenceURL())

        withPrivatePasteboard { pasteboard in
            pasteboard.writeObjects([referenceURL])
            let paths = TerminalFilePathText.filePaths(on: pasteboard)

            #expect(paths.count == 1)
            #expect(paths.first?.hasSuffix("/referenced file.txt") == true)
            #expect(paths.first?.contains("/.file/id=") == false)
        }
    }

    @Test
    func unresolvableFileReferenceIsSkipped() throws {
        try withPrivatePasteboard { pasteboard in
            let staleReference = try #require(URL(string: "file:///.file/id=1.999999999"))
            pasteboard.writeObjects([staleReference as NSURL])

            #expect(TerminalFilePathText.filePaths(on: pasteboard).isEmpty)
        }
    }

    @Test
    func textThatLooksLikeAPathYieldsNoPaths() {
        withPrivatePasteboard { pasteboard in
            pasteboard.setString("/tmp/x", forType: .string)

            #expect(TerminalFilePathText.filePaths(on: pasteboard).isEmpty)
        }

        withPrivatePasteboard { pasteboard in
            pasteboard.setString("file:///etc/passwd", forType: .string)

            #expect(TerminalFilePathText.filePaths(on: pasteboard).isEmpty)
        }
    }

    @Test
    func webURLsYieldNoPaths() throws {
        try withPrivatePasteboard { pasteboard in
            let url = try #require(URL(string: "https://example.com/a b"))
            pasteboard.writeObjects([url as NSURL])

            #expect(TerminalFilePathText.filePaths(on: pasteboard).isEmpty)
        }
    }
}

/// Runs `body` with a uniquely named pasteboard and releases it afterwards.
@MainActor
func withPrivatePasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("SwiftTerminalTests.\(UUID().uuidString)"))
    pasteboard.clearContents()
    defer {
        pasteboard.releaseGlobally()
    }

    try body(pasteboard)
}
#endif
