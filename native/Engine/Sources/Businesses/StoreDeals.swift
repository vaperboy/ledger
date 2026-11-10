import Foundation
import GameCore

public enum StoreDeals {
    public enum Kind: Int, Sendable { case none = 0, small, clearance, big, blackFriday }

    public struct Deal: Equatable, Sendable {
        public var kind: Kind
        public var factor: Double
        public var label: String
        public var isOn: Bool { kind != .none }
        public var percentOff: Int { Int(saturating: ((1 - factor) * 100).rounded()) }
    }

    public static let none = Deal(kind: .none, factor: 1, label: "")

    private static func pct(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    public static func isBlackFridayWeek(_ week: Int) -> Bool {
        for d in 0..<7 {
            let x = GameCalendar.date(week: week, dayOffset: d)
            if x.month == 10 && x.weekday == 4 && x.day >= 23 && x.day <= 29 { return true }
        }
        return false
    }

    public static func isClearanceWeek(_ week: Int) -> Bool {
        let d = GameCalendar.date(week: week, dayOffset: 6)
        return d.month == 0 && d.day <= 21
    }

    public static func deal(week: Int, seed: Int, key: String) -> Deal {
        var r = HashedRandom("\(seed):deal:\(week):\(key)")
        let roll = r.next()
        let depth = r.next()
        if isBlackFridayWeek(week) {
            if roll < 0.92 { return Deal(kind: .blackFriday, factor: pct(0.50 + depth * 0.25), label: "Black Friday") }
            return Deal(kind: .small, factor: 0.92, label: "Sale")
        }
        if isClearanceWeek(week) && roll < 0.55 {
            return Deal(kind: .clearance, factor: pct(0.80 + depth * 0.10), label: "Clearance")
        }
        if roll < 0.03 { return Deal(kind: .big, factor: pct(0.60 + depth * 0.15), label: "Mega deal") }
        if roll < 0.28 { return Deal(kind: .small, factor: pct(0.90 + depth * 0.06), label: "Sale") }
        return none
    }
}
