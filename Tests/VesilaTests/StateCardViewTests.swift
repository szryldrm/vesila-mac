import AppKit
import Testing
@testable import Vesila

/// Hosts a card and answers the press tracking that pulls drags and the release from its window.
/// Tests must not feed that loop through the application's event queue: posting an event stops the
/// main run loop (that is how AppKit wakes a waiting event loop), and Swift Testing's async entry
/// point exits the process, with status 0 and no summary, once its main run loop stops. This window
/// answers from a fixed script instead, and with nil once it runs out, so tracking ends, never waits.
private final class ScriptedEventWindow: NSWindow {
    var script: [NSEvent] = []
    /// Runs before each event the card asks for, while the card shows the effect of the previous one.
    var onRequest: () -> Void = {}
    private(set) var requests = 0

    convenience init(hosting card: StateCardView) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
                  styleMask: .borderless, backing: .buffered, defer: false)
        contentView = card
    }

    override func nextEvent(matching mask: NSEvent.EventTypeMask) -> NSEvent? {
        scriptedEvent(matching: mask, dequeue: true)
    }

    override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                            inMode mode: RunLoop.Mode, dequeue: Bool) -> NSEvent? {
        scriptedEvent(matching: mask, dequeue: dequeue)
    }

    private func scriptedEvent(matching mask: NSEvent.EventTypeMask, dequeue: Bool) -> NSEvent? {
        requests += 1
        onRequest()
        guard let index = script.firstIndex(where: { mask.contains(NSEvent.EventTypeMask(type: $0.type)) }) else {
            return nil
        }
        return dequeue ? script.remove(at: index) : script[index]
    }
}

/// What a card looks like: its layer tree rendered to pixels. Comparing snapshots checks what the user
/// sees, whichever of the layers AppKit and the card draw with carries the change.
private struct Snapshot: Equatable, CustomStringConvertible {
    let pixels: [UInt8]
    var description: String { "\(pixels.count / 4)-pixel snapshot" }
}

@Suite("Clickable state cards")
@MainActor
struct StateCardViewTests {
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

    private func mouse(_ type: NSEvent.EventType, at location: NSPoint, in window: NSWindow) throws -> NSEvent {
        if type == .mouseEntered {
            return try #require(NSEvent.enterExitEvent(with: type, location: location, modifierFlags: [],
                                                       timestamp: 0, windowNumber: window.windowNumber,
                                                       context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        }
        return try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                               timestamp: 0, windowNumber: window.windowNumber,
                                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func key(_ characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: 0))
    }

    private func snapshot(_ card: StateCardView) throws -> Snapshot {
        let layer = try #require(card.layer)
        let width = Int(card.bounds.width.rounded(.up)), height = Int(card.bounds.height.rounded(.up))
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: sRGB,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        layer.render(in: context)
        let data = try #require(context.data)
        return Snapshot(pixels: Array(UnsafeRawBufferPointer(start: data, count: width * height * 4)))
    }

    private func descendants<View: NSView>(of view: NSView, as _: View.Type) -> [View] {
        view.subviews.flatMap { subview in
            [subview as? View].compactMap { $0 } + descendants(of: subview, as: View.self)
        }
    }

    @Test(arguments: [true, false], [StateCardView.Layout.prominent, .compact])
    func disabledRejectsEveryActivationAndExposesRequirement(storedChoice: Bool, layout: StateCardView.Layout) throws {
        var changes: [Bool] = []
        let card = StateCardView(title: "Presence", symbol: "person", layout: layout, requirement: "Requires System Awake") {
            changes.append($0)
        }
        let window = ScriptedEventWindow(hosting: card)
        card.update(isOn: storedChoice, isEnabled: false)
        // Reads as off and unavailable, with the requirement as its help, whatever the stored choice.
        #expect(!card.isOn)
        #expect(card.accessibilityValue() as? Bool == false)
        #expect(!card.isAccessibilityEnabled())
        #expect(!card.acceptsFirstResponder)
        #expect(card.toolTip == "Requires System Awake")
        #expect(card.accessibilityHelp() == "Requires System Awake")
        // Looks disabled: the dimmed surface, no accent border, and dimmed icon and title.
        #expect(card.fillColor == CardColor.disabledSurface)
        #expect(card.layer?.borderWidth == 0)
        let icon = try #require(descendants(of: card, as: NSImageView.self).first)
        let title = try #require(descendants(of: card, as: NSTextField.self).first)
        #expect(icon.contentTintColor == .tertiaryLabelColor)
        #expect(title.textColor == .tertiaryLabelColor)

        #expect(!card.accessibilityPerformPress())
        card.keyDown(with: try key(" "))
        card.keyDown(with: try key("\r"))
        // Point at and press the card's center, so the rejection cannot come from missing it. The script
        // holds a release there, which the card would commit if it started tracking the press.
        let center = try clickPoints(card, in: window).inside
        let resting = try snapshot(card)
        card.mouseEntered(with: try mouse(.mouseEntered, at: center, in: window))
        #expect(try snapshot(card) == resting, "pointer entry shows no hover feedback")
        window.script = [try mouse(.leftMouseUp, at: center, in: window)]
        card.mouseDown(with: try mouse(.leftMouseDown, at: center, in: window))
        #expect(window.requests == 0, "a disabled card never starts tracking the press")
        #expect(window.script.count == 1)
        #expect(try snapshot(card) == resting, "a press shows no feedback")
        #expect(changes.isEmpty)
        #expect(!card.isOn)

        // Only the disabled state suppresses feedback: once enabled, the same pointer entry shows it,
        // so the comparisons above could see feedback had there been any.
        card.update(isOn: storedChoice)
        #expect(icon.contentTintColor == .labelColor)
        #expect(title.textColor == .labelColor)
        let enabledResting = try snapshot(card)
        card.mouseEntered(with: try mouse(.mouseEntered, at: center, in: window))
        #expect(try snapshot(card) != enabledResting, "pointer entry shows hover feedback once enabled")
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
        let window = ScriptedEventWindow(hosting: card)
        let points = try clickPoints(card, in: window)
        let down = try mouse(.leftMouseDown, at: points.inside, in: window)

        // Dragging out drops the press feedback and dragging back restores it; releasing outside cancels,
        // and tracking ends with the release.
        let resting = try snapshot(card)
        var pressedWhenAsked: [Bool] = []
        window.onRequest = { pressedWhenAsked.append((try? self.snapshot(card)) != resting) }
        window.script = [try mouse(.leftMouseDragged, at: points.outside, in: window),
                         try mouse(.leftMouseDragged, at: points.inside, in: window),
                         try mouse(.leftMouseUp, at: points.outside, in: window)]
        card.mouseDown(with: down)
        #expect(window.script.isEmpty)
        #expect(pressedWhenAsked == [true, false, true])
        #expect(try snapshot(card) == resting, "feedback clears and nothing changes")
        #expect(changes.isEmpty)
        #expect(!card.isOn)

        // Releasing inside commits; releasing outside leaves the committed state alone.
        window.onRequest = {}
        window.script = [try mouse(.leftMouseUp, at: points.inside, in: window)]
        card.mouseDown(with: down)
        #expect(window.script.isEmpty)
        #expect(changes == [true])
        #expect(card.isOn)
        window.script = [try mouse(.leftMouseUp, at: points.outside, in: window)]
        card.mouseDown(with: down)
        #expect(window.script.isEmpty)
        #expect(changes == [true])
        #expect(card.isOn)
        window.script = [try mouse(.leftMouseUp, at: points.inside, in: window)]
        card.mouseDown(with: down)
        #expect(changes == [true, false])
        #expect(!card.isOn)
    }

    /// A compact card shows its icon and one-line title side by side, vertically centered, inside the
    /// card's horizontal insets, with the title wide enough for its text. Auto Layout positions alignment
    /// rects: a label's frame adds text cell padding and a symbol image view's frame the glyph's
    /// overhang, so placement is measured on alignment rects and containment on frames.
    private func expectCompactContent(_ card: StateCardView, pixel: CGFloat) throws {
        let icon = try #require(descendants(of: card, as: NSImageView.self).first)
        let title = try #require(descendants(of: card, as: NSTextField.self).first)
        let titleCell = try #require(title.cell)
        let iconRect = card.convert(icon.alignmentRect(forFrame: icon.frame), from: icon.superview)
        let titleRect = card.convert(title.alignmentRect(forFrame: title.frame), from: title.superview)
        let geometry = "\(title.stringValue): icon \(iconRect), title \(titleRect), "
            + "title frame \(card.convert(title.bounds, from: title)), card \(card.bounds)"
        #expect(card.bounds.height == 38, "\(geometry)")
        #expect(iconRect.minX == MenuStyle.gap, "\(geometry)")
        #expect(iconRect.maxX < titleRect.minX, "\(geometry)")
        #expect(titleRect.maxX <= card.bounds.maxX - MenuStyle.gap, "\(geometry)")
        #expect(card.bounds.contains(card.convert(icon.bounds, from: icon)), "\(geometry)")
        #expect(card.bounds.contains(card.convert(title.bounds, from: title)), "\(geometry)")
        #expect(title.maximumNumberOfLines == 1)
        #expect(titleCell.cellSize.width <= title.bounds.width, "\(geometry)")
        // Centering items of different heights can fall between two pixels; AppKit rounds each frame to
        // the backing pixel grid, so a centered item may land up to one pixel from the exact center.
        #expect(abs(iconRect.midY - titleRect.midY) <= pixel, "\(geometry)")
        #expect(abs(iconRect.midY - card.bounds.midY) <= pixel, "\(geometry)")
        #expect(abs(titleRect.midY - card.bounds.midY) <= pixel, "\(geometry)")
    }

    @Test func menuFitsCompactCardsAtPopoverWidth() throws {
        let menu = VesilaMenuView(state: VesilaState(), now: .now,
                                  loginItemStatus: .notRegistered) { _ in }
        let window = NSWindow(contentRect: menu.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = menu
        menu.layoutSubtreeIfNeeded()
        let cards = descendants(of: menu, as: StateCardView.self)
        let presence = try #require(cards.first { $0.accessibilityLabel() == "Presence" })
        let locked = try #require(cards.first { $0.accessibilityLabel() == "Stay Active When Locked" })
        let launch = try #require(cards.first { $0.accessibilityLabel() == "Start on Launch" })
        let awake = try #require(cards.first { $0.accessibilityLabel() == "System Awake" })
        func frame(_ card: StateCardView) -> NSRect { menu.convert(card.bounds, from: card) }

        #expect(menu.frame.width == MenuStyle.width)
        let contentArea = menu.bounds.insetBy(dx: MenuStyle.inset, dy: 0)
        for card in [awake, presence, locked, launch] {
            #expect(contentArea.contains(frame(card)), "\(card.accessibilityLabel() ?? "") at \(frame(card))")
        }
        // System Awake stays the prominent card; Start on Launch spans the same width, compact.
        #expect(frame(awake).height == 76)
        #expect(frame(launch).minX == frame(awake).minX)
        #expect(frame(launch).maxX == frame(awake).maxX)
        // Presence and Stay Active When Locked share one row across that width: Presence at its natural
        // width, the longer label taking the rest, one row gap apart.
        #expect(frame(presence).minY == frame(locked).minY)
        #expect(frame(presence).height == frame(locked).height)
        #expect(frame(presence).minX == frame(awake).minX)
        #expect(frame(locked).maxX == frame(awake).maxX)
        #expect(frame(locked).minX - frame(presence).maxX == MenuStyle.childGap)
        #expect(presence.frame.width == presence.intrinsicContentSize.width)
        #expect(locked.frame.width >= locked.intrinsicContentSize.width)
        for card in [presence, locked, launch] {
            try expectCompactContent(card, pixel: 1 / window.backingScaleFactor)
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
