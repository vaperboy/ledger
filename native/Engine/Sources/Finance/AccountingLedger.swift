import Foundation
import GameCore

public enum AccountingLedger {
    public static let keepWeeks = 104

    public struct Annotation: Sendable {
        public var category: String
        public var label: String
        public var ref: String
        public init(category: String, label: String, ref: String = "") { self.category = category; self.label = label; self.ref = ref }
    }

    nonisolated(unsafe) static var pending: Annotation?

    public static func note(category: String?, label: String?, ref: String = "") {
        pending = Annotation(category: category ?? "-", label: label ?? "", ref: ref)
    }

    static func record(_ s: inout GameState, companyIndex i: Int, amount: Double) {
        let a = pending
        pending = nil
        if amount == 0 { return }
        let cat = a?.category ?? "-"
        let label = (a?.label.isEmpty ?? true) ? "Other movement" : a!.label
        let ref = a?.ref ?? ""
        var led = s.companies[i].raw.removeValue(forKey: "led") ?? .object([:])
        guard case .object(var weeks) = led else { s.companies[i].raw["led"] = led; return }
        led = .null
        let key = "w\(s.week)"
        var rows: [JSONValue] = []
        if let existing = weeks.removeValue(forKey: key), case .array(let r) = existing { rows = r }
        else {
            if s.companies[i].raw["ledFrom"] == nil { s.companies[i].raw["ledFrom"] = .number(Double(s.week)) }
            if weeks.count >= keepWeeks {
                let old = weeks.keys.compactMap { Int($0.dropFirst()) }.sorted().prefix(weeks.count - keepWeeks + 1)
                for w in old { weeks.removeValue(forKey: "w\(w)") }
            }
        }
        let positive = amount > 0
        if let k = rows.firstIndex(where: {
            $0.array.count > 4 && ($0.array[0].double > 0) == positive && $0.array[2].string == cat && $0.array[3].string == label && $0.array[4].string == ref
        }) {
            var row = rows[k].array
            row[0] = .number(row[0].double + amount); row[1] = .number(row[1].double + 1); row[5] = .number(Double(s.day))
            rows[k] = .array(row)
        } else {
            rows.append(.array([.number(amount), .number(1), .string(cat), .string(label), .string(ref), .number(Double(s.day))]))
        }
        weeks[key] = .array(rows)
        s.companies[i].raw["led"] = .object(weeks)
    }

    public struct Row: Equatable, Sendable {
        public var week: Int
        public var index: Int
        public var amount: Double
        public var count: Int
        public var category: String
        public var label: String
        public var ref: String
        public var day: Int
        public var id: String { "w\(week).\(index)" }
    }

    public static func rows(_ co: Company) -> [Row] {
        guard case .object(let weeks) = co.value("led") else { return [] }
        var out: [Row] = []
        for (k, v) in weeks {
            guard let w = Int(k.dropFirst()) else { continue }
            for (n, r) in v.array.enumerated() where r.array.count > 5 {
                let a = r.array
                out.append(Row(week: w, index: n, amount: a[0].double, count: a[1].int, category: a[2].string, label: a[3].string, ref: a[4].string, day: a[5].int))
            }
        }
        return out.sorted { $0.week != $1.week ? $0.week > $1.week : $0.index > $1.index }
    }
}
