import Foundation
import GameCore
import Countries
import Finance

/// Companies that depend on each other. A buyer can switch an input (cleaning, building materials, freight, food, power ...)
/// from outside suppliers to one of your own companies at market price, cost plus 10% or cost. The supplier gets the volume
/// (and uses its capacity), the group keeps the margin, and supply is steadier, until the supplier struggles: then the buyer
/// pays for emergency supply and its reputation suffers. Original: features/company/intercompany_supply.js (`R27`).
/// The links are saved in `rest["l27"]`. As in the original, a sale between your companies is booked as revenue of the supplier
/// and a lower cost of the buyer, with VAT as on any sale in the country (`transferVat`); the profit tax of each company follows from its own books.
/// Not ported: the 'supply from inside' protection against outside supplier events, the 25%-of-capital limit on lending from your own bank.
public enum IntercompanySupply {
    public struct Kind: Equatable, Sendable {
        public var id: String
        public var name: String
        /// Trades that can supply it
        public var suppliers: [String]
        /// The supplier has to be in the buyer's city
        public var local: Bool
        /// Where the saving shows in the buyer's books
        public var category: String
        /// Takes no capacity of the supplier (electricity)
        public var noCapacity: Bool
        /// Share of sales each buying trade spends on it
        public var buyers: [String: Double]
        /// A delivery service: the spend is a share of the sales a delivery add-on brings, not of all sales (`weeklySpend`).
        public var delivered = false
    }

    /// The kinds, from `Resources/supply_kinds.json` (a new kind or trade is data only).
    public static let kinds: [Kind] = {
        guard let url = Bundle.module.url(forResource: "supply_kinds", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [] }
        return j["kinds"].array.map { k in
            Kind(id: k["id"].string, name: k["name"].string, suppliers: k["suppliers"].array.map { $0.string }, local: k["local"].bool, category: k["category"].string,
                 noCapacity: k["noCapacity"].bool, buyers: k["buyers"].object.mapValues { $0.double }, delivered: k["delivered"].bool)
        }
    }()

    public static func kind(_ id: String) -> Kind? { kinds.first { $0.id == id } }
    public static let modes: [(id: String, name: String)] = [("mkt", "Market price"), ("c10", "Cost + 10%"), ("cost", "At cost")]
    public static func modeName(_ id: String) -> String { modes.first { $0.id == id }?.name ?? id }

    // MARK: Links

    static func rawLinks(_ s: GameState) -> [JSONValue] { s.rest["l27"]?.array ?? [] }

    public struct Link: Equatable, Identifiable, Sendable {
        public var id: Int
        public var kindID: String
        public var buyerID: Int
        public var supplierID: Int
        public var mode: String
        /// Last week: spend, share delivered, price factor
        public var lastSpend: Double
        public var lastShare: Double
        public var lastPriceFactor: Double
        /// Saved by the buyer since the link started
        public var saved: Double
        /// How the buyer pays: nil = settled weekly, else a terms id ("net14", "net30").
        public var termsID: String?
        init(_ j: JSONValue) {
            termsID = j["tm"].isNull ? nil : j["tm"].string
            id = j["id"].int; kindID = j["k"].string; buyerID = j["b"].int; supplierID = j["s"].int; mode = j["mode"].string
            lastSpend = j["last"]["x"].double; lastShare = j["last"]["f"].isNull ? 1 : j["last"]["f"].double; lastPriceFactor = j["last"]["pf"].isNull ? 1 : j["last"]["pf"].double
            saved = j["sum"].double
        }
    }

    static func isLive(_ c: Company?) -> Bool { c != nil && c!.status.isLive }

    /// The links whose buyer and supplier both still exist.
    public static func links(_ s: GameState) -> [Link] {
        rawLinks(s).filter { isLive(s.company($0["b"].int)) && isLive(s.company($0["s"].int)) }.map { Link($0) }
    }
    public static func link(_ s: GameState, buyer: Int, kind: String) -> Link? { links(s).first { $0.buyerID == buyer && $0.kindID == kind } }

    /// Inputs this company buys that your own companies might supply. Original: `kindsFor`.
    public static func kindsFor(_ co: Company) -> [Kind] { kinds.filter { $0.buyers[co.type] != nil && !$0.suppliers.contains(co.type) } }

    /// Your companies that could supply this buyer. Original: `suppliersFor`.
    public static func suppliers(_ s: GameState, for co: Company, kind k: Kind) -> [Company] {
        s.companies.filter { $0.status == .open && $0.id != co.id && k.suppliers.contains($0.type) && $0.countryCode == co.countryCode && (!k.local || $0.cityID == co.cityID) }
    }

    /// The supplier's full cost per unit of sales, from its own results. Original: `costRatio`.
    /// `perkCut` is the industrial titan perk (`Ambitions.supplyCostCut`): your own suppliers work that much cheaper for the group.
    public static func costRatio(_ c: Company, data: GameData, perkCut: Double = 0) -> Double {
        let h = c.monthlyHistory.suffix(3)
        let rv = h.reduce(0.0) { $0 + $1.revenue }, pf = h.reduce(0.0) { $0 + $1.profit }
        let cr = (rv > 0 ? 1 - pf / rv : 1 - (data.catalog[c.type]?.margin ?? 0.1)) * (1 - perkCut)
        return clamp(cr, 0.45, 1.3)
    }
    static func varRatio(_ c: Company, data: GameData) -> Double {
        let b = (c.books.month["rev"] ?? 0) != 0 ? c.books.month : c.books.year
        let rev = b["rev"] ?? 0
        return clamp(rev != 0 ? (b["cogs"] ?? 0) / rev : (data.catalog[c.type]?.costOfSales ?? 0.3), 0.05, 0.8)
    }
    /// A transfer price never goes above what the buyer would pay outside. Original: `pfOf`.
    public static func priceFactor(mode: String, supplier c: Company, data: GameData, perkCut: Double = 0) -> Double {
        mode == "mkt" ? 1 : mode == "c10" ? min(1, costRatio(c, data: data, perkCut: perkCut) * 1.1) : min(1, costRatio(c, data: data, perkCut: perkCut))
    }

    /// Weekly spend of a buyer on an input. Original: `spendOf`.
    /// A delivery service is paid on the orders the delivery add-on brought (`dlvRev`, kept by `SalesWays.weekly`).
    static func weeklySpend(_ b: Company, _ k: Kind) -> Double { max(0, (k.delivered ? b.num("dlvRev") : b.lastWeekRevenue) * (k.buyers[b.type] ?? 0)) }
    /// What the buyer spends on it in a year, from its last three months. Original: `yearSpend`.
    public static func yearlySpend(_ b: Company, _ k: Kind) -> Double {
        if k.delivered { return weeklySpend(b, k) * 52 }
        let h = b.monthlyHistory.suffix(3)
        let rv = h.reduce(0.0) { $0 + $1.revenue }
        let y = h.isEmpty ? b.lastWeekRevenue * 52 : rv / Double(h.count) * 12
        return max(0, y * (k.buyers[b.type] ?? 0))
    }

    // MARK: Delivery to customers

    /// The delivery service, if the data has one.
    public static var deliveryKind: Kind? { kinds.first { $0.delivered } }

    /// The add-on of this trade that sells by delivery (a platform way whose data carries `deliv`), if it has one.
    public static func deliveryWay(_ tradeID: String, _ balance: Balance) -> Balance.SalesWay? {
        balance.salesWays[tradeID]?.first { $0.kind == "platform" && ($0.options["deliv"] ?? 0) > 0 }
    }

    /// Share of the add-on's orders that actually reach the customer. An outside courier delivers its reliability (`rel` in the add-on's data).
    /// One of your own couriers delivers the share it had capacity for last week; what it could not carry goes to an outside courier.
    /// Demand only grows by this share of the add-on's lift, so a delivery that is not supplied brings no customers.
    public static func deliveryFill(_ s: GameState, buyer co: Company, way: Balance.SalesWay) -> Double {
        let rel = clamp(way.options["rel"] ?? 1, 0, 1)
        guard let k = deliveryKind,
              let l = rawLinks(s).first(where: { $0["b"].int == co.id && $0["k"].string == k.id }),
              let sp = s.company(l["s"].int), sp.status.isLive else { return rel }
        let f = sp.status != .open ? 0 : l["last"]["f"].isNull ? 1 : clamp(l["last"]["f"].double, 0, 1)
        return f + (1 - f) * rel
    }

    // MARK: Changing links

    /// Switch an input to one of your own companies. Original: `ACT.ch27set`.
    @discardableResult
    public static func setSupplier(_ s: inout GameState, buyer: Int, kind kid: String, supplier: Int, mode: String) -> Bool {
        guard let b = s.company(buyer), let sp = s.company(supplier), let k = kind(kid), k.suppliers.contains(sp.type), modes.contains(where: { $0.id == mode }) else { return false }
        AccountSupply.clear(&s, buyer: b.id, kind: kid)   // a new supplier ends a deal with a business customer for the same input
        var L = rawLinks(s).filter { !($0["b"].int == b.id && $0["k"].string == kid) }
        L.append(.object(["id": .number(Double(s.makeID())), "k": .string(kid), "b": .number(Double(b.id)), "s": .number(Double(sp.id)), "mode": .string(mode), "w0": .number(Double(s.week))]))
        s.rest["l27"] = .array(L)
        return true
    }

    /// Agree how the buyer pays an own-company supplier: nil or "weekly" = settled each week (as always), "net14" / "net30" = on invoice.
    @discardableResult
    public static func setTerms(_ s: inout GameState, buyer: Int, kind kid: String, term: String?) -> Bool {
        var L = rawLinks(s)
        guard let k = L.firstIndex(where: { $0["b"].int == buyer && $0["k"].string == kid }) else { return false }
        if term == nil || term == "weekly" { var o = L[k].object; o.removeValue(forKey: "tm"); L[k] = .object(o) }
        else if let t = term, SupplyTerms.groupTerm(t) != nil { L[k]["tm"] = .string(t) }
        else { return false }
        s.rest["l27"] = .array(L)
        return true
    }

    /// Back to outside suppliers. Original: `ACT.ch27off`.
    public static func clearSupplier(_ s: inout GameState, buyer: Int, kind kid: String) {
        s.rest["l27"] = .array(rawLinks(s).filter { !($0["b"].int == buyer && $0["k"].string == kid) })
    }

    // MARK: The weekly settlement

    /// Capacity a supplier holds back for the group (units a week). Original: `co.int27u`.
    public static func heldBack(_ c: Company) -> Double { c.num("int27u") }

    /// VAT on a sale between two of your companies in the same country: a taxable supply like any other. The supplier charges its country's rate for
    /// its trade (nothing below its registration threshold, nothing where the country has a sales tax instead, which does not tax a sale for resale)
    /// and owes it; the buyer pays it and reclaims it, unless it is itself below the threshold, in which case it is a cost. Returns the VAT.
    /// The transfer price cap (never above the outside price) is `priceFactor`; cross-border supply is not offered (same country only), and
    /// transfer-pricing rules beyond that cap are not modelled (KNOWN_GAPS.md).
    @discardableResult
    static func transferVat(_ s: inout GameState, supplier sp: Company, buyerIndex bi: Int, net: Double, data: GameData, _ w: World, cashNow: Bool) -> Double {
        guard net > 0, let sbd = data.catalog[sp.type], !w.country(sp).usesSalesTax else { return 0 }
        let vat = jsRound(net * Vat.rate(sp, sbd, w))
        guard vat > 0, let si = s.companyIndex(sp.id) else { return 0 }
        s.companies[si].vatBalance += Double(vat)
        if cashNow {
            Ledger.moveRaw(&s, .company(sp.id), Double(vat))
            Ledger.moveRaw(&s, .company(s.companies[bi].id), -Double(vat))
        }
        if Vat.isExempt(s.companies[bi], w) {
            var b = s.companies[bi].books; b.add("oth", Double(vat)); s.companies[bi].books = b
        } else {
            s.companies[bi].vatBalance -= Double(vat)
        }
        return Double(vat)
    }

    static func weekly(_ s: inout GameState, data: GameData) {
        guard !rawLinks(s).isEmpty || s.companies.contains(where: { $0.num("int27u") > 0 }) else { return }
        let titanCut = Ambitions.supplyCostCut(s, data)
        // tickets are worked out before anything moves (they read the whole state)
        var tickets: [Int: Double] = [:]
        let w0 = World(state: s, data: data)
        for c in s.companies where c.status == .open {
            if let bd = data.catalog[c.type], rawLinks(s).contains(where: { $0["s"].int == c.id }) { tickets[c.id] = Pricing.ticket(c, bd, w0) }
        }
        var used: [Int: Double] = [:]
        var kept: [JSONValue] = []
        for l0 in rawLinks(s) {
            var l = l0
            guard let bi = s.companyIndex(l["b"].int), let K = kind(l["k"].string), s.companies[bi].status.isLive else { continue }
            let b = s.companies[bi]
            guard let si = s.companyIndex(l["s"].int), s.companies[si].status.isLive else {
                if b.status == .open {
                    s.addMessage(kind: "info", from: b.name, title: "Supplier gone: \(K.name.lowercased()) for \(b.name)",
                                 body: "Your supplier no longer exists, so \(b.name) buys \(K.name.lowercased()) outside again, at short notice and higher prices for a few weeks.", companyID: b.id, tone: "bad")
                    var mods = s.companies[bi].value("mods").array
                    mods.append(.object(["k": "cogsup", "m": 1.03, "w": 4]))
                    s.companies[bi].set("mods", .array(mods))
                }
                continue
            }
            kept.append(l)
            let sp = s.companies[si]
            if b.status != .open { continue }
            let x = weeklySpend(b, K)
            if x <= 0 { l["last"] = .object(["x": 0, "f": 1, "w": .number(Double(s.week))]); kept[kept.count - 1] = l; continue }
            let ticket = tickets[sp.id] ?? 0
            let u = K.noCapacity ? 0 : (ticket > 0 ? x / ticket : 0)
            let capB = sp.status == .open ? sp.value("lastW")["cap"].double + sp.num("int27u") : 0
            let f = K.noCapacity ? (sp.status == .open ? 1.0 : 0) : (u > 0 ? clamp(capB / u, 0, 1) : 1)
            let pf = priceFactor(mode: l["mode"].string, supplier: sp, data: data, perkCut: titanCut), vr = varRatio(sp, data: data)
            let got = x * f
            // the buyer: what it paid outside before, against what it pays the group now
            let diff = got * (1 - pf)
            if let terms = SupplyTerms.groupTerm(l["tm"].string), terms.days > 0, got > 0 {
                // On credit (`SupplyTerms`): the outside purchase the buyer would have paid is replaced by an invoice from the supplier. The buyer
                // owes it and the supplier holds the receivable; the cash moves between them when it falls due.
                Payments.companyReceives(&s, companyID: b.id, amount: got, category: nil, label: nil)
                Payments.book(&s, companyID: b.id, category: K.category, amount: -jsRound(got))
                let vat = transferVat(&s, supplier: sp, buyerIndex: bi, net: got * pf, data: data, w0, cashNow: false)
                SupplyTerms.issue(&s, buyer: b.id, provider: sp.id, vendorID: "", name: sp.name, kind: K.id, amount: got * pf + vat, weeks: terms.weeks)
                Payments.book(&s, companyID: b.id, category: K.category, amount: jsRound(got * pf))
                Payments.book(&s, companyID: sp.id, category: "rev", amount: jsRound(got * pf))
                Payments.companyPays(&s, companyID: sp.id, amount: got * vr, category: "cogs", label: nil)
            } else {
                if diff > 0 {
                    Payments.companyReceives(&s, companyID: b.id, amount: diff, category: nil, label: nil)
                    Payments.book(&s, companyID: b.id, category: K.category, amount: -jsRound(diff))
                } else if diff < 0 {
                    Payments.companyPays(&s, companyID: b.id, amount: -diff, category: K.category, label: nil)
                }
                // the supplier: sales to the group and the goods that go into them
                if got > 0 {
                    Payments.companyReceives(&s, companyID: sp.id, amount: got * pf, category: "rev", label: nil)
                    Payments.companyPays(&s, companyID: sp.id, amount: got * vr, category: "cogs", label: nil)
                    transferVat(&s, supplier: sp, buyerIndex: bi, net: got * pf, data: data, w0, cashNow: true)
                }
            }
            // what it could not deliver is bought outside at a premium, and customers notice
            if f < 0.98 {
                Payments.companyPays(&s, companyID: b.id, amount: x * (1 - f) * 0.2, category: K.category, label: nil)
                if f < 0.8 {
                    s.companies[bi].reputation = max(0, s.companies[bi].reputation - 0.4 * (1 - f))
                    if l["warn"].isNull || Double(s.week) - l["warn"].double > 6 {
                        l["warn"] = .number(Double(s.week))
                        s.addMessage(kind: "info", from: b.name, title: "\(sp.name) could not deliver to \(b.name)",
                                     body: "\(sp.name) delivered only \(Int((f * 100).rounded()))% of the \(K.name.lowercased()) \(b.name) needed. The rest was bought outside at short notice, and some customers noticed.", companyID: b.id, tone: "bad")
                    }
                }
            }
            l["last"] = .object(["x": .number(x), "f": .number(f), "pf": .number(pf), "w": .number(Double(s.week)), "save": .number(diff)])
            l["sum"] = .number(l["sum"].double + diff)
            l["gm"] = .number(l["gm"].double + got * (1 - vr))
            used[sp.id, default: 0] += u * f
            kept[kept.count - 1] = l
        }
        s.rest["l27"] = .array(kept)
        // capacity the suppliers hold back next week
        for i in s.companies.indices {
            let n = used[s.companies[i].id] ?? 0
            if n != 0 || s.companies[i].num("int27u") != 0 { s.companies[i].set("int27u", n) }
        }
    }
}
