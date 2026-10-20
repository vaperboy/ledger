import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Selling a whole company. Original: features/player/selling_startups_and_crisis.js (the sale screen) and
/// engine/world/deals.js (`acceptSale`). You put a company on the market, privately or through a broker; buyers make
/// offers over the next weeks (each open six weeks); you accept, counter once (+8%) or decline. Listings live in
/// `state.rest["sales"]`, earn-outs in `state.rest["deferred"]`.
///
/// Not ported: selling part of your shares, raising funding from investors, founding startups of your own.
public enum CompanySale {
    public struct Offer: Identifiable, Equatable {
        public var id: Int
        public var kind: String          // private, fund, rival, mbo
        public var buyer: String
        public var price: Double         // for the whole company
        public var note: String
        public var expiresWeek: Int
        public var countered: Bool
    }
    public struct Listing: Equatable {
        public var companyID: Int
        public var broker: Bool
        public var since: Int
        public var offers: [Offer]
    }

    public static let brokerFee = 0.04

    // MARK: Reading

    public static func listing(_ s: GameState, companyID: Int) -> Listing? {
        guard let raw = (s.rest["sales"]?.array ?? []).first(where: { $0["co"].int == companyID }) else { return nil }
        return Listing(companyID: companyID, broker: raw["m"].string == "broker", since: raw["w0"].int,
                       offers: raw["offers"].array.map {
                           Offer(id: $0["id"].int, kind: $0["k"].string, buyer: $0["name"].string, price: $0["price"].double, note: $0["note"].string,
                                 expiresWeek: $0["exp"].int, countered: $0["ctr"].bool)
                       })
    }

    /// Value as shown on the sale screen: what a buyer would pay for the whole company.
    public static func estimatedValue(_ s: GameState, companyID: Int, data: GameData) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        return max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
    }

    public static func canSell(_ s: GameState, companyID: Int) -> Bool {
        guard let co = s.company(companyID) else { return false }
        return (co.status == .open || co.status == .closed) && co.type != "hold" && s.companies.filter { $0.status.isLive }.count > 0
    }

    // MARK: Listing

    static func write(_ s: inout GameState, _ list: [JSONValue]) { s.rest["sales"] = .array(list) }

    @discardableResult
    public static func startListing(_ s: inout GameState, companyID: Int, broker: Bool) -> Bool {
        guard canSell(s, companyID: companyID), listing(s, companyID: companyID) == nil else { return false }
        var list = s.rest["sales"]?.array ?? []
        list.append(.object(["co": .number(Double(companyID)), "m": .string(broker ? "broker" : "private"), "w0": .number(Double(s.week)), "offers": .array([])]))
        write(&s, list)
        return true
    }

    public static func withdraw(_ s: inout GameState, companyID: Int) {
        write(&s, (s.rest["sales"]?.array ?? []).filter { $0["co"].int != companyID })
    }

    static func update(_ s: inout GameState, companyID: Int, _ body: (inout JSONValue) -> Void) {
        var list = s.rest["sales"]?.array ?? []
        if let k = list.firstIndex(where: { $0["co"].int == companyID }) { body(&list[k]); write(&s, list) }
    }

    public static func decline(_ s: inout GameState, companyID: Int, offerID: Int) {
        update(&s, companyID: companyID) { l in l["offers"] = .array(l["offers"].array.filter { $0["id"].int != offerID }) }
    }

    /// Ask for 8% more, once. Some buyers walk away. Original: `ACT.salectr`.
    public static func counter(_ s: inout GameState, companyID: Int, offerID: Int) {
        guard let o = listing(s, companyID: companyID)?.offers.first(where: { $0.id == offerID }), !o.countered else { return }
        let ok = s.random.chance(o.kind == "rival" || o.kind == "fund" ? 0.55 : 0.4)
        update(&s, companyID: companyID) { l in
            var offers = l["offers"].array
            guard let k = offers.firstIndex(where: { $0["id"].int == offerID }) else { return }
            if ok {
                offers[k]["price"] = .number((o.price * 1.08 / 1000).rounded() * 1000)
                offers[k]["note"] = .string("Accepted your counter-offer.")
                offers[k]["ctr"] = .number(1)
            } else { offers.remove(at: k) }
            l["offers"] = .array(offers)
        }
        if !ok { s.note("\(o.buyer) walked away.", tone: "n", companyID: companyID) }
    }

    /// Accept an offer. Returns the cash you get, or nil if it is no longer possible.
    @discardableResult
    public static func accept(_ s: inout GameState, companyID: Int, offerID: Int, data: GameData, context fc: FinanceContext) -> Double? {
        guard let l = listing(s, companyID: companyID), let o = l.offers.first(where: { $0.id == offerID }), let i = s.companyIndex(companyID) else { return nil }
        let got = complete(&s, companyIndex: i, buyer: o.buyer, price: o.price, mbo: o.kind == "mbo", data: data, context: fc)
        if let got = got {
            if l.broker {
                let fee = jsRound(o.price * brokerFee)
                Payments.playerPays(&s, fee, label: "Broker fee")
            }
            if o.price > s.companies[i].injectedCapital * 1.3 { s.rest["exits"] = .number((s.rest["exits"]?.double ?? 0) + 1) }
            withdraw(&s, companyID: companyID)
            return got - (l.broker ? jsRound(o.price * brokerFee) : 0)
        }
        return nil
    }

    /// The sale itself: proceeds to you, loans closed, staff released. Original: `acceptSale`.
    /// With `mbo` a third of the price is lent back to the buyers and paid after two years.
    @discardableResult
    static func complete(_ s: inout GameState, companyIndex i: Int, buyer: String, price: Double, mbo: Bool = false, data: GameData, context fc: FinanceContext) -> Double? {
        let co = s.companies[i]
        guard co.status.isLive else { return nil }
        let mine = co.ownership / 100
        let proceeds = jsRound(price * mine)
        let basis = max(0, co.injectedCapital)
        s.tax.gains += max(0, proceeds - basis * mine)
        var now = proceeds
        if mbo {
            let later = jsRound(proceeds / 3)
            now -= later
            var d = s.rest["deferred"]?.array ?? []
            d.append(.object(["w": .number(Double(s.week + 104)), "amt": .number(later), "name": .string(co.name), "hurdle": .number(0)]))
            s.rest["deferred"] = .array(d)
        }
        Payments.playerReceives(&s, now, label: "Sold \(co.name) (\(buyer))", companyID: co.id)
        for l in s.loans.filter({ $0.companyID == co.id }) { Banking.close(loanID: l.id, repaid: l.balance, state: &s) }
        for m in s.companies[i].staff { if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p } }
        s.companies[i].staff = []
        if let mid = co.managerID, var p = s.people[mid] { p.employerID = 0; s.people[mid] = p }
        s.companies[i].status = .sold
        Ledger.set(&s, .company(co.id), to: 0)
        s.stats.companiesSold += 1
        for k in s.inbox.indices where s.inbox[k].companyID == co.id && s.inbox[k].status == "open" { s.inbox[k].set("status", "done") }
        for k in s.companies.indices where s.companies[k].holdingID == co.id { s.companies[k].holdingID = 0 }
        s.note("Sold \(co.name) for \(fc.homeCurrency(s).display(proceeds)) to \(buyer).", tone: "good")
        return now
    }

    // MARK: Weekly

    /// How well the company is doing in the eyes of investors, 0...1. Original: `traction`.
    static func traction(_ co: Company, _ s: GameState) -> Double {
        let e = CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week)
        let rev = (co.books.year["rev"] ?? 0) > 0 ? co.books.year["rev"]! : co.lastWeekRevenue * 52
        let mg = rev > 0 ? e / rev : -0.2
        let h = co.monthlyHistory.suffix(6).map { $0.revenue }
        let g = h.count >= 2 && h[0] > 0 ? h[h.count - 1] / h[0] - 1 : 0
        return clamp(0.25 + mg * 1.5 + clamp(g, -0.5, 1) * 0.6 + (co.reputation - 50) / 150 + min(0.2, Double(s.week - co.foundedWeek) / 260), 0, 1)
    }

    static let notes: [String: String] = [
        "rival": "Strategic buyer. Pays well but may close it and keep only the customers.",
        "fund": "Wants to grow it and sell again. Keeps staff and the brand.",
        "mbo": "Management buyout. A third is paid as a seller loan over two years. Safe, loyal, slower to pay.",
        "private": "A private buyer who wants to run it themselves."]

    /// Offers arrive; old ones lapse; earn-outs fall due. Original: `salesWeek`, `deferredWeek`.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for raw in s.rest["sales"]?.array ?? [] {
            let id = raw["co"].int
            guard let i = s.companyIndex(id), s.companies[i].status.isLive else { withdraw(&s, companyID: id); continue }
            let broker = raw["m"].string == "broker"
            var offers = raw["offers"].array.filter { s.week < $0["exp"].int }
            if offers.count < 4 {
                let co = s.companies[i]
                let currency = fc.currency(co.countryCode, s)
                let v0 = max(currency.scaledPrice(20000), Valuation.companyValue(co, state: s, trades: data.catalog))
                let tr = traction(co, s)
                let profit = CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week) > 0
                if s.random.chance((broker ? 0.42 : 0.16) * (0.35 + tr) * (profit ? 1 : 0.45)) {
                    var kinds = ["private", "fund", "rival"]
                    if co.managerID != nil && s.people[co.managerID!] != nil { kinds.append("mbo") }
                    let k = s.random.pick(kinds)
                    let f: Double = { switch k { case "rival": return s.random.range(0.95, 1.18); case "fund": return s.random.range(0.82, 1.02)
                                                case "mbo": return s.random.range(0.62, 0.8); default: return s.random.range(0.8, 1) } }() * (broker ? 1.05 : 1) * (0.85 + tr * 0.3)
                    let name: String = k == "mbo" ? (s.people[co.managerID ?? 0]?.name ?? "Your manager") + ", your manager"
                        : k == "rival" ? "A rival in your trade" : k == "fund" ? "An investment fund" : "A private buyer"
                    let price = (v0 * f / 1000).rounded() * 1000
                    offers.append(.object(["id": .number(Double(s.makeID())), "k": .string(k), "name": .string(name), "price": .number(price), "note": .string(notes[k] ?? ""),
                                           "exp": .number(Double(s.week + 6)), "ctr": .number(0)]))
                    s.addMessage(from: name, title: "Offer for \(co.name)", body: "\(name) offers \(currency.display(price * co.ownership / 100)) for your stake.", companyID: co.id, tone: "good")
                    if broker && !raw["heard"].bool {
                        update(&s, companyID: id) { $0["heard"] = .number(1) }
                        let m = co.value("mood").isNull ? 60 : co.num("mood")
                        s.companies[i].set("mood", clamp(m - 8, 0, 100))
                        s.note("Word is out that \(co.name) is for sale. Staff are uneasy and rivals are watching.", tone: "n", companyID: co.id)
                    }
                }
            }
            update(&s, companyID: id) { $0["offers"] = .array(offers) }
        }
        // Earn-outs
        var keep: [JSONValue] = []
        for d in s.rest["deferred"]?.array ?? [] {
            guard s.week >= d["w"].int else { keep.append(d); continue }
            let paid = jsRound(d["amt"].double)
            Payments.playerReceives(&s, paid, label: "Paid back for \(d["name"].string)")
            s.note("The money still owed for \(d["name"].string) has been paid.", tone: "good")
        }
        s.rest["deferred"] = .array(keep)
    }
}
