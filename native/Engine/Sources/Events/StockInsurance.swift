import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum StockInsurance {
    public static let product = "stock"
    static let yearlyRate = 0.012

    public static func isInsured(_ co: Company) -> Bool { co.value("ins")[product].bool }

    public static func eventsOn(_ s: GameState) -> Bool { s.rest["lg"]?["events"].bool ?? false }
    public static func setEventsOn(_ s: inout GameState, _ on: Bool) {
        var lg = s.rest["lg"] ?? .object([:])
        lg["events"] = .bool(on)
        s.rest["lg"] = lg
    }

    public static func excess(_ cur: Currency) -> Double { cur.scaledPrice(10000) }

    public static func weeklyPremium(_ co: Company) -> Double {
        guard isInsured(co), co.inventory > 0 else { return 0 }
        return jsRound(co.inventory * yearlyRate / 52 * Advisers.premiumFactor(co))
    }

    public static func estimatedWeeklyPremium(_ co: Company) -> Double {
        guard co.inventory > 0 else { return 0 }
        return jsRound(co.inventory * yearlyRate / 52 * Advisers.premiumFactor(co))
    }

    public struct Settlement: Equatable, Sendable {
        public var loss: Double
        public var paid: Double
        public var net: Double { loss - paid }
    }

    @discardableResult
    public static func settle(_ s: inout GameState, companyID: Int, amount: Double, fromInventory: Bool, data: GameData) -> Settlement {
        guard let i = s.companyIndex(companyID) else { return Settlement(loss: 0, paid: 0) }
        var loss = jsRound(max(0, amount))
        if fromInventory { loss = min(loss, max(0, s.companies[i].inventory)) }
        guard loss > 0 else { return Settlement(loss: 0, paid: 0) }
        if fromInventory { s.companies[i].inventory -= loss }
        Payments.book(&s, companyID: companyID, category: "loss", amount: loss)
        var paid = 0.0
        if isInsured(s.companies[i]) {
            let cur = World(state: s, data: data).currency(s.companies[i])
            paid = max(0, loss - excess(cur))
            if paid > 0 {
                Payments.companyReceives(&s, companyID: companyID, amount: paid, category: nil, label: "Insurance payout")
                Payments.book(&s, companyID: companyID, category: "loss", amount: -paid)
            }
        }
        return Settlement(loss: loss, paid: paid)
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        let rolls = eventsOn(s)
        for i in s.companies.indices where s.companies[i].status == .open {
            let id = s.companies[i].id
            let premium = weeklyPremium(s.companies[i])
            if premium > 0 { Payments.companyPays(&s, companyID: id, amount: premium, category: "ins", label: "Stock insurance premium") }
            guard rolls, s.companies[i].inventory > 0 else { continue }
            var r = HashedRandom("\(s.seed):stk:\(s.week):\(id)")
            let kinds: [(name: String, chance: Double, low: Double, high: Double, text: String)] = [
                ("fire", 0.0012, 0.25, 0.9, "A fire at"),
                ("water", 0.003, 0.05, 0.3, "Water damage at"),
                ("theft", 0.004, 0.03, 0.2, "A theft at"),
            ]
            for k in kinds {
                let hit = r.next() < k.chance
                let share = k.low + (k.high - k.low) * r.next()
                guard hit else { continue }
                let co = s.companies[i]
                let insured = isInsured(co)
                let st = settle(&s, companyID: id, amount: co.inventory * share, fromInventory: true, data: data)
                let cur = World(state: s, data: data).currency(s.companies[i])
                let tail = insured ? "The insurer paid \(cur.display(st.paid)); you bear \(cur.display(st.net))." : "It was not insured: \(cur.display(st.loss)) is a loss."
                let body = "\(k.text) \(co.name) destroyed stock worth \(cur.display(st.loss)). \(tail)"
                s.note(body, tone: "bad", companyID: id)
                s.addMessage(kind: "info", from: "Your insurer", title: k.name == "fire" ? "Fire in the stock room" : k.name == "water" ? "Water damage to stock" : "Stock stolen",
                             body: body, companyID: id, tone: "bad")
                break
            }
        }
    }
}
