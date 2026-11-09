import Foundation

/// Simple display-name rules, applied by the app before sending and by the server on receipt.
enum ProfileRules {
    static let minLength = 2, maxLength = 20

    private static let reserved: [String] = ["admin", "moderator", "ledger", "support", "staff", "official"]
    /// A short blocklist, matched after lower-casing and undoing common look-alike digits.
    private static let blocked: [String] = ["fuck", "shit", "cunt", "nazi", "bitch", "whore", "rape", "nigg", "fagg"]

    /// nil when the name is acceptable, otherwise one plain sentence saying why not.
    static func problem(with raw: String) -> String? {
        let name: String = clean(raw)
        if name.count < minLength { return "Use at least \(minLength) characters." }
        if name.count > maxLength { return "Use at most \(maxLength) characters." }
        let allowed: CharacterSet = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: " .-_'"))
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) { return "Use letters, numbers, spaces and . - _ ' only." }
        if !name.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) { return "Include at least one letter." }
        let flat: String = squash(name)
        if blocked.contains(where: { flat.contains($0) }) { return "That name is not allowed." }
        if reserved.contains(where: { flat.contains($0) }) { return "That name is reserved." }
        if flat.contains("http") || flat.contains("www") || flat.contains(".com") { return "A name cannot be a web address." }
        return nil
    }

    /// Trims and collapses runs of spaces.
    static func clean(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func squash(_ s: String) -> String {
        let map: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"]
        return String(s.lowercased().compactMap { (c: Character) -> Character? in
            if c == " " || c == "." || c == "-" || c == "_" || c == "'" { return nil }
            return map[c] ?? c
        })
    }
}
