import Foundation
import GameCore
import Countries
import Finance

/// Price moves: prices change in percent, customers get used to a price, discount campaigns (and the fine for a fake discount),
/// and the history that tells a rival you cut. Originals: `priceWeek`, `ACT.pm16go`, `ACT.pm16camp`, `ACT.pm16end`, `cutRise`,
/// `DISC` (features/sales/price_moves_and_lawsuits.js). The demand side (`priceDem`) is `Pricing.demandEffect`.
/// Forecast boxes (`forecast`, `Forecast.text`): what a change does to customers (at first, and once they are used to it) and to the margin;
/// the owner only has a feeling, a data analyst in the head office gives a range as sharp as their skill (`est`, `fcBoxes`, `guess`).
/// Managers move prices in small steps (6% of the price, not a whole level; `managerStep`). Rival calls about matched cuts: `Rivals.rivalCall`.
public enum PriceMoves {
    /// How deep each trade can discount (0 or absent = not done in that trade). Original: `DISC`.
    static let discountMax: [String: Int] = [
        "cons": 15, "tutor": 30, "carclean": 30, "photo": 25, "handy": 15, "cleaning": 20, "webdev": 15, "mktg": 15, "barber": 25, "drivsk": 15,
        "physio": 10, "pets": 25, "foodtruck": 30, "cafe": 30, "restaurant": 25, "nightclub": 20, "gym": 40, "hotel": 40, "fun": 30, "kiosk": 25,
        "boutique": 40, "webshop": 40, "grocery": 25, "hardware": 30, "cardealer": 10, "event": 10, "bakery": 30, "brewery": 20, "furniture": 30,
        "factory": 10, "taxi": 15, "courier": 20, "airline": 40, "parking": 20,
    ]

    public static func maxDiscount(_ type: String) -> Int { discountMax[type] ?? 0 }
    public static func discountOptions(_ type: String) -> [Int] { [10, 15, 20, 25, 30, 40].filter { $0 <= maxDiscount(type) } }

    /// Temporary effect on demand (events, campaigns). Same record the event engine writes.
    static func addModifier(_ s: inout GameState, _ i: Int, key: String, multiplier m: Double, weeks: Double) {
        var mods = s.companies[i].value("mods").array
        mods.append(.object(["k": .string(key), "m": .number(m), "w": .number(jsRound(weeks))]))
        s.companies[i].set("mods", .array(mods))
    }

    // MARK: Weekly

    /// What customers are used to, the price history, and the running campaign. Original: `priceWeek`.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open {
            let co = s.companies[i]
            let base = data.balance.priceMultiplier(level: co.priceLevel)
            let pref = co.value("pref16").isNull ? base : co.num("pref16")
            s.companies[i].set("pref16", jsRound((pref + (base - pref) * 0.18) * 10000) / 10000)
            // "Hold my prices": the price the market would have reached keeps running away from the held one (`ig`), so customers see it as cheaper.
            if co.flag("inflHold") { s.companies[i].set("ig", co.num("ig", 1) * pow(1 + s.economy.inflation, 1.0 / 52)) }
            var hist = co.value("ph16").array
            hist.append(.array([.number(Double(s.week)), .number(jsRound(base * 1000) / 1000)]))
            if hist.count > 10 { hist.removeFirst(hist.count - 10) }
            s.companies[i].set("ph16", .array(hist))
            let c = co.value("camp16")
            guard !c.isNull else { continue }
            if Double(s.week) < c["end"].double {
                var cw = co.value("cw16").array
                cw.append(.number(Double(s.week)))
                if cw.count > 20 { cw.removeFirst(cw.count - 20) }
                s.companies[i].set("cw16", .array(cw))
                var h = HashedRandom("\(s.seed):fake:\(s.week):\(co.id)")
                if c["fake"].double > 0, !c["caught"].bool, h.next() < 0.2 {
                    var camp = c; camp["caught"] = true; s.companies[i].set("camp16", camp)
                    let cur = World(state: s, data: data).currency(co)
                    let fine = (cur.scaledPrice(40000) * clamp(co.size, 0.5, 3) / 1000).rounded() * 1000
                    Payments.companyPays(&s, companyID: co.id, amount: fine, category: "fine", label: "Consumer authority: misleading discount")
                    s.companies[i].reputation = clamp(s.companies[i].reputation - 3, 0, 100)
                    s.addMessage(from: "Consumer authority", title: "Misleading sale at \(co.name)",
                                 body: "Your \(c["pct"].int)% off was measured against a price you raised \(c["fake"].int) weeks before. The before-price must be the price of the last 30 days. Fine: \(cur.display(fine)).",
                                 companyID: co.id, tone: "bad")
                }
            } else {
                if let bd = data.catalog[co.type], ["retail", "venue", "prod"].contains(bd.family) {
                    addModifier(&s, i, key: "dem", multiplier: 1 - c["pct"].double / 100 * 0.35, weeks: 1)
                }
                s.note("The \(c["pct"].int)% discount at \(co.name) has ended.", tone: "n", companyID: co.id)
                s.companies[i].set("camp16", .null)
            }
        }
    }

    // MARK: Actions

    /// Weeks since the price was raised by more than 3%, if within the last four. A "discount" right after is measured from a price
    /// that is not 30 days old. Original: `cutRise`.
    public static func raisedWeeksAgo(_ co: Company, week: Int, balance: Balance) -> Int {
        let now = balance.priceMultiplier(level: co.priceLevel)
        var w = 99
        for h in co.value("ph16").array where week - h[0].int <= 4 && now / max(0.01, h[1].double) - 1 > 0.03 { w = min(w, week - h[0].int) }
        return w == 99 ? 0 : max(1, w)
    }

    /// How far the price was cut from its recent high, if within six weeks. Original: `cutOf`.
    public static func recentCut(_ co: Company, week: Int, balance: Balance) -> Double {
        let now = balance.priceMultiplier(level: co.priceLevel)
        var mx = 0.0
        for h in co.value("ph16").array where week - h[0].int <= 6 { mx = max(mx, h[1].double / now - 1) }
        return mx
    }

    /// Move the price by a share (e.g. +0.05). Customers notice a change against what they are used to. Original: `ACT.pm16go`.
    @discardableResult
    public static func changePrice(_ s: inout GameState, companyID: Int, byShare d: Double, data: GameData) -> Double? {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open || s.companies[i].status == .closed else { return nil }
        let b = data.balance
        let old = b.priceMultiplier(level: s.companies[i].priceLevel)
        if s.companies[i].value("pref16").isNull { s.companies[i].set("pref16", old) }
        if s.companies[i].value("ph16").isNull { s.companies[i].set("ph16", .array([.array([.number(Double(s.week)), .number(jsRound(old * 1000) / 1000)])])) }
        let nb = clamp(old * (1 + d), b.priceMultipliers[0], b.priceMultipliers[6])
        s.companies[i].priceLevel = clamp(b.priceLevel(multiplier: nb), -3, 3)
        var f = s.companies[i].value("flags"); f["priceAt"] = .number(Double(s.week)); s.companies[i].set("flags", f)
        return nb / old - 1
    }

    /// Start a discount campaign. Original: `ACT.pm16camp`.
    public static func startCampaign(_ s: inout GameState, companyID: Int, percent: Int, weeks: Int, data: GameData) -> String? {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open else { return "Only an open company can run a discount." }
        guard maxDiscount(s.companies[i].type) >= percent, percent > 0 else { return "This trade does not discount that deep." }
        guard Pricing.discount(s.companies[i], s.week) == 0 else { return "A discount is already running." }
        let rose = raisedWeeksAgo(s.companies[i], week: s.week, balance: data.balance)
        s.companies[i].set("camp16", .object(["pct": .number(Double(percent)), "end": .number(Double(s.week + weeks)), "w0": .number(Double(s.week)), "fake": .number(Double(rose))]))
        return nil
    }

    public static func endCampaign(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        s.companies[i].set("camp16", .null)
    }

    // MARK: Managers move prices in small steps

    /// A manager raises or lowers the price by 6%, not by a whole level. Original: `step` ('tune.after', 'askManager.after').
    public static func managerStep(_ s: inout GameState, _ ci: Int, up: Bool, balance b: Balance) {
        let old = b.priceMultiplier(level: s.companies[ci].priceLevel)
        let nb = clamp(old * (up ? 1.06 : 0.94), b.priceMultipliers[0], b.priceMultipliers[6])
        s.companies[ci].priceLevel = clamp(b.priceLevel(multiplier: nb), -3, 3)
    }

    // MARK: Forecast

    public struct Forecast: Equatable {
        /// Change in customers in the first weeks, and once customers are used to the new price (0.05 = 5% more).
        public var customersAtFirst: Double, customersLater: Double
        /// Margin now and after the change (nil when there are no figures yet).
        public var marginNow: Double?, marginAfter: Double?
        /// Demand already above what the shop can serve: more demand would not turn into sales.
        public var full: Bool
    }

    /// What a price change (`byShare`) or a campaign (`campaignPercent`) would do. Original: `est`.
    public static func forecast(_ s: GameState, companyID: Int, byShare d: Double, campaignPercent cp: Int = 0, data: GameData) -> Forecast? {
        guard let co0 = s.company(companyID), let bd = data.catalog[co0.type], bd.normalDemand > 0 else { return nil }
        let w = World(state: s, data: data), b = data.balance
        var co = co0
        if co.value("pref16").isNull { co.set("pref16", b.priceMultiplier(level: co.priceLevel)) }
        let isGoods = ["retail", "prod"].contains(bd.family)
        let cap = isGoods ? Double.infinity : CapacityModel.compute(co, bd, w).capacity * (bd.family == "svc" ? 1.1 : 1)
        let e0 = Pricing.priceIndex(co, w), D0 = DemandModel.compute(co, bd, w).customers
        let old = b.priceMultiplier(level: co.priceLevel)
        let nb = clamp(old * (1 + d), b.priceMultipliers[0], b.priceMultipliers[6])
        co.priceLevel = clamp(b.priceLevel(multiplier: nb), -3, 3)
        if cp > 0 { co.set("camp16", .object(["pct": .number(Double(cp)), "end": .number(Double(s.week + 9)), "w0": .number(Double(s.week))])) }
        let e1 = Pricing.priceIndex(co, w), D1 = DemandModel.compute(co, bd, w).customers
        if cp == 0 { co.set("pref16", nb) }
        let D2 = DemandModel.compute(co, bd, w).customers
        let u0 = min(D0, cap), u1 = min(D1, cap), u2 = min(D2, cap)
        var m0: Double? = nil, m1: Double? = nil
        if let h = co0.monthlyHistory.last, h.revenue > 0, u0 > 0 {
            let lw = co0.value("lastW")
            let v = lw["rev"].double > 0 ? clamp(lw["cogs"].double / lw["rev"].double, 0, 0.95) : bd.costOfSales
            let ur = (cp > 0 ? u1 : u2) / u0, pr = e1 / max(0.0001, e0)
            let rev1 = h.revenue * ur * pr, varC = h.revenue * v, fix = h.revenue - h.profit - varC
            m0 = h.profit / h.revenue
            m1 = rev1 > 0 ? (rev1 - varC * ur - fix) / rev1 : nil
        }
        return Forecast(customersAtFirst: u0 > 0 ? D1 / D0 - 1 : 0, customersLater: u0 > 0 ? D2 / D0 - 1 : 0, marginNow: m0, marginAfter: m1, full: D0 > cap * 1.02)
    }

    static func gutWord(_ c: Double) -> String {
        c < -0.25 ? "Many fewer" : c < -0.08 ? "Fewer" : c < -0.02 ? "A few fewer" : c <= 0.02 ? "Same" : c < 0.08 ? "A few more" : c < 0.25 ? "More" : "Many more"
    }

    /// A range around the true value, as wide as the analyst is unsure. Original: `guess`.
    static func guess(_ v: Double, key: String, analyst k: MarketMap.Knowledge, unit: Double, sign: Bool, seed: Int, week: Int) -> String {
        var h = HashedRandom("\(seed):g16:\(key):\(k.id):\(week / 4)")
        let a = h.next(), b = h.next()
        let off = (a - 0.5) * 2 * (1 - k.skill) * unit * 2.2 * (b < k.skill ? 0.4 : 1), w = unit * (0.35 + (1 - k.skill) * 2)
        func f(_ x: Double) -> String { (sign && x > 0 ? "+" : x < 0 ? "−" : "") + "\(Int(jsRound(abs(x) * 100)))%" }
        return f(v + off - w / 2) + " to " + f(v + off + w / 2)
    }

    public struct ForecastText: Equatable { public var customers: String, margin: String, byAnalyst: Bool }

    /// The two boxes: customers and margin, as the owner or the data analyst sees them. Original: `fcBoxes`.
    public static func forecastText(_ f: Forecast, _ s: GameState, key: String, campaign: Bool = false) -> ForecastText {
        let cv = campaign ? f.customersAtFirst : f.customersLater
        if let an = MarketMap.dataAnalyst(s) {
            return ForecastText(customers: guess(cv, key: key + "c", analyst: an, unit: 0.08, sign: true, seed: s.seed, week: s.week),
                                margin: f.marginAfter.map { guess($0, key: key + "m", analyst: an, unit: 0.06, sign: false, seed: s.seed, week: s.week) } ?? "?", byAnalyst: true)
        }
        var m = "?"
        if let m1 = f.marginAfter, let m0 = f.marginNow {
            var h = HashedRandom("\(s.seed):gm16:\(key):\(s.week / 4)")
            let dm = m1 - m0 + (h.next() - 0.5) * 0.12
            m = abs(dm) < 0.02 ? "Hard to say" : dm > 0 ? "Better?" : "Worse?"
        }
        return ForecastText(customers: gutWord(cv), margin: m, byAnalyst: false)
    }
}
