//
//  TerminalFilePathText.swift
//  SwiftTerminal
//
//  Created by GitSwift on 2026/10/01.
//

import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// The text a terminal inserts for files that are pasted or dropped on it.
///
/// It matches Terminal.app on macOS: every path is escaped for the shell by putting a backslash in
/// front of each shell metacharacter, and each path is followed by a space, so several files read
/// as separate arguments and the next argument can be typed straight away. Characters outside the
/// metacharacter set, including every non-ASCII character, are kept as they are, except control
/// characters, which are quoted so they cannot act as keys. Nothing appends a newline, so the
/// shell never runs the line on its own.
enum TerminalFilePathText {
    /// The characters Terminal.app escapes in a pasted or dropped path, a leading `~` included.
    static let shellMetacharacters: Set<Unicode.Scalar> = Set(
        #"\!|&;<>()$'` "#.unicodeScalars
            + "\t\n\r".unicodeScalars
            + #"*?[]#~=%{},:""#.unicodeScalars
    )

    /// Returns `path` with a backslash in front of every shell metacharacter.
    ///
    /// Other control characters, such as ESC or Control-O, which a file name can contain, are
    /// written as ANSI-C quoted octal escapes like `$'\033'` instead of raw bytes. Terminal.app
    /// passes them through, but raw they would act as keys in the shell's line editor, and an
    /// ESC could end a bracketed paste early, so a name could run or rewrite the command line.
    /// zsh, bash, and ksh read the escape back as the original character; other shells may read
    /// a different name, but nothing in the text acts as a key.
    static func shellEscapedPath(_ path: String) -> String {
        var escaped = String.UnicodeScalarView()
        escaped.reserveCapacity(path.unicodeScalars.count)

        for scalar in path.unicodeScalars {
            if let quotedControl = ansiCQuotedControlCharacter(scalar) {
                escaped.append(contentsOf: quotedControl.unicodeScalars)
                continue
            }

            if shellMetacharacters.contains(scalar) {
                escaped.append("\\")
            }
            escaped.append(scalar)
        }

        return String(escaped)
    }

    /// Returns the `$'\ooo'` form of a C0 control character or DEL, except tab, newline, and
    /// carriage return, which Terminal.app escapes with a backslash like the metacharacters.
    private static func ansiCQuotedControlCharacter(_ scalar: Unicode.Scalar) -> String? {
        let value = scalar.value
        let isControl = value < 0x20 || value == 0x7F
        guard isControl, !shellMetacharacters.contains(scalar) else {
            return nil
        }

        let octal = String(value, radix: 8)
        return "$'\\" + String(repeating: "0", count: 3 - octal.count) + octal + "'"
    }

    /// Returns the text to insert for `paths`, or `nil` when there is no path to insert.
    ///
    /// Each path is escaped and followed by a single space.
    static func insertionText(forPaths paths: [String]) -> String? {
        let nonEmptyPaths = paths.filter { !$0.isEmpty }
        guard !nonEmptyPaths.isEmpty else {
            return nil
        }

        return nonEmptyPaths.map { shellEscapedPath($0) + " " }.joined()
    }

    #if canImport(AppKit)
    /// Returns the file-system paths of the file URLs on `pasteboard`, in pasteboard order.
    ///
    /// Only file URLs count, so a pasteboard that holds text, including text that looks like a
    /// path or a `file:` URL, yields no paths. A file reference URL, which Finder can put on the
    /// pasteboard, is resolved to its path; one that cannot be resolved is skipped rather than
    /// inserted as its `/.file/id=` form.
    @MainActor
    static func filePaths(on pasteboard: NSPasteboard) -> [String] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []

        return objects.compactMap { object in
            guard let url = object as? NSURL else {
                return nil
            }

            return filePath(of: url)
        }
    }

    private static func filePath(of url: NSURL) -> String? {
        let pathURL: NSURL?
        if url.isFileReferenceURL() {
            pathURL = url.filePathURL as NSURL?
        } else {
            pathURL = url
        }

        guard let pathURL,
              pathURL.isFileURL,
              !pathURL.isFileReferenceURL(),
              let path = pathURL.path,
              !path.isEmpty
        else {
            return nil
        }

        return path
    }
    #endif
}
