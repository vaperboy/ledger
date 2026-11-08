import Foundation
import GameCore
import Countries
import Employees
import Finance

/// A chain owned by one owner is one company with branches, not a set of companies. Its branches draw on the chain's pooled cash, share one
/// board, one cap table (the head office's, the oldest store) and one dividend (`Payments.payDividend`). A branch is not a legal entity: it never
/// goes bankrupt on its own (only the whole chain can, `Failure.chainChecks`), and it leaves the chain in one of two ways: closed and wound down,
/// or sold as a going concern. Saved: the chain's `neg` (weeks its combined account has been overdrawn) and `warnW`; a branch that left keeps
/// `brEnd` {k: "closed" | "sold", w, price}.
public enum ChainBranches {
    // MARK: The chain as one company

    /// The live stores of a chain, oldest (the head office) first.
    public static func branches(_ s: GameState, chainID: Int) -> [Company] {
        guard let ch = Chains.chain(s, id: chainID) else { return [] }
        return Chains.stores(s, ch)
    }
    /// The chain's cash: every branch's account together.
    public static func combinedCash(_ s: GameState, chainID: Int) -> Double { branches(s, chainID: chainID).reduce(0) { $0 + $1.cash } }
    /// Weeks in a row the chain's combined account has been below zero.
    public static func weeksOverdrawn(_ s: GameState, chainID: Int) -> Int { Chains.chain(s, id: chainID)?["neg"].int ?? 0 }

    /// Weekly, before anything can fail: a branch short of cash is covered by the rest of the chain, the chain's overdrawn weeks are counted,
    /// and a board a store kept from before it joined becomes part of the chain's one board.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for ch in Chains.list(s) {
            let id = ch["id"].int
            let L = Chains.stores(s, ch)
            if L.isEmpty { continue }
            if L.count >= 2 { pool(&s, chainID: id, data: data) }
            mergeStoreBoards(&s, chainID: id)
            ChainLocations.leadProposals(&s, chainID: id, data: data)
            guard var c = Chains.chain(s, id: id) else { continue }
            let n = combinedCash(s, chainID: id) < 0 ? c["neg"].int + 1 : 0
            if c["neg"].int != n { c["neg"] = .number(Double(n)); Chains.save(&s, c) }
        }
    }

    /// One account for the whole chain: a branch below zero is topped up from its sisters, first from what they have above two weeks of
    /// costs, then from anything they hold. The move is kept as an inter-branch balance (`gl56`) so per-branch accounts stay readable.
    static func pool(_ s: inout GameState, chainID: Int, data: GameData) {
        for short in branches(s, chainID: chainID) {
            guard let si = s.companyIndex(short.id), s.companies[si].cash < 0 else { continue }
            let cost = ManagerModel.weekCost(s, s.companies[si], data: data)
            for keep in [2.0, 0.0] {
                let deficit = -s.companies[si].cash
                if deficit <= 0 { break }
                let want = keep > 0 ? deficit + cost : deficit
                var got = 0.0
                let donors = branches(s, chainID: chainID).filter { $0.id != short.id }.sorted { $0.cash != $1.cash ? $0.cash > $1.cash : $0.id < $1.id }
                for d in donors where got < want {
                    let x = jsRound(min(want - got, d.cash - ManagerModel.weekCost(s, d, data: data) * keep))
                    if x <= 0 { continue }
                    move(&s, from: d.id, to: short.id, amount: x, label: "Chain cash")
                    if let k = s.companyIndex(short.id) {
                        var gl = s.companies[k].value("gl56").array
                        gl.append(.object(["from": .number(Double(d.id)), "amt": .number(x), "w": .number(Double(s.week)), "pool": 1]))
                        s.companies[k].set("gl56", .array(gl))
                    }
                    got += x
                }
            }
        }
    }

    /// Money moving inside the chain: not income or cost of either branch.
    static func move(_ s: inout GameState, from a: Int, to b: Int, amount: Double, label: String) {
        guard amount > 0, let ca = s.company(a), let cb = s.company(b) else { return }
        Payments.companyPays(&s, companyID: a, amount: amount, category: nil, label: "\(label) to \(cb.name)")
        Payments.companyReceives(&s, companyID: b, amount: amount, category: nil, label: "\(label) from \(ca.name)")
    }

    /// A board a store had before it joined: its seats join the chain's one board (as far as there is room), so no store keeps a board of its own.
    static func mergeStoreBoards(_ s: inout GameState, chainID: Int) {
        let key = "ch:\(chainID)"
        for c in branches(s, chainID: chainID) {
            let own = c.value("brd")
            guard !own.isNull, let i = s.companyIndex(c.id) else { continue }
            var b = ManagerModel.board(s, key: key)
            var seats = b["seats"].array
            var left: [JSONValue] = []
            for x in own["seats"].array where !seats.contains(where: { $0["id"].int == x["id"].int }) {
                if seats.count + 2 < ManagerModel.maxBoard { seats.append(x) } else { left.append(x) }
            }
            b["seats"] = .array(seats)
            ManagerModel.writeBoard(&s, key: key, b)
            if left.isEmpty { s.companies[i].set("brd", .null) } else { var o = own; o["seats"] = .array(left); s.companies[i].set("brd", o) }
        }
    }

    // MARK: Leaving the chain

    public enum Refusal: Error, Equatable, Sendable {
        /// The company is not a branch: a chain of one store, or no chain. Close or sell the company itself.
        case notABranch
        /// It runs the brand's franchise system, which lives on this store.
        case runsFranchising
        /// It is listed for sale as a company: withdraw that first.
        case listed
        /// The chain's co-owners voted against closing it: the percent of the shares that were for it.
        case votedDown(Int)

        public var text: String {
            switch self {
            case .votedDown(let pct): return "The co-owners voted against closing it: \(pct)% of the shares were for it."
            case .notABranch: return "This is not a branch of a chain of two or more stores: close or sell the company itself."
            case .runsFranchising: return "This store runs the brand's franchising, so it stays in the chain."
            case .listed: return "It is on the market as a company: withdraw that listing first."
            }
        }
    }

    static func refusal(_ s: GameState, _ co: Company) -> Refusal? {
        if !s.isBranch(co) { return .notABranch }
        if co.value("fr")["on"].bool { return .runsFranchising }
        if SaleListings.isListed(s, companyID: co.id) { return .listed }
        return nil
    }

    /// The branch that takes over what moves and the cash left: the open sister with the most cash.
    static func receiver(_ s: GameState, _ co: Company) -> Company? {
        let sis = s.chainStores(of: co).filter { $0.id != co.id }
        let open = sis.filter { $0.status == .open }
        return (open.isEmpty ? sis : open).max { $0.cash != $1.cash ? $0.cash < $1.cash : $0.id > $1.id }
    }

    public struct Transfer: Equatable, Sendable {
        public var staffID: Int
        public var name: String
        public var role: String
        public var toStoreID: Int
        public var toStoreName: String
    }

    /// What closing a branch involves. Nothing is changed.
    public struct ClosurePlan: Equatable, Sendable {
        public var storeID: Int
        public var storeName: String
        /// The branch that takes the stock, the vehicles, the loans and the cash left.
        public var receiverID: Int
        public var receiverName: String
        /// Three months' rent to give up a rented site (the notice period), and the deposit that comes back.
        public var leaseExit: Double
        public var depositBack: Double
        /// An owned site is sold.
        public var premisesSale: Double
        /// People moved to sister branches short of their role.
        public var transfers: [Transfer]
        /// People (and the manager) let go for redundancy, and what that costs.
        public var redundancies: Int
        public var redundancyPay: Double
        /// Equipment sold at 70% of book value; the fit-out is left behind (written off).
        public var equipmentSale: Double
        public var fitOutWrittenOff: Double
        public var stockMoved: Double
        public var vehiclesMoved: Int
        /// The cash the closure brings in (sales, deposit) less what it costs (notice rent, redundancy pay).
        public var net: Double { depositBack + premisesSale + equipmentSale - leaseExit - redundancyPay }
    }

    /// Staff of a closing branch who can move to a sister branch that is short of their role.
    static func transfers(_ s: GameState, _ co: Company, data: GameData) -> [Transfer] {
        var gap: [Int: [String: Int]] = [:]
        let sis = s.chainStores(of: co).filter { $0.id != co.id && ($0.status == .open || $0.status == .setup) }
        for c in sis {
            guard let bd = data.catalog[c.type] else { continue }
            for r in CompanySetup.standardStaff(bd, size: c.size) { gap[c.id, default: [:]][r.role, default: 0] += r.count }
            for m in c.staff { gap[c.id, default: [:]][m.role, default: 0] -= 1 }
        }
        var out: [Transfer] = []
        for m in co.staff {
            guard let to = sis.first(where: { (gap[$0.id]?[m.role] ?? 0) > 0 }) else { continue }
            gap[to.id, default: [:]][m.role, default: 0] -= 1
            out.append(Transfer(staffID: m.id, name: s.people[m.id]?.name ?? "A team member", role: m.role, toStoreID: to.id, toStoreName: to.name))
        }
        return out
    }

    public static func closurePlan(_ s: GameState, storeID: Int, data: GameData) -> ClosurePlan? {
        guard let co = s.company(storeID), refusal(s, co) == nil, let to = receiver(s, co) else { return nil }
        let prem = co.value("prem")
        let rented = prem["m2"].double > 0 && !prem["owned"].bool
        let moves = transfers(s, co, data: data)
        let moving = Set(moves.map { $0.staffID })
        let going = co.staff.filter { !moving.contains($0.id) }
        var pay = going.reduce(0) { $0 + (Dismissal.quote(s, companyID: co.id, staffID: $1.id, reason: .redundancy, data: data)?.total ?? 0) }
        if let mid = co.managerID {
            let hired = co.value("mgrW0").isNull ? Double(s.week - 52) : co.num("mgrW0")
            pay += Dismissal.quote(World(state: s, data: data), co, monthlyWage: co.managerMonthlyWage, tenureWeeks: Double(s.week) - hired, reason: .redundancy,
                                   age: s.people[mid].map { Double($0.age) }).total
        }
        let eq = co.value("eq").object
        return ClosurePlan(storeID: co.id, storeName: co.name, receiverID: to.id, receiverName: to.name,
                           leaseExit: rented ? jsRound(prem["rent"].double * prem["m2"].double / 12 * 3) : 0, depositBack: rented ? prem["dep"].double : 0,
                           premisesSale: prem["owned"].bool ? jsRound(prem["val"].double * 0.95) : 0,
                           transfers: moves, redundancies: going.count + (co.managerID != nil ? 1 : 0), redundancyPay: jsRound(pay),
                           equipmentSale: jsRound(eq.filter { $0.key != "fit" }.reduce(0) { $0 + $1.value["bv"].double } * 0.7), fitOutWrittenOff: eq["fit"]?["bv"].double ?? 0,
                           stockMoved: co.inventory, vehiclesMoved: co.value("veh").array.filter { $0["mode"].string != "lease" }.count)
    }

    /// You propose closing a branch and the chain's board votes at once: with nobody else owning part of the chain it is yours to decide;
    /// co-owners may vote it down (`BoardVote`, kind "close"), and then nothing closes.
    public static func closeByVote(_ s: inout GameState, storeID: Int, data: GameData) -> Result<ClosurePlan, Refusal> {
        guard let co = s.company(storeID) else { return .failure(.notABranch) }
        if let r = refusal(s, co) { return .failure(r) }
        if let pct = ManagerModel.boardGate(s, kind: "close", companyID: storeID) { return .failure(.votedDown(pct)) }
        return close(&s, storeID: storeID, data: data)
    }

    /// Close a branch for good: the lease is given up (notice rent, deposit back) or the owned site sold, staff move to sister branches short of
    /// their role and the rest are made redundant, stock and vehicles go to a sister branch, equipment is sold, bills are settled, and loans and
    /// cash pass to the chain. The owner decides; the branch is then gone.
    public static func close(_ s: inout GameState, storeID: Int, data: GameData) -> Result<ClosurePlan, Refusal> {
        guard let co = s.company(storeID) else { return .failure(.notABranch) }
        if let r = refusal(s, co) { return .failure(r) }
        guard let plan = closurePlan(s, storeID: storeID, data: data), s.companyIndex(plan.receiverID) != nil else { return .failure(.notABranch) }
        _ = HeldMoney.settle(&s, companyID: storeID)
        for t in plan.transfers { _ = moveWorker(&s, staffID: t.staffID, from: storeID, to: t.toStoreID) }
        for m in s.company(storeID)?.staff ?? [] { Dismissal.dismiss(&s, companyID: storeID, staffID: m.id, reason: .redundancy, data: data) }
        for _ in 0..<3 where s.company(storeID)?.managerID != nil { Dismissal.dismissManager(&s, companyID: storeID, reason: .redundancy, data: data) }
        guard let i = s.companyIndex(storeID) else { return .failure(.notABranch) }
        let prem = s.companies[i].value("prem")
        if plan.leaseExit > 0 { Payments.companyPays(&s, companyID: storeID, amount: plan.leaseExit, category: "rent", label: "Lease given up (notice period)") }
        if plan.depositBack > 0 { Payments.companyReceives(&s, companyID: storeID, amount: plan.depositBack, category: nil, label: "Lease deposit returned") }
        if plan.premisesSale > 0 {
            Payments.companyReceives(&s, companyID: storeID, amount: plan.premisesSale, category: nil, label: "Premises sold")
            if prem["val"].double > plan.premisesSale { Payments.book(&s, companyID: storeID, category: "loss", amount: prem["val"].double - plan.premisesSale) }
        }
        s.companies[i].set("prem", .null)
        for k in s.companies[i].value("eq").object.keys.sorted() where k != "fit" { EquipmentMarket.sellAll(&s, companyID: storeID, equipmentID: k) }
        if plan.fitOutWrittenOff > 0 { Payments.book(&s, companyID: storeID, category: "loss", amount: plan.fitOutWrittenOff) }
        s.companies[i].set("eq", .object([:])); s.companies[i].set("units", .object([:]))
        // Stock and owned vehicles move to the sister branch; leases end with the site.
        let owned = s.companies[i].value("veh").array.filter { $0["mode"].string != "lease" }
        if let r = s.companyIndex(plan.receiverID) {
            s.companies[r].set("veh", .array(s.companies[r].value("veh").array + owned))
            s.companies[r].inventory += s.companies[i].inventory
        }
        s.companies[i].set("veh", .array([]))
        s.companies[i].inventory = 0
        EquipmentMarket.endAllLeases(&s, companyIndex: i)
        handOver(&s, storeID: storeID, to: plan.receiverID, end: .object(["k": "closed", "w": .number(Double(s.week)), "to": .number(Double(plan.receiverID))]))
        s.note("\(plan.storeName) is closed. Its stock went to \(plan.receiverName); \(plan.transfers.count) moved to other branches and \(plan.redundancies) were made redundant.", tone: "n", companyID: plan.receiverID)
        return .success(plan)
    }

    /// Move one person from a branch to a sister branch.
    @discardableResult
    static func moveWorker(_ s: inout GameState, staffID: Int, from a: Int, to b: Int) -> Bool {
        guard let ia = s.companyIndex(a), let ib = s.companyIndex(b), let m = s.companies[ia].staff.first(where: { $0.id == staffID }) else { return false }
        s.companies[ia].staff = s.companies[ia].staff.filter { $0.id != staffID }
        s.companies[ib].staff = s.companies[ib].staff + [m]
        if var p = s.people[staffID] { p.employerID = b; s.people[staffID] = p }
        return true
    }

    /// What a buyer pays for a branch as a going concern: its site, fit-out, equipment and stock, plus its customers, from its revenue and profit.
    public struct SaleQuote: Equatable, Sendable {
        public var storeID: Int
        public var storeName: String
        /// The branch that receives the price and takes over the branch's loans and cash.
        public var receiverID: Int
        public var receiverName: String
        public var yearlyRevenue: Double
        public var yearlyProfit: Double
        /// Book value of what goes with the site: fit-out, equipment, vehicles, stock, an owned site or the lease deposit.
        public var assets: Double
        /// What the customers are worth to the buyer (goodwill from profit, at least a small share of revenue).
        public var customers: Double
        public var price: Double
        /// People who go with the business to the buyer.
        public var staffGoing: Int
    }

    public static func saleQuote(_ s: GameState, storeID: Int, data: GameData) -> SaleQuote? {
        guard let co = s.company(storeID), refusal(s, co) == nil, let to = receiver(s, co) else { return nil }
        let prem = co.value("prem")
        let h = co.monthlyHistory.suffix(12)
        let scale = h.isEmpty ? 0 : 12 / Double(h.count)
        let rev = h.reduce(0) { $0 + $1.revenue } * scale, prof = h.reduce(0) { $0 + $1.profit } * scale
        let assets = CompanyFigures.equipmentBookValue(co) + co.inventory + (prem["owned"].bool ? prem["val"].double : prem["dep"].double)
        // A branch that makes money sells at its things plus its customers; one that loses money sells for its kit at a discount.
        let earns = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit } > 0
        let customers = earns ? max(Valuation.goodwill(co, state: s, trades: data.catalog), rev * 0.03) : rev * 0.01
        let cur = World(state: s, data: data).currency(co)
        let price = max(0, cur.roundedStep((earns ? assets : assets * 0.6) + customers, about: 1000))
        return SaleQuote(storeID: co.id, storeName: co.name, receiverID: to.id, receiverName: to.name, yearlyRevenue: jsRound(rev), yearlyProfit: jsRound(prof),
                         assets: jsRound(assets), customers: jsRound(customers), price: price, staffGoing: co.staff.count + (co.managerID != nil ? 1 : 0))
    }

    /// Sell a branch as a going concern: the buyer takes the site (the lease or the owned premises), the fit-out, equipment, stock and the staff;
    /// the price goes to the chain. Bills are settled and the branch's loans and cash pass to the chain.
    public static func sell(_ s: inout GameState, storeID: Int, data: GameData) -> Result<SaleQuote, Refusal> {
        guard let co = s.company(storeID) else { return .failure(.notABranch) }
        if let r = refusal(s, co) { return .failure(r) }
        guard let q = saleQuote(s, storeID: storeID, data: data), let i = s.companyIndex(storeID) else { return .failure(.notABranch) }
        _ = HeldMoney.settle(&s, companyID: storeID)
        // The staff and the manager stay with the business under its new owner.
        for m in s.companies[i].staff { if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p } }
        if let mid = s.companies[i].managerID, var p = s.people[mid] { p.employerID = 0; s.people[mid] = p }
        s.companies[i].staff = []
        ManagerModel.stepDown(&s, i)
        for k in ["prem", "eq", "units", "veh", "lease", "eqL"] { s.companies[i].set(k, .null) }
        s.companies[i].inventory = 0
        Payments.companyReceives(&s, companyID: q.receiverID, amount: q.price, category: nil, label: "Sale of \(q.storeName) as a going concern")
        if q.assets > q.price { Payments.book(&s, companyID: q.receiverID, category: "loss", amount: q.assets - q.price) }
        handOver(&s, storeID: storeID, to: q.receiverID, end: .object(["k": "sold", "w": .number(Double(s.week)), "price": .number(q.price), "to": .number(Double(q.receiverID))]))
        s.note("\(q.storeName) was sold as a going concern for \(World(state: s, data: data).currency(co).display(q.price)). The buyer takes the site and the staff; the money went to \(q.receiverName).", tone: "good", companyID: q.receiverID)
        return .success(q)
    }

    /// The last step of a branch leaving: its bills are paid, what customers owe is collected, its loans, tax so far this year and cash pass to
    /// the receiving branch, and it is gone from the chain.
    static func handOver(_ s: inout GameState, storeID: Int, to r: Int, end: JSONValue) {
        guard let i = s.companyIndex(storeID), let ri = s.companyIndex(r) else { return }
        let owedToUs = s.companies[i].receivables.reduce(0) { $0 + $1.amount } + max(0, -s.companies[i].vatBalance)
        if owedToUs > 0 { Payments.companyReceives(&s, companyID: storeID, amount: owedToUs, category: nil, label: "Customer invoices collected") }
        let bills = CompanyFigures.billsOwed(s.companies[i])
        if bills > 0 { Payments.companyPays(&s, companyID: storeID, amount: bills, category: nil, label: "Final bills settled") }
        s.companies[i].set("recv", .array([])); s.companies[i].set("pay", .object([:])); s.companies[i].vatBalance = 0
        s.companies[ri].yearProfitSoFar += s.companies[i].yearProfitSoFar
        s.companies[ri].taxAccrued += s.companies[i].taxAccrued
        s.companies[i].yearProfitSoFar = 0; s.companies[i].taxAccrued = 0
        for k in s.loans.indices where s.loans[k].companyID == storeID { s.loans[k].companyID = r }
        if s.companies[i].int("loanCall") > 0 && s.companies[ri].int("loanCall") == 0 { s.companies[ri].set("loanCall", s.companies[i].int("loanCall")) }
        s.companies[i].set("gl56", .array([]))   // what it owed its sisters was the chain's own money
        let c = jsRound(s.companies[i].cash)
        if c > 0 { move(&s, from: storeID, to: r, amount: c, label: "Cash of a branch that left") }
        if c < 0 { move(&s, from: r, to: storeID, amount: -c, label: "Overdraft of a branch that left") }
        Ledger.set(&s, .company(storeID), to: 0)
        s.companies[i].status = .sold
        s.companies[i].set("open13", .null)
        s.companies[i].set("brEnd", end)
        for k in s.inbox.indices where s.inbox[k].companyID == storeID && s.inbox[k].status == "open" { s.inbox[k].set("status", "done") }
    }

    /// How a branch left its chain, if it did: "closed" or "sold".
    public static func ending(_ co: Company) -> String? { co.value("brEnd").isNull ? nil : co.value("brEnd")["k"].string }
}
