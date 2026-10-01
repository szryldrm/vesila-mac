import AppKit
import Testing
@testable import Vesila

@Suite("Stay Active When Locked row")
@MainActor
struct StayActiveWhenLockedRowTests {
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @Test(arguments: [true, false])
    func disabledRowShowsStoredChoiceAndRejectsInput(storedChoice: Bool) throws {
        var changes: [Bool] = []
        let row = StayActiveWhenLockedRowView { changes.append($0) }
        row.update(isOn: storedChoice, isAvailable: false)
        let views = descendants(of: row)
        let toggle = try #require(views.compactMap { $0 as? VesilaToggleControl }.first)
        let hint = try #require(views.compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "Requires System Awake" })
        #expect(toggle.isOn == storedChoice)
        #expect(!toggle.isEnabled)
        #expect(!hint.isHidden)
        #expect(row.toolTip == "Requires System Awake")
        #expect(toggle.accessibilityHelp() == "Requires System Awake")
        #expect(row.fillColor == CardColor.surface)
        #expect(!toggle.accessibilityPerformPress())
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        toggle.mouseDown(with: click)
        #expect(toggle.isOn == storedChoice)
        #expect(changes.isEmpty)
    }

    @Test func reenablingRestoresInteractionWithoutChangingHeight() throws {
        var changes: [Bool] = []
        let row = StayActiveWhenLockedRowView { changes.append($0) }
        row.update(isOn: true, isAvailable: false)
        let disabledHeight = row.fittingSize.height
        let views = descendants(of: row)
        let toggle = try #require(views.compactMap { $0 as? VesilaToggleControl }.first)
        let hint = try #require(views.compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "Requires System Awake" })
        row.update(isOn: true, isAvailable: true)
        #expect(toggle.isOn)
        #expect(toggle.isEnabled)
        #expect(hint.isHidden)
        #expect(row.toolTip == nil)
        #expect(toggle.accessibilityHelp() == nil)
        #expect(row.fillColor == CardColor.accentFillSubtle)
        #expect(disabledHeight == 48)
        #expect(row.fittingSize.height == disabledHeight)
        #expect(toggle.accessibilityPerformPress())
        #expect(changes == [false])
        row.update(isOn: false, isAvailable: true)
        #expect(row.fillColor == CardColor.surface)
        #expect(row.fittingSize.height == disabledHeight)
    }
}
