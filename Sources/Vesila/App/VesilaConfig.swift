import Foundation
import OSLog

enum VesilaConfig {
    static let appName = "Vesila"
    /// Stamped into Info.plist from the VERSION file by Scripts/build_app.sh.
    /// "dev" when running outside an app bundle (`swift run`).
    static let version: String = {
        guard let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !value.isEmpty else { return "dev" }
        return value
    }()
    static let tagline = "Stay present while you read, think, or review."
    static let githubURL = URL(string: "https://github.com/szryldrm/vesila-mac")
}

extension Logger {
    static let vesila = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sezeryildirim.vesila", category: "Vesila")
}
