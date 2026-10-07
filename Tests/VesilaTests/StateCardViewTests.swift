import AppKit
import Testing
@testable import Vesila

@Suite("Clickable state cards")
@MainActor
struct StateCardViewTests {
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = card
        card.frame = NSRect(x: 0, y: 0, width: 160, height: 100)
        card.update(isOn: storedChoice, isEnabled: false)
        #expect(!card.isOn)
        #expect(!card.acceptsFirstResponder)
        #expect(!card.isAccessibilityEnabled())
        #expect(card.accessibilityHelp() == "Requires System Awake")
        #expect(card.fillColor == CardColor.disabledSurface)
        #expect(!card.accessibilityPerformPress())
        card.keyDown(with: try key(" "))
        card.keyDown(with: try key("\r"))
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        window.postEvent(up, atStart: true)
        card.mouseEntered(with: click)
        card.mouseDown(with: click)
        // Disabled input leaves the queued mouse-up untouched; drain it before the next test.
        _ = window.nextEvent(matching: [.leftMouseUp], until: .now, inMode: .default, dequeue: true)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = card
        card.frame = NSRect(x: 0, y: 0, width: 160, height: 100)
        func click(_ type: NSEvent.EventType, _ location: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                            timestamp: 0, windowNumber: window.windowNumber,
                                            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let down = try click(.leftMouseDown, NSPoint(x: 20, y: 20))
        window.postEvent(try click(.leftMouseUp, NSPoint(x: 20, y: 20)), atStart: true)
        card.mouseDown(with: down)
        #expect(changes == [true])
        window.postEvent(try click(.leftMouseUp, NSPoint(x: -20, y: -20)), atStart: true)
        card.mouseDown(with: down)
        #expect(changes == [true])
    }

    private func expectHorizontalContent(_ card: StateCardView) throws {
        let content = try #require(card.subviews.compactMap { $0 as? NSStackView }.first)
        let icon = try #require(content.arrangedSubviews.first as? NSImageView)
        let title = try #require(content.arrangedSubviews.last as? NSTextField)
        let iconFrame = card.convert(icon.bounds, from: icon)
        let titleFrame = card.convert(title.bounds, from: title)
        #expect(content.orientation == .horizontal)
        #expect(content.alignment == .centerY)
        #expect(title.maximumNumberOfLines == 1)
        #expect(iconFrame.maxX < titleFrame.minX)
        // Centering the 14 pt icon and a label of different height parity in the 38 pt card yields
        // half-point origins that AppKit rounds onto its layout grid; half a point is that rounding.
        #expect(abs(iconFrame.midY - titleFrame.midY) <= 0.5)
        #expect(abs(iconFrame.midY - card.bounds.midY) <= 0.5)
        #expect(title.fittingSize.width <= title.frame.width + 0.5)
        #expect(titleFrame.maxX <= card.bounds.maxX - MenuStyle.gap + 0.5)
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
