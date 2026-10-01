//
//  SwiftTerminalAppKitWebViewFilePathTests.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/10/01.
//

#if canImport(AppKit)
import AppKit
import Testing
import WebKit
@testable import SwiftTerminal

/// Exercises how the macOS terminal web view turns pasted and dropped file URLs into paths.
///
/// The suite shares one web view, like the host view suite, because the first `WKWebView`
/// initialization stalls the main thread long enough to disturb timing-sensitive tests. Every
/// pasteboard is private, so the user's clipboard is never read or written.
@MainActor
@Suite("SwiftTerminalAppKitWebView file paths", .serialized)
struct SwiftTerminalAppKitWebViewFilePathTests {
    @Test
    func pasteInsertsEscapedPathsWhenEnabled() {
        let recorder = FilePathPasteRecorder(isEnabled: true)
        let webView = makeFilePathWebView(recorder: recorder)

        withPrivatePasteboard { pasteboard in
            pasteboard.writeObjects([
                URL(fileURLWithPath: "/Users/me/My Folder", isDirectory: true) as NSURL,
                URL(fileURLWithPath: "/Users/me/a&b.txt") as NSURL,
            ])
            webView.pastePasteboard = pasteboard

            #expect(webView.pasteFilePathsFromPasteboard())
            #expect(recorder.pastedPaths == [["/Users/me/My Folder", "/Users/me/a&b.txt"]])
        }
    }

    @Test
    func pasteLeavesFileURLsToWebKitWhileDisabled() {
        let recorder = FilePathPasteRecorder(isEnabled: false)
        let webView = makeFilePathWebView(recorder: recorder)

        withPrivatePasteboard { pasteboard in
            pasteboard.writeObjects([URL(fileURLWithPath: "/Users/me/My Folder") as NSURL])
            webView.pastePasteboard = pasteboard

            #expect(webView.pasteFilePathsFromPasteboard() == false)
            #expect(recorder.pastedPaths.isEmpty)
        }
    }

    @Test
    func pasteLeavesTextToWebKit() {
        let recorder = FilePathPasteRecorder(isEnabled: true)
        let webView = makeFilePathWebView(recorder: recorder)

        withPrivatePasteboard { pasteboard in
            pasteboard.setString("/Users/me/My Folder", forType: .string)
            webView.pastePasteboard = pasteboard

            #expect(webView.pasteFilePathsFromPasteboard() == false)
            #expect(recorder.pastedPaths.isEmpty)
        }
    }

    @Test
    func pasteActionIsAnObjectiveCOverrideOfWebKitPaste() {
        let selector = #selector(NSText.paste(_:))

        #expect(WKWebView.instancesRespond(to: selector))
        #expect(
            class_getMethodImplementation(SwiftTerminalAppKitWebView.self, selector)
                != class_getMethodImplementation(WKWebView.self, selector)
        )
    }

    @Test
    func fileDropInsertsPathsWhenEnabled() {
        let recorder = FilePathPasteRecorder(isEnabled: true)
        let webView = makeFilePathWebView(recorder: recorder)

        withPrivatePasteboard { pasteboard in
            pasteboard.writeObjects([URL(fileURLWithPath: "/Users/me/文档/Résumé (final).pdf") as NSURL])
            let drag = FakeDraggingInfo(pasteboard: pasteboard)

            #expect(webView.draggingEntered(drag) == .copy)
            #expect(webView.isHandlingFileDrop)
            #expect(webView.draggingUpdated(drag) == .copy)
            #expect(webView.prepareForDragOperation(drag))
            #expect(webView.performDragOperation(drag))
            webView.concludeDragOperation(drag)

            #expect(recorder.pastedPaths == [["/Users/me/文档/Résumé (final).pdf"]])
            #expect(webView.isHandlingFileDrop == false)
        }
    }

    @Test
    func exitedFileDropInsertsNothing() {
        let recorder = FilePathPasteRecorder(isEnabled: true)
        let webView = makeFilePathWebView(recorder: recorder)

        withPrivatePasteboard { pasteboard in
            pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/file") as NSURL])
            let drag = FakeDraggingInfo(pasteboard: pasteboard)

            #expect(webView.draggingEntered(drag) == .copy)
            webView.draggingExited(drag)

            #expect(webView.isHandlingFileDrop == false)
            #expect(recorder.pastedPaths.isEmpty)
        }
    }

    @Test
    func fileDropIsLeftToWebKitWhileDisabled() {
        let recorder = FilePathPasteRecorder(isEnabled: false)
        let webView = makeFilePathWebView(recorder: recorder)

        withPrivatePasteboard { pasteboard in
            pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/file") as NSURL])
            let drag = FakeDraggingInfo(pasteboard: pasteboard)

            _ = webView.draggingEntered(drag)
            #expect(webView.isHandlingFileDrop == false)
            webView.draggingExited(drag)
            #expect(recorder.pastedPaths.isEmpty)
        }
    }

    @Test
    func textDropIsLeftToWebKit() {
        let recorder = FilePathPasteRecorder(isEnabled: true)
        let webView = makeFilePathWebView(recorder: recorder)

        withPrivatePasteboard { pasteboard in
            pasteboard.setString("/tmp/file", forType: .string)
            let drag = FakeDraggingInfo(pasteboard: pasteboard)

            _ = webView.draggingEntered(drag)
            #expect(webView.isHandlingFileDrop == false)
            webView.draggingExited(drag)
            #expect(recorder.pastedPaths.isEmpty)
        }
    }

    @Test
    func coordinatorRoutesFilePathsThroughTheSessionPaste() async throws {
        let session = SwiftTerminalSession()
        let coordinator = SwiftTerminalCoordinator(session: session)
        let webView = try #require(coordinator.makeWebView() as? SwiftTerminalAppKitWebView)
        defer {
            coordinator.teardown()
        }

        #expect(webView.pastesFileURLsAsPaths?() == true)
        #expect(webView.filePathPasteHandler?(["/tmp/a b"]) == true)

        session.pastesFileURLsAsPaths = false

        #expect(webView.pastesFileURLsAsPaths?() == false)
        #expect(webView.filePathPasteHandler?(["/tmp/a b"]) == false)
    }
}

@MainActor
private final class FilePathPasteRecorder {
    let isEnabled: Bool
    var pastedPaths: [[String]] = []

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

@MainActor
private enum SharedFilePathTestWebView {
    static let shared = SwiftTerminalAppKitWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    static let window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = shared
        return window
    }()
}

@MainActor
private func makeFilePathWebView(recorder: FilePathPasteRecorder) -> SwiftTerminalAppKitWebView {
    let webView = SharedFilePathTestWebView.shared
    _ = SharedFilePathTestWebView.window
    webView.pastePasteboard = NSPasteboard(name: NSPasteboard.Name("SwiftTerminalTests.unused"))
    webView.pastesFileURLsAsPaths = { recorder.isEnabled }
    webView.filePathPasteHandler = { paths in
        guard recorder.isEnabled else {
            return false
        }

        recorder.pastedPaths.append(paths)
        return true
    }
    return webView
}

@MainActor
private final class FakeDraggingInfo: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        draggingPasteboard = pasteboard
    }

    var draggingDestinationWindow: NSWindow? {
        SharedFilePathTestWebView.window
    }

    var draggingSourceOperationMask: NSDragOperation {
        [.copy, .link, .generic]
    }

    var draggingLocation: NSPoint {
        NSPoint(x: 100, y: 100)
    }

    var draggedImageLocation: NSPoint {
        NSPoint(x: 100, y: 100)
    }

    var draggedImage: NSImage? {
        nil
    }

    var draggingSource: Any? {
        nil
    }

    var draggingSequenceNumber: Int {
        1
    }

    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    var springLoadingHighlight: NSSpringLoadingHighlight {
        .none
    }

    func slideDraggedImage(to _: NSPoint) {}

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions = [],
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}
#endif
