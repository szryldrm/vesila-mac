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

    @Test(arguments: [true, false])
    func disabledRejectsEveryActivationAndExposesRequirement(storedChoice: Bool) throws {
        var changes: [Bool] = []
        let card = StateCardView(title: "Presence", symbol: "person", requirement: "Requires System Awake") {
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
        #expect(card.layer?.sublayers?.last?.opacity == 0)
    }

    @Test func enabledTogglesAndKeepsHeightAndAccessibleState() throws {
        var changes: [Bool] = []
        let card = StateCardView(title: "System Awake", symbol: "sun.max") { changes.append($0) }
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
        #expect(height == 76)
        #expect(card.fittingSize.height == height)
    }

    @Test func mouseUpInsideCommitsAndOutsideCancels() throws {
        var changes: [Bool] = []
        let card = StateCardView(title: "Presence", symbol: "person") { changes.append($0) }
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

    @Test func launchCardPreservesApprovalHelp() {
        let card = StartOnLaunchRowView { _ in }
        card.update(status: .requiresApproval)
        #expect(card.toolTip == "Approval required in System Settings > General > Login Items.")
        #expect(card.accessibilityHelp() == card.toolTip)
    }
}
