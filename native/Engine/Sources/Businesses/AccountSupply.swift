import Foundation
import GameCore
import Countries
import Finance

/// Buying an input from one of your business customers (a key account). A key account of any of your companies that runs the
/// right trade (a cleaner, a bakery, a web agency ...) can supply one of your other companies once you know them well enough
/// (familiar or closer). They sell a little below the outside price; the saving is booked as a lower cost of the buyer each week
/// and the relationship keeps warming. A new link ends an own-company link for the same input (`IntercompanySupply`) and the other
/// way round. Originals: `ACT.ch39set`, `ACT.ch39off`, `custSuppliers`, `theirPf` and the weekly step 'small_team_and_rewards weekly'
/// (features/company/small_team_and_rewards.js). The links are saved in `rest["l39"]` as { id, k, b (buyer), a (account), w0, save }.
public enum AccountSupply {
    public struct Candidate: Equatable, Identifiable, Sendable {
        public var id: Int { accountID }
        public var accountID: Int
        public var accountName: String
        /// The company of yours that the account buys from
        public var ownerCompanyID: Int
        public var ownerCompanyName: String
        public var relationship: Double
        /// Familiar or closer: only then do they sell to you.
        public var canBuy: Bool
        /// Their price against the outside price (1 = same).
        public var priceFactor: Double
        /// What the buyer would save in a year at today's spending.
        public var yearlySaving: Double
    }

    public struct Link: Equatable, Identifiable, Sendable {
        public var id: Int
        public var kindID: String
        public var buyerID: Int
        public var accountID: Int
        public var savedSoFar: Double
        init(_ j: JSONValue) { id = j["id"].int; kindID = j["k"].string; buyerID = j["b"].int; accountID = j["a"].int; savedSoFar = j["save"].double }
    }

    static func rawLinks(_ s: GameState) -> [JSONValue] { s.rest["l39"]?.array ?? [] }

    /// Original: `theirPf`: 2% below the outside price, plus the discount of the relationship, plus a quarter of the discount you give them.
    public static func priceFactor(relationship: Double, discountPercent: Int) -> Double {
        1 - min(0.2, 0.02 + Suppliers.relationshipDiscount(relationship) + Double(discountPercent) / 400)
    }

    public static func links(_ s: GameState) -> [Link] { rawLinks(s).map { Link($0) } }
    public static func link(_ s: GameState, buyer: Int, kind: String) -> Link? { links(s).first { $0.buyerID == buyer && $0.kindID == kind } }

    /// The key accounts of your open companies in the buyer's country (and city, for local inputs) whose trade supplies this input.
    /// Original: `custSuppliers`. A company's own accounts are left out.
    public static func candidates(_ s: GameState, buyer: Int, kind kid: String, data: GameData) -> [Candidate] {
        guard let b = s.company(buyer), let k = IntercompanySupply.kind(kid), k.buyers[b.type] != nil else { return [] }
        let spend = IntercompanySupply.yearlySpend(b, k)
        var out: [Candidate] = []
        for c in s.companies where c.status == .open && c.id != b.id && c.countryCode == b.countryCode && (!k.local || c.cityID == b.cityID) {
            for a in KeyAccounts.accounts(c) where k.suppliers.contains(a.tradeID) {
                let pf = priceFactor(relationship: a.relationship, discountPercent: a.discount)
                out.append(Candidate(accountID: a.id, accountName: a.name, ownerCompanyID: c.id, ownerCompanyName: c.name, relationship: a.relationship,
                                     canBuy: KeyAccounts.profile(a, data: data).canBuy, priceFactor: pf, yearlySaving: spend * (1 - pf)))
            }
        }
        return out
    }

    /// Where an account lives: its record and the company it belongs to.
    static func find(_ s: GameState, accountID: Int) -> (company: Int, index: Int)? {
        for (ci, c) in s.companies.enumerated() where c.status.isLive {
            if let k = c.value("accts").array.firstIndex(where: { $0["id"].int == accountID }) { return (ci, k) }
        }
        return nil
    }

    public enum SetResult: Equatable, Sendable { case ok, notAllowed, unknownAccount, notKnownWell }

    /// Buy this input from that business customer. Original: `ACT.ch39set`.
    @discardableResult
    public static func set(_ s: inout GameState, buyer: Int, kind kid: String, accountID: Int, data: GameData) -> SetResult {
        guard let b = s.company(buyer), b.status.isLive, IntercompanySupply.kind(kid) != nil else { return .notAllowed }
        guard let c = candidates(s, buyer: buyer, kind: kid, data: data).first(where: { $0.accountID == accountID }) else { return .unknownAccount }
        guard c.canBuy else { return .notKnownWell }
        IntercompanySupply.clearSupplier(&s, buyer: buyer, kind: kid)
        var L = rawLinks(s).filter { !($0["b"].int == buyer && $0["k"].string == kid) }
        L.append(.object(["id": .number(Double(s.makeID())), "k": .string(kid), "b": .number(Double(buyer)), "a": .number(Double(accountID)), "w0": .number(Double(s.week)), "save": 0]))
        s.rest["l39"] = .array(L)
        return .ok
    }

    /// Back to outside suppliers. Original: `ACT.ch39off`.
    public static func clear(_ s: inout GameState, buyer: Int, kind kid: String) {
        guard s.rest["l39"] != nil else { return }
        s.rest["l39"] = .array(rawLinks(s).filter { !($0["b"].int == buyer && $0["k"].string == kid) })
    }

    /// Each week: the buyer saves what it would have paid above their price, and the relationship warms.
    static func weekly(_ s: inout GameState) {
        guard !rawLinks(s).isEmpty else { return }
        var kept: [JSONValue] = []
        for l0 in rawLinks(s) {
            var l = l0
            guard let bi = s.companyIndex(l["b"].int), s.companies[bi].status.isLive, let K = IntercompanySupply.kind(l["k"].string) else { continue }
            let b = s.companies[bi]
            guard let at = find(s, accountID: l["a"].int) else {
                s.addMessage(kind: "info", from: b.name, title: "A business customer stopped supplying \(b.name)",
                             body: "Your business customer stopped supplying \(K.name.lowercased()) to \(b.name). It buys outside again.", companyID: b.id, tone: "bad")
                continue
            }
            kept.append(l)
            guard b.status == .open else { continue }
            let ci = at.company, ai = at.index
            var accts = s.companies[ci].value("accts").array
            let rel = accts[ai]["rel"].double
            let pf = priceFactor(relationship: rel, discountPercent: accts[ai]["disc"].int)
            let sv = IntercompanySupply.weeklySpend(b, K) * (1 - pf)
            if sv > 0 {
                Payments.companyReceives(&s, companyID: b.id, amount: sv, category: nil, label: nil)
                Payments.book(&s, companyID: b.id, category: K.category, amount: -jsRound(sv))
            }
            l["save"] = .number(l["save"].double + sv)
            kept[kept.count - 1] = l
            accts[ai]["rel"] = .number(min(100, rel + 0.3 * (1 - pow(rel / 100, 1.6))))
            s.companies[ci].set("accts", .array(accts))
        }
        s.rest["l39"] = .array(kept)
    }
}
