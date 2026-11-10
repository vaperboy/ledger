import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum MarketTips {
    static let key = "dtip"
    static let firstWeek = 8
    static let supplierStep = 0.03
    static let demandStep = 0.08
    static let exchangeStep = 0.04

    public struct Tip: Equatable, Sendable {
        public var id: String
        public var text: String
        public var weight: Double
    }

    static func percent(_ x: Double) -> Int { Int(saturating: (abs(x) * 100).rounded()) }

    public static func candidates(_ s: GameState, data: GameData) -> [Tip] {
        var list: [Tip] = []
        let world = World(state: s, data: data)
        for co in s.companies where co.status == .open {
            let supplier: Double = co.value("mods").array.filter { $0["k"].string == "cogsup" }.reduce(1.0) { $0 * $1["m"].double }
            if supplier >= 1 + supplierStep {
                list.append(Tip(id: "sup.up.\(co.id)", weight: supplier - 1,
                                text: "Supplier prices for \(co.name) are up about \(percent(supplier - 1))% for now. Check your selling prices before the margin thins."))
            } else if supplier <= 1 - supplierStep {
                list.append(Tip(id: "sup.down.\(co.id)", weight: 1 - supplier,
                                text: "Supplier prices for \(co.name) are down about \(percent(supplier - 1))% for now. A good time to stock up."))
            }
            guard let bd = data.catalog[co.type], bd.normalDemand != 0 else { continue }
            let demand = DemandModel.compute(co, bd, world)
            if let f = demand.part("season") {
                if f >= 1 + demandStep {
                    list.append(Tip(id: "season.up.\(co.id)", weight: f - 1,
                                    text: "Demand for \(co.name) is about \(percent(f - 1))% above normal this season. Make sure stock and staff can keep up."))
                } else if f <= 1 - demandStep {
                    list.append(Tip(id: "season.down.\(co.id)", weight: 1 - f,
                                    text: "Demand for \(co.name) is about \(percent(f - 1))% below normal this season. Go easy on stock and hiring."))
                }
            }
            if let f = demand.part("events"), abs(f - 1) >= demandStep / 2 {
                list.append(Tip(id: "event.\(f > 1 ? "up" : "down").\(co.id)", weight: abs(f - 1),
                                text: f > 1 ? "Something in town is lifting demand for \(co.name) by about \(percent(f - 1))%. Be ready for the extra customers."
                                            : "Something in town is cutting demand for \(co.name) by about \(percent(f - 1))%. Do not overbuy while it lasts."))
            }
        }
        let book = ExchangeBook(s)
        for ins in book.instruments.values.sorted(by: { $0.id < $1.id }) where !ins.isOwn && !ins.halted {
            let c = ins.change
            if c >= exchangeStep {
                list.append(Tip(id: "xch.up.\(ins.id)", weight: c, text: "\(ins.name) rose \(percent(c))% at the last close. Holders are ahead; buyers pay more today."))
            } else if c <= -exchangeStep {
                list.append(Tip(id: "xch.down.\(ins.id)", weight: -c, text: "\(ins.name) fell \(percent(c))% at the last close. Look at it before you buy more or sell."))
            }
        }
        return list
    }

    public static func best(_ s: GameState, data: GameData) -> Tip? {
        candidates(s, data: data).sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.id < $1.id }.first
    }

    public static func runDay(_ s: inout GameState, data: GameData) {
        guard s.week >= firstWeek else { return }
        let today = s.week * 7 + s.day
        var st = s.rest[key] ?? .object([:])
        guard st["d"].isNull || st["d"].int != today else { return }
        guard let tip = best(s, data: data) else { return }
        st["d"] = .number(Double(today))
        st["id"] = .string(tip.id)
        s.rest[key] = st
        s.news("Tip: " + tip.text, tone: "n")
    }
}
