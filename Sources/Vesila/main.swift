import AppKit

// Top-level code runs on the main thread; this makes that explicit to the compiler.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    // NSApplication holds its delegate weakly.
    withExtendedLifetime(delegate) {
        app.run()
    }
}
