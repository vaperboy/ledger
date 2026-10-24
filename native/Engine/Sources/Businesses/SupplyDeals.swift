import Foundation
import GameCore
import Countries
import Finance

/// What choosing a provider does (one engine action, `GameEngine.switchSupplier`, carries it out).
public enum SupplierSwitch: Equatable, Sendable {
    /// A named outside supplier of goods ("auto" lets the manager or market choose).
    case goodsVendor(String)
    /// A named outside repair supplier ("auto" = none fixed).
    case repairVendor(String)
    /// Back to outside suppliers (for an input that your own companies could supply).
    case outside
    case ownCompany(Int, mode: String)
    case businessCustomer(Int)
}

public enum SupplierSwitchResult: Equatable, Sendable { case ok, notAllowed, notKnownWell, unknown, governed }

/// The deals with providers behind the Suppliers section: switching (one path for a store and for a chain rule), the chain-wide supplier rule,
/// and the negotiation of a supplier's price. Outside suppliers are negotiated through the shared `Negotiation` module; your own companies
/// at their transfer price are not (the price is fixed by the mode you pick).
///
/// Chain rule: `rules.sup[input]` of the chain (key present only while a rule is set). It is mandatory for the chain's stores in the same
/// way a knob standard is: each store switches on its own terms, a store that cannot (the provider does not serve it, the own company has no
/// spare capacity) keeps its choice and is reported, and releasing the rule gives the choice back. A franchised unit follows the rule only if its
/// franchise agreement fixes that input (`franchise.supStd`); a holding imposes nothing on its subsidiaries (the rule belongs to a chain).
public enum SupplyDeals {
    // MARK: Switching

    /// The input ids: "goods", "repair" or a supply kind id.
    public static func perform(_ s: inout GameState, _ d: GameData, companyID: Int, input: String, to change: SupplierSwitch) -> SupplierSwitchResult {
        guard let co = s.company(companyID), co.status.isLive else { return .unknown }
        switch change {
        case .goodsVendor(let id):
            guard input == "goods", id == "auto" || Suppliers.candidates(s, company: co, scope: "goods", data: d).contains(where: { $0.id == id }) else { return .notAllowed }
            Suppliers.chooseGoodsVendor(&s, companyID: companyID, vendorID: id); return .ok
        case .repairVendor(let id):
            guard input == "repair", id == "auto" || Suppliers.candidates(s, company: co, scope: "fix", data: d).contains(where: { $0.id == id }) else { return .notAllowed }
            Suppliers.chooseRepairVendor(&s, companyID: companyID, vendorID: id); return .ok
        case .outside:
            guard IntercompanySupply.kind(input) != nil else { return .notAllowed }
            IntercompanySupply.clearSupplier(&s, buyer: companyID, kind: input)
            AccountSupply.clear(&s, buyer: companyID, kind: input); return .ok
        case .ownCompany(let sid, let mode):
            guard let k = IntercompanySupply.kind(input), IntercompanySupply.suppliers(s, for: co, kind: k).contains(where: { $0.id == sid }) else { return .notAllowed }
            return IntercompanySupply.setSupplier(&s, buyer: companyID, kind: input, supplier: sid, mode: mode) ? .ok : .notAllowed
        case .businessCustomer(let aid):
            guard IntercompanySupply.kind(input) != nil else { return .notAllowed }
            switch AccountSupply.set(&s, buyer: companyID, kind: input, accountID: aid, data: d) {
            case .ok: return .ok
            case .notKnownWell: return .notKnownWell
            case .notAllowed: return .notAllowed
            case .unknownAccount: return .unknown
            }
        }
    }

    /// Is this the provider the company uses for the input now?
    public static func isCurrent(_ s: GameState, _ co: Company, input: String, _ change: SupplierSwitch) -> Bool {
        switch change {
        case .goodsVendor(let id):
            let v = co.value("src")["v"]
            return id == "auto" ? (v.isNull || v.string == "auto") : v.string == id
        case .repairVendor(let id):
            let f = co.value("fixv")
            return id == "auto" ? (f.isNull || f.string == "auto" || f.string.isEmpty) : f.string == id
        case .outside:
            return IntercompanySupply.link(s, buyer: co.id, kind: input) == nil && AccountSupply.link(s, buyer: co.id, kind: input) == nil
        case .ownCompany(let sid, let mode):
            let l = IntercompanySupply.link(s, buyer: co.id, kind: input)
            return l?.supplierID == sid && l?.mode == mode
        case .businessCustomer(let aid):
            return AccountSupply.link(s, buyer: co.id, kind: input)?.accountID == aid
        }
    }

    // MARK: Chain rule

    static func encode(_ c: SupplierSwitch) -> JSONValue {
        switch c {
        case .goodsVendor(let id): return .object(["t": "gv", "id": .string(id)])
        case .repairVendor(let id): return .object(["t": "rv", "id": .string(id)])
        case .outside: return .object(["t": "out"])
        case .ownCompany(let id, let mode): return .object(["t": "own", "n": .number(Double(id)), "mode": .string(mode)])
        case .businessCustomer(let id): return .object(["t": "acct", "n": .number(Double(id))])
        }
    }
    static func decode(_ j: JSONValue) -> SupplierSwitch? {
        switch j["t"].string {
        case "gv": return .goodsVendor(j["id"].string)
        case "rv": return .repairVendor(j["id"].string)
        case "out": return .outside
        case "own": return .ownCompany(j["n"].int, mode: j["mode"].string)
        case "acct": return .businessCustomer(j["n"].int)
        default: return nil
        }
    }

    /// The chain's rule for an input, if it has one.
    public static func chainRule(_ s: GameState, chainID: Int, input: String) -> SupplierSwitch? {
        Chains.chain(s, id: chainID).flatMap { decode($0["rules"]["sup"][input]) }
    }
    /// The inputs a chain has a rule for.
    public static func chainRuleInputs(_ s: GameState, chainID: Int) -> [String] {
        (Chains.chain(s, id: chainID)?["rules"]["sup"].object.keys.sorted()) ?? []
    }

    /// Who governs this input for the company, if anyone. A franchised unit is bound only where its agreement says so.
    public static func governedBy(_ s: GameState, _ co: Company, input: String) -> String? {
        guard let ch = Chains.chain(s, of: co), !ch["rules"]["sup"][input].isNull else { return nil }
        let f = co.value("franchise")
        if f["fran"].bool {
            return f["supStd"][input].isNull ? nil : "Your franchise agreement with \(f["brandName"].isNull ? "the franchisor" : f["brandName"].string) fixes this."
        }
        return "\(ch["name"].string) sets this for all its stores."
    }

    public struct ChainLine: Equatable, Identifiable, Sendable {
        public var id: Int { storeID }
        public var storeID: Int
        public var storeName: String
        /// False when the store already uses the provider.
        public var changes: Bool
        /// Why this store keeps its choice (nil = it follows the rule).
        public var reason: String?
        /// True when the store is a franchised unit that the rule does not bind.
        public var free: Bool
    }
    public struct ChainPlan: Equatable, Sendable {
        public var lines: [ChainLine]
        public init(lines: [ChainLine]) { self.lines = lines }
        public var changing: Int { lines.filter { $0.changes && $0.reason == nil }.count }
        public var exceptions: Int { lines.filter { $0.changes && $0.reason != nil }.count }
    }

    /// Why this store could not use that provider (nil = it can). `committed` is the capacity already promised to a supplier in this round.
    static func problem(_ s: GameState, _ d: GameData, store co: Company, input: String, _ change: SupplierSwitch, committed: inout [Int: Double]) -> String? {
        switch change {
        case .goodsVendor(let id):
            if input != "goods" { return "Not an input of this store." }
            if id != "auto", !Suppliers.candidates(s, company: co, scope: "goods", data: d).contains(where: { $0.id == id }) { return "That supplier does not serve this store." }
            return nil
        case .repairVendor(let id):
            if input != "repair" { return "Not an input of this store." }
            if id != "auto", !Suppliers.candidates(s, company: co, scope: "fix", data: d).contains(where: { $0.id == id }) { return "That supplier does not serve this store." }
            return nil
        case .outside:
            return IntercompanySupply.kind(input) != nil && IntercompanySupply.kindsFor(co).contains(where: { $0.id == input }) ? nil : "This store does not buy that input."
        case .ownCompany(let sid, _):
            guard let k = IntercompanySupply.kind(input), IntercompanySupply.kindsFor(co).contains(where: { $0.id == input }) else { return "This store does not buy that input." }
            guard let sp = IntercompanySupply.suppliers(s, for: co, kind: k).first(where: { $0.id == sid }) else {
                return "\(s.company(sid)?.name ?? "That company") cannot supply this store" + (k.local ? " (it must be in the same city)." : " (it must be in the same country).")
            }
            if k.noCapacity { return nil }
            guard sp.status == .open else { return "\(sp.name) is not trading yet." }
            guard let bd = d.catalog[sp.type] else { return nil }
            let ticket = Pricing.ticket(sp, bd, World(state: s, data: d))
            guard ticket > 0 else { return nil }
            let need = IntercompanySupply.weeklySpend(co, k) / ticket
            let lw = sp.value("lastW")
            let free = max(0, lw["cap"].double - lw["units"].double) - (committed[sid] ?? 0)
            let already = IntercompanySupply.link(s, buyer: co.id, kind: input)?.supplierID == sid
            if !already && need > free + 1e-9 { return "\(sp.name) has no spare capacity for it (needs about \(Int(need.rounded())) sales a week, \(Int(free.rounded())) free)." }
            if !already { committed[sid, default: 0] += need }
            return nil
        case .businessCustomer(let aid):
            guard IntercompanySupply.kindsFor(co).contains(where: { $0.id == input }) else { return "This store does not buy that input." }
            guard let c = AccountSupply.candidates(s, buyer: co.id, kind: input, data: d).first(where: { $0.accountID == aid }) else { return "That business customer is not available to this store." }
            return c.canBuy ? nil : "They do not know this store well enough yet."
        }
    }

    /// What making this the chain's rule would do store by store. Nothing is changed.
    public static func chainPlan(_ s: GameState, _ d: GameData, chainID: Int, input: String, _ change: SupplierSwitch) -> ChainPlan {
        guard let ch = Chains.chain(s, id: chainID) else { return ChainPlan(lines: []) }
        var committed: [Int: Double] = [:]
        var lines: [ChainLine] = []
        for co in Chains.stores(s, ch) {
            let f = co.value("franchise")
            let free = f["fran"].bool && f["supStd"][input].isNull
            let same = isCurrent(s, co, input: input, change)
            var reason: String? = nil
            if free { reason = "A franchised unit: its agreement does not cover this, so it decides." }
            else if !same { reason = problem(s, d, store: co, input: input, change, committed: &committed) }
            lines.append(ChainLine(storeID: co.id, storeName: co.name, changes: !same, reason: reason, free: free))
        }
        return ChainPlan(lines: lines)
    }

    /// Make this the chain's mandatory rule for the input and switch every store it governs. A store that cannot keeps its choice and is
    /// reported; running it again later retries the stores that still differ.
    @discardableResult
    public static func setChainRule(_ s: inout GameState, _ d: GameData, chainID: Int, input: String, _ change: SupplierSwitch) -> ChainPlan {
        guard var ch = Chains.chain(s, id: chainID) else { return ChainPlan(lines: []) }
        let plan0 = chainPlan(s, d, chainID: chainID, input: input, change)
        ch["rules"]["sup"][input] = encode(change)
        Chains.save(&s, ch)
        var lines = plan0.lines
        for n in lines.indices where lines[n].changes && lines[n].reason == nil {
            let r = perform(&s, d, companyID: lines[n].storeID, input: input, to: change)
            if r != .ok {
                lines[n].reason = "The switch was not possible (\(r))."
                s.note("\(lines[n].storeName) keeps its supplier for \(inputTitle(input)): the switch was not possible.", tone: "warn", companyID: lines[n].storeID)
            }
        }
        for l in lines where l.changes && l.reason != nil && !l.free {
            s.note("\(l.storeName) keeps its own supplier for \(inputTitle(input)): \(l.reason ?? "")", tone: "warn", companyID: l.storeID)
        }
        return ChainPlan(lines: lines)
    }

    /// Give the choice back to the stores.
    public static func releaseChainRule(_ s: inout GameState, chainID: Int, input: String) {
        guard var ch = Chains.chain(s, id: chainID) else { return }
        var sup = ch["rules"]["sup"].object
        sup.removeValue(forKey: input)
        if sup.isEmpty { var r = ch["rules"].object; r.removeValue(forKey: "sup"); ch["rules"] = .object(r) } else { ch["rules"]["sup"] = .object(sup) }
        Chains.save(&s, ch)
    }

    /// A store that joins a chain (or opens in it) follows the chain's supplier rules like any other; one that cannot is told so.
    static func applyChainRules(_ s: inout GameState, _ d: GameData, storeID: Int) {
        guard let co = s.company(storeID), let ch = Chains.chain(s, of: co) else { return }
        for input in ch["rules"]["sup"].object.keys.sorted() {
            guard let c = decode(ch["rules"]["sup"][input]), let cur = s.company(storeID), governedBy(s, cur, input: input) != nil, !isCurrent(s, cur, input: input, c) else { continue }
            var committed: [Int: Double] = [:]
            if let why = problem(s, d, store: cur, input: input, c, committed: &committed) {
                s.note("\(cur.name) joined \(ch["name"].string) but keeps its own supplier for \(inputTitle(input)): \(why)", tone: "warn", companyID: storeID)
            } else { _ = perform(&s, d, companyID: storeID, input: input, to: c) }
        }
    }

    public static func inputTitle(_ input: String) -> String {
        input == "goods" ? "goods" : input == "repair" ? "repairs" : (IntercompanySupply.kind(input)?.name.lowercased() ?? input)
    }

    // MARK: Negotiated prices

    static func scope(_ input: String) -> String? { input == "goods" ? "goods" : input == "repair" ? "fix" : nil }

    /// The extra discount a deal with this supplier gives (on top of the relationship's), while it lasts.
    public static func dealDiscount(_ co: Company, scope: String, vendorID: String, week: Int) -> Double {
        let d = co.value("sdl")[scope]
        guard !d.isNull, d["v"].string == vendorID, week - d["w"].int < SupplyTerms.tables.dealWeeks else { return 0 }
        return d["d"].double
    }
    public struct Deal: Equatable, Sendable { public var vendorID: String; public var extraDiscount: Double; public var weeksLeft: Int }
    public static func deal(_ co: Company, input: String, week: Int) -> Deal? {
        guard let sc = scope(input) else { return nil }
        let d = co.value("sdl")[sc]
        guard !d.isNull, week - d["w"].int < SupplyTerms.tables.dealWeeks else { return nil }
        return Deal(vendorID: d["v"].string, extraDiscount: d["d"].double, weeksLeft: SupplyTerms.tables.dealWeeks - (week - d["w"].int))
    }
    /// Until which week the supplier will not talk (after a walk-out), or nil.
    public static func coolUntil(_ co: Company, vendorID: String, week: Int) -> Int? {
        let u = co.value("sdl")["cool"][vendorID]
        return u.isNull || u.int <= week ? nil : u.int
    }

    @discardableResult
    static func dropDeal(_ s: inout GameState, companyIndex i: Int, vendorID: String) -> Bool {
        var sdl = s.companies[i].value("sdl")
        guard !sdl.isNull else { return false }
        var o = sdl.object
        var dropped = false
        for sc in ["goods", "fix"] where o[sc]?["v"].string == vendorID { o.removeValue(forKey: sc); dropped = true }
        guard dropped else { return false }
        sdl = .object(o)
        if o.isEmpty || (o.count == 1 && o["cool"]?.object.isEmpty == true) { s.companies[i].raw.removeValue(forKey: "sdl") } else { s.companies[i].set("sdl", sdl) }
        return true
    }

    public enum Talk: Equatable, Sendable {
        /// Agreed: the extra discount (0 = list terms) and the supplier is now used.
        case agreed(extra: Double)
        /// The supplier names its own figure (an extra discount): accept it, counter, or walk away.
        case countered(Negotiation.Counter)
        case refused
        /// Patience gone: the supplier will not talk until this week.
        case walkedAway(until: Int)
        case cooling(until: Int)
        case notAllowed
        case notNeeded(String)
    }

    /// The most extra discount this supplier could give someone it knows this well (hidden from the player; the talk finds it).
    static func headroom(relationship r: Double) -> Double {
        let t = SupplyTerms.tables
        return t.headroomBase + t.headroomPerRelationship * r
    }

    static func partyKey(_ vendorID: String, _ input: String) -> Int {
        Int(HashedRandom.first("talk:\(vendorID):\(input)") * 900) + 1
    }

    /// Ask an outside supplier for an extra discount `ask` (a share, 0.02 = 2 points) and use them. The better you know them, the more they
    /// can give and the longer they listen; asking for nothing is just taking their list terms. Your own companies, business customers and
    /// "back to outside suppliers" need no talk.
    public static func negotiate(_ s: inout GameState, _ d: GameData, companyID: Int, input: String, vendorID: String, ask: Double) -> Talk {
        guard let sc = scope(input), let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return .notNeeded("Only outside suppliers of goods and repairs are negotiated.") }
        let co = s.companies[i]
        if governedBy(s, co, input: input) != nil { return .notAllowed }
        guard Suppliers.candidates(s, company: co, scope: sc, data: d).contains(where: { $0.id == vendorID }) else { return .notAllowed }
        let now = s.week
        if let until = coolUntil(co, vendorID: vendorID, week: now) { return .cooling(until: until) }
        let switchTo: SupplierSwitch = input == "goods" ? .goodsVendor(vendorID) : .repairVendor(vendorID)
        func finish(_ extra: Double) -> Talk {
            _ = perform(&s, d, companyID: companyID, input: input, to: switchTo)
            if let k = s.companyIndex(companyID) {
                var talkless = s.companies[k]
                Negotiation.State().store(in: &talkless)
                s.companies[k] = talkless
                if extra > 0 {
                    var sdl = s.companies[k].value("sdl"); if sdl.isNull { sdl = .object([:]) }
                    sdl[sc] = .object(["v": .string(vendorID), "d": .number(extra), "w": .number(Double(now))])
                    s.companies[k].set("sdl", sdl)
                } else {
                    let cur = s.companies[k].value("sdl")[sc]
                    if !cur.isNull, cur["v"].string != vendorID { _ = dropDeal(&s, companyIndex: k, vendorID: cur["v"].string) }
                }
            }
            return .agreed(extra: extra)
        }
        if ask <= 0 { return finish(0) }
        let rel = Suppliers.relationship(s, vendorID)
        var temper = Negotiation.temperament(personality: nil, key: vendorID)
        temper.patience *= 1 + SupplyTerms.tables.patiencePerRelationship * rel
        let position = Negotiation.position(reservation: headroom(relationship: rel), direction: .lower, temperament: temper, key: "sup:\(vendorID)")
        var talk = Negotiation.State.resume(co, party: partyKey(vendorID, input), week: now)
        let reply = Negotiation.respond(offer: ask, position: position, temperament: temper, rank: SupplyTerms.tables.rank, state: &talk, week: now,
                                        step: SupplyTerms.tables.step, random: &s.random)
        switch reply.answer {
        case .accept:
            return finish(ask)
        case .counter(let c):
            talk.store(in: &s.companies[i]); return .countered(c)
        case .refuse:
            talk.store(in: &s.companies[i]); return .refused
        case .walkAway:
            var c2 = s.companies[i]
            Negotiation.State().store(in: &c2)
            var sdl = c2.value("sdl"); if sdl.isNull { sdl = .object([:]) }
            let until = now + SupplyTerms.tables.coolWeeks
            sdl["cool"][vendorID] = .number(Double(until))
            c2.set("sdl", sdl)
            s.companies[i] = c2
            Suppliers.dock(&s, vendorID, by: SupplyTerms.tables.walkAwayHit)
            let name = Suppliers.vendor(s, id: vendorID, scope: sc, data: d)?.name ?? "The supplier"
            s.note("\(name) lost patience with \(co.name) and ended the talks for now.", tone: "warn", companyID: companyID)
            return .walkedAway(until: until)
        }
    }
}
