import Foundation

/// Reads the original game's packed save texts ("LZ1:..." and "LZ64:..."), a copy of the lz-string compression
/// scheme the HTML game uses (original: `lzUnpack`, `unpackText`, `unpackText64` in engine/core/state.js).
public enum LZString {
    private static let base64Alphabet: [UInt16] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".utf16)

    /// "LZ1:" payload: 15 bits per character, offset by 32.
    public static func unpackText(_ packed: String) -> String? {
        let u = Array(packed.utf16)
        guard !u.isEmpty else { return "" }
        return unpack(length: u.count, reset: 16384) { i in i < u.count ? Int(u[i]) - 32 : 0 }
    }

    /// "LZ64:" payload: 6 bits per character from a base-64 alphabet.
    public static func unpackText64(_ packed: String) -> String? {
        let allowed = Set(base64Alphabet)
        let u = packed.utf16.filter { allowed.contains($0) }
        guard !u.isEmpty else { return "" }
        return unpack(length: u.count, reset: 32) { i in
            guard i < u.count, let idx = base64Alphabet.firstIndex(of: u[i]) else { return 0 }
            return idx
        }
    }

    /// Any of the three save text forms (plain JSON, LZ1, LZ64) to JSON text. Original: `saveJSON`.
    public static func jsonText(fromSaveText text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("LZ1:") { return unpackText(String(t.dropFirst(4))) }
        if t.hasPrefix("LZ64:") { return unpackText64(String(t.dropFirst(5))) }
        return t
    }

    private static func unpack(length: Int, reset: Int, next: (Int) -> Int) -> String? {
        var dict: [Int: [UInt16]] = [:]
        var result: [UInt16] = []
        var enlarge = 4, size = 4, nb = 3
        var val = next(0), pos = reset, idx = 1

        func get(_ n: Int) -> Int {
            var b = 0, p = 1
            for _ in 0..<n {
                let r = val & pos
                pos >>= 1
                if pos == 0 { pos = reset; val = next(idx); idx += 1 }
                if r > 0 { b |= p }
                p <<= 1
            }
            return b
        }

        let t = get(2)
        if t == 2 { return "" }
        let first = UInt16(truncatingIfNeeded: get(t == 0 ? 8 : 16))
        dict[3] = [first]
        var w: [UInt16] = [first]
        result.append(first)
        while true {
            if idx > length { return "" }
            var k = get(nb)
            if k == 2 { return String(decoding: result, as: UTF16.self) }
            if k < 2 {
                dict[size] = [UInt16(truncatingIfNeeded: get(k == 0 ? 8 : 16))]
                size += 1
                k = size - 1
                enlarge -= 1
                if enlarge == 0 { enlarge = 1 << nb; nb += 1 }
            }
            let e: [UInt16]
            if let d = dict[k], !d.isEmpty { e = d }
            else if k == size { e = w + [w[0]] }
            else { return nil }
            result.append(contentsOf: e)
            dict[size] = w + [e[0]]
            size += 1
            w = e
            enlarge -= 1
            if enlarge == 0 { enlarge = 1 << nb; nb += 1 }
        }
    }
}
