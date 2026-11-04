import Foundation
import GameCore
import Countries
import Finance

/// Sale add-ons of the two car sales companies (trades `usedcar` and `cardealer`): dealer warranty, car loans through the bank, and insurance at
/// the sale. One reusable module: the dealer's sale code asks `offers(forSale:car:company:state:data:)` what a sale could bring (for previews) and calls
/// `apply(_:companyID:sale:data:)` when a car is sold; `weekly(_:companyIndex:data:)` runs the setup reviews, warranty claims and expiries.
///
/// Money only moves through `Payments` (cash in or out, booked in the company's accounts), so `Ledger.gaps` stays empty:
///  - Warranty: the customer's extension price is revenue. Every warranty (included or sold) sets aside a reserve for the claims it is expected to
///    bring: an expense in the accounts and a real liability (`payables["warr"]`, see `reserve(_:)`). Claims are paid in cash from the reserve (any
///    excess is an expense when it falls); what is left when a warranty ends is released back to the accounts.
///  - Loans: the customer's loan is the bank's. The bank pays the dealer a commission on the financed amount (revenue). A declined application can lose the sale.
///  - Insurance: the customer pays the insurer and holds a real policy record; the insurer pays the dealer a one-time commission on the first-year premium.
/// Data: `dealer_addons.json`. Stored on the company under `dap`, written only once something is set or sold.
public enum DealerAddon: String, CaseIterable, Sendable, Identifiable {
    case warranty = "wty"
    case loan
    case insurance = "ins"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .warranty: return "Dealer warranty"
        case .loan: return "Car loans through the bank"
        case .insurance: return "Insurance at the sale"
        }
    }
}

/// The car being sold, as far as the add-ons care: how old and how worn it is.
public struct DealerCar: Sendable, Equatable {
    public var title: String
    public var ageYears: Double
    /// 0 as new ... 1 worn out.
    public var wear: Double
    public init(title: String, ageYears: Double, wear: Double) { self.title = title; self.ageYears = max(0, ageYears); self.wear = clamp(wear, 0, 1) }
    /// A new car from the showroom.
    public static func new(title: String) -> DealerCar { DealerCar(title: title, ageYears: 0, wear: 0.02) }
}

/// One sale as the dealer's sale code reports it. `key` makes the customer's choices repeatable (use the car's or the sale's id).
public struct DealerSale: Sendable, Equatable {
    public var key: String
    public var price: Double
    public var car: DealerCar
    public init(key: String, price: Double, car: DealerCar) { self.key = key; self.price = price; self.car = car }
}

public struct DealerAddonOffer: Sendable, Equatable, Identifiable {
    public var id: String { addon.rawValue }
    public var addon: DealerAddon
    /// Set up (approved) and switched on: `apply` will use it.
    public var active: Bool
    public var setUp: Bool
    /// Chance that a customer takes it (for the loan: that the customer finances through you and is approved).
    public var takeRate: Double
    /// What the customer pays or owes for it (warranty price, financed amount, first-year premium).
    public var customerPrice: Double
    public var expectedIncome: Double
    /// Expected claims reserve (warranty only).
    public var expectedCost: Double
    public var expectedNet: Double { expectedIncome - expectedCost }
    /// Chance the sale is lost because the bank declines (loans only).
    public var lostSaleChance: Double
    /// Relative lift of the sale chance the add-on gives (use as 1 + demandBoost).
    public var demandBoost: Double
    /// Customer's yearly saving against buying separately (insurance).
    public var customerSaving: Double
    public var detail: String
}

public struct DealerAddonResult: Sendable, Equatable {
    /// False when the bank declined the customer and the customer walked away: the dealer's sale code must not complete the sale.
    public var saleCompleted = true
    public var financedAmount = 0.0
    public var financeDeclined = false
    public var financeCommission = 0.0
    public var warrantyMonths = 0
    public var warrantyPrice = 0.0
    public var warrantyReserve = 0.0
    public var policyNumber: String?
    public var insuranceCommission = 0.0
    /// Cash that reached the company through the add-ons (commissions and warranty prices).
    public var income: Double { financeCommission + warrantyPrice + insuranceCommission }
    public var lines: [String] = []
    public init() {}
}

public struct DealerAddonSettings: Equatable, Sendable {
    public var warrantyOn = false, loanOn = false, insuranceOn = false
    public var includedMonths = 0
    public var extraMonths = 12
    /// Extended warranty price per year as a share of the car price.
    public var extraRate = 0.07
    public var loanCommission = 0.02
    public var insuranceCommission = 0.15
    public init() {}
}

public struct DealerSetupRequirement: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var cost: Double
    public var reviewWeeks: Int
    public var isLicence: Bool
}

public struct DealerSetupCondition: Sendable, Equatable {
    public var text: String
    public var met: Bool
}

public enum DealerSetupPhase: Sendable, Equatable {
    case notStarted
    case inReview(weeksLeft: Int)
    case approved
    case rejected(reason: String)
}

public struct DealerSetupStatus: Sendable, Equatable {
    public var addon: DealerAddon
    public var phase: DealerSetupPhase
    public var requirements: [DealerSetupRequirement]
    public var conditions: [DealerSetupCondition]
    public var totalCost: Double
    public var reviewWeeks: Int
    public var canStart: Bool
}

public enum DealerSetupResult: Sendable, Equatable {
    case started(cost: Double, reviewWeeks: Int)
    case refused(String)
}

public struct DealerWarrantyRecord: Sendable, Equatable, Identifiable {
    public var id: Int
    public var car: String
    public var soldWeek: Int
    public var untilWeek: Int
    public var months: Int
    public var extraPrice: Double
    /// Reserve still held for this warranty.
    public var reserveLeft: Double
}

public struct DealerPolicyRecord: Sendable, Equatable, Identifiable {
    public var id: Int
    public var number: String
    public var car: String
    public var week: Int
    public var untilWeek: Int
    public var premium: Double
    public var commission: Double
    public var yearlySaving: Double
}

public struct DealerAddonTotals: Sendable, Equatable {
    public var warrantiesSold = 0, extendedSold = 0
    public var warrantyRevenue = 0.0, claimsPaid = 0.0, claimCount = 0, reserveReleased = 0.0
    public var financedSales = 0, financedAmount = 0.0, financeCommission = 0.0, financeDeclined = 0
    public var policies = 0, insuranceCommission = 0.0
    public init() {}
}

public enum DealerAddons {
    public static let tradeIDs: Set<String> = ["usedcar", "cardealer"]
    public static let reserveKey = "warr"

    static let book: JSONValue = {
        guard let url = Bundle.module.url(forResource: "dealer_addons", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    static func n(_ a: DealerAddon, _ key: String) -> Double { book[a.rawValue][key].double }
    static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }
    public static func supports(_ co: Company) -> Bool { tradeIDs.contains(co.type) }

    // MARK: Settings

    public static func settings(_ co: Company) -> DealerAddonSettings {
        let d = co.value("dap"), on = d["on"], c = d["cfg"]
        var r = DealerAddonSettings()
        r.warrantyOn = on["wty"].bool; r.loanOn = on["loan"].bool; r.insuranceOn = on["ins"].bool
        r.includedMonths = c["inc"].isNull ? (co.type == "cardealer" ? 12 : Int(n(.warranty, "defaultIncludedMonths"))) : c["inc"].int
        r.extraMonths = c["xm"].isNull ? Int(n(.warranty, "defaultExtraMonths")) : c["xm"].int
        r.extraRate = c["xr"].isNull ? n(.warranty, "defaultExtraRate") : c["xr"].double
        r.loanCommission = c["lc"].isNull ? n(.loan, "defaultCommission") : c["lc"].double
        r.insuranceCommission = c["ic"].isNull ? n(.insurance, "defaultCommission") : c["ic"].double
        return r
    }

    static func put(_ s: inout GameState, _ i: Int, _ path: [String], _ v: JSONValue) {
        var d = s.companies[i].value("dap")
        if path.count == 1 { d[path[0]] = v } else {
            var sub = d[path[0]]
            sub[path[1]] = v
            d[path[0]] = sub
        }
        s.companies[i].set("dap", d)
    }

    /// Switch an add-on on or off. Only an approved add-on can be switched on.
    @discardableResult
    public static func setEnabled(_ s: inout GameState, companyID: Int, addon: DealerAddon, on: Bool) -> String? {
        guard let i = s.companyIndex(companyID), supports(s.companies[i]) else { return "This company does not sell cars." }
        if on && phase(s.companies[i], addon, week: s.week) != .approved { return "Finish the setup first." }
        put(&s, i, ["on", addon.rawValue], on ? 1 : 0)
        return nil
    }

    public static func setWarranty(_ s: inout GameState, companyID: Int, includedMonths: Int? = nil, extraMonths: Int? = nil, extraRate: Double? = nil) {
        guard let i = s.companyIndex(companyID), supports(s.companies[i]) else { return }
        if let m = includedMonths { put(&s, i, ["cfg", "inc"], .number(Double(max(0, m)))) }
        if let m = extraMonths { put(&s, i, ["cfg", "xm"], .number(Double(max(0, m)))) }
        if let r = extraRate { put(&s, i, ["cfg", "xr"], .number(max(0, r))) }
    }

    /// The dealer's own share. Within the partner's schedule (loans 1 to 3 percent of the financed amount, insurance 10 to 20 percent of the first-year premium).
    public static func setCommission(_ s: inout GameState, companyID: Int, addon: DealerAddon, rate: Double) {
        guard let i = s.companyIndex(companyID), supports(s.companies[i]) else { return }
        switch addon {
        case .warranty: return
        case .loan: put(&s, i, ["cfg", "lc"], .number(clamp(rate, n(.loan, "commissionMin"), n(.loan, "commissionMax"))))
        case .insurance: put(&s, i, ["cfg", "ic"], .number(clamp(rate, n(.insurance, "commissionMin"), n(.insurance, "commissionMax"))))
        }
    }

    // MARK: Setup

    static func requirements(_ a: DealerAddon, cur: Currency) -> [DealerSetupRequirement] {
        book[a.rawValue]["requirements"].array.map {
            DealerSetupRequirement(id: $0["id"].string, title: $0["title"].string, detail: $0["detail"].string, cost: cur.scaledPrice($0["cost"].double),
                                   reviewWeeks: $0["weeks"].int, isLicence: $0["licence"].bool)
        }
    }

    static func conditions(_ co: Company, _ a: DealerAddon, week: Int) -> [DealerSetupCondition] {
        var out = [DealerSetupCondition(text: "The company is open", met: co.status == .open)]
        let rep = n(a, "minReputation"), age = Int(n(a, "minWeeksOpen"))
        if rep > 0 { out.append(DealerSetupCondition(text: "Reputation at least \(Int(rep))", met: co.reputation >= rep)) }
        if age > 0 { out.append(DealerSetupCondition(text: "Trading for at least \(age) weeks", met: week - (co.openedWeek ?? co.foundedWeek) >= age)) }
        return out
    }

    static func phase(_ co: Company, _ a: DealerAddon, week: Int) -> DealerSetupPhase {
        let r = co.value("dap")["set"][a.rawValue]
        switch r["ph"].string {
        case "ok": return .approved
        case "no": return .rejected(reason: r["why"].string)
        case "review": return .inReview(weeksLeft: max(0, r["ready"].int - week))
        default: return .notStarted
        }
    }

    public static func setupStatus(_ s: GameState, companyID: Int, addon: DealerAddon, data: GameData) -> DealerSetupStatus? {
        guard let co = s.company(companyID), supports(co) else { return nil }
        let cur = World(state: s, data: data).currency(co)
        let reqs = requirements(addon, cur: cur)
        let conds = conditions(co, addon, week: s.week)
        let ph = phase(co, addon, week: s.week)
        var can = conds.allSatisfy { $0.met }
        if ph == .approved { can = false }
        if case .inReview = ph { can = false }
        return DealerSetupStatus(addon: addon, phase: ph, requirements: reqs, conditions: conds, totalCost: reqs.reduce(0) { $0 + $1.cost },
                                 reviewWeeks: reqs.map { $0.reviewWeeks }.max() ?? 0, canStart: can)
    }

    /// Pay the one-time fees of every requirement and start the review. The review takes as long as the slowest requirement; fees are not refunded if it fails.
    public static func startSetup(_ s: inout GameState, companyID: Int, addon: DealerAddon, data: GameData) -> DealerSetupResult {
        guard let st = setupStatus(s, companyID: companyID, addon: addon, data: data), let i = s.companyIndex(companyID) else { return .refused("This company does not sell cars.") }
        switch st.phase {
        case .approved: return .refused("Already set up.")
        case .inReview: return .refused("The application is already being reviewed.")
        default: break
        }
        if let bad = st.conditions.first(where: { !$0.met }) { return .refused("Not yet: \(bad.text.lowercased()).") }
        if s.companies[i].cash < st.totalCost { return .refused("The company cannot pay the setup fees.") }
        for r in st.requirements { Payments.companyPays(&s, companyID: companyID, amount: r.cost, category: "oth", label: "\(addon.title) setup: \(r.title)") }
        put(&s, i, ["set", addon.rawValue], .object(["ph": "review", "from": .number(Double(s.week)), "ready": .number(Double(s.week + st.reviewWeeks)), "paid": .number(st.totalCost)]))
        return .started(cost: st.totalCost, reviewWeeks: st.reviewWeeks)
    }

    // MARK: Models

    static func claimRate(_ car: DealerCar) -> Double {
        n(.warranty, "claimsBase") + n(.warranty, "claimsPerYear") * car.ageYears + n(.warranty, "claimsPerWear") * car.wear
    }
    static func meanSpread() -> Double { (n(.warranty, "claimLow") + n(.warranty, "claimHigh")) / 2 }
    /// The claims a warranty of `months` months is expected to bring.
    static func expectedClaims(price: Double, car: DealerCar, months: Int) -> Double {
        claimRate(car) * Double(months) / 12 * n(.warranty, "claimShare") * meanSpread() * price
    }

    struct WarrantyQuote { var included: Double; var extraPrice: Double; var extraReserve: Double; var take: Double; var fairRate: Double; var boost: Double }
    static func warrantyQuote(price: Double, car: DealerCar, cfg: DealerAddonSettings) -> WarrantyQuote {
        let fair = max(n(.warranty, "perceivedFloor"), claimRate(car) * n(.warranty, "claimShare") * meanSpread() * n(.warranty, "fairLoad"))
        let ratio = max(1e-9, cfg.extraRate / fair)
        let worry = min(car.ageYears, n(.warranty, "worryYears")) / n(.warranty, "worryYears")
        let take = cfg.extraMonths > 0 ? logistic(n(.warranty, "takeBase") + n(.warranty, "takeWorry") * worry - n(.warranty, "takeSlope") * log(ratio)) : 0
        return WarrantyQuote(included: expectedClaims(price: price, car: car, months: cfg.includedMonths), extraPrice: jsRound(price * cfg.extraRate * Double(cfg.extraMonths) / 12),
                             extraReserve: expectedClaims(price: price, car: car, months: cfg.includedMonths + cfg.extraMonths), take: take, fairRate: fair,
                             boost: n(.warranty, "boostPerIncludedYear") * Double(cfg.includedMonths) / 12)
    }

    struct LoanQuote { var need: Double; var prefer: Double; var approval: Double; var financed: Double; var commission: Double; var apr: Double; var boost: Double }
    static func loanQuote(price: Double, car: DealerCar, cfg: DealerAddonSettings, bench: Double) -> LoanQuote {
        let need = n(.loan, "needBase") + n(.loan, "needSlope") * (1 - exp(-price / bench))
        let markup = cfg.loanCommission / (n(.loan, "termYears") / 2)
        let prefer = logistic(n(.loan, "preferBase") - n(.loan, "preferSlope") * (markup - n(.loan, "preferRefMarkup")))
        let approval = logistic(n(.loan, "approveBase") - n(.loan, "approvePerBench") * price / bench - n(.loan, "approvePerYear") * car.ageYears)
        let financed = jsRound(price * (1 - n(.loan, "deposit")))
        return LoanQuote(need: need, prefer: prefer, approval: approval, financed: financed, commission: jsRound(financed * cfg.loanCommission),
                         apr: n(.loan, "baseApr") + markup, boost: n(.loan, "boostFromNeed") * need)
    }

    struct InsuranceQuote { var independent: Double; var bundled: Double; var discount: Double; var commission: Double; var take: Double }
    static func insuranceQuote(price: Double, car: DealerCar, cfg: DealerAddonSettings) -> InsuranceQuote {
        let independent = jsRound(price * n(.insurance, "premiumRate") * (1 + n(.insurance, "premiumAgeLoad") * car.ageYears))
        let discount = max(0, n(.insurance, "distributionBudget") - cfg.insuranceCommission)
        let bundled = jsRound(independent * (1 - discount))
        return InsuranceQuote(independent: independent, bundled: bundled, discount: discount, commission: jsRound(bundled * cfg.insuranceCommission),
                              take: logistic(n(.insurance, "takeBase") + n(.insurance, "takeSlope") * discount))
    }

    static func benchmark(_ co: Company, state s: GameState, data: GameData) -> Double {
        // The benchmark sits where the file puts it against a typical car; car money in this game is the trade's own ticket (a used car about 180 000
        // accounting units), so it scales with the ticket, not with the file's realistic prices (a 16 000 benchmark made every loan look unaffordable).
        // One ratio for every trade: the benchmark is 1.8 times the trade's ticket, so a car sold at the ticket price is approved about 90 percent
        // of the time and a dearer one less.
        let ticket = data.catalog[co.type]?.ticket ?? 0
        let scale = ticket > 0 ? ticket / 10000 : 1
        return World(state: s, data: data).currency(co).scaledPrice(book["benchmarkPrice"].double * scale)
    }

    // MARK: Offers

    /// What the add-ons would bring on a sale at `price`: take rates and expected income per sale, for the sale screen and the settings preview.
    /// Empty for a company that is not a car dealer.
    public static func offers(forSale price: Double, car: DealerCar, company co: Company, state s: GameState, data: GameData) -> [DealerAddonOffer] {
        guard supports(co) else { return [] }
        let cfg = settings(co), bench = benchmark(co, state: s, data: data)
        let w = warrantyQuote(price: price, car: car, cfg: cfg), l = loanQuote(price: price, car: car, cfg: cfg, bench: bench), q = insuranceQuote(price: price, car: car, cfg: cfg)
        func isSet(_ a: DealerAddon) -> Bool { phase(co, a, week: s.week) == .approved }
        let pct: (Double) -> String = { String(format: "%.1f%%", $0 * 100) }
        let wOn = cfg.warrantyOn && isSet(.warranty), lOn = cfg.loanOn && isSet(.loan), iOn = cfg.insuranceOn && isSet(.insurance)
        let pFin = l.need * l.prefer
        return [
            DealerAddonOffer(addon: .warranty, active: wOn, setUp: isSet(.warranty), takeRate: w.take, customerPrice: w.extraPrice, expectedIncome: w.take * w.extraPrice,
                             expectedCost: w.included + w.take * (w.extraReserve - w.included), lostSaleChance: 0, demandBoost: w.boost, customerSaving: 0,
                             detail: "\(cfg.includedMonths) months included, \(cfg.extraMonths) more for \(pct(cfg.extraRate)) of the price a year. Fair price to a customer: \(pct(w.fairRate)) a year."),
            DealerAddonOffer(addon: .loan, active: lOn, setUp: isSet(.loan), takeRate: pFin * l.approval, customerPrice: l.financed, expectedIncome: pFin * l.approval * l.commission,
                             expectedCost: 0, lostSaleChance: pFin * (1 - l.approval) * n(.loan, "walkAway"), demandBoost: l.boost, customerSaving: 0,
                             detail: "\(Int((pFin * 100).rounded())) in 100 customers finance with you, the bank approves \(Int((l.approval * 100).rounded())) in 100. Customer rate \(pct(l.apr)), your commission \(pct(cfg.loanCommission))."),
            DealerAddonOffer(addon: .insurance, active: iOn, setUp: isSet(.insurance), takeRate: q.take, customerPrice: q.bundled, expectedIncome: q.take * q.commission,
                             expectedCost: 0, lostSaleChance: 0, demandBoost: n(.insurance, "boostPerSaving") * q.discount, customerSaving: q.independent - q.bundled,
                             detail: "First year \(pct(q.discount)) cheaper than buying it separately; your one-time commission \(pct(cfg.insuranceCommission)) of the premium."),
        ]
    }

    /// A typical car and price for the settings preview: the sale of an average car of the trade, scaled to the company's currency.
    public static func typicalSale(company co: Company, state s: GameState, data: GameData) -> (price: Double, car: DealerCar) {
        let t = book["typicalCar"][co.type]
        let cur = World(state: s, data: data).currency(co)
        let ticket = data.catalog[co.type]?.ticket ?? 0
        let price = cur.scaledPrice(ticket > 0 ? ticket : (t["price"].isNull ? 14000 : t["price"].double))
        return (price, DealerCar(title: "Typical car", ageYears: t["age"].double, wear: t["wear"].double))
    }

    // MARK: Reads

    /// The reserve held for warranty claims: a real liability of the company.
    public static func reserve(_ co: Company) -> Double { co.payables[reserveKey] ?? 0 }
    public static func totals(_ co: Company) -> DealerAddonTotals {
        let t = co.value("dap")["st"]
        var r = DealerAddonTotals()
        r.warrantiesSold = t["wn"].int; r.extendedSold = t["xn"].int; r.warrantyRevenue = t["wr"].double; r.claimsPaid = t["cp"].double; r.claimCount = t["cn"].int
        r.reserveReleased = t["rl"].double; r.financedSales = t["fn"].int; r.financedAmount = t["fa"].double; r.financeCommission = t["fc"].double
        r.financeDeclined = t["fd"].int; r.policies = t["pn"].int; r.insuranceCommission = t["pc"].double
        return r
    }
    public static func warranties(_ co: Company) -> [DealerWarrantyRecord] {
        co.value("dap")["wty"].array.map { DealerWarrantyRecord(id: $0["id"].int, car: $0["car"].string, soldWeek: $0["wk"].int, untilWeek: $0["until"].int, months: $0["m"].int, extraPrice: $0["xp"].double, reserveLeft: $0["left"].double) }
    }
    public static func policies(_ co: Company) -> [DealerPolicyRecord] {
        co.value("dap")["pol"].array.map { DealerPolicyRecord(id: $0["id"].int, number: $0["no"].string, car: $0["car"].string, week: $0["wk"].int, untilWeek: $0["until"].int, premium: $0["prem"].double, commission: $0["com"].double, yearlySaving: $0["sav"].double) }
    }

    // MARK: Applying a sale

    /// Call when a car has been sold. Books what the add-ons bring through `Payments`. If `saleCompleted` is false the bank declined and the customer walked away.
    @discardableResult
    public static func apply(_ s: inout GameState, companyID: Int, sale: DealerSale, data: GameData) -> DealerAddonResult {
        var res = DealerAddonResult()
        guard let i = s.companyIndex(companyID), supports(s.companies[i]), s.companies[i].status.isLive else { return res }
        let co = s.companies[i], cfg = settings(co)
        let bench = benchmark(co, state: s, data: data)
        let cur = World(state: s, data: data).currency(co)
        var rnd = HashedRandom("\(s.seed):dap:\(companyID):\(s.week):\(s.day):\(sale.key)")
        let rFin = rnd.next(), rPrefer = rnd.next(), rApprove = rnd.next(), rWalk = rnd.next(), rWty = rnd.next(), rIns = rnd.next()
        let week = s.week
        func on(_ a: DealerAddon) -> Bool {
            let ok = phase(co, a, week: week) == .approved
            switch a {
            case .warranty: return cfg.warrantyOn && ok
            case .loan: return cfg.loanOn && ok
            case .insurance: return cfg.insuranceOn && ok
            }
        }
        let name = sale.car.title
        // 1. The bank
        if on(.loan) {
            let l = loanQuote(price: sale.price, car: sale.car, cfg: cfg, bench: bench)
            if rFin < l.need && rPrefer < l.prefer {
                if rApprove < l.approval {
                    Payments.companyReceives(&s, companyID: companyID, amount: l.commission, category: "rev", label: "Finance commission: \(name)")
                    res.financedAmount = l.financed; res.financeCommission = jsRound(l.commission)
                    res.lines.append("Financed \(cur.display(l.financed)) through the bank; commission \(cur.display(jsRound(l.commission)))")
                    bump(&s, i, "fn", 1); bump(&s, i, "fa", l.financed); bump(&s, i, "fc", jsRound(l.commission))
                    var f = s.companies[i].value("dap")["fin"].array
                    f.append(.object(["id": .number(nextID(&s, i)), "wk": .number(Double(s.week)), "car": .string(name), "amt": .number(l.financed), "apr": .number(l.apr), "com": .number(jsRound(l.commission))]))
                    put(&s, i, ["fin"], .array(f))
                } else {
                    res.financeDeclined = true
                    bump(&s, i, "fd", 1)
                    if rWalk < n(.loan, "walkAway") {
                        res.saleCompleted = false
                        res.lines.append("The bank declined the customer's loan and the customer left")
                        return res
                    }
                    res.lines.append("The bank declined the loan; the customer paid in cash")
                }
            }
        }
        // 2. Warranty
        if on(.warranty) {
            let w = warrantyQuote(price: sale.price, car: sale.car, cfg: cfg)
            let extra = rWty < w.take
            let months = cfg.includedMonths + (extra ? cfg.extraMonths : 0)
            if months > 0 {
                if extra && w.extraPrice > 0 {
                    Payments.companyReceives(&s, companyID: companyID, amount: w.extraPrice, category: "rev", label: "Extended warranty: \(name)")
                    res.warrantyPrice = w.extraPrice
                    bump(&s, i, "wr", w.extraPrice); bump(&s, i, "xn", 1)
                }
                let reserve = jsRound(expectedClaims(price: sale.price, car: sale.car, months: months))
                if reserve > 0 {
                    Payments.book(&s, companyID: companyID, category: "oth", amount: reserve)
                    s.companies[i].addPayable(reserveKey, reserve)
                }
                let until = s.week + Int((Double(months) * 52 / 12).rounded(.up))
                var list = s.companies[i].value("dap")["wty"].array
                list.append(.object(["id": .number(nextID(&s, i)), "car": .string(name), "wk": .number(Double(s.week)), "until": .number(Double(until)), "m": .number(Double(months)),
                                     "xp": .number(extra ? w.extraPrice : 0), "lam": .number(claimRate(sale.car)), "px": .number(sale.price), "left": .number(reserve)]))
                put(&s, i, ["wty"], .array(list))
                bump(&s, i, "wn", 1)
                res.warrantyMonths = months; res.warrantyReserve = reserve
                res.lines.append("\(months) months warranty" + (extra ? ", extension sold for \(cur.display(w.extraPrice))" : " included") + "; reserve \(cur.display(reserve))")
            }
        }
        // 3. Insurance
        if on(.insurance) {
            let q = insuranceQuote(price: sale.price, car: sale.car, cfg: cfg)
            if rIns < q.take {
                if q.commission > 0 { Payments.companyReceives(&s, companyID: companyID, amount: q.commission, category: "rev", label: "Insurance commission: \(name)") }
                let id = nextID(&s, i)
                var r = HashedRandom("\(s.seed):dapol:\(companyID):\(id)")
                let digits: String = (0..<5).map { _ in String(Int((r.next() * 10).rounded(.down))) }.joined()
                let no = "DI-" + String(GameCalendar.year(week: s.week)) + "-" + digits
                var list = s.companies[i].value("dap")["pol"].array
                list.append(.object(["id": .number(id), "no": .string(no), "car": .string(name), "wk": .number(Double(s.week)),
                                     "until": .number(Double(s.week) + n(.insurance, "policyYearWeeks")), "prem": .number(q.bundled), "com": .number(q.commission),
                                     "sav": .number(q.independent - q.bundled)]))
                put(&s, i, ["pol"], .array(list))
                bump(&s, i, "pn", 1); bump(&s, i, "pc", q.commission)
                res.policyNumber = no; res.insuranceCommission = q.commission
                res.lines.append("Insurance policy \(no); commission \(cur.display(q.commission))")
            }
        }
        return res
    }

    static func nextID(_ s: inout GameState, _ i: Int) -> Double {
        let id = s.companies[i].value("dap")["n"].double + 1
        put(&s, i, ["n"], .number(id))
        return id
    }

    static func bump(_ s: inout GameState, _ i: Int, _ key: String, _ by: Double) {
        put(&s, i, ["st", key], .number(s.companies[i].value("dap")["st"][key].double + by))
    }

    // MARK: Weekly

    /// Setup reviews, warranty claims and expiries. Call once a week for each car dealer.
    public static func weekly(_ s: inout GameState, companyIndex i: Int, data: GameData) {
        guard s.companies.indices.contains(i), supports(s.companies[i]), s.companies[i].status.isLive, !s.companies[i].value("dap").isNull else { return }
        reviews(&s, i, data: data)
        claims(&s, i, data: data)
    }

    static func reviews(_ s: inout GameState, _ i: Int, data: GameData) {
        for a in DealerAddon.allCases {
            let co = s.companies[i]
            let r = co.value("dap")["set"][a.rawValue]
            guard r["ph"].string == "review", r["ready"].int <= s.week else { continue }
            let bad = conditions(co, a, week: s.week).first { !$0.met }
            if let bad = bad {
                let why = "The application was turned down: \(bad.text.lowercased()). The fees are not refunded."
                put(&s, i, ["set", a.rawValue], .object(["ph": "no", "why": .string(why), "from": r["from"], "paid": r["paid"]]))
                s.addMessage(from: co.name, title: "\(a.title): application declined", body: why, companyID: co.id, tone: "bad")
            } else {
                put(&s, i, ["set", a.rawValue], .object(["ph": "ok", "from": r["from"], "paid": r["paid"], "done": .number(Double(s.week))]))
                s.addMessage(from: co.name, title: "\(a.title): approved", body: "The partner contracts and registrations are in place. You can switch it on in the company's add-on settings.", companyID: co.id, tone: "good")
            }
        }
    }

    static func claims(_ s: inout GameState, _ i: Int, data: GameData) {
        let id = s.companies[i].id
        var list = s.companies[i].value("dap")["wty"].array
        guard !list.isEmpty else { return }
        var keep: [JSONValue] = []
        for var w in list {
            if s.week >= w["until"].int {
                let left = w["left"].double
                if left > 0 {
                    var p = s.companies[i].payables
                    p[reserveKey] = max(0, (p[reserveKey] ?? 0) - left)
                    if (p[reserveKey] ?? 0) < 0.5 { p[reserveKey] = nil }
                    s.companies[i].payables = p
                    Payments.book(&s, companyID: id, category: "oth", amount: -left)
                    bump(&s, i, "rl", left)
                }
                continue
            }
            var r = HashedRandom("\(s.seed):dapclaim:\(id):\(w["id"].int):\(s.week)")
            let chance = 1 - exp(-w["lam"].double / 52)
            if r.next() < chance {
                let cost = jsRound(w["px"].double * n(.warranty, "claimShare") * (n(.warranty, "claimLow") + (n(.warranty, "claimHigh") - n(.warranty, "claimLow")) * r.next()))
                let fromReserve = min(cost, w["left"].double)
                if fromReserve > 0 {
                    Payments.companyPays(&s, companyID: id, amount: fromReserve, category: nil, label: "Warranty repair: \(w["car"].string)")
                    var p = s.companies[i].payables
                    p[reserveKey] = max(0, (p[reserveKey] ?? 0) - fromReserve)
                    if (p[reserveKey] ?? 0) < 0.5 { p[reserveKey] = nil }
                    s.companies[i].payables = p
                    w["left"] = .number(w["left"].double - fromReserve)
                }
                if cost > fromReserve { Payments.companyPays(&s, companyID: id, amount: cost - fromReserve, category: "oth", label: "Warranty repair above the reserve: \(w["car"].string)") }
                bump(&s, i, "cp", cost); bump(&s, i, "cn", 1)
            }
            keep.append(w)
        }
        list = keep
        put(&s, i, ["wty"], .array(list))
    }
}
