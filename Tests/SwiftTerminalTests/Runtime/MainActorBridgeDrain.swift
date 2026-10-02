//
//  MainActorBridgeDrain.swift
//  SwiftTerminalTests
//
//  Created by GitSwift on 2026/10/03.
//

/// Lets the bridge work a session has started run to completion before a test inspects its
/// runtime spy.
///
/// `SwiftTerminalSession` delivers host commands from main-actor `Task`s, sometimes from a task
/// that one of those tasks starts, and the spies record commands on the main actor without
/// suspending. The main actor runs its jobs in the order they were enqueued, so each
/// `Task.yield()` puts the test behind every job queued before it, and the next yield behind the
/// jobs those started. The session's deepest chain is three tasks, so a few rounds settle it no
/// matter how long other main-actor work, such as a parallel UIKit view test, holds the main
/// thread. A wall-clock sleep gives no such guarantee: its timer can fire while the main thread is
/// busy and resume the test ahead of a task that was queued later.
@MainActor
func waitForAsyncBridge() async {
    for _ in 0..<16 {
        await Task.yield()
    }
}
