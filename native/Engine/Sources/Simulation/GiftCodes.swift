import Foundation

/// Offline gift codes that open the full game for a period. A code is 10 bytes: kind, serial, and a keyed hash of both, written as
/// 16 base-32 characters. The app only checks the hash and remembers which serials it has used on this device; sharing is stopped
/// by trust, not by a server. For AltStore builds only: App Store builds should hand out StoreKit offer codes instead.
public enum GiftCodes {
    public struct Gift: Equatable, Sendable {
        public var serial: Int
        public var days: Int
        public var title: String
    }

    /// kind byte: what the code gives.
    static let kinds: [UInt8: (days: Int, title: String)] = [1: (365, "A year of the full game"), 2: (3650, "The full game, for good")]
    private static let secret: [UInt8] = Array("ledger.gift.v1.e5d36db96440fa8dcaacb8ae7ce54f8d".utf8)
    private static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Makes the code text for a kind and serial (used to print codes; the app never makes codes).
    public static func make(kind: UInt8, serial: Int) -> String {
        let head: [UInt8] = [kind, UInt8((serial >> 8) & 255), UInt8(serial & 255)]
        let mac: [UInt8] = Array(HMAC.sha256(key: secret, message: head).prefix(7))
        let text: String = String(encode(head + mac))
        return stride(from: 0, to: 16, by: 4).map { (i: Int) -> String in String(text.dropFirst(i).prefix(4)) }.joined(separator: "-")
    }

    /// The gift in a typed code, or nil when it is not a genuine code. Case, dashes, spaces and look-alike letters are forgiven.
    public static func check(_ raw: String) -> Gift? {
        var chars: [Character] = []
        for c in raw.uppercased() where c != "-" && c != " " {
            switch c {
            case "O": chars.append("0")
            case "I", "L": chars.append("1")
            default: chars.append(c)
            }
        }
        guard chars.count == 16, let bytes = decode(chars), bytes.count == 10 else { return nil }
        let head: [UInt8] = Array(bytes.prefix(3))
        let mac: [UInt8] = Array(HMAC.sha256(key: secret, message: head).prefix(7))
        guard Array(bytes.suffix(7)) == mac, let k = kinds[head[0]] else { return nil }
        return Gift(serial: (Int(head[1]) << 8) | Int(head[2]), days: k.days, title: k.title)
    }

    private static func encode(_ bytes: [UInt8]) -> [Character] {
        var out: [Character] = []
        var acc: UInt32 = 0
        var bits = 0
        for b in bytes {
            acc = (acc << 8) | UInt32(b); bits += 8
            while bits >= 5 { bits -= 5; out.append(alphabet[Int((acc >> UInt32(bits)) & 31)]) }
        }
        if bits > 0 { out.append(alphabet[Int((acc << UInt32(5 - bits)) & 31)]) }
        return out
    }

    private static func decode(_ chars: [Character]) -> [UInt8]? {
        var out: [UInt8] = []
        var acc: UInt32 = 0
        var bits = 0
        for c in chars {
            guard let v = alphabet.firstIndex(of: c) else { return nil }
            acc = (acc << 5) | UInt32(v); bits += 5
            if bits >= 8 { bits -= 8; out.append(UInt8((acc >> UInt32(bits)) & 255)) }
        }
        return out
    }
}

/// The used serials, the gift's end and the newest date the clock has shown, kept together so the app can mirror them in two places
/// (UserDefaults and the keychain) and merge them. The clock only moves forward here, so setting the phone back cannot stretch a gift.
public struct GiftWallet: Codable, Equatable, Sendable {
    public var serials: [Int] = []
    public var expires: Date?
    public var lastSeen: Date?
    public init() {}

    public enum Result: Equatable, Sendable { case invalid, used, ok(until: Date) }

    /// The later of the real clock and the newest date seen.
    public func trustedNow(_ now: Date) -> Date { max(now, lastSeen ?? now) }
    public mutating func noteSeen(_ now: Date) { lastSeen = trustedNow(now) }

    /// Union of two copies: every serial used anywhere stays used, the later dates win.
    public func merged(_ o: GiftWallet) -> GiftWallet {
        var m = GiftWallet()
        m.serials = Array(Set(serials).union(o.serials)).sorted()
        m.expires = [expires, o.expires].compactMap { $0 }.max()
        m.lastSeen = [lastSeen, o.lastSeen].compactMap { $0 }.max()
        return m
    }

    /// Redeems a typed code: the period is added to any time still left, counted from the trusted clock.
    public mutating func redeem(_ text: String, now: Date) -> Result {
        guard let gift = GiftCodes.check(text) else { return .invalid }
        if serials.contains(gift.serial) { return .used }
        let t = trustedNow(now)
        let end = max(t, expires ?? t).addingTimeInterval(Double(gift.days) * AdPolicy.passDuration)
        serials.append(gift.serial); expires = end; lastSeen = t
        return .ok(until: end)
    }
}

/// SHA-256 and HMAC, written out so the engine needs no crypto package (it also builds on Linux).
enum HMAC {
    static func sha256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var k: [UInt8] = key.count > 64 ? SHA256.hash(key) : key
        k += [UInt8](repeating: 0, count: 64 - k.count)
        let inner: [UInt8] = SHA256.hash(k.map { $0 ^ 0x36 } + message)
        return SHA256.hash(k.map { $0 ^ 0x5c } + inner)
    }
}

enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var m: [UInt8] = message
        let bitLength: UInt64 = UInt64(message.count) * 8
        m.append(0x80)
        while m.count % 64 != 56 { m.append(0) }
        for i in stride(from: 56, through: 0, by: -8) { m.append(UInt8((bitLength >> UInt64(i)) & 255)) }
        for chunk in stride(from: 0, to: m.count, by: 64) {
            var w: [UInt32] = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j: Int = chunk + i * 4
                w[i] = (UInt32(m[j]) << 24) | (UInt32(m[j + 1]) << 16) | (UInt32(m[j + 2]) << 8) | UInt32(m[j + 3])
            }
            for i in 16..<64 {
                let s0: UInt32 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1: UInt32 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1: UInt32 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch: UInt32 = (e & f) ^ (~e & g)
                let t1: UInt32 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0: UInt32 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj: UInt32 = (a & b) ^ (a & c) ^ (b & c)
                let t2: UInt32 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.flatMap { (v: UInt32) -> [UInt8] in [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
    }
}
