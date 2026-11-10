import Foundation

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

public enum FaceStyle: Sendable {
    case casual, suit
    public var sheets: [FaceSheetID] { self == .casual ? [.casual, .workers] : [.suits, .managers] }
    public var other: FaceStyle { self == .casual ? .suit : .casual }
}

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

public enum FaceCatalog {
    public struct Tag: Equatable, Sendable { public var gender: Character; public var age: Character; public var region: Character }

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

    public static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    static func ageFits(_ tag: Character, _ band: Character) -> Bool { tag == band || (tag == "X" && band != "O") }

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
