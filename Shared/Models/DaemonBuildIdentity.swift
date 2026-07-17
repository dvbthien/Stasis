import CryptoKit
import Darwin
import Foundation

/// Identifies a daemon build by hashing its executable. The daemon reports the
/// hash of the binary it was spawned from; the app hashes the daemon bundled
/// inside its own bundle. A mismatch means launchd is still running an older
/// build and the registration should be repaired.
enum DaemonBuildIdentity {
    static func executableHash(at url: URL) -> String? {
        // Memory-mapped so the binary is never copied into the heap; pages
        // are read on demand while hashing and stay evictable.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Hash of the executable backing the current process.
    static func currentExecutableHash() -> String? {
        var capacity = UInt32(PATH_MAX)
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        if _NSGetExecutablePath(&buffer, &capacity) != 0 {
            buffer = [CChar](repeating: 0, count: Int(capacity))
            guard _NSGetExecutablePath(&buffer, &capacity) == 0 else { return nil }
        }
        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let url = URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self))
            .resolvingSymlinksInPath()
        return executableHash(at: url)
    }
}
