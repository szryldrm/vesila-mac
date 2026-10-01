import AppKit
import OSLog

/// The four status icons. Cup fill = Presence, steam = System Awake.
/// Stay Active When Locked has no icon of its own.
@MainActor
enum VesilaIconLibrary {
    private static var cache: [String: NSImage] = [:]

    static func statusImage(for features: MainFeatures) -> NSImage {
        switch (features.presence, features.systemAwake) {
        case (false, false): return templateImage(named: "vesila-idle")
        case (true, false): return templateImage(named: "vesila-presence")
        case (false, true): return templateImage(named: "vesila-awake")
        case (true, true): return templateImage(named: "vesila-both")
        }
    }

    private static func templateImage(named name: String) -> NSImage {
        if let cached = cache[name] {
            return cached
        }
        let image: NSImage
        if let url = Bundle.module.url(forResource: name, withExtension: "svg"),
           let svg = NSImage(contentsOf: url) {
            svg.size = NSSize(width: 24, height: 24)
            image = svg
        } else {
            // Never leave the status item blank: it is the only way to reach Vesila.
            Logger.vesila.error("Missing status icon \(name, privacy: .public).svg; using a fallback symbol.")
            image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: VesilaConfig.appName)
                ?? NSImage(size: NSSize(width: 18, height: 18))
        }
        image.isTemplate = true
        cache[name] = image
        return image
    }
}
