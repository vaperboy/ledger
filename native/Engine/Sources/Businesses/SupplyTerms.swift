import Foundation
import GameCore
import Countries
import Finance

/// Payment terms between a buyer and its suppliers, and what lateness costs. One module for outside suppliers, your own companies
/// supplying each other, and your business customers paying you. All behaviour comes from `Resources/supplier_terms.json`; a country
/// can set its own late-payment rule under `commerce.latePayment` in its data (`policyPlus` margin over the policy rate, or a fixed
/// yearly rate); a country without one uses the game's default monthly rate.
///
/// The ways a purchase can be paid (the buyer chooses, within what the supplier offers):
///  - outside goods supplier: cash on delivery (a small cash discount), month end (how bills have always worked: the default), 30 or 60
///    days (the supplier charges a little for the credit). What a supplier offers depends on how well you know them (`minRelationship`).
///  - your own company supplying another (`IntercompanySupply`): settled weekly (the default, as before), or on 14 / 30 days. On days a real
///    invoice exists: the buyer owes it (`payables["inv"]`), the supplier holds the receivable, and the cash moves between the two when due.
///  - a business customer of yours (`KeyAccounts`) pays on the trade's own terms and may pay late.
///
/// An invoice is paid in full on its due week if the buyer's account (with its overdraft room) can cover it, oldest first. If not it is late:
/// every week it carries interest (booked on both sides when both are your companies); the first week late an outside supplier cools towards
/// you (the same relationship values as the discount), takes back a negotiated deal, and repeated lateness makes suppliers tighten (cash only)
/// and then stop delivering stock (the same `supCut` levels and messages as missed monthly bills). Nothing is capped: a company that always
/// pays on time never meets any of it.
///
/// Saved: invoices in `rest["sinv"]` (only while one exists), a company's agreed terms in `pterm` (only when set), its late record in `lt` and
/// a cut-off from invoices in `supCutI`.
public enum SupplyTerms {
    public struct Term: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        /// Days until it is due; 0 = on delivery; negative = at month end (the usual monthly bill).
        public var days: Int
        /// Added to the price of what is bought (cash discount negative, credit charge positive).
        public var priceEffect: Double
        /// The relationship score from which a supplier offers it.
        public var minRelationship: Double
        public var isMonthEnd: Bool { days < 0 }
        /// Whole weeks until due.
        public var weeks: Int { days <= 0 ? 0 : (days + 6) / 7 }
    }

    struct Tables {
        var vendor: [Term] = []
        var group: [Term] = []
        var defaultMonthly = 0.02
        var relationshipHit = 4.0
        var dealLost = true
        var cutoffAfter = 3, windowWeeks = 26, levelFirst = 1, levelRepeat = 2, cutoffWeeks = 8
        var billMissHit = 2.0
        var lateChanceBase = 0.3, lateChanceRelationship = 0.25, weakEconomy = 1.6
        var customerLate: ClosedRange<Int> = 1...6
        var repeatNotice = 3
        var asks: [Double] = [0.01, 0.02, 0.03, 0.05]
        var headroomBase = 0.01, headroomPerRelationship = 0.0004, patiencePerRelationship = 0.006, step = 0.005
        var dealWeeks = 52, coolWeeks = 6
        var walkAwayHit = 3.0
        var rank = "manager"
        var ownFlagAfter = 4, ownCapacityFactor = 0.8
    }

    static let tables: Tables = {
        var t = Tables()
        guard let url = Bundle.module.url(forResource: "supplier_terms", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return t }
        func term(_ v: JSONValue) -> Term { Term(id: v["id"].string, name: v["name"].string, days: v["days"].int, priceEffect: v["priceEffect"].double, minRelationship: v["minRelationship"].double) }
        t.vendor = j["vendorTerms"].array.map(term)
        t.group = j["groupTerms"].array.map(term)
        let l = j["late"]
        t.defaultMonthly = l["defaultMonthlyInterest"].double
        t.relationshipHit = l["relationshipHit"].double
        t.dealLost = l["dealLost"].bool
        t.cutoffAfter = l["cutoffAfter"].int; t.windowWeeks = l["windowWeeks"].int
        t.levelFirst = l["cutoffLevelFirst"].int; t.levelRepeat = l["cutoffLevelRepeat"].int; t.cutoffWeeks = l["cutoffWeeks"].int
        t.billMissHit = l["billMissRelationshipHit"].double
        let c = j["customer"]
        t.lateChanceBase = c["lateChanceBase"].double; t.lateChanceRelationship = c["lateChanceRelationship"].double; t.weakEconomy = c["weakEconomyFactor"].double
        let lw = c["lateWeeks"].array.map { $0.int }
        if lw.count == 2 { t.customerLate = lw[0]...max(lw[0], lw[1]) }
        t.repeatNotice = c["repeatNotice"].int
        if !j["ownLate"].isNull { t.ownFlagAfter = j["ownLate"]["flagAfterWeeks"].int; t.ownCapacityFactor = j["ownLate"]["capacityFactor"].double }
        let n = j["negotiation"]
        t.headroomBase = n["headroomBase"].double; t.headroomPerRelationship = n["headroomPerRelationship"].double
        t.patiencePerRelationship = n["patiencePerRelationship"].double; t.step = n["step"].double
        let a = n["asks"].array.map { $0.double }
        if !a.isEmpty { t.asks = a }
        t.dealWeeks = n["dealWeeks"].int; t.coolWeeks = n["coolWeeks"].int; t.walkAwayHit = n["walkAwayRelationshipHit"].double
        t.rank = n["rank"].string
        return t
    }()

    /// The extra discounts a player can ask for, as shares.
    public static var asks: [Double] { tables.asks }
    public static var vendorTerms: [Term] { tables.vendor }
    public static var groupTerms: [Term] { tables.group }
    public static func vendorTerm(_ id: String) -> Term? { tables.vendor.first { $0.id == id } }
    public static func groupTerm(_ id: String) -> Term? { tables.group.first { $0.id == id } }
    /// The terms a supplier offers someone it knows this well.
    public static func offered(relationship r: Double) -> [Term] { tables.vendor.filter { r >= $0.minRelationship } }

    // MARK: Late interest

    /// The yearly interest on an overdue commercial debt in this country: its own rule when its data has one, else the game's default.
    public static func lateAnnualRate(country: Country, policyRate: Double) -> Double {
        let rule = country.pack["commerce"]["latePayment"]
        if !rule["annual"].isNull { return max(0, rule["annual"].double) }
        if !rule["margin"].isNull { return max(0, policyRate + rule["margin"].double) }
        return tables.defaultMonthly * 12
    }
    public static func lateMonthlyRate(country: Country, policyRate: Double) -> Double { lateAnnualRate(country: country, policyRate: policyRate) / 12 }

    // MARK: Terms a company has agreed

    /// The terms id agreed with the goods supplier (nil = month end, as always).
    public static func agreedGoodsTerm(_ co: Company) -> String? {
        let v = co.value("pterm")["goods"]
        return v.isNull ? nil : v.string
    }

    /// The terms that apply now: agreed, and still offered by the supplier at today's relationship.
    public static func goodsTerm(_ s: GameState, _ co: Company, data: GameData) -> Term? {
        guard let id = agreedGoodsTerm(co), let t = vendorTerm(id), !t.isMonthEnd else { return nil }
        guard let v = Suppliers.goodsVendor(s, company: co, data: data), v.relationship >= t.minRelationship else { return nil }
        return t
    }

    /// Agree terms with the goods supplier. nil or "monthly" go back to the usual monthly bill.
    @discardableResult
    public static func setGoodsTerm(_ s: inout GameState, companyID: Int, term id: String?, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return false }
        var tm = s.companies[i].value("pterm")
        if id == nil || id == "monthly" {
            if !tm.isNull { var o = tm.object; o.removeValue(forKey: "goods"); if o.isEmpty { s.companies[i].raw.removeValue(forKey: "pterm") } else { s.companies[i].set("pterm", .object(o)) } }
            return true
        }
        guard let id, let t = vendorTerm(id), let v = Suppliers.goodsVendor(s, company: s.companies[i], data: data), v.relationship >= t.minRelationship else { return false }
        if tm.isNull { tm = .object([:]) }
        tm["goods"] = .string(id)
        s.companies[i].set("pterm", tm)
        return true
    }

    // MARK: Short-paying your own companies

    /// How many weeks the longest overdue invoice from this own supplier to this buyer has been late (0 = none).
    public static func ownLateWeeks(_ s: GameState, buyer: Int, supplier: Int) -> Int {
        raw(s).filter { $0["b"].int == buyer && $0["p"].int == supplier }.map { $0["l"].int }.max() ?? 0
    }
    /// An own supplier that has been short-paid this long is flagged and keeps back part of its capacity.
    public static func ownSupplierStrained(_ s: GameState, buyer: Int, supplier: Int) -> Bool {
        ownLateWeeks(s, buyer: buyer, supplier: supplier) >= tables.ownFlagAfter
    }
    /// The share of what it could carry that a short-paid own supplier still delivers.
    public static var ownStrainFactor: Double { tables.ownCapacityFactor }

    // MARK: Repair terms (the same terms as goods, with the repair supplier)

    /// The terms id agreed with the repair supplier (nil = paid as the upkeep falls due, as always).
    public static func agreedRepairTerm(_ co: Company) -> String? {
        let v = co.value("pterm")["fix"]
        return v.isNull ? nil : v.string
    }

    /// The repair terms that apply now: agreed, and still offered by the chosen repair supplier at today's relationship.
    public static func repairTerm(_ s: GameState, _ co: Company, data: GameData) -> Term? {
        guard let id = agreedRepairTerm(co), let t = vendorTerm(id), !t.isMonthEnd else { return nil }
        guard let v = Suppliers.repairVendor(s, company: co, data: data), v.relationship >= t.minRelationship else { return nil }
        return t
    }

    /// Agree terms with the repair supplier. nil or "monthly" go back to paying as the bill comes.
    @discardableResult
    public static func setRepairTerm(_ s: inout GameState, companyID: Int, term id: String?, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return false }
        var tm = s.companies[i].value("pterm")
        if id == nil || id == "monthly" {
            if !tm.isNull { var o = tm.object; o.removeValue(forKey: "fix"); if o.isEmpty { s.companies[i].raw.removeValue(forKey: "pterm") } else { s.companies[i].set("pterm", .object(o)) } }
            return true
        }
        guard let id, let t = vendorTerm(id), let v = Suppliers.repairVendor(s, company: s.companies[i], data: data), v.relationship >= t.minRelationship else { return false }
        if tm.isNull { tm = .object([:]) }
        tm["fix"] = .string(id)
        s.companies[i].set("pterm", tm)
        return true
    }

    /// Pay a repair or upkeep bill (`amount` is after the supplier's discount) on the agreed terms: at once with the cash discount, or as an
    /// invoice that falls due later. The cost is booked now in either case. Returns false if it had to be paid now and the cash was not there.
    @discardableResult
    static func payRepairs(_ s: inout GameState, companyIndex i: Int, amount: Double, label: String?, data: GameData) -> Bool {
        guard amount > 0 else { return true }
        let co = s.companies[i]
        guard let t = repairTerm(s, co, data: data) else {
            Payments.companyPays(&s, companyID: co.id, amount: amount, category: "oth", label: label)
            return true
        }
        let price = amount * (1 + t.priceEffect)
        if t.days == 0 {
            Payments.companyPays(&s, companyID: co.id, amount: price, category: "oth", label: label)
            return true
        }
        let v = Suppliers.repairVendor(s, company: co, data: data)
        Payments.book(&s, companyID: co.id, category: "oth", amount: jsRound(price))
        issue(&s, buyer: co.id, provider: 0, vendorID: v?.id ?? "", name: v?.name ?? "Repair supplier", kind: "fix", amount: price, weeks: t.weeks)
        return true
    }

    // MARK: Invoices

    public struct Invoice: Equatable, Identifiable, Sendable {
        public var id: Int
        public var buyerID: Int
        /// The supplying company of yours, or 0 for an outside supplier.
        public var providerID: Int
        public var vendorID: String
        public var providerName: String
        public var kind: String
        public var amount: Double
        public var issuedWeek: Int
        public var dueWeek: Int
        public var lateWeeks: Int
        /// The amount first invoiced; `amount` has grown by the late interest since.
        public var face: Double
        init(_ j: JSONValue) {
            id = j["id"].int; buyerID = j["b"].int; providerID = j["p"].int; vendorID = j["v"].string; providerName = j["n"].string; kind = j["k"].string
            amount = j["a"].double; issuedWeek = j["w0"].int; dueWeek = j["d"].int; lateWeeks = j["l"].int
            face = j["f"].isNull ? j["a"].double : j["f"].double
        }
    }

    static func raw(_ s: GameState) -> [JSONValue] { s.rest["sinv"]?.array ?? [] }
    static func save(_ s: inout GameState, _ list: [JSONValue]) { if list.isEmpty { s.rest.removeValue(forKey: "sinv") } else { s.rest["sinv"] = .array(list) } }

    /// The open invoices (all, or one buyer's), oldest due first.
    public static func invoices(_ s: GameState, buyer: Int? = nil) -> [Invoice] {
        raw(s).map { Invoice($0) }.filter { buyer == nil || $0.buyerID == buyer }.sorted { $0.dueWeek != $1.dueWeek ? $0.dueWeek < $1.dueWeek : $0.id < $1.id }
    }
    /// What a company owes on invoices (the same figure as its `payables["inv"]`).
    public static func owed(_ s: GameState, buyer: Int) -> Double { invoices(s, buyer: buyer).reduce(0) { $0 + $1.amount } }

    /// A buyer owes `amount` to a supplier, due after `weeks` weeks. A company of yours as supplier books the revenue and holds the receivable.
    /// The buyer's cost is booked by the caller (it is the same cost whenever it is paid).
    @discardableResult
    static func issue(_ s: inout GameState, buyer: Int, provider: Int, vendorID: String, name: String, kind: String, amount: Double, weeks: Int) -> Int? {
        let a = jsRound(amount)
        guard a > 0, let bi = s.companyIndex(buyer) else { return nil }
        let id = s.makeID()
        var list = raw(s)
        list.append(.object(["id": .number(Double(id)), "b": .number(Double(buyer)), "p": .number(Double(provider)), "v": .string(vendorID), "n": .string(name), "k": .string(kind),
                             "a": .number(a), "f": .number(a), "w0": .number(Double(s.week)), "d": .number(Double(s.week + weeks)), "l": 0]))
        save(&s, list)
        s.companies[bi].addPayable("inv", a)
        if provider != 0, let si = s.companyIndex(provider) {
            var r = Receivable(amount: a, dueWeek: s.week + weeks, willDefault: false)
            r.set("ic", id)
            var recv = s.companies[si].receivables
            recv.append(r)
            s.companies[si].receivables = recv
        }
        return id
    }

    /// The buyer's purchase of goods from an outside supplier on terms: pay now (cash on delivery) or owe it.
    static func buyGoods(_ s: inout GameState, companyIndex i: Int, amount: Double, term t: Term, data: GameData) {
        guard amount > 0 else { return }
        let co = s.companies[i]
        if t.days == 0 {
            Payments.companyPays(&s, companyID: co.id, amount: amount, category: nil, label: nil)
            return
        }
        let v = Suppliers.goodsVendor(s, company: co, data: data)
        issue(&s, buyer: co.id, provider: 0, vendorID: v?.id ?? "", name: v?.name ?? "Supplier", kind: "goods", amount: amount, weeks: t.weeks)
    }

    // MARK: Lateness record

    static func lateWeeks(_ co: Company) -> [Int] { co.value("lt").array.map { $0.int } }

    /// The cut-off level that invoices alone put on this company now.
    public static func invoiceCutLevel(_ co: Company, week: Int) -> Int {
        let c = co.value("supCutI")
        return c.isNull || c["u"].int <= week ? 0 : c["l"].int
    }

    /// Show the stricter of the bill cut-off and the invoice cut-off; one key (`supCut`) is what stock buying reads.
    static func refreshCut(_ s: inout GameState, _ i: Int) {
        let co = s.companies[i]
        let inv = invoiceCutLevel(co, week: s.week)
        if co.value("supCutI").isNull == false, inv == 0 { s.companies[i].raw.removeValue(forKey: "supCutI") }
        let level = max(inv, co.int("supCutB"))
        if level != co.int("supCut") { s.companies[i].set("supCut", level) }
    }

    /// An outside supplier's invoice went late for the first time.
    static func lateEvent(_ s: inout GameState, _ inv: Invoice, buyerIndex bi: Int) {
        let t = tables
        let co = s.companies[bi]
        var detail = ""
        if !inv.vendorID.isEmpty {
            Suppliers.dock(&s, inv.vendorID, by: t.relationshipHit)
            detail = " \(inv.providerName) now trusts \(co.name) less."
            if t.dealLost, SupplyDeals.dropDeal(&s, companyIndex: bi, vendorID: inv.vendorID) { detail += " The special price you negotiated is withdrawn." }
        }
        let hist = (lateWeeks(co).filter { s.week - $0 < t.windowWeeks }) + [s.week]
        s.companies[bi].set("lt", .array(hist.map { .number(Double($0)) }))
        let before = invoiceCutLevel(s.companies[bi], week: s.week)
        if hist.count >= t.cutoffAfter && !inv.vendorID.isEmpty {
            let level = hist.count > t.cutoffAfter ? t.levelRepeat : t.levelFirst
            if level > before {
                s.companies[bi].set("supCutI", .object(["l": .number(Double(level)), "u": .number(Double(s.week + t.cutoffWeeks))]))
                s.addMessage(from: co.name, title: level == 1 ? "Suppliers want cash at \(co.name)" : "Suppliers stop delivering to \(co.name)",
                             body: level == 1 ? "After repeated late payments suppliers only deliver stock against cash in the account. Pay what is overdue and keep to the terms to get credit back."
                                              : "Suppliers refuse new stock after repeated late payments. Sales will suffer until you pay on time.",
                             companyID: co.id, tone: "bad")
            }
        }
        refreshCut(&s, bi)
        s.addMessage(from: co.name, title: "Late payment: \(inv.providerName)", body: "An invoice to \(inv.providerName) was not paid when due because the account of \(co.name) could not cover it. It now carries late interest." + detail,
                     companyID: co.id, tone: "bad")
    }

    // MARK: Weekly

    /// Once a week after the companies' own weeks: terms that the supplier no longer offers lapse, due invoices are paid or go late.
    static func weekly(_ s: inout GameState, data: GameData, context: FinanceContext) {
        lapseTerms(&s, data: data)
        var list = raw(s)
        if !list.isEmpty {
            let order = list.indices.sorted { a, b in
                let x = list[a], y = list[b]
                return x["d"].int != y["d"].int ? x["d"].int < y["d"].int : x["id"].int < y["id"].int
            }
            var room: [Int: Double] = [:]
            var gone: Set<Int> = []
            for k in order {
                var j = list[k]
                let bid = j["b"].int
                guard let bi = s.companyIndex(bid), s.companies[bi].status.isLive else { gone.insert(k); closeOut(&s, j); continue }
                guard s.week >= j["d"].int else { continue }
                let co = s.companies[bi]
                if room[bid] == nil { room[bid] = max(0, co.cash + context.overdraftRoom(co, s)) }
                let amount = j["a"].double
                let pid = j["p"].int
                let supplierLive = pid != 0 && (s.company(pid)?.status.isLive ?? false)
                if (room[bid] ?? 0) >= amount - 0.5 {
                    room[bid]! -= amount
                    Ledger.moveRaw(&s, .company(bid), -amount)
                    s.companies[bi].addTransaction(week: s.week, amount: -jsRound(amount), label: "Invoice: \(j["n"].string)")
                    if pid != 0, supplierLive, let si = s.companyIndex(pid) {
                        Ledger.moveRaw(&s, .company(pid), amount)
                        s.companies[si].addTransaction(week: s.week, amount: jsRound(amount), label: "Paid by \(co.name)")
                    }
                    gone.insert(k)
                    closeOut(&s, j, paid: true)
                } else {
                    let policy = s.economy.policyRate
                    let rate = lateAnnualRate(country: context.country(of: co, s), policyRate: policy) / 52
                    let interest = jsRound(amount * rate)
                    if j["l"].int == 0 { lateEvent(&s, Invoice(j), buyerIndex: bi) }
                    j["l"] = .number(Double(j["l"].int + 1))
                    if pid != 0, supplierLive, j["l"].int == tables.ownFlagAfter, let sp = s.company(pid) {
                        // No cut-off between your own companies, but the group is told: the supplier has been waiting for its money.
                        s.addMessage(from: co.name, title: "\(co.name) is short-paying \(sp.name)",
                                     body: "\(co.name) has owed \(sp.name), another company of yours, for \(tables.ownFlagAfter) weeks. \(sp.name) now keeps back part of its capacity for the group until it is paid. Move cash between the companies or settle weekly.",
                                     companyID: co.id, tone: "bad")
                    }
                    if interest > 0 {
                        j["a"] = .number(amount + interest)
                        s.companies[bi].addPayable("inv", interest)
                        Payments.book(&s, companyID: bid, category: "int", amount: interest)
                        if pid != 0, supplierLive, let si = s.companyIndex(pid) {
                            Payments.book(&s, companyID: pid, category: "int", amount: -interest)
                            var recv = s.companies[si].receivables
                            if let r = recv.firstIndex(where: { $0.int("ic") == j["id"].int }) { recv[r].amount += interest; s.companies[si].receivables = recv }
                        }
                    }
                    list[k] = j
                }
            }
            list = list.indices.filter { !gone.contains($0) }.map { list[$0] }
            // closeOut/lateEvent may have added invoices (they do not); re-read to be safe about ones made meanwhile
            save(&s, list)
        }
        for i in s.companies.indices where s.companies[i].status.isLive && (!s.companies[i].value("supCutI").isNull) {
            let before = s.companies[i].int("supCut")
            refreshCut(&s, i)
            if before > 0, s.companies[i].int("supCut") == 0 {
                s.addMessage(from: s.companies[i].name, title: "Suppliers deliver normally again", body: "\(s.companies[i].name) has kept to its payment terms. Suppliers are back on normal terms.", companyID: s.companies[i].id, tone: "good")
            }
        }
    }

    /// An invoice ends (paid, or its buyer is gone): the buyer's payable and the supplier's receivable go with it.
    static func closeOut(_ s: inout GameState, _ j: JSONValue, paid: Bool = false) {
        let a = j["a"].double
        if let bi = s.companyIndex(j["b"].int) {
            var p = s.companies[bi].payables
            p["inv"] = max(0, (p["inv"] ?? 0) - a)
            if (p["inv"] ?? 0) < 0.5 { p.removeValue(forKey: "sinv") }
            s.companies[bi].payables = p
        }
        if j["p"].int != 0, let si = s.companyIndex(j["p"].int) {
            s.companies[si].receivables = s.companies[si].receivables.filter { $0.int("ic") != j["id"].int }
        }
    }

    /// Terms that the supplier no longer offers (the relationship fell) lapse; purchases go back to the monthly bill.
    static func lapseTerms(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status.isLive && !s.companies[i].value("pterm")["fix"].isNull {
            let co = s.companies[i]
            guard let id = agreedRepairTerm(co), let t = vendorTerm(id) else { continue }
            let v = Suppliers.repairVendor(s, company: co, data: data)
            if v == nil || v!.relationship < t.minRelationship {
                _ = setRepairTerm(&s, companyID: co.id, term: nil, data: data)
                s.addMessage(from: co.name, title: "\(v?.name ?? "Your repair supplier") ends your \(t.name.lowercased()) terms",
                             body: "\(co.name) no longer has the standing for \(t.name.lowercased()) with \(v?.name ?? "its repair supplier"). Repairs go back to being paid as the bill comes. Better relations bring the terms back.",
                             companyID: co.id, tone: "bad")
            }
        }
        for i in s.companies.indices where s.companies[i].status.isLive && !s.companies[i].value("pterm").isNull {
            let co = s.companies[i]
            guard let id = agreedGoodsTerm(co), let t = vendorTerm(id) else { continue }
            let v = Suppliers.goodsVendor(s, company: co, data: data)
            if v == nil || v!.relationship < t.minRelationship {
                _ = setGoodsTerm(&s, companyID: co.id, term: nil, data: data)
                s.addMessage(from: co.name, title: "\(v?.name ?? "Your supplier") ends your \(t.name.lowercased()) terms",
                             body: "\(co.name) no longer has the standing for \(t.name.lowercased()) with \(v?.name ?? "its supplier"). Goods go back to the usual monthly bill. Better relations bring the terms back.",
                             companyID: co.id, tone: "bad")
            }
        }
    }

    // MARK: Missed monthly bills

    /// Rent and supplier bills could not be paid this month: the goods and repair suppliers think less of you (the relationship values the discounts use).
    public static func billsMissed(_ s: inout GameState, companyIndex i: Int, data: GameData) {
        let co = s.companies[i]
        for v in [Suppliers.goodsVendor(s, company: co, data: data), Suppliers.repairVendor(s, company: co, data: data)].compactMap({ $0 }) {
            Suppliers.dock(&s, v.id, by: tables.billMissHit)
        }
    }

    // MARK: Business customers paying

    /// Whether and how late a business customer pays one invoice: from how well they know you and the state of the economy. Same draw every replay.
    static func customerLateness(_ s: GameState, companyID: Int, accountID: Int, relationship r: Double) -> Int {
        let t = tables
        var h = HashedRandom("\(s.seed):cpay:\(s.week):\(companyID):\(accountID)")
        var p = max(0, t.lateChanceBase - t.lateChanceRelationship * min(100, r) / 100)
        if s.economy.demand < 0.97 { p *= t.weakEconomy }
        guard h.next() < p else { return 0 }
        return t.customerLate.lowerBound + Int(h.next() * Double(t.customerLate.count))
    }

    /// Invoices of business customers that were paid this week. Late ones earn the late interest the country allows and are remembered;
    /// a customer that keeps paying late is reported.
    static func customersPaid(_ s: inout GameState, companyIndex i: Int, paid: [(account: Int, late: Int, amount: Double)], country: Country) {
        guard !paid.isEmpty else { return }
        let rate = lateAnnualRate(country: country, policyRate: s.economy.policyRate) / 52
        for p in paid {
            var list = s.companies[i].value("accts").array
            guard let k = list.firstIndex(where: { $0["id"].int == p.account }) else { continue }
            if p.late > 0 {
                list[k]["lc"] = .number(list[k]["lc"].double + 1)
                list[k]["lw"] = .number(list[k]["lw"].double + Double(p.late))
                let interest = jsRound(p.amount * rate * Double(p.late))
                if interest > 0 {
                    Payments.companyReceives(&s, companyID: s.companies[i].id, amount: interest, category: nil, label: nil)
                    Payments.book(&s, companyID: s.companies[i].id, category: "int", amount: -interest)
                }
                if list[k]["lc"].int == tables.repeatNotice {
                    s.note("\(list[k]["name"].string) keeps paying \(s.companies[i].name) late. The cash comes in weeks after the sale.", tone: "warn", companyID: s.companies[i].id)
                }
            } else if list[k]["lc"].double > 0 {
                list[k]["lc"] = .number(0)
            }
            s.companies[i].set("accts", .array(list))
        }
    }
}
