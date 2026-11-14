import Foundation
import GameCore
import Countries
import Finance

public enum IntercompanySupply {
    public struct Kind: Equatable, Sendable {
        public var id: String
        public var name: String
        public var suppliers: [String]
        public var local: Bool
        public var category: String
        public var noCapacity: Bool
        public var buyers: [String: Double]
        public var delivered = false
    }

    // Lines an own company can take over, with each buying trade's share of sales, from the one supply map.
    public static let kinds: [Kind] = {
        SupplyMap.allLines.compactMap { (l: SupplyMap.LineSpec) -> Kind? in
            var buyers: [String: Double] = [:]
            for t in SupplyMap.buyers(of: l.id) { if let share = SupplyMap.need(t, line: l.id)?.salesShare { buyers[t] = share } }
            guard !buyers.isEmpty, !l.suppliers.isEmpty else { return nil }
            return Kind(id: l.id, name: l.name, suppliers: l.suppliers, local: l.local, category: l.category, noCapacity: l.noCapacity, buyers: buyers, delivered: l.delivered)
        }
    }()

    public static func kind(_ id: String) -> Kind? { kinds.first { $0.id == id } }
    public static let modes: [(id: String, name: String)] = [("mkt", "Full price"), ("c10", "Cost + 10%"), ("cost", "At cost")]
    public static func modeName(_ id: String) -> String { modes.first { $0.id == id }?.name ?? id }

    static func rawLinks(_ s: GameState) -> [JSONValue] { s.rest["l27"]?.array ?? [] }

    public struct Link: Equatable, Identifiable, Sendable {
        public var id: Int
        public var kindID: String
        public var buyerID: Int
        public var supplierID: Int
        public var mode: String
        public var lastSpend: Double
        public var lastShare: Double
        public var lastPriceFactor: Double
        public var saved: Double
        public var termsID: String?
        init(_ j: JSONValue) {
            termsID = j["tm"].isNull ? nil : j["tm"].string
            id = j["id"].int; kindID = j["k"].string; buyerID = j["b"].int; supplierID = j["s"].int; mode = j["mode"].string
            lastSpend = j["last"]["x"].double; lastShare = j["last"]["f"].isNull ? 1 : j["last"]["f"].double; lastPriceFactor = j["last"]["pf"].isNull ? 1 : j["last"]["pf"].double
            saved = j["sum"].double
        }
    }

    static func isLive(_ c: Company?) -> Bool { c != nil && c!.status.isLive }

    public static func links(_ s: GameState) -> [Link] {
        rawLinks(s).filter { isLive(s.company($0["b"].int)) && isLive(s.company($0["s"].int)) }.map { Link($0) }
    }
    public static func link(_ s: GameState, buyer: Int, kind: String) -> Link? { links(s).first { $0.buyerID == buyer && $0.kindID == kind } }

    public static let automaticKinds: Set<String> = ["power", "web"]

    public static func kindsFor(_ co: Company) -> [Kind] {
        kinds.filter { !automaticKinds.contains($0.id) && $0.buyers[co.type] != nil }
    }

    public static func suppliers(_ s: GameState, for co: Company, kind k: Kind) -> [Company] {
        let trades = SupplyMap.suppliers(line: k.id, buyer: co.type)
        return s.companies.filter { $0.status == .open && $0.id != co.id && trades.contains($0.type) && $0.countryCode == co.countryCode && (!k.local || $0.cityID == co.cityID) }
    }

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
    public static func priceFactor(mode: String, supplier c: Company, data: GameData, perkCut: Double = 0) -> Double {
        mode == "mkt" ? 1 : mode == "c10" ? min(1, costRatio(c, data: data, perkCut: perkCut) * 1.1) : min(1, costRatio(c, data: data, perkCut: perkCut))
    }

    static func weeklySpend(_ b: Company, _ k: Kind) -> Double { max(0, (k.delivered ? b.num("dlvRev") : b.lastWeekRevenue) * (k.buyers[b.type] ?? 0)) }
    public static func yearlySpend(_ b: Company, _ k: Kind) -> Double {
        if k.delivered { return weeklySpend(b, k) * 52 }
        let h = b.monthlyHistory.suffix(3)
        let rv = h.reduce(0.0) { $0 + $1.revenue }
        let y = h.isEmpty ? b.lastWeekRevenue * 52 : rv / Double(h.count) * 12
        return max(0, y * (k.buyers[b.type] ?? 0))
    }

    public static var deliveryKind: Kind? { kinds.first { $0.delivered } }

    public static func deliveryWay(_ tradeID: String, _ balance: Balance) -> Balance.SalesWay? {
        balance.salesWays[tradeID]?.first { $0.kind == "platform" && ($0.options["deliv"] ?? 0) > 0 }
    }

    public static func hasOwnDelivery(_ s: GameState, buyer: Int) -> Bool {
        guard let k = deliveryKind, let l = rawLinks(s).first(where: { $0["b"].int == buyer && $0["k"].string == k.id }) else { return false }
        return isLive(s.company(l["s"].int))
    }

    public static func deliveryFill(_ s: GameState, buyer co: Company, way: Balance.SalesWay) -> Double {
        let rel = clamp(way.options["rel"] ?? 1, 0, 1)
        guard let k = deliveryKind,
              let l = rawLinks(s).first(where: { $0["b"].int == co.id && $0["k"].string == k.id }),
              let sp = s.company(l["s"].int), sp.status.isLive else { return rel }
        let f = sp.status != .open ? 0 : l["last"]["f"].isNull ? 1 : clamp(l["last"]["f"].double, 0, 1)
        return f + (1 - f) * rel
    }

    @discardableResult
    public static func setSupplier(_ s: inout GameState, buyer: Int, kind kid: String, supplier: Int, mode: String) -> Bool {
        guard let b = s.company(buyer), let sp = s.company(supplier), let k = kind(kid), SupplyMap.suppliers(line: k.id, buyer: b.type).contains(sp.type), modes.contains(where: { $0.id == mode }) else { return false }
        AccountSupply.clear(&s, buyer: b.id, kind: kid)
        var L = rawLinks(s).filter { !($0["b"].int == b.id && $0["k"].string == kid) }
        L.append(.object(["id": .number(Double(s.makeID())), "k": .string(kid), "b": .number(Double(b.id)), "s": .number(Double(sp.id)), "mode": .string(mode), "w0": .number(Double(s.week))]))
        s.rest["l27"] = .array(L)
        return true
    }

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

    public static func clearSupplier(_ s: inout GameState, buyer: Int, kind kid: String) {
        s.rest["l27"] = .array(rawLinks(s).filter { !($0["b"].int == buyer && $0["k"].string == kid) })
    }

    public static func heldBack(_ c: Company) -> Double { c.num("int27u") }

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
            let strain = SupplyTerms.ownSupplierStrained(s, buyer: b.id, supplier: sp.id) ? SupplyTerms.ownStrainFactor : 1
            let capB = sp.status == .open ? (sp.value("lastW")["cap"].double + sp.num("int27u")) * strain : 0
            let f = K.noCapacity ? (sp.status == .open ? strain : 0) : (u > 0 ? clamp(capB / u, 0, 1) : 1)
            let pf = priceFactor(mode: l["mode"].string, supplier: sp, data: data, perkCut: titanCut), vr = varRatio(sp, data: data)
            let got = x * f
            let diff = got * (1 - pf)
            if let terms = SupplyTerms.groupTerm(l["tm"].string), terms.days > 0, got > 0 {
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
                if got > 0 {
                    Payments.companyReceives(&s, companyID: sp.id, amount: got * pf, category: "rev", label: nil)
                    Payments.companyPays(&s, companyID: sp.id, amount: got * vr, category: "cogs", label: nil)
                    transferVat(&s, supplier: sp, buyerIndex: bi, net: got * pf, data: data, w0, cashNow: true)
                }
            }
            if f < 0.98 {
                Payments.companyPays(&s, companyID: b.id, amount: x * (1 - f) * 0.2, category: K.category, label: nil)
                if f < 0.8 {
                    s.companies[bi].reputation = max(0, s.companies[bi].reputation - 0.4 * (1 - f))
                    if l["warn"].isNull || Double(s.week) - l["warn"].double > 6 {
                        l["warn"] = .number(Double(s.week))
                        s.addMessage(kind: "info", from: b.name, title: "\(sp.name) could not deliver to \(b.name)",
                                     body: "\(sp.name) delivered only \(Int(saturating: (f * 100).rounded()))% of the \(K.name.lowercased()) \(b.name) needed. The rest was bought outside at short notice, and some customers noticed.", companyID: b.id, tone: "bad")
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
        for i in s.companies.indices {
            let n = used[s.companies[i].id] ?? 0
            if n != 0 || s.companies[i].num("int27u") != 0 { s.companies[i].set("int27u", n) }
        }
    }
}
