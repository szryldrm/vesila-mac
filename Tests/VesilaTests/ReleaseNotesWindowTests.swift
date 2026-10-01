import AppKit
import Testing
@testable import Vesila

@Suite("ReleaseNotes window layout")
@MainActor
struct ReleaseNotesWindowTests {
    @Test(arguments: [1, 240])
    func notesWrapAndDocumentFitsAllLines(noteCount: Int) throws {
        _ = NSApplication.shared
        let note = "A long release note that should wrap within the readable viewport. "
            + String(repeating: "More details about this update. ", count: 12)
        let controller = ReleaseNotesWindowController(version: "1.0.3", entries: [
            ReleaseNotes(version: "1.0.3", notes: Array(repeating: note, count: noteCount))
        ], onClose: {})
        let root = try #require(controller.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let scrollView = descendants(of: root).compactMap { $0 as? NSScrollView }.first
        scrollView?.layoutSubtreeIfNeeded()
        let textView = try #require(descendants(of: root).compactMap { $0 as? NSTextView }.first)
        let container = try #require(textView.textContainer)
        let manager = try #require(textView.layoutManager)
        manager.ensureLayout(for: container)
        let usedRect = manager.usedRect(for: container)

        #expect(root.bounds.width == 640)
        #expect(abs(container.containerSize.width + 2 * textView.textContainerInset.width
            - textView.frame.width) < 1)
        #expect(usedRect.width <= container.containerSize.width + 1)
        #expect(textView.frame.height >= usedRect.maxY + 2 * textView.textContainerInset.height)
        let hint = descendants(of: root).compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "Scroll to read more ↓" }
        let button = try #require(descendants(of: root).compactMap { $0 as? VesilaActionButton }.first)
        let heading = try #require(descendants(of: root).compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "What's New in Vesila 1.0.3" })
        let labels = descendants(of: root).compactMap { $0 as? NSTextField }
        #expect(!labels.contains { $0.stringValue == "Vesila" })
        #expect(textView.string.hasPrefix("• "))
        #expect(textView.string == Array(repeating: "• \(note)", count: noteCount).joined(separator: "\n\n"))
        let title = heading.attributedStringValue
        let versionRange = (title.string as NSString).range(of: "1.0.3")
        let prefixFont = try #require(title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let versionFont = try #require(title.attribute(.font, at: versionRange.location, effectiveRange: nil) as? NSFont)
        #expect(!NSFontManager.shared.traits(of: prefixFont).contains(.boldFontMask))
        #expect(NSFontManager.shared.traits(of: versionFont).contains(.boldFontMask))
        #expect(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .labelColor)
        #expect(title.attribute(.foregroundColor, at: versionRange.location, effectiveRange: nil) as? NSColor == .controlAccentColor)
        let buttonFrame = button.convert(button.bounds, to: root)
        let headingFrame = heading.convert(heading.bounds, to: root)
        #expect(root.bounds.contains(buttonFrame))
        #expect(root.bounds.contains(headingFrame))
        #expect(abs(buttonFrame.minY - 24) < 1)
        if noteCount == 240 {
            let scrollView = try #require(scrollView)
            #expect(!scrollView.hasHorizontalScroller)
            #expect(scrollView.hasVerticalScroller)
            #expect(scrollView.scrollerStyle == .legacy)
            #expect(!scrollView.autohidesScrollers)
            #expect(scrollView.verticalScroller?.isHidden == false)
            #expect(abs(textView.frame.width - scrollView.contentView.bounds.width) < 1)
            #expect(textView.frame.height > scrollView.contentView.bounds.height)
            let scroller = try #require(scrollView.verticalScroller)
            #expect(scroller.frame.minX >= scrollView.contentView.frame.maxX - 1)
            #expect(hint != nil)
            #expect(textView.frame.height > 10 * scrollView.contentView.bounds.height)
            #expect(!button.isDescendant(of: scrollView))
            #expect(!heading.isDescendant(of: scrollView))
            let viewportFrame = scrollView.convert(scrollView.bounds, to: root)
            #expect(buttonFrame.maxY + 16 <= viewportFrame.minY)
            #expect(headingFrame.minY >= viewportFrame.maxY)

            // Read to the last line, then return to the start. Only the clip view moves.
            let lastLine = manager.boundingRect(
                forGlyphRange: NSRange(location: manager.numberOfGlyphs - 1, length: 1),
                in: container
            ).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            for end in [true, false] {
                let y = end ? textView.frame.height - scrollView.contentView.bounds.height : 0
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                root.layoutSubtreeIfNeeded()
                #expect(abs(scrollView.contentView.bounds.minX) < 1)
                #expect(button.convert(button.bounds, to: root) == buttonFrame)
                #expect(heading.convert(heading.bounds, to: root) == headingFrame)
                #expect(scrollView.convert(scrollView.bounds, to: root) == viewportFrame)
                if end {
                    #expect(textView.visibleRect.contains(lastLine))
                    #expect(abs(textView.visibleRect.maxY - textView.bounds.maxY) < 1)
                } else {
                    #expect(abs(textView.visibleRect.minY) < 1)
                }
            }
        } else {
            #expect(scrollView == nil)
            #expect(hint == nil)
            #expect(root.bounds.contains(textView.convert(textView.bounds, to: root)))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
