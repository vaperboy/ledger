import Foundation
import Security
import Simulation

/// Keeps the gift wallet (used serials, the gift's end, the newest date seen) in two places, UserDefaults and the keychain, and returns the
/// union of both. Wiping app data or reinstalling then neither frees a used code nor drops a redeemed gift. Gift codes are for AltStore builds;
/// App Store builds should use StoreKit offer codes.
enum GiftVault {
    private static let defaultsKey = "ledger.giftWallet"
    private static let legacyExpires = "ledger.giftExpires"
    private static let legacySerials = "ledger.giftSerials"
    private static let service = "ledger.giftWallet"

    static func load() -> GiftWallet {
        var w = GiftWallet()
        if let d = UserDefaults.standard.data(forKey: defaultsKey), let x = try? JSONDecoder().decode(GiftWallet.self, from: d) { w = w.merged(x) }
        if let d = keychainRead(), let x = try? JSONDecoder().decode(GiftWallet.self, from: d) { w = w.merged(x) }
        // The two keys of the first version.
        var old = GiftWallet()
        old.serials = UserDefaults.standard.array(forKey: legacySerials) as? [Int] ?? []
        let t: Double = UserDefaults.standard.double(forKey: legacyExpires)
        if t > 0 { old.expires = Date(timeIntervalSince1970: t) }
        return w.merged(old)
    }

    static func save(_ w: GiftWallet) {
        guard let d = try? JSONEncoder().encode(w) else { return }
        UserDefaults.standard.set(d, forKey: defaultsKey)
        keychainWrite(d)
    }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "wallet"]
    }

    private static func keychainRead() -> Data? {
        var q: [String: Any] = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func keychainWrite(_ d: Data) {
        let status: OSStatus = SecItemUpdate(query() as CFDictionary, [kSecValueData as String: d] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var q: [String: Any] = query()
        q[kSecValueData as String] = d
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(q as CFDictionary, nil)
    }
}
