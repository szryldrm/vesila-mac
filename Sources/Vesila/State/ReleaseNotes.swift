import Foundation

/// Release notes stay in the app bundle; loading failures simply suppress the window.
struct ReleaseNotes: Decodable, Equatable {
    let version: String
    let notes: [String]

    static func decode(_ data: Data?) -> [ReleaseNotes] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ReleaseNotes].self, from: data)) ?? []
    }

    static func loadBundled() -> [ReleaseNotes] {
        guard let url = Bundle.module.url(forResource: "ReleaseNotes", withExtension: "json") else { return [] }
        return decode(try? Data(contentsOf: url))
    }

    static func entriesToShow(
        previousVersion: String?,
        currentVersion: String,
        isOnboardingCompleted: Bool,
        entries: [ReleaseNotes]
    ) -> [ReleaseNotes] {
        guard currentVersion != "dev", isOnboardingCompleted else { return [] }
        guard let previousVersion else {
            return entries.filter { $0.version == currentVersion }
        }
        guard previousVersion.compare(currentVersion, options: .numeric) == .orderedAscending else { return [] }
        return entries.filter {
            previousVersion.compare($0.version, options: .numeric) == .orderedAscending &&
            $0.version.compare(currentVersion, options: .numeric) != .orderedDescending
        }.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
}
