import XCTest
import AppKit
@testable import MacUtils

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testConcealedCopyIsNotRecorded() {
        let store = ClipboardStore.shared
        store.clear()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, .init("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("hunter2-secret", forType: .string)
        store.start()
        store.stop()
        XCTAssertFalse(store.items.contains { if case .text(let t) = $0.content { return t == "hunter2-secret" } else { return false } })
    }
    
    func testDuplicateMovesToTopWithoutGrowing() {
        let store = ClipboardStore.shared
        store.clear()
        let a = ClipboardItem(content: .text("a"), sourceBundleID: nil)
        let b = ClipboardItem(content: .text("b"), sourceBundleID: nil)
        store.writeToPasteboard(a)
        store.writeToPasteboard(b)
        store.writeToPasteboard(a)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.key, a.key)
    }
}
