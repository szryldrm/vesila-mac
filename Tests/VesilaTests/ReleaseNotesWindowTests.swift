import AppKit
import Testing
@testable import Vesila

@Suite("ReleaseNotes window layout")
@MainActor
struct ReleaseNotesWindowTests {
    @Test(arguments: [1, 80])
    func notesWrapAndDocumentFitsAllLines(noteCount: Int) throws {
        _ = NSApplication.shared
        let note = "A long release note that should wrap within the readable viewport. "
            + String(repeating: "More details about this update. ", count: 8)
        let controller = ReleaseNotesWindowController(version: "1.0.3", entries: [
            ReleaseNotes(version: "1.0.3", notes: Array(repeating: note, count: noteCount))
        ], onClose: {})
        let root = try #require(controller.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let scrollView = try #require(descendants(of: root).compactMap { $0 as? NSScrollView }.first)
        scrollView.layoutSubtreeIfNeeded()
        let textView = try #require(scrollView.documentView as? NSTextView)
        let container = try #require(textView.textContainer)
        let manager = try #require(textView.layoutManager)
        manager.ensureLayout(for: container)
        let usedRect = manager.usedRect(for: container)

        #expect(!scrollView.hasHorizontalScroller)
        #expect(abs(textView.frame.width - scrollView.contentView.bounds.width) < 1)
        #expect(abs(container.containerSize.width + 2 * textView.textContainerInset.width
            - scrollView.contentView.bounds.width) < 1)
        #expect(usedRect.width <= container.containerSize.width + 1)
        #expect(textView.frame.height >= usedRect.maxY + 2 * textView.textContainerInset.height)
        if noteCount == 80 {
            #expect(textView.frame.height > scrollView.contentView.bounds.height)
        }
        let button = try #require(descendants(of: root).compactMap { $0 as? VesilaActionButton }.first)
        #expect(root.bounds.contains(button.convert(button.bounds, to: root)))
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
