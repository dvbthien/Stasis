import os.log

extension Logger {
    /// Shared factory for all of the app's loggers — keeps the subsystem
    /// string in exactly one place instead of repeated (and occasionally
    /// mistyped) across every service/view model.
    static func stasis(_ category: String) -> Logger {
        Logger(subsystem: Constants.Identity.app, category: category)
    }
}
