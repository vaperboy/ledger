import Foundation

/// The sheets of portraits the owner supplied. `casual` (`faces-sheet.jpg`, 15 x 9 = 135 faces) and `suits` (`faces-suits.jpg`, 13 x 13 = 169 faces,
/// business dress) are tagged by the owner; `workers` (`art/workers-sheet.jpg`, 90 faces, work clothes) and `managers` (`art/managers-sheet.jpg`,
/// 110 faces, business wear) are tagged only roughly: gender, "older" where it is plain, age and region otherwise unknown (X).
/// The engine picks portraits; the app only cuts the picture out of the sheet.
public enum FaceSheetID: String, CaseIterable, Sendable {
    case casual = "c"
    case suits = "s"
    case workers = "w"
    case managers = "m"

    public var cellCount: Int {
        switch self {
        case .casual: return 135
        case .suits: return 169
        case .workers: return 90
        case .managers: return 110
        }
    }
}

/// How a person dresses: casual work clothes or business wear. Each style draws from two sheets.
public enum FaceStyle: Sendable {
    case casual, suit
    public var sheets: [FaceSheetID] { self == .casual ? [.casual, .workers] : [.suits, .managers] }
    public var other: FaceStyle { self == .casual ? .suit : .casual }
}

/// One portrait: a sheet and a cell of it. Written "c12": the form stored on the person. An older save may hold "c12.2" (a variant, no longer
/// used): the part after the dot is ignored, so it reads as the plain cell.
public struct FaceKey: Hashable, Sendable {
    public var sheet: FaceSheetID
    public var cell: Int

    public init(sheet: FaceSheetID, cell: Int) { self.sheet = sheet; self.cell = cell }

    public var string: String { "\(sheet.rawValue)\(cell)" }

    public init?(_ text: String?) {
        guard let text, let first = text.first, let sheet = FaceSheetID(rawValue: String(first)) else { return nil }
        guard let cell = Int(text.dropFirst().split(separator: ".").first ?? ""), cell >= 0, cell < sheet.cellCount else { return nil }
        self.init(sheet: sheet, cell: cell)
    }
}

/// What the owner tagged on each portrait, and the deterministic choice of a free one for a person.
public enum FaceCatalog {
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

    /// Rough tags: gender, age (X unknown, O plainly older), region X unknown. Rows as laid out on the sheet (workers: 10 + 10 x 8; managers: 11 x 10).
    static let workerRows: [String] = [
        "MXX MXX MXX MXX FXX MXX MXX MXX MXX MXX",
        "MXX MXX FXX FXX MXX MXX MXX FXX",
        "MXX MXX FXX MXX MXX MXX MXX FXX",
        "MXX FXX MXX MXX MXX MXX FXX MXX",
        "MXX FXX MXX MXX MXX MXX FXX MXX",
        "MXX MXX MXX MXX MOX MXX MXX MXX",
        "MXX FXX FXX FXX MXX MXX MXX MXX",
        "MXX MXX FXX FXX MOX MXX MXX MXX",
        "MXX MXX MXX MXX MXX MXX FXX MXX",
        "MXX MXX FXX MXX FXX FXX MXX MXX",
        "MXX MOX MXX FXX MXX MXX MXX MXX",
    ]
    static let managerRows: [String] = [
        "MXX FXX MXX FXX MOX MXX FXX MXX FXX MXX",
        "FXX MXX MXX FXX FXX MXX FXX MXX FXX MXX",
        "FXX FXX MOX FXX MXX MOX MXX FXX FXX FXX",
        "MXX FXX FXX MXX MXX MXX MXX MXX FXX FXX",
        "MXX MXX MXX FXX MXX MXX FXX FXX MXX MXX",
        "MXX MXX MXX FXX MXX MXX MXX MXX MXX MXX",
        "MXX MXX FXX MXX MXX FXX MXX FXX FXX FXX",
        "MXX FXX MXX FXX MOX MXX MXX MXX MXX MXX",
        "MXX MXX MXX FXX FXX FXX FXX MXX MXX FXX",
        "MXX FXX FXX FXX MXX MXX MXX MXX MXX MXX",
        "MOX FXX FXX FXX FXX FXX MXX MXX MXX FXX",
    ]

    static func parse(_ rows: [String]) -> [Tag] {
        rows.flatMap { row in row.split(separator: " ").map { t -> Tag in let c = Array(t); return Tag(gender: c[0], age: c[1], region: c[2]) } }
    }

    static let casualTags: [Tag] = parse(casualRows)
    static let suitTags: [Tag] = parse(suitRows)
    static let workerTags: [Tag] = parse(workerRows)
    static let managerTags: [Tag] = parse(managerRows)

    public static func tags(_ sheet: FaceSheetID) -> [Tag] {
        switch sheet {
        case .casual: return casualTags
        case .suits: return suitTags
        case .workers: return workerTags
        case .managers: return managerTags
        }
    }

    /// FNV-1a: the same on every launch (Swift's own hashing is randomised per launch).
    public static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    /// Whether a tag's age fits a person's band: an unknown age (X) fits young and middle-aged people; "older" only the older.
    static func ageFits(_ tag: Character, _ band: Character) -> Bool { tag == band || (tag == "X" && band != "O") }

    /// The cells of a style (both its sheets) in order of preference for a person: gender + age + region, gender + region, gender + age, gender, any.
    /// An unknown region skips the region tiers; a cell tagged region X never matches a region. Empty tiers are left out.
    static func tiers(_ t: FaceTraits, style: FaceStyle) -> [[(sheet: FaceSheetID, cell: Int)]] {
        var all: [(sheet: FaceSheetID, cell: Int, tag: Tag)] = []
        for sheet in style.sheets { for (i, tag) in tags(sheet).enumerated() { all.append((sheet, i, tag)) } }
        let g = all.filter { $0.tag.gender == t.gender }
        var out: [[(sheet: FaceSheetID, cell: Int, tag: Tag)]] = []
        if let r = t.region {
            out.append(g.filter { ageFits($0.tag.age, t.ageBand) && $0.tag.region == r })
            out.append(g.filter { $0.tag.region == r })
        }
        out.append(g.filter { ageFits($0.tag.age, t.ageBand) })
        out.append(g)
        out.append(all)
        return out.filter { !$0.isEmpty }.map { $0.map { (sheet: $0.sheet, cell: $0.cell) } }
    }

    /// A free portrait for a person, never one `isTaken` refuses: the best preference tier that has an unused original, then wider tiers (any
    /// age, any region, any gender), then the other style. Nil when every original is taken (the screens then show initials). Deterministic: the
    /// same traits, style, salt and taken set give the same answer.
    public static func pick(_ traits: FaceTraits, style: FaceStyle, salt: String = "", isTaken: (FaceKey) -> Bool) -> FaceKey? {
        let h = stableHash(traits.key + "|" + salt)
        for st in [style, style.other] {
            for cells in tiers(traits, style: st) {
                let start = Int(h % UInt64(cells.count))
                for k in 0..<cells.count {
                    let c = cells[(start + k) % cells.count]
                    let key = FaceKey(sheet: c.sheet, cell: c.cell)
                    if !isTaken(key) { return key }
                }
            }
        }
        return nil
    }
}
