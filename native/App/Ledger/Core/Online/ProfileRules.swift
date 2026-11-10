import Foundation

enum ProfileRules {
    static let minLength = 3, maxLength = 16

    private static let reserved: [String] = ["admin", "moderator", "ledger", "support", "staff", "official"]
    private static let blocked: [String] = ["fuck", "shit", "cunt", "nazi", "bitch", "whore", "rape", "nigg", "fagg"]

    static func problem(with raw: String) -> String? {
        let name: String = clean(raw)
        if name.count < minLength { return "Use at least \(minLength) characters." }
        if name.count > maxLength { return "Use at most \(maxLength) characters." }
        if !name.unicodeScalars.allSatisfy({ isAllowed($0) }) { return "Use letters, numbers and _ only, with no spaces." }
        if let first = name.unicodeScalars.first, !isLetter(first) { return "Start with a letter." }
        let flat: String = squash(name)
        if blocked.contains(where: { flat.contains($0) }) { return "That name is not allowed." }
        if reserved.contains(where: { flat.contains($0) }) { return "That name is reserved." }
        if flat.contains("http") || flat.contains("www") { return "A name cannot be a web address." }
        return nil
    }

    static func clean(_ raw: String) -> String { raw.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func isLetter(_ s: Unicode.Scalar) -> Bool { (s.value >= 65 && s.value <= 90) || (s.value >= 97 && s.value <= 122) }

    private static func isAllowed(_ s: Unicode.Scalar) -> Bool { isLetter(s) || (s.value >= 48 && s.value <= 57) || s == "_" }

    private static func squash(_ s: String) -> String {
        let map: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t"]
        return String(s.lowercased().compactMap { (c: Character) -> Character? in
            if c == "_" { return nil }
            return map[c] ?? c
        })
    }
}
