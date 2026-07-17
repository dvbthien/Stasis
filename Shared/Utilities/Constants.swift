/// Project-wide constants shared across the app, the charging daemon, and the
/// SMC reader XPC service. Add new groups here as nested enums instead of
/// scattering string literals.
enum Constants {
    /// Bundle/service identifiers. Change them here instead of hunting down
    /// string literals.
    ///
    /// Note: the launchd plist (`StasisDaemon/com.srimanachanta.stasis-daemon.plist`)
    /// and the `PRODUCT_BUNDLE_IDENTIFIER` build settings must be kept in sync
    /// by hand — they cannot reference Swift constants.
    enum Identity {
        /// The app's bundle identifier, its log subsystem, and the
        /// code-signing identity the daemon requires of XPC clients.
        static let app = "com.srimanachanta.stasis"

        /// Launchd label, mach service name, bundle identifier, and log
        /// subsystem of the privileged charging daemon. This is also the
        /// Background Task Management identity users approved — changing it
        /// orphans installed daemons and forces re-approval.
        static let daemon = "com.srimanachanta.stasis-daemon"

        /// Name of the daemon's launchd plist embedded in the app bundle.
        static let daemonPlistName = daemon + ".plist"

        /// Location of the daemon executable inside the app bundle, relative
        /// to the bundle root. Must match `BundleProgram` in the launchd plist.
        static let daemonExecutableBundlePath = "Contents/Library/LaunchDaemons/StasisDaemon"

        /// Bundle identifier of the SMC reader XPC service — the name the app
        /// connects to — and its log subsystem.
        static let smcReaderService = app + ".StasisHelper"
    }
}
