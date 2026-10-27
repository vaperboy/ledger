import Foundation

/// The two sheets of portraits the owner supplied. `casual` (`faces-sheet.jpg`, 15 x 9 = 135 faces) and `suits` (`faces-suits.jpg`,
/// 13 x 13 = 169 faces, business dress). The engine picks portraits; the app only cuts the picture out of the sheet.
public enum FaceSheetID: String, CaseIterable, Sendable {
    case casual = "c"
    case suits = "s"

    public var columns: Int { self == .casual ? 15 : 13 }
    public var rows: Int { self == .casual ? 9 : 13 }
    public var cellCount: Int { columns * rows }
    public var other: FaceSheetID { self == .casual ? .suits : .casual }
}

/// One portrait: a sheet, a cell and a variant (0 the plain cell; 1 mirrored; 2 a closer offset crop; 3 mirrored, closer and a mild warm grade).
/// Written "c12.0": the form stored on the person.
public struct FaceKey: Hashable, Sendable {
    public var sheet: FaceSheetID
    public var cell: Int
    public var variant: Int

    public init(sheet: FaceSheetID, cell: Int, variant: Int) { self.sheet = sheet; self.cell = cell; self.variant = variant }

    public var string: String { "\(sheet.rawValue)\(cell).\(variant)" }

    public init?(_ text: String?) {
        guard let text, let first = text.first, let sheet = FaceSheetID(rawValue: String(first)) else { return nil }
        let rest = text.dropFirst().split(separator: ".")
        guard rest.count == 2, let cell = Int(rest[0]), let variant = Int(rest[1]),
              cell >= 0, cell < sheet.cellCount, variant >= 0, variant < FaceCatalog.variantCount else { return nil }
        self.init(sheet: sheet, cell: cell, variant: variant)
    }
}

/// What the owner tagged on each portrait, and the deterministic choice of a free one for a person.
public enum FaceCatalog {
    public static let variantCount = 4

    public struct Tag: Equatable, Sendable { public var gender: Character; public var age: Character; public var region: Character }

    /// gender (F/M), age band (Y/M/O), region (S E U A L W) per cell, row by row, left to right.
    static let casualRows: [String] = [
        "FYS FYE FYS FYS MYS MYE MYU FYE FMS MOE FOU MOU MYA MYU MOU",
        "FYE FYS MYS FYU MYS MYU MYS MML FYS MYS FYE MOU FYA MYS MYA",
        "FYS FYS FYE MYW MOU FYS MYA FMS MYS MYA MMU MMU FYS MYA MYA",
        "FMS FYE FYE MMS FYE FYE MYS MYA FYE FYE MMS FYE FMU MYS MOU",
        "FYE MOU FYS MYS MYS MYS MYS FYL FYS MMU FMS FYE MYS MME MYA",
        "MYE FYU MOU MMA FYS FYS FYS MME FYS MME MYS MYS MYS FMS MOU",
        "FYS MYS FYE FYE MOA MYA MYE MMA MMU MYS MYE FYA FYE MYA FYE",
        "FYS FYE FYS MYS FYS MYA MYS MYS FMS MME MYA MMU FYE MOA MME",
        "FYS MOU MMA MYU FYE MMS MYA FYE MYE MOU FMS FYE FYS MYS MYE",
    ]
    static let suitRows: [String] = [
        "MYA MYA FYU MYU FYU FOU MOU MOU FYA MYW MYW FOU MYU",
        "FYS FYE MYU FYA FYE FYE MYS MYA FYE MYU MYU FYS MYA",
        "MYA MYE FYE FYA MYA FYE MYU MYA MYS FYE MYW FYL MYU",
        "MYU FYU MYU FYE MOU MYW MYE FYE MYA MYE FYL MYA FYA",
        "MYA FYA MYU FYU MYU FYE MOU MYU MOU MYA MYU FYL MYU",
        "MYA FYU FYE FYE MYA MYA MYA MYU MYA MYW MYS MYA FYE",
        "MYU MYU FOU MYS MYU MYA FYE FYE MYA FYE MYW FYE MYU",
        "MYA FYE MYU MOU MYU MYS MYL MYE MYS MMA FYA FYE MYU",
        "MYA FYU MOU FYA FYE FYA MYS MYA MYA MYW MYS FYU FYE",
        "MYE FYE MYA MYW FYU MYS MYA MYU FYE FYE FYA FYL MYU",
        "MYS FYE MYU MYU MOU MYA MOU FYE FYA FYS FYE FOU MOU",
        "MYA FYE FYE MYS MYE FYS FYE FOU MYU FOU MYA MMU FYA",
        "FYS FYE FYE MYU MYA FYS MYU FYS MYU FYA MYA MYS MYU",
    ]

    static func parse(_ rows: [String]) -> [Tag] {
        rows.flatMap { row in row.split(separator: " ").map { t -> Tag in let c = Array(t); return Tag(gender: c[0], age: c[1], region: c[2]) } }
    }

    static let casualTags: [Tag] = parse(casualRows)
    static let suitTags: [Tag] = parse(suitRows)

    public static func tags(_ sheet: FaceSheetID) -> [Tag] { sheet == .casual ? casualTags : suitTags }

    /// FNV-1a: the same on every launch (Swift's own hashing is randomised per launch).
    public static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    /// Cells of a sheet in order of preference for a person: gender + age + region, gender + region, gender + age, gender, any.
    /// An unknown region skips the region tiers. Empty tiers are left out.
    static func tiers(_ t: FaceTraits, sheet: FaceSheetID) -> [[Int]] {
        let tags = tags(sheet)
        let all = Array(0..<tags.count)
        let g = all.filter { tags[$0].gender == t.gender }
        var out: [[Int]] = []
        if let r = t.region {
            out.append(g.filter { tags[$0].age == t.ageBand && tags[$0].region == r })
            out.append(g.filter { tags[$0].region == r })
        }
        out.append(g.filter { tags[$0].age == t.ageBand })
        out.append(g)
        out.append(all)
        return out.filter { !$0.isEmpty }
    }

    /// A free portrait for a person, never one `isTaken` refuses: within each preference tier the plain cells first, and only when every plain
    /// cell of the tier is taken its variants; then the next tier; then the other sheet. Nil when everything is taken (the screens then show
    /// initials). Deterministic: the same traits, sheet, salt and taken set give the same answer.
    public static func pick(_ traits: FaceTraits, sheet: FaceSheetID, salt: String = "", isTaken: (FaceKey) -> Bool) -> FaceKey? {
        let h = stableHash(traits.key + "|" + salt)
        for s in [sheet, sheet.other] {
            for cells in tiers(traits, sheet: s) {
                let start = Int(h % UInt64(cells.count))
                for k in 0..<cells.count {
                    let key = FaceKey(sheet: s, cell: cells[(start + k) % cells.count], variant: 0)
                    if !isTaken(key) { return key }
                }
                let vStart = Int((h >> 17) % UInt64(variantCount - 1))
                for step in 0..<(variantCount - 1) {
                    let variant = 1 + (vStart + step) % (variantCount - 1)
                    for k in 0..<cells.count {
                        let key = FaceKey(sheet: s, cell: cells[(start + k) % cells.count], variant: variant)
                        if !isTaken(key) { return key }
                    }
                }
            }
        }
        return nil
    }
}
