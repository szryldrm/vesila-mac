import Foundation

extension Timer {
    /// Every timer in Vesila is created through this, for two reasons:
    /// - It is added to the main run loop in `.common` modes. The default mode is paused while a
    ///   menu is tracking, which would freeze the menu's countdown and delay expiration.
    /// - It never outlives `owner`: once the owner is gone, the next fire invalidates the timer.
    @MainActor
    static func scheduledOnMain<Owner: AnyObject & Sendable>(
        interval: TimeInterval,
        repeats: Bool,
        tolerance: TimeInterval = 0,
        owner: Owner,
        _ block: @escaping @MainActor @Sendable (Owner) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak owner] timer in
            guard let owner else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                block(owner)
            }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
