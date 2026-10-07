import AppKit
import Testing
@testable import Vesila

// Serialized: these cases post to and drain the shared application event queue in turn.
@Suite("Clickable state cards", .serialized)
@MainActor
struct StateCardViewTests {
    /// Hosts the card in a window. NSWindow's postEvent and nextEvent only forward to NSApp, so the
    /// shared application must exist, as in the other window tests, or synthetic releases are dropped
    /// and whether they reach a queue would depend on which suite happened to create NSApp first.
    private func hostWindow(_ card: StateCardView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = card
        card.frame = NSRect(x: 0, y: 0, width: 160, height: 100)
        return window
    }

    /// Queues a release ahead of everything else, and fails here, rather than inside the card's
    /// tracking loop (which waits for a release without a deadline, like real input), unless that
    /// release is the next event the loop will see.
    private func queueRelease(_ up: NSEvent, in window: NSWindow) throws {
        window.postEvent(up, atStart: true)
        let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: .distantPast,
                                    inMode: .default, dequeue: false)
        try #require(next?.type == .leftMouseUp && next?.locationInWindow == up.locationInWindow,
                     "synthetic release at \(up.locationInWindow) not queued; next event \(String(describing: next))")
    }

    /// The release the tracking loop has not consumed, removed so it cannot leak into the next case.
    private func takeQueuedRelease(in window: NSWindow) -> NSEvent? {
        window.nextEvent(matching: [.leftMouseUp], until: .distantPast, inMode: .default, dequeue: true)
    }

    /// Lays the fixture window out, then returns the window locations of the card's center and of a
    /// point outside it, so synthetic events follow the card's constrained geometry, not its preset frame.
    private func clickPoints(_ card: StateCardView, in window: NSWindow) throws -> (inside: NSPoint, outside: NSPoint) {
        window.layoutIfNeeded()
        try #require(!card.bounds.isEmpty, "card bounds \(card.bounds) after layout")
        let inside = card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil)
        let outside = card.convert(NSPoint(x: card.bounds.minX - 20, y: card.bounds.minY - 20), to: nil)
        #expect(card.bounds.contains(card.convert(inside, from: nil)))
        #expect(!card.bounds.contains(card.convert(outside, from: nil)))
        return (inside, outside)
    }

    private func key(_ characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: 0))
    }

    @Test(arguments: [true, false], [StateCardView.Layout.prominent, .compact])
    func disabledRejectsEveryActivationAndExposesRequirement(storedChoice: Bool, layout: StateCardView.Layout) throws {
        var changes: [Bool] = []
        let card = StateCardView(title: "Presence", symbol: "person", layout: layout, requirement: "Requires System Awake") {
            changes.append($0)
        }
        let window = hostWindow(card)
        card.update(isOn: storedChoice, isEnabled: false)
        #expect(!card.isOn)
        #expect(!card.acceptsFirstResponder)
        #expect(!card.isAccessibilityEnabled())
        #expect(card.accessibilityHelp() == "Requires System Awake")
        #expect(card.fillColor == CardColor.disabledSurface)
        #expect(!card.accessibilityPerformPress())
        card.keyDown(with: try key(" "))
        card.keyDown(with: try key("\r"))
        // Click the card's center, so the rejection cannot come from the press landing outside it.
        let center = try clickPoints(card, in: window).inside
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: center, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: center, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        try queueRelease(up, in: window)
        card.mouseEntered(with: click)
        card.mouseDown(with: click)
        // Disabled input never starts tracking, so the queued release is still there, untouched.
        #expect(takeQueuedRelease(in: window)?.locationInWindow == center)
        #expect(changes.isEmpty)
        #expect(!card.isOn)
        // AppKit decides where subview layers sit among the card's sublayers, so find the card's
        // own hover/press feedback layer by identity rather than by position.
        let subviewLayers = card.subviews.compactMap(\.layer)
        let feedback = try #require(card.layer?.sublayers?.first { layer in !subviewLayers.contains { $0 === layer } })
        #expect(feedback.opacity == 0)
        // Only the disabled state suppresses it: the same pointer entry shows feedback once enabled.
        card.update(isOn: storedChoice)
        card.mouseEntered(with: click)
        #expect(feedback.opacity == 1)
    }

    @Test(arguments: [StateCardView.Layout.prominent, .compact])
    func enabledTogglesAndKeepsHeightAndAccessibleState(layout: StateCardView.Layout) throws {
        var changes: [Bool] = []
        let card = StateCardView(title: "System Awake", symbol: "sun.max", layout: layout) { changes.append($0) }
        card.update(isOn: false, isEnabled: false)
        let height = card.fittingSize.height
        card.update(isOn: false)
        #expect(card.fillColor == CardColor.surface)
        #expect(card.accessibilityRole() == .checkBox)
        #expect(card.accessibilityLabel() == "System Awake")
        #expect(card.accessibilityValue() as? Bool == false)
        #expect(card.accessibilityChildren()?.isEmpty == true)
        #expect(card.isAccessibilityEnabled())
        #expect(card.acceptsFirstResponder)
        #expect(card.accessibilityPerformPress())
        #expect(card.fillColor == CardColor.accentFill)
        #expect(card.accessibilityValue() as? Bool == true)
        #expect(card.layer?.borderWidth == 1)
        card.keyDown(with: try key(" "))
        card.keyDown(with: try key("\r"))
        #expect(changes == [true, false, true])
        #expect(height == (layout == .compact ? 38 : 76))
        #expect(card.fittingSize.height == height)
    }

    @Test(arguments: [StateCardView.Layout.prominent, .compact])
    func mouseUpInsideCommitsAndOutsideCancels(layout: StateCardView.Layout) throws {
        var changes: [Bool] = []
        let card = StateCardView(title: "Presence", symbol: "person", layout: layout) { changes.append($0) }
        let window = hostWindow(card)
        func click(_ type: NSEvent.EventType, _ location: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                            timestamp: 0, windowNumber: window.windowNumber,
                                            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let points = try clickPoints(card, in: window)
        let down = try click(.leftMouseDown, points.inside)
        try queueRelease(try click(.leftMouseUp, points.inside), in: window)
        card.mouseDown(with: down)
        #expect(takeQueuedRelease(in: window) == nil)
        #expect(changes == [true])
        #expect(card.isOn)
        try queueRelease(try click(.leftMouseUp, points.outside), in: window)
        card.mouseDown(with: down)
        #expect(takeQueuedRelease(in: window) == nil)
        #expect(changes == [true])
        #expect(card.isOn)
    }

    private func expectHorizontalContent(_ card: StateCardView) throws {
        let content = try #require(card.subviews.compactMap { $0 as? NSStackView }.first)
        let icon = try #require(content.arrangedSubviews.first as? NSImageView)
        let title = try #require(content.arrangedSubviews.last as? NSTextField)
        // Auto Layout positions alignment rects. A label's frame extends past its alignment rect by its
        // text cell padding (alignmentRectInsets), so the visible text spans the alignment rect.
        let iconFrame = card.convert(icon.alignmentRect(forFrame: icon.frame), from: icon.superview)
        let titleFrame = card.convert(title.alignmentRect(forFrame: title.frame), from: title.superview)
        let titleViewFrame = card.convert(title.bounds, from: title)
        #expect(content.orientation == .horizontal)
        #expect(content.alignment == .centerY)
        #expect(title.maximumNumberOfLines == 1)
        #expect(iconFrame.maxX < titleFrame.minX)
        // Centering the 14 pt icon and a label of different height parity in the 38 pt card yields
        // half-point origins that AppKit rounds onto its layout grid; half a point is that rounding.
        #expect(abs(iconFrame.midY - titleFrame.midY) <= 0.5)
        #expect(abs(iconFrame.midY - card.bounds.midY) <= 0.5)
        #expect(title.fittingSize.width <= title.frame.width + 0.5)
        let geometry = "title alignment \(titleFrame), frame \(titleViewFrame), "
            + "insets \(title.alignmentRectInsets), card \(card.bounds)"
        #expect(titleFrame.maxX <= card.bounds.maxX - MenuStyle.gap + 0.5, "\(geometry)")
        #expect(titleViewFrame.maxX <= card.bounds.maxX)
        #expect(card.frame.height == 38)
        #expect(card.fittingSize.height == 38)
    }

    @Test func menuFitsCompactCardsAtPopoverWidth() throws {
        let menu = VesilaMenuView(state: VesilaState(), now: .now,
                                  loginItemStatus: .notRegistered) { _ in }
        let window = NSWindow(contentRect: menu.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = menu
        menu.layoutSubtreeIfNeeded()
        func cards(in view: NSView) -> [StateCardView] {
            if let card = view as? StateCardView { return [card] }
            return view.subviews.flatMap { cards(in: $0) }
        }
        let allCards = cards(in: menu)
        let presence = try #require(allCards.first { $0.accessibilityLabel() == "Presence" })
        let locked = try #require(allCards.first { $0.accessibilityLabel() == "Stay Active When Locked" })
        let launch = try #require(allCards.first { $0.accessibilityLabel() == "Start on Launch" })
        let awake = try #require(allCards.first { $0.accessibilityLabel() == "System Awake" })
        #expect(menu.frame.width == MenuStyle.width)
        #expect(presence.frame.height == locked.frame.height)
        #expect(locked.frame.width >= presence.frame.width)
        let presenceFrame = menu.convert(presence.bounds, from: presence)
        let lockedFrame = menu.convert(locked.bounds, from: locked)
        #expect(abs(presenceFrame.midY - lockedFrame.midY) < 0.5)
        #expect(abs(lockedFrame.minX - presenceFrame.maxX - MenuStyle.childGap) < 0.5)
        #expect(abs(presence.frame.width + locked.frame.width - 270) < 0.5)
        #expect(awake.frame.height == 76)
        for card in [presence, locked, launch] {
            try expectHorizontalContent(card)
        }
    }

    @Test func launchCardPreservesApprovalHelp() {
        let card = StartOnLaunchRowView { _ in }
        #expect(card.fittingSize.height == 38)
        card.update(status: .requiresApproval)
        #expect(card.toolTip == "Approval required in System Settings > General > Login Items.")
        #expect(card.accessibilityHelp() == card.toolTip)
    }
}
