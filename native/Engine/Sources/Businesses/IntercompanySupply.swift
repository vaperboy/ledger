import Foundation
import GameCore
import Countries
import Finance

/// Companies that depend on each other. A buyer can switch an input (cleaning, building materials, freight, food, power ...)
/// from outside suppliers to one of your own companies at market price, cost plus 10% or cost. The supplier gets the volume
/// (and uses its capacity), the group keeps the margin, and supply is steadier, until the supplier struggles: then the buyer
/// pays for emergency supply and its reputation suffers. Original: features/company/intercompany_supply.js (`R27`).
/// The links are saved in `rest["l27"]`. As in the original, a sale between your companies is booked as revenue of the supplier
/// and a lower cost of the buyer, without VAT; the profit tax of each company follows from its own books.
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
    }

    public static let kinds: [Kind] = [
        Kind(id: "clean", name: "Cleaning", suppliers: ["cleaning"], local: true, category: "oth", noCapacity: false, buyers: ["hotel": 0.035, "restaurant": 0.015, "cafe": 0.012, "gym": 0.02, "nightclub": 0.015, "casino": 0.015, "fun": 0.015, "grocery": 0.008, "boutique": 0.008, "hardware": 0.006, "cardealer": 0.008, "physio": 0.015, "law": 0.01, "acctfirm": 0.01, "cons": 0.01, "webdev": 0.008, "mktg": 0.008, "staffing": 0.006, "bank": 0.004, "insco": 0.004, "estate": 0.01, "barber": 0.012, "pets": 0.012, "drivsk": 0.006, "kiosk": 0.006]),
        Kind(id: "build", name: "Building materials", suppliers: ["hardware"], local: false, category: "cogs", noCapacity: false, buyers: ["construction": 0.3, "realdev": 0.25, "electrician": 0.18, "plumber": 0.2, "handy": 0.15]),
        Kind(id: "freight", name: "Freight", suppliers: ["trucking"], local: false, category: "cogs", noCapacity: false, buyers: ["factory": 0.05, "furniture": 0.05, "bakery": 0.03, "brewery": 0.05, "farm": 0.05, "salmon": 0.06, "grocery": 0.025, "hardware": 0.03, "cardealer": 0.015, "construction": 0.02]),
        Kind(id: "parcel", name: "Parcel delivery", suppliers: ["courier"], local: false, category: "cogs", noCapacity: false, buyers: ["webshop": 0.07, "boutique": 0.01, "pets": 0.005, "furniture": 0.01]),
        Kind(id: "bread", name: "Bread and pastries", suppliers: ["bakery"], local: true, category: "cogs", noCapacity: false, buyers: ["cafe": 0.06, "restaurant": 0.02, "hotel": 0.015, "grocery": 0.02, "kiosk": 0.03, "foodtruck": 0.03]),
        Kind(id: "beer", name: "Beer", suppliers: ["brewery"], local: false, category: "cogs", noCapacity: false, buyers: ["restaurant": 0.03, "nightclub": 0.08, "hotel": 0.015, "grocery": 0.015, "fun": 0.02, "kiosk": 0.01]),
        Kind(id: "produce", name: "Farm produce", suppliers: ["farm"], local: false, category: "cogs", noCapacity: false, buyers: ["restaurant": 0.04, "cafe": 0.02, "hotel": 0.02, "grocery": 0.04, "bakery": 0.04, "brewery": 0.03, "foodtruck": 0.03]),
        Kind(id: "fish", name: "Fish", suppliers: ["salmon"], local: false, category: "cogs", noCapacity: false, buyers: ["restaurant": 0.03, "grocery": 0.02, "hotel": 0.01]),
        Kind(id: "furn", name: "Furniture", suppliers: ["furniture"], local: false, category: "oth", noCapacity: false, buyers: ["hotel": 0.02, "restaurant": 0.008, "cafe": 0.008, "realdev": 0.03]),
        Kind(id: "web", name: "Web and IT", suppliers: ["webdev"], local: false, category: "oth", noCapacity: false, buyers: ["webshop": 0.03, "boutique": 0.008, "hotel": 0.004, "mktg": 0.02, "bank": 0.01, "insco": 0.01, "staffing": 0.006]),
        Kind(id: "ads", name: "Marketing services", suppliers: ["mktg"], local: false, category: "mkt", noCapacity: false, buyers: ["hotel": 0.015, "restaurant": 0.01, "gym": 0.015, "cardealer": 0.01, "webshop": 0.02, "boutique": 0.015, "fun": 0.01]),
        Kind(id: "temp", name: "Temporary staff", suppliers: ["staffing"], local: true, category: "wages", noCapacity: false, buyers: ["hotel": 0.02, "restaurant": 0.015, "grocery": 0.01, "construction": 0.03, "factory": 0.02, "courier": 0.02, "event": 0.03, "fun": 0.015]),
        Kind(id: "carserv", name: "Vehicle service and repairs", suppliers: ["carrepair"], local: true, category: "oth", noCapacity: false, buyers: ["taxi": 0.06, "courier": 0.04, "trucking": 0.05, "cardealer": 0.03, "handy": 0.008, "carclean": 0.01, "electrician": 0.008, "plumber": 0.008]),
        Kind(id: "whouse", name: "Warehousing and fulfilment", suppliers: ["wh3pl"], local: false, category: "cogs", noCapacity: false, buyers: ["webshop": 0.09, "boutique": 0.015, "hardware": 0.02, "furniture": 0.03, "brewery": 0.02, "grocery": 0.008]),
        Kind(id: "power", name: "Electricity", suppliers: ["power"], local: false, category: "oth", noCapacity: true, buyers: ["factory": 0.04, "bakery": 0.03, "brewery": 0.03, "salmon": 0.03, "hotel": 0.02, "grocery": 0.015, "farm": 0.02, "casino": 0.01, "gym": 0.01]),
    ]

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
        init(_ j: JSONValue) {
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
    static func weeklySpend(_ b: Company, _ k: Kind) -> Double { max(0, b.lastWeekRevenue * (k.buyers[b.type] ?? 0)) }
    /// What the buyer spends on it in a year, from its last three months. Original: `yearSpend`.
    public static func yearlySpend(_ b: Company, _ k: Kind) -> Double {
        let h = b.monthlyHistory.suffix(3)
        let rv = h.reduce(0.0) { $0 + $1.revenue }
        let y = h.isEmpty ? b.lastWeekRevenue * 52 : rv / Double(h.count) * 12
        return max(0, y * (k.buyers[b.type] ?? 0))
    }

    // MARK: Changing links

    /// Switch an input to one of your own companies. Original: `ACT.ch27set`.
    @discardableResult
    public static func setSupplier(_ s: inout GameState, buyer: Int, kind kid: String, supplier: Int, mode: String) -> Bool {
        guard let b = s.company(buyer), let sp = s.company(supplier), let k = kind(kid), k.suppliers.contains(sp.type), modes.contains(where: { $0.id == mode }) else { return false }
        var L = rawLinks(s).filter { !($0["b"].int == b.id && $0["k"].string == kid) }
        L.append(.object(["id": .number(Double(s.makeID())), "k": .string(kid), "b": .number(Double(b.id)), "s": .number(Double(sp.id)), "mode": .string(mode), "w0": .number(Double(s.week))]))
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

    static func weekly(_ s: inout GameState, data: GameData) {
        guard !rawLinks(s).isEmpty || s.companies.contains(where: { $0.num("int27u") > 0 }) else { return }
        let titanCut = Ambitions.supplyCostCut(s, data)
        // tickets are worked out before anything moves (they read the whole state)
        var tickets: [Int: Double] = [:]
        do {
            let w = World(state: s, data: data)
            for c in s.companies where c.status == .open {
                if let bd = data.catalog[c.type], rawLinks(s).contains(where: { $0["s"].int == c.id }) { tickets[c.id] = Pricing.ticket(c, bd, w) }
            }
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
