import Foundation

/// Cloud backup of the save (Ledger Plus/Pro). iCloud needs the iCloud capability and a container in the app's
/// entitlements, which have to be added to the project. Until then `iCloudReady` stays false and the screen shows a disabled state.
enum CloudConfig {
    /// Set to true once the iCloud capability (key-value storage and iCloud Documents) is in the entitlements and provisioning profile.
    static let iCloudReady: Bool = false
}

enum CloudBackup {
    private static let key = "ledger.backup.text"
    private static let stampKey = "ledger.backup.date"
    /// Saves up to this many bytes go to key-value storage (its limit is 1 MB in all); larger ones to iCloud Drive.
    private static let smallLimit = 700_000
    private static let fileName = "Ledger backup.json"

    /// When the last backup was made on this account, if any.
    static var lastBackup: Date? {
        guard CloudConfig.iCloudReady else { return nil }
        let t: Double = NSUbiquitousKeyValueStore.default.double(forKey: stampKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private static func driveFile() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(fileName)
    }

    /// Returns a short problem in words, or nil when the backup was written.
    static func back(up text: String) -> String? {
        guard CloudConfig.iCloudReady else { return "Needs iCloud set-up" }
        let kv = NSUbiquitousKeyValueStore.default
        if text.utf8.count <= smallLimit {
            kv.set(text, forKey: key)
        } else {
            guard let url = driveFile() else { return "iCloud Drive is off for Ledger" }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch { return "The backup could not be written" }
            kv.removeObject(forKey: key)
        }
        kv.set(Date().timeIntervalSince1970, forKey: stampKey)
        kv.synchronize()
        return nil
    }

    /// The backed-up save text, or nil when there is none.
    static func restoreText() -> String? {
        guard CloudConfig.iCloudReady else { return nil }
        if let t = NSUbiquitousKeyValueStore.default.string(forKey: key) { return t }
        guard let url = driveFile() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
