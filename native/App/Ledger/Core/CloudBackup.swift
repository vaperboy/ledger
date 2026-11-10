import Foundation

enum CloudConfig {
    static let iCloudReady: Bool = false
}

enum CloudBackup {
    private static let key = "ledger.backup.text"
    private static let stampKey = "ledger.backup.date"
    private static let smallLimit = 700_000
    private static let fileName = "Ledger backup.json"

    static var lastBackup: Date? {
        guard CloudConfig.iCloudReady else { return nil }
        let t: Double = NSUbiquitousKeyValueStore.default.double(forKey: stampKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private static func driveFile() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(fileName)
    }

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

    static func restoreText() -> String? {
        guard CloudConfig.iCloudReady else { return nil }
        if let t = NSUbiquitousKeyValueStore.default.string(forKey: key) { return t }
        guard let url = driveFile() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
