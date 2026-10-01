import Foundation
import Testing
@testable import Vesila

struct UpdateConfigurationTests {
    private let appURL = URL(fileURLWithPath: "/Applications/Vesila.app")
    private var validInfo: [String: Any] {
        [
            "CFBundleShortVersionString": "1.0.0",
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString()
        ]
    }

    @Test func packagedReleaseCanStart() {
        #expect(UpdateConfiguration.unavailableReason(bundleURL: appURL, info: validInfo) == nil)
    }

    @Test func nonBundleRunCannotStart() {
        #expect(UpdateConfiguration.unavailableReason(
            bundleURL: URL(fileURLWithPath: "/tmp/Vesila"), info: validInfo
        ) != nil)
    }

    @Test(arguments: ["", "dev"])
    func developmentVersionCannotStart(version: String) {
        var info = validInfo
        info["CFBundleShortVersionString"] = version
        #expect(UpdateConfiguration.unavailableReason(bundleURL: appURL, info: info) != nil)
    }

    @Test(arguments: ["CFBundleShortVersionString", "SUFeedURL", "SUPublicEDKey"])
    func missingConfigurationCannotStart(key: String) {
        var info = validInfo
        info.removeValue(forKey: key)
        #expect(UpdateConfiguration.unavailableReason(bundleURL: appURL, info: info) != nil)
    }

    @Test(arguments: ["http://example.com/feed", "https:", "invalid"])
    func invalidFeedCannotStart(feed: String) {
        var info = validInfo
        info["SUFeedURL"] = feed
        #expect(UpdateConfiguration.unavailableReason(bundleURL: appURL, info: info) != nil)
    }

    @Test(arguments: ["PLACEHOLDER", "", Data(repeating: 1, count: 31).base64EncodedString()])
    func invalidKeyCannotStart(key: String) {
        var info = validInfo
        info["SUPublicEDKey"] = key
        #expect(UpdateConfiguration.unavailableReason(bundleURL: appURL, info: info) != nil)
    }

    @Test func packagingUsesSafeUpdaterDefaults() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Packaging/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let feed = try #require(info["SUFeedURL"] as? String)
        #expect(URL(string: feed)?.scheme == "https")
        #expect(feed == "https://github.com/szryldrm/vesila-mac/releases/latest/download/appcast.xml")
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86400)
        #expect(info["SUEnableSystemProfiling"] == nil)
        #expect(info["LSUIElement"] as? Bool == true)
        #expect(info["LSMinimumSystemVersion"] as? String == "14.0")
    }
}
