import Foundation
import GameCore
import Countries
import Finance

/// Stakes a holding company holds in other companies, bought or sold in whole or in part.
///
/// Tiers (share of the company the holding owns, own and rival companies alike):
///  - under 20%: passive investment. Dividends only, no board seat, nothing consolidated.
///  - 20% to 50%: significant influence. The holding may take a board seat; its share of profit is shown as an associate, not consolidated.
///  - over 50%: control. Consolidated (revenue, cash and debt in the group view), the holding votes at the board with a seat of right and the
///    owner can run the company and replace its manager.
///  - 90% or more: squeeze-out right (the rest may be bought at fair value and the company merged into the holding) and the tax group.
///  - 100%: wholly owned.
/// Price = valuation x percent, x 1.25 (control premium) when the shares bought take the holding over 50%, x 0.85 (minority discount) when it
/// stays under 20%; shares bought from the owner personally always change hands at fair value. Selling to the market fetches 0.80 / 0.90 / 1.00
/// of fair value for a passive / influence / control stake, so buying and selling back never earns money.
///
/// State: a stake in one of your companies is a `holders[]` entry on its cap table (real shares) with `hid` = the holding's id and `seat` = whether
/// the holding sits on the board. Shares the owner put under the holding with `HoldingModel.move` stay `Company.ownership` + `holdingID`; the
/// holding's share is both together (`sharePercent`). A stake in a rival is a record in the holding's `fm.rs` = [{ k: market key, id, name, pct,
/// paid, val }]; its value follows the rival and it pays a yearly yield on that value.
public enum HoldingStakes {
    public static let passiveBelow = 20.0
    public static let controlAbove = 50.0
    public static let squeezeOutFrom = 90.0
    public static let controlPremium = 1.25
    public static let minorityDiscount = 0.85
    /// Yearly dividend a rival stake pays, as a share of its value.
    public static let rivalYield = 0.04
    /// Smallest step that can be bought or sold, in percent.
    public static let minimumPercent = 0.5

    public enum Tier: String, Equatable, Sendable {
        case none, passive, influence, control, squeezeOut, whole

        public var title: String {
            switch self {
            case .none: return "No stake"
            case .passive: return "Passive investment"
            case .influence: return "Significant influence"
            case .control: return "Control"
            case .squeezeOut: return "Control, squeeze-out right"
            case .whole: return "Wholly owned"
            }
        }
        public var summary: String {
            switch self {
            case .none: return "The holding owns no shares."
            case .passive: return "Dividends only. No board seat."
            case .influence: return "May take a board seat. Its share of profit is shown as an associate, not consolidated."
            case .control: return "Consolidated. Votes at the board and appoints the management."
            case .squeezeOut: return "May buy the remaining shares at fair value and merge the company into the holding. Part of the tax group."
            case .whole: return "Owns every share."
            }
        }
        public var canSitOnBoard: Bool { self != .none && self != .passive }
        public var isConsolidated: Bool { self == .control || self == .squeezeOut || self == .whole }
    }

    public static func tier(forPercent p: Double) -> Tier {
        if p <= 0.0001 { return .none }
        if p < passiveBelow { return .passive }
        if p <= controlAbove { return .influence }
        if p < squeezeOutFrom { return .control }
        if p < 99.9999 { return .squeezeOut }
        return .whole
    }

    public enum Failure: Error, Equatable, Sendable {
        case notAHolding, notFound
        case notEnoughCash(needed: Double)
        case refused(String)

        /// One plain sentence for the screen.
        public var reason: String {
            switch self {
            case .notAHolding: return "That is not an open holding company."
            case .notFound: return "That company is not available."
            case .notEnoughCash(let n): return "The holding needs \(Int(saturating: n.rounded())) in its account for this. Put cash into the holding first."
            case .refused(let why): return why
            }
        }
    }

    public enum Source: String, Equatable, Sendable { case auto, owner, others }
    public enum Buyer: String, Equatable, Sendable { case market, owner }

    // MARK: Reading stakes

    /// The holding's own cap table entry in a company, if it has one.
    static func line(_ c: Company, _ hid: Int) -> JSONValue? {
        c.value("holders").array.first { $0["hid"].int == hid && $0["sh"].int > 0 }
    }
    /// Share of a company (in percent) that sits in a holding: shares bought as a stake plus the owner's shares put under it.
    public static func sharePercent(of c: Company, holdingID hid: Int) -> Double {
        (c.holdingID == hid ? c.ownership : 0) + (line(c, hid)?["pct"].double ?? 0)
    }
    /// Shares of a company held by any holding through a stake (not counting the owner's own shares moved under one).
    public static func heldByHoldings(_ c: Company) -> Double {
        c.value("holders").array.filter { $0["hid"].int != 0 }.reduce(0) { $0 + $1["pct"].double }
    }
    public static func hasSeat(_ c: Company, holdingID hid: Int) -> Bool {
        guard let l = line(c, hid) else { return false }
        return l["seat"].bool || l["pct"].double > controlAbove
    }
    /// What the owner's side votes with in a company: own shares plus every stake of a holding that sits on the board (a controlling one always does).
    public static func votingPercent(_ c: Company) -> Double {
        c.ownership + c.value("holders").array.filter { $0["hid"].int != 0 && ($0["seat"].bool || $0["pct"].double > controlAbove) }.reduce(0) { $0 + $1["pct"].double }
    }
    /// The holding that owns at least 90% of a company through a stake, for the tax group.
    static func controllingHolding(of c: Company, in s: GameState) -> Company? {
        guard let l = c.value("holders").array.first(where: { $0["hid"].int != 0 && $0["pct"].double >= squeezeOutFrom }) else { return nil }
        return s.company(l["hid"].int)
    }

    public static func tier(_ s: GameState, holdingID: Int, companyID: Int) -> Tier {
        guard let c = s.company(companyID) else { return .none }
        return tier(forPercent: sharePercent(of: c, holdingID: holdingID))
    }

    /// Live companies the holding owns shares of, whatever the size of the stake.
    public static func stakeCompanies(of holdingID: Int, in s: GameState) -> [Company] {
        s.companies.filter { $0.status.isLive && $0.type != "hold" && sharePercent(of: $0, holdingID: holdingID) > 0 }
    }

    // MARK: Rival stakes

    public struct RivalStake: Identifiable, Equatable, Sendable {
        public var id: Int
        public var key: String
        public var name: String
        public var percent: Double
        public var paid: Double
        public var value: Double
        public var share: Double { value * percent / 100 }
        public var tier: Tier { HoldingStakes.tier(forPercent: percent) }
    }

    public static func rivalStakes(_ h: Company) -> [RivalStake] {
        h.value("fm")["rs"].array.map {
            RivalStake(id: $0["id"].int, key: $0["k"].string, name: $0["name"].string, percent: $0["pct"].double, paid: $0["paid"].double, value: $0["val"].double)
        }
    }
    /// What the holding's rival stakes are worth, from the values kept at the last revaluation.
    public static func rivalStakesValue(_ h: Company) -> Double { rivalStakes(h).reduce(0) { $0 + $1.share } }

    /// The market key and rival record for a rival id (ids are unique across markets).
    static func findRival(_ s: GameState, id: Int) -> (key: String, rival: Rivals.Rival)? {
        for key in (s.rest["mk"]?.object ?? [:]).keys.sorted() {
            if let r = Rivals.rivals(s, key: key).first(where: { $0.id == id }) { return (key, r) }
        }
        return nil
    }
    /// What a rival business is worth, worked from one of your own companies in the same market. Nil when there is none or the rival is gone.
    static func rivalValue(_ s: GameState, key: String, id: Int, data: GameData) -> Double? {
        guard let ref = s.companies.first(where: { $0.status.isLive && Rivals.key($0) == key }), let bd = data.catalog[ref.type],
              let r = Rivals.rivals(s, key: key).first(where: { $0.id == id }) else { return nil }
        return Rivals.value(bd, r, World(state: s, data: data), ref)
    }

    /// Bring the stored value of each rival stake up to date; a rival that has closed takes the stake with it. Returns the total worth of the stakes.
    @discardableResult
    static func revalueRivals(_ s: inout GameState, holdingID: Int, data: GameData) -> Double {
        guard let i = s.companyIndex(holdingID) else { return 0 }
        var fm = s.companies[i].value("fm")
        var list = fm["rs"].array
        if list.isEmpty { return 0 }
        var out: [JSONValue] = []
        var lost: [String] = []
        for var rec in list {
            let key = rec["k"].string, id = rec["id"].int
            if let v = rivalValue(s, key: key, id: id, data: data) {
                rec["val"] = .number(v); out.append(rec)
            } else if !s.companies.contains(where: { $0.status.isLive && Rivals.key($0) == key }) {
                out.append(rec)   // no company of yours in that market any more: keep the last value
            } else {
                lost.append(rec["name"].string)
            }
        }
        list = out
        fm["rs"] = .array(list)
        s.companies[i].set("fm", fm)
        for n in lost { s.note("\(n) has closed, so \(s.companies[i].name) lost its stake.", tone: "bad", companyID: holdingID) }
        return rivalStakesValue(s.companies[i])
    }

    /// Rival stakes pay their yield into the holding's cash once a month (four weeks at a time).
    static func weekly(_ s: inout GameState) {
        guard s.week % 4 == 0 else { return }
        for h in s.companies where h.type == "hold" && h.status == .open {
            let pay = rivalStakesValue(h) * rivalYield * 4 / 52
            guard pay >= 1 else { continue }
            Payments.companyReceives(&s, companyID: h.id, amount: pay, category: nil, label: "Dividends from rival stakes")
        }
    }

    // MARK: Prices

    /// Factor on the fair price for shares bought from outside owners that leave the holding with `after` percent.
    public static func buyFactor(afterPercent after: Double) -> Double {
        after > controlAbove ? controlPremium : after >= passiveBelow ? 1 : minorityDiscount
    }
    /// Factor on the fair price when the holding sells to the market, by the size of the stake before the sale.
    public static func sellFactor(beforePercent before: Double) -> Double {
        before > controlAbove ? 1 : before >= passiveBelow ? 0.9 : 0.8
    }

    // MARK: Offers and quotes

    public struct Offer: Identifiable, Equatable, Sendable {
        public var id: String
        public var companyID: Int?
        public var rivalID: Int?
        /// One of your companies in the same market, the base for a rival's value (nil for your own companies).
        public var referenceCompanyID: Int?
        public var name: String
        public var trade: String
        public var isOwn: Bool
        /// What the whole business is worth.
        public var value: Double
        public var heldPercent: Double
        public var availablePercent: Double
        /// Asking price for one percent, at the discount a small stake gets and at the premium a controlling one costs.
        public var pricePerPercentMinority: Double
        public var pricePerPercentControl: Double
        public var note: String
    }

    public struct Quote: Equatable, Sendable {
        public var percent: Double
        public var value: Double
        public var price: Double
        public var fromOwnerPercent: Double
        public var fromOthersPercent: Double
        public var priceFactor: Double
        public var heldAfter: Double
        public var tierAfter: Tier
        /// For a sale: how much of `percent` comes from shares the holding bought and how much from shares you moved under it.
        public var boughtPercent: Double = 0
        public var movedPercent: Double = 0
    }

    public struct Deal: Equatable, Sendable {
        public var percent: Double
        public var amount: Double
        public var heldAfter: Double
        public var tierAfter: Tier
        /// For a sale: the split of `percent` between bought and moved shares (see `Quote`).
        public var boughtPercent: Double = 0
        public var movedPercent: Double = 0
    }

    static func eligibleCompany(_ c: Company, holdingID hid: Int, in s: GameState) -> Bool {
        c.status.isLive && c.form == .limited && c.type != "hold" && c.id != hid && !s.isBranch(c) && !isDivision(c)
    }
    static func openHolding(_ s: GameState, _ hid: Int) -> Company? {
        guard let h = s.company(hid), h.type == "hold", h.status.isLive else { return nil }
        return h
    }
    static func percentOf(shares n: Int, total: Int) -> Double { Double(n) / Double(max(1, total)) * 100 }
    static func sharesFor(percent: Double, total: Int) -> Int { Int(saturating: (Double(total) * percent / 100).rounded()) }

    /// Percent the owner could sell personally, and percent outside owners could sell, in a company.
    static func available(_ c: Company) -> (owner: Double, others: Double) {
        let t = CapTable.table(c)
        let owner = c.holdingID == 0 ? percentOf(shares: max(0, t.you - 1), total: t.total) : 0
        let others = c.value("holders").array.filter { $0["hid"].int == 0 }.reduce(0) { $0 + $1["pct"].double }
        return (owner, others)
    }

    /// Candidates: your own companies that have shares to buy and rivals that could sell a stake, with their asking prices.
    public static func offers(_ s: GameState, holdingID: Int, data: GameData) -> [Offer] {
        guard openHolding(s, holdingID) != nil else { return [] }
        var out: [Offer] = []
        for c in s.companies where eligibleCompany(c, holdingID: holdingID, in: s) {
            let v = Valuation.companyValue(c, state: s, trades: data.catalog)
            let a = available(c)
            let avail = a.owner + a.others
            let held = sharePercent(of: c, holdingID: holdingID)
            guard v > 0, avail >= minimumPercent else { continue }
            let note = c.holdingID != 0 && c.holdingID != holdingID ? "Your shares are under another holding. Outside owners may sell." : a.owner > 0 ? "You can sell your own shares to the holding at fair value." : "Outside owners hold the shares offered."
            out.append(Offer(id: "c:\(c.id)", companyID: c.id, rivalID: nil, referenceCompanyID: nil, name: c.name, trade: data.catalog.facts(for: c.type)?.id ?? c.type, isOwn: true,
                             value: v, heldPercent: held, availablePercent: avail, pricePerPercentMinority: jsRound(v / 100 * minorityDiscount),
                             pricePerPercentControl: jsRound(v / 100 * controlPremium), note: note))
        }
        var seen = Set<String>()
        for ref in s.companies where ref.status.isLive && ref.type != "hold" {
            let key = Rivals.key(ref)
            guard seen.insert(key).inserted, let bd = data.catalog[ref.type] else { continue }
            let w = World(state: s, data: data)
            for r in Rivals.rivals(s, key: key) where r.groupID == nil {
                let v = Rivals.value(bd, r, w, ref)
                let held = rivalStakes(s.company(holdingID)!).first { $0.id == r.id }?.percent ?? 0
                guard v > 0, 100 - held >= minimumPercent else { continue }
                out.append(Offer(id: "r:\(r.id)", companyID: nil, rivalID: r.id, referenceCompanyID: ref.id, name: r.name, trade: ref.type, isOwn: false, value: v, heldPercent: held,
                                 availablePercent: 100 - held, pricePerPercentMinority: jsRound(v / 100 * minorityDiscount), pricePerPercentControl: jsRound(v / 100 * controlPremium),
                                 note: r.forSale ? "\(r.owner) is open to selling." : r.relationship >= 45 ? "\(r.owner) may sell a stake." : "\(r.owner) will only sell a small stake."))
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    /// What buying `percent` of one of your companies would cost and leave. Refuses with the reason.
    public static func quote(_ s: GameState, holdingID: Int, companyID: Int, percent: Double, from source: Source = .auto, data: GameData) -> Result<Quote, Failure> {
        guard let h = openHolding(s, holdingID) else { return .failure(.notAHolding) }
        guard let c = s.company(companyID), eligibleCompany(c, holdingID: h.id, in: s) else { return .failure(.notFound) }
        guard percent >= minimumPercent, percent <= 100 else { return .failure(.refused("Choose at least \(minimumPercent)% and at most 100%.")) }
        let v = Valuation.companyValue(c, state: s, trades: data.catalog)
        guard v > 0 else { return .failure(.refused("\(c.name) is not worth anything yet.")) }
        let t = CapTable.table(c)
        let a = available(c)
        let wantOwner = source == .others ? 0 : min(percent, a.owner)
        let wantOthers = percent - wantOwner
        if source == .owner && wantOthers > 0.0001 { return .failure(.refused("You only hold \(String(format: "%.1f", a.owner))% of \(c.name) personally.")) }
        if wantOthers > a.others + 0.0001 {
            return .failure(.refused(a.others < minimumPercent ? "Nobody else owns shares of \(c.name) to sell." : "Only \(String(format: "%.1f", a.others))% of \(c.name) is for sale from outside owners."))
        }
        let nOwner = sharesFor(percent: wantOwner, total: t.total), nOthers = min(sharesFor(percent: wantOthers, total: t.total), Int(saturating: (a.others * Double(t.total) / 100).rounded()))
        guard nOwner + nOthers > 0 else { return .failure(.refused("That is less than one share.")) }
        let pOwner = percentOf(shares: nOwner, total: t.total), pOthers = percentOf(shares: nOthers, total: t.total)
        let after = sharePercent(of: c, holdingID: h.id) + pOwner + pOthers
        let factor = buyFactor(afterPercent: after)
        let price = jsRound(v * pOwner / 100 + v * pOthers / 100 * factor)
        return .success(Quote(percent: pOwner + pOthers, value: v, price: price, fromOwnerPercent: pOwner, fromOthersPercent: pOthers, priceFactor: factor, heldAfter: after, tierAfter: tier(forPercent: after)))
    }

    /// The same for a rival; `referenceCompanyID` is one of your companies in its market.
    public static func rivalQuote(_ s: GameState, holdingID: Int, rivalID: Int, percent: Double, data: GameData) -> Result<Quote, Failure> {
        guard let h = openHolding(s, holdingID) else { return .failure(.notAHolding) }
        guard let found = findRival(s, id: rivalID), let v = rivalValue(s, key: found.key, id: rivalID, data: data), v > 0 else { return .failure(.notFound) }
        let r = found.rival
        guard r.groupID == nil else { return .failure(.refused("\(r.name) belongs to a group. Deal with the group instead.")) }
        guard percent >= minimumPercent, percent <= 100 else { return .failure(.refused("Choose at least \(minimumPercent)% and at most 100%.")) }
        let held = rivalStakes(h).first { $0.id == rivalID }?.percent ?? 0
        guard held + percent <= 100.0001 else { return .failure(.refused("The holding already owns \(String(format: "%.1f", held))% of \(r.name).")) }
        let after = held + percent
        if after > controlAbove && !r.forSale && r.relationship < 45 { return .failure(.refused("\(r.owner) will not give up control of \(r.name). A stake of 50% or less may be possible.")) }
        if r.relationship < 25 && !r.forSale { return .failure(.refused("\(r.owner) does not want you as a shareholder.")) }
        let factor = buyFactor(afterPercent: after)
        return .success(Quote(percent: percent, value: v, price: jsRound(v * percent / 100 * factor), fromOwnerPercent: 0, fromOthersPercent: percent, priceFactor: factor, heldAfter: after, tierAfter: tier(forPercent: after)))
    }

    // MARK: Buying

    /// Move shares to the holding's line on the cap table: `nOwner` from the owner's own shares, `nOthers` pro rata from the outside owners.
    static func moveShares(_ s: inout GameState, _ ci: Int, to h: Company, fromOwner nOwner: Int, fromOthers nOthers: Int, paid: Double) {
        CapTable.normalise(&s, ci)
        let t = CapTable.read(s.companies[ci])
        var list = s.companies[ci].value("holders").array
        let pool = list.indices.filter { list[$0]["hid"].int == 0 }
        let poolShares = pool.reduce(0) { $0 + list[$1]["sh"].int }
        var taken = 0
        if nOthers > 0, poolShares > 0 {
            for k in pool {
                let take = min(list[k]["sh"].int, Int(saturating: (Double(list[k]["sh"].int) * Double(nOthers) / Double(poolShares)).rounded()))
                list[k]["sh"] = .number(Double(list[k]["sh"].int - take)); taken += take
            }
            // rounding leaves a few shares over or short: settle them on the largest outside owner
            var gap = nOthers - taken
            for k in pool.sorted(by: { list[$0]["sh"].int > list[$1]["sh"].int }) where gap != 0 {
                let adj = gap > 0 ? -min(gap, list[k]["sh"].int) : min(-gap, taken)
                list[k]["sh"] = .number(Double(list[k]["sh"].int + adj)); taken -= adj; gap = nOthers - taken
            }
        }
        let moved = nOwner + taken
        if let k = list.firstIndex(where: { $0["hid"].int == h.id }) {
            list[k]["sh"] = .number(Double(list[k]["sh"].int + moved)); list[k]["in"] = .number(list[k]["in"].double + paid)
        } else {
            list.append(.object(["name": .string(h.name), "sh": .number(Double(moved)), "pct": 0, "in": .number(paid), "sat": 100, "w0": .number(Double(s.week)), "hid": .number(Double(h.id))]))
        }
        list.removeAll { $0["sh"].int <= 0 }
        CapTable.sync(&s.companies[ci], total: t.total, me: t.you - nOwner, holders: list)
    }

    /// The holding buys `percent` of one of your companies: the owner's own shares first (fair value, paid to you), then outside owners'.
    public static func buy(_ s: inout GameState, holdingID: Int, companyID: Int, percent: Double, from source: Source = .auto, data: GameData) -> Result<Deal, Failure> {
        switch quote(s, holdingID: holdingID, companyID: companyID, percent: percent, from: source, data: data) {
        case .failure(let f): return .failure(f)
        case .success(let q):
            guard let hi = s.companyIndex(holdingID), let ci = s.companyIndex(companyID) else { return .failure(.notFound) }
            guard s.companies[hi].cash >= q.price else { return .failure(.notEnoughCash(needed: q.price)) }
            let c = s.companies[ci], h = s.companies[hi]
            let t = CapTable.table(c)
            let nOwner = sharesFor(percent: q.fromOwnerPercent, total: t.total), nOthers = sharesFor(percent: q.fromOthersPercent, total: t.total)
            let toOwner = jsRound(q.value * q.fromOwnerPercent / 100)
            Ledger.moveRaw(&s, .company(holdingID), -q.price)
            s.companies[hi].addTransaction(week: s.week, amount: -q.price, label: "Bought \(String(format: "%.1f", q.percent))% of \(c.name)")
            if toOwner > 0 {
                Payments.playerReceives(&s, toOwner, label: "Sold shares of \(c.name) to \(h.name)", companyID: companyID)
                s.tax.gains += max(0, toOwner - c.injectedCapital * q.fromOwnerPercent / 100)
            }
            moveShares(&s, ci, to: h, fromOwner: nOwner, fromOthers: nOthers, paid: q.price)
            HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
            let now = tier(forPercent: sharePercent(of: s.companies[ci], holdingID: holdingID))
            s.note("\(h.name) now owns \(String(format: "%.1f", q.heldAfter))% of \(c.name) (\(now.title.lowercased())).", tone: "good", companyID: holdingID)
            return .success(Deal(percent: q.percent, amount: q.price, heldAfter: q.heldAfter, tierAfter: now))
        }
    }

    /// The holding buys `percent` of a rival business.
    public static func buyRival(_ s: inout GameState, holdingID: Int, rivalID: Int, percent: Double, data: GameData) -> Result<Deal, Failure> {
        switch rivalQuote(s, holdingID: holdingID, rivalID: rivalID, percent: percent, data: data) {
        case .failure(let f): return .failure(f)
        case .success(let q):
            guard let hi = s.companyIndex(holdingID), let found = findRival(s, id: rivalID) else { return .failure(.notFound) }
            guard s.companies[hi].cash >= q.price else { return .failure(.notEnoughCash(needed: q.price)) }
            Ledger.moveRaw(&s, .company(holdingID), -q.price)
            s.companies[hi].addTransaction(week: s.week, amount: -q.price, label: "Bought \(String(format: "%.1f", percent))% of \(found.rival.name)")
            var fm = s.companies[hi].value("fm")
            var list = fm["rs"].array
            if let k = list.firstIndex(where: { $0["id"].int == rivalID }) {
                list[k]["pct"] = .number(list[k]["pct"].double + percent); list[k]["paid"] = .number(list[k]["paid"].double + q.price); list[k]["val"] = .number(q.value)
            } else {
                list.append(.object(["k": .string(found.key), "id": .number(Double(rivalID)), "name": .string(found.rival.name), "pct": .number(percent), "paid": .number(q.price), "val": .number(q.value)]))
            }
            fm["rs"] = .array(list)
            s.companies[hi].set("fm", fm)
            HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
            let hname = s.companies[hi].name
            s.note("\(hname) now owns \(String(format: "%.1f", q.heldAfter))% of \(found.rival.name).", tone: "good", companyID: holdingID)
            return .success(Deal(percent: percent, amount: q.price, heldAfter: q.heldAfter, tierAfter: tier(forPercent: q.heldAfter)))
        }
    }

    // MARK: Borrowing to buy

    /// Margin the lender adds for a holding on top of the business-loan margin (a holding has no trade of its own to lend against).
    public static let holdingLoanMargin = 0.005
    /// Debt the holding may carry after the purchase, as a share of what it then owns (cash, funds and stakes).
    public static let maxDebtShare = 0.5

    /// What a loan for the part of a purchase the holding cannot pay from its own cash would cost. `amount` is 0 when no loan is needed;
    /// `reason` is empty when the loan can be had.
    public struct BorrowTerms: Equatable, Sendable {
        public var price: Double
        public var holdingCash: Double
        /// What the holding is short of the price.
        public var shortfall: Double
        /// The loan, sized to the shortfall.
        public var amount: Double
        /// The most the lender will lend the holding now.
        public var maximum: Double
        public var yearlyRate: Double
        public var margin: Double
        public var termMonths: Int
        public var monthlyPayment: Double
        public var totalInterest: Double
        /// The player's own bank (company id) when it funds the loan, else 0 for an outside bank.
        public var lenderCompanyID: Int
        public var lender: String
        public var creditBand: String
        /// The holding's debt before and after the loan, in the group figures.
        public var debtBefore: Double
        public var debtAfter: Double
        public var reason: String
        public var allowed: Bool { reason.isEmpty }
    }

    /// A purchase made with a holding loan: the deal and the loan that paid for the shortfall (`loanID` 0 and `borrowed` 0 when cash was enough).
    public struct LoanDeal: Equatable, Sendable {
        public var deal: Deal
        public var loanID: Int
        public var borrowed: Double
        public var monthlyPayment: Double
        public var yearlyRate: Double
    }

    /// The loan for buying something that costs `price`: rate = policy rate + credit margin + business margin + holding margin, capped so that
    /// debt stays within `maxDebtShare` of what the holding owns once the shares are bought.
    static func loanTerms(_ s: GameState, holdingID: Int, price: Double, termMonths: Int, context: FinanceContext) -> BorrowTerms {
        guard let h = openHolding(s, holdingID) else {
            return BorrowTerms(price: price, holdingCash: 0, shortfall: 0, amount: 0, maximum: 0, yearlyRate: 0, margin: 0, termMonths: termMonths, monthlyPayment: 0, totalInterest: 0,
                               lenderCompanyID: 0, lender: "", creditBand: "", debtBefore: 0, debtAfter: 0, reason: Failure.notAHolding.reason)
        }
        let cash = max(0, h.cash)
        // Round up from the exact gap: rounding to nearest can leave the account a fraction short of the price.
        let amount = max(0, (price - h.cash).rounded(.up))
        let shortfall = amount
        let months = max(6, min(120, termMonths))
        let band = Banking.creditBand(s.credit)
        let debt = CompanyFigures.debts(h, loans: s.loans)
        let owned = cash + max(0, h.value("fm")["assets"].double)
        let room = max(0, (maxDebtShare * owned - debt) / (1 - maxDebtShare))
        let maximum = room.rounded(.down)
        let margin = Banking.creditMargin(s.credit) + 0.01 + holdingLoanMargin + context.lending.marginAdjustment("biz", h, s)
        let rate = s.economy.policyRate + Banking.countryRateShift(companyID: h.id, state: s, context: context) + margin
        let monthly = amount > 0 ? Loans.annuity(principal: amount, yearlyRate: rate, months: Double(months)) : 0
        // The player's own bank funds it when it has the room (a quarter of its capital) and the cash; else an outside bank does.
        var lenderID = 0, lender = "Bank"
        if amount > 0, let b = s.companies.first(where: { b in
            guard b.type == "bank" && b.status == .open else { return false }
            let fm = b.value("fm"), equity = b.cash + fm["book"].double + fm["gb"].double - fm["dep"].double
            return fm["gb"].double + amount <= max(0, equity) * 0.25 && b.cash > amount * 1.2
        }) { lenderID = b.id; lender = b.name }
        var reason = ""
        if amount <= 0 { reason = "" }
        else if band == "E" { reason = "The bank would not lend to you at the moment." }
        else if h.flag("loanFrozen") { reason = "The bank has restricted this company's loans." }
        else if amount > maximum + 0.5 { reason = "The holding can borrow at most \(Int(maximum)) against what it owns. Put more cash into the holding first." }
        return BorrowTerms(price: price, holdingCash: h.cash, shortfall: shortfall, amount: amount, maximum: maximum, yearlyRate: rate, margin: margin, termMonths: months,
                           monthlyPayment: monthly, totalInterest: max(0, monthly * Double(months) - amount), lenderCompanyID: lenderID, lender: lender, creditBand: band,
                           debtBefore: debt, debtAfter: debt + amount, reason: reason)
    }

    /// The loan the holding would need to buy `percent` of one of your companies, with its rate and instalment. Nothing is changed.
    public static func borrowTerms(_ s: GameState, holdingID: Int, companyID: Int, percent: Double, from source: Source = .auto, termMonths: Int = 60,
                                   data: GameData, context: FinanceContext) -> Result<BorrowTerms, Failure> {
        switch quote(s, holdingID: holdingID, companyID: companyID, percent: percent, from: source, data: data) {
        case .failure(let f): return .failure(f)
        case .success(let q): return .success(loanTerms(s, holdingID: holdingID, price: q.price, termMonths: termMonths, context: context))
        }
    }

    /// Pay out the loan into the holding's account as a business loan of the holding: it shows in the holding's debt and is collected with the
    /// monthly instalments like any other loan.
    static func drawLoan(_ s: inout GameState, holdingID: Int, terms t: BorrowTerms) -> Int {
        var loan = Loan(raw: [:])
        loan.id = s.makeID()
        loan.kind = "biz"
        loan.name = "Holding loan"
        loan.balance = t.amount
        loan.originalAmount = t.amount
        loan.margin = t.margin
        loan.termMonths = t.termMonths
        loan.companyID = holdingID
        loan.startWeek = s.week
        loan.isGuaranteed = false
        loan.bankCompanyID = t.lenderCompanyID
        loan.monthlyPayment = t.monthlyPayment
        if t.lenderCompanyID != 0, let bi = s.companyIndex(t.lenderCompanyID) {
            Ledger.moveRaw(&s, .company(t.lenderCompanyID), -t.amount)
            var fm = s.companies[bi].value("fm")
            fm["gb"] = .number(fm["gb"].double + t.amount)
            s.companies[bi].set("fm", fm)
        }
        s.loans.append(loan)
        Payments.companyReceives(&s, companyID: holdingID, amount: t.amount, category: nil, label: "Loan drawn")
        return loan.id
    }

    /// Buy shares, borrowing the shortfall when the holding's cash is not enough. All or nothing: a refusal leaves the state as it was.
    public static func buyWithLoan(_ s: inout GameState, holdingID: Int, companyID: Int, percent: Double, from source: Source = .auto, termMonths: Int = 60,
                                   data: GameData, context: FinanceContext) -> Result<LoanDeal, Failure> {
        let terms: BorrowTerms
        switch borrowTerms(s, holdingID: holdingID, companyID: companyID, percent: percent, from: source, termMonths: termMonths, data: data, context: context) {
        case .failure(let f): return .failure(f)
        case .success(let t): terms = t
        }
        guard terms.allowed else { return .failure(.refused(terms.reason)) }
        var work = s
        var loanID = 0
        if terms.amount > 0 { loanID = drawLoan(&work, holdingID: holdingID, terms: terms) }
        switch buy(&work, holdingID: holdingID, companyID: companyID, percent: percent, from: source, data: data) {
        case .failure(let f): return .failure(f)
        case .success(let deal):
            s = work
            return .success(LoanDeal(deal: deal, loanID: loanID, borrowed: terms.amount, monthlyPayment: terms.monthlyPayment, yearlyRate: terms.yearlyRate))
        }
    }

    // MARK: Selling

    /// How a sale of `percent` splits into shares the holding bought (a line on the cap table, sold first) and shares you moved under it
    /// (your own shares, `Company.holdingID`; you keep one share). Counts of shares, capped at what the holding has.
    static func sellSplit(_ c: Company, holdingID: Int, percent: Double) -> (bought: Int, moved: Int, total: Int) {
        let t = CapTable.table(c)
        let haveBought = line(c, holdingID)?["sh"].int ?? 0
        let haveMoved = c.holdingID == holdingID ? max(0, t.you - 1) : 0
        let want = sharesFor(percent: percent, total: t.total)
        let bought = min(haveBought, want)
        let moved = min(haveMoved, want - bought)
        return (bought, moved, t.total)
    }

    /// What selling `percent` of a stake would bring, and to whom: the market (discounted by the size of the stake) or you (fair value, your money).
    /// Shares the holding bought go first, then shares you moved under it; `boughtPercent` and `movedPercent` give the split.
    public static func sellQuote(_ s: GameState, holdingID: Int, companyID: Int, percent: Double, to buyer: Buyer = .market, data: GameData) -> Result<Quote, Failure> {
        guard openHolding(s, holdingID) != nil else { return .failure(.notAHolding) }
        guard let c = s.company(companyID), sharePercent(of: c, holdingID: holdingID) > 0 else { return .failure(.refused("The holding owns no shares of that company.")) }
        guard percent >= minimumPercent else { return .failure(.refused("Choose at least \(minimumPercent)%.")) }
        let before = sharePercent(of: c, holdingID: holdingID)
        let sp = sellSplit(c, holdingID: holdingID, percent: percent)
        guard sp.bought + sp.moved > 0 else { return .failure(.refused("That is less than one share.")) }
        if percent > before + 0.0001 { return .failure(.refused("The holding owns only \(String(format: "%.1f", before))% of \(c.name).")) }
        if buyer == .owner && sp.moved > 0 { return .failure(.refused("Shares you moved under the holding come back to you with release, not as a purchase.")) }
        if buyer == .owner && c.holdingID != 0 { return .failure(.refused("Your shares in \(c.name) already sit under a holding.")) }
        let v = Valuation.companyValue(c, state: s, trades: data.catalog)
        let pb = percentOf(shares: sp.bought, total: sp.total), pm = percentOf(shares: sp.moved, total: sp.total), p = pb + pm
        let factor = buyer == .owner ? 1 : sellFactor(beforePercent: before)
        let left = before - p
        var q = Quote(percent: p, value: v, price: jsRound(v * p / 100 * factor), fromOwnerPercent: 0, fromOthersPercent: p, priceFactor: factor, heldAfter: left, tierAfter: tier(forPercent: left))
        q.boughtPercent = pb; q.movedPercent = pm
        return .success(q)
    }

    public static func sell(_ s: inout GameState, holdingID: Int, companyID: Int, percent: Double, to buyer: Buyer = .market, data: GameData) -> Result<Deal, Failure> {
        switch sellQuote(s, holdingID: holdingID, companyID: companyID, percent: percent, to: buyer, data: data) {
        case .failure(let f): return .failure(f)
        case .success(let q):
            guard let hi = s.companyIndex(holdingID), let ci = s.companyIndex(companyID) else { return .failure(.notFound) }
            if buyer == .owner && Payments.liquid(s) < q.price { return .failure(.refused("You do not have that much cash.")) }
            CapTable.normalise(&s, ci)
            let sp = sellSplit(s.companies[ci], holdingID: holdingID, percent: percent)
            let t = CapTable.read(s.companies[ci])
            var list = s.companies[ci].value("holders").array
            if sp.bought > 0 {
                guard let k = list.firstIndex(where: { $0["hid"].int == holdingID }) else { return .failure(.notFound) }
                let frac = Double(sp.bought) / Double(max(1, list[k]["sh"].int))
                list[k]["in"] = .number(list[k]["in"].double * (1 - frac))
                list[k]["sh"] = .number(Double(list[k]["sh"].int - sp.bought))
            }
            let n = sp.bought + sp.moved
            var me = t.you - sp.moved
            if buyer == .owner {
                me += n
            } else if let m = list.firstIndex(where: { $0["name"].string == "Market investors" && $0["hid"].int == 0 }) {
                list[m]["sh"] = .number(Double(list[m]["sh"].int + n))
            } else {
                list.append(.object(["name": "Market investors", "sh": .number(Double(n)), "pct": 0, "in": .number(q.price), "sat": 60, "w0": .number(Double(s.week))]))
            }
            list.removeAll { $0["sh"].int <= 0 }
            CapTable.sync(&s.companies[ci], total: t.total, me: me, holders: list)
            let hname = s.companies[hi].name, cname = s.companies[ci].name
            if buyer == .owner {
                Payments.transferFromSavings(&s, need: q.price)
                Payments.playerPays(&s, q.price, label: "Bought shares of \(cname) from \(hname)", companyID: companyID)
            }
            Ledger.moveRaw(&s, .company(holdingID), q.price)
            s.companies[hi].addTransaction(week: s.week, amount: q.price, label: "Sold \(String(format: "%.1f", q.percent))% of \(cname)")
            HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
            s.note("\(hname) sold \(String(format: "%.1f", q.percent))% of \(cname).", tone: "n", companyID: holdingID)
            var d = Deal(percent: q.percent, amount: q.price, heldAfter: q.heldAfter, tierAfter: q.tierAfter)
            d.boughtPercent = q.boughtPercent; d.movedPercent = q.movedPercent
            return .success(d)
        }
    }

    public static func sellRival(_ s: inout GameState, holdingID: Int, rivalID: Int, percent: Double, data: GameData) -> Result<Deal, Failure> {
        guard let hi = s.companyIndex(holdingID), openHolding(s, holdingID) != nil else { return .failure(.notAHolding) }
        revalueRivals(&s, holdingID: holdingID, data: data)
        guard let st = rivalStakes(s.companies[hi]).first(where: { $0.id == rivalID }) else { return .failure(.notFound) }
        guard percent >= minimumPercent, percent <= st.percent + 0.0001 else { return .failure(.refused("The holding owns \(String(format: "%.1f", st.percent))% of \(st.name).")) }
        let amount = jsRound(st.value * percent / 100 * sellFactor(beforePercent: st.percent))
        var fm = s.companies[hi].value("fm")
        var list = fm["rs"].array
        guard let k = list.firstIndex(where: { $0["id"].int == rivalID }) else { return .failure(.notFound) }
        let left = max(0, st.percent - percent)
        if left < 0.0001 { list.remove(at: k) } else {
            list[k]["paid"] = .number(list[k]["paid"].double * left / st.percent); list[k]["pct"] = .number(left)
        }
        fm["rs"] = .array(list)
        s.companies[hi].set("fm", fm)
        Ledger.moveRaw(&s, .company(holdingID), amount)
        s.companies[hi].addTransaction(week: s.week, amount: amount, label: "Sold \(String(format: "%.1f", percent))% of \(st.name)")
        HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
        return .success(Deal(percent: percent, amount: amount, heldAfter: left, tierAfter: tier(forPercent: left)))
    }

    // MARK: Moving your own shares under the holding

    /// Put `percent` of one of your companies (of the whole company, taken from your own shares) under the holding at no price, as a contribution.
    /// 100 moves everything, as `HoldingModel.move` does; less leaves you the rest personally.
    public static func moveShare(_ s: inout GameState, companyID: Int, into holdingID: Int, percent: Double, data: GameData) -> Result<Double, Failure> {
        guard let h = openHolding(s, holdingID) else { return .failure(.notAHolding) }
        guard let ci = s.companyIndex(companyID), eligibleCompany(s.companies[ci], holdingID: holdingID, in: s) else { return .failure(.notFound) }
        if percent >= 99.9999 {
            guard HoldingModel.move(&s, companyID: companyID, into: holdingID, data: data) else { return .failure(.refused("That company cannot be moved under the holding.")) }
            return .success(sharePercent(of: s.companies[ci], holdingID: holdingID))
        }
        guard percent >= minimumPercent else { return .failure(.refused("Choose at least \(minimumPercent)%.")) }
        let c = s.companies[ci]
        if c.holdingID != 0 { return .failure(.refused("Your shares in \(c.name) already sit under a holding.")) }
        let t = CapTable.table(c)
        let n = sharesFor(percent: percent, total: t.total)
        guard n > 0, n <= t.you - 1 else { return .failure(.refused("You hold \(String(format: "%.1f", c.ownership))% of \(c.name) and must keep some of it.")) }
        moveShares(&s, ci, to: h, fromOwner: n, fromOthers: 0, paid: 0)
        HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
        return .success(sharePercent(of: s.companies[ci], holdingID: holdingID))
    }

    /// Take the holding's bought shares of one company back to you at no price (the opposite of `moveShare`).
    public static func releaseStake(_ s: inout GameState, companyID: Int, from holdingID: Int, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), line(s.companies[ci], holdingID) != nil else { return false }
        CapTable.normalise(&s, ci)
        let t = CapTable.read(s.companies[ci])
        var list = s.companies[ci].value("holders").array
        let back = list.filter { $0["hid"].int == holdingID }.reduce(0) { $0 + $1["sh"].int }
        list.removeAll { $0["hid"].int == holdingID }
        CapTable.sync(&s.companies[ci], total: t.total, me: t.you + back, holders: list)
        HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
        return true
    }

    // MARK: Merging into the holding

    public struct MergeTerms: Equatable, Sendable {
        public var allowed: Bool
        /// Why not (empty when allowed).
        public var reason: String
        public var heldPercent: Double
        /// What the rest of the shares cost at fair value, and the part of that which is paid to you personally.
        public var cost: Double
        public var paidToYou: Double
        public var summary: String
    }

    /// Merging buys every other share at fair value and makes the holding the only owner (`holdingID` set, 100%). Allowed with a squeeze-out
    /// right (90% or more), or with control (over 50%) when nobody but you owns the rest.
    public static func mergeTerms(_ s: GameState, holdingID: Int, companyID: Int, data: GameData) -> MergeTerms {
        func no(_ why: String, held: Double = 0) -> MergeTerms { MergeTerms(allowed: false, reason: why, heldPercent: held, cost: 0, paidToYou: 0, summary: why) }
        guard openHolding(s, holdingID) != nil else { return no(Failure.notAHolding.reason) }
        guard let c = s.company(companyID), eligibleCompany(c, holdingID: holdingID, in: s) else { return no(Failure.notFound.reason) }
        let held = sharePercent(of: c, holdingID: holdingID)
        if held <= 0 { return no("The holding owns no shares of \(c.name).") }
        if c.holdingID != 0 && c.holdingID != holdingID { return no("Your shares in \(c.name) sit under another holding.", held: held) }
        if c.value("holders").array.contains(where: { $0["hid"].int != 0 && $0["hid"].int != holdingID }) { return no("Another holding also owns shares of \(c.name). Sell them first.", held: held) }
        let ownerPct = c.holdingID == 0 ? c.ownership : 0
        let others = max(0, 100 - held - ownerPct)
        let squeeze = held >= squeezeOutFrom - 0.0001
        if !squeeze && !(held > controlAbove && others < 0.0001) {
            return no(held > controlAbove ? "Outside owners still hold \(String(format: "%.1f", others))%. Merging needs \(Int(squeezeOutFrom))% or more, or no outside owners." : "Merging needs control (over \(Int(controlAbove))%) and either \(Int(squeezeOutFrom))% or no outside owners.", held: held)
        }
        let v = Valuation.companyValue(c, state: s, trades: data.catalog)
        let cost = jsRound(v * (ownerPct + others) / 100), toYou = jsRound(v * ownerPct / 100)
        return MergeTerms(allowed: true, reason: "", heldPercent: held, cost: cost, paidToYou: toYou,
                          summary: cost > 0 ? "The holding buys the other \(String(format: "%.1f", ownerPct + others))% at fair value for \(Int(cost)) and owns \(c.name) alone." : "\(c.name) is already wholly owned by the holding.")
    }

    public static func merge(_ s: inout GameState, holdingID: Int, companyID: Int, data: GameData) -> Result<Double, Failure> {
        let t = mergeTerms(s, holdingID: holdingID, companyID: companyID, data: data)
        guard t.allowed, let hi = s.companyIndex(holdingID), let ci = s.companyIndex(companyID) else { return .failure(.refused(t.reason)) }
        guard s.companies[hi].cash >= t.cost else { return .failure(.notEnoughCash(needed: t.cost)) }
        let c = s.companies[ci], hname = s.companies[hi].name
        CapTable.normalise(&s, ci)
        let tab = CapTable.read(s.companies[ci])
        if t.cost > 0 {
            Ledger.moveRaw(&s, .company(holdingID), -t.cost)
            s.companies[hi].addTransaction(week: s.week, amount: -t.cost, label: "Bought out the other owners of \(c.name)")
        }
        if t.paidToYou > 0 {
            let ownerPct = c.holdingID == 0 ? c.ownership : 0
            Payments.playerReceives(&s, t.paidToYou, label: "Sold your shares of \(c.name) to \(hname)", companyID: companyID)
            s.tax.gains += max(0, t.paidToYou - c.injectedCapital * ownerPct / 100)
        }
        CapTable.sync(&s.companies[ci], total: tab.total, me: tab.total, holders: [])
        s.companies[ci].holdingID = holdingID
        HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
        s.note("\(c.name) is now wholly owned by \(hname).", tone: "good", companyID: holdingID)
        return .success(t.cost)
    }

    // MARK: Division

    /// A wholly owned company can stop being a legal entity and become a division of the holding, or of another company under the same holding.
    /// Saved on the company: `div` = id of the company or holding it is a division of.
    public static func isDivision(_ c: Company) -> Bool { !c.value("div").isNull }
    public static func divisionHostID(_ c: Company) -> Int? { isDivision(c) ? c.value("div").int : nil }
    /// The live divisions of a holding or company.
    public static func divisions(of hostID: Int, in s: GameState) -> [Company] {
        s.companies.filter { $0.status.isLive && divisionHostID($0) == hostID }
    }

    public struct DivisionTerms: Equatable, Sendable {
        public var allowed: Bool
        /// Why not (empty when allowed).
        public var reason: String
        public var companyID: Int
        public var companyName: String
        public var hostID: Int
        public var hostName: String
        public var hostIsHolding: Bool
        /// What the company is worth, its cash and its people: all of it stays, so net worth does not change.
        public var value: Double
        public var cash: Double
        public var staff: Int
        public var summary: String
    }

    /// The terms for turning `companyID` into a division of `hostID` (the holding itself when nil). The company must be wholly owned by the
    /// holding with no other owner (merge it first at under 100%). The host must be the holding, or a company the holding wholly owns in the same country.
    public static func divisionTerms(_ s: GameState, holdingID: Int, companyID: Int, hostID: Int? = nil, data: GameData) -> DivisionTerms {
        let hid = hostID ?? holdingID
        func no(_ why: String, _ c: Company? = nil, _ host: Company? = nil) -> DivisionTerms {
            DivisionTerms(allowed: false, reason: why, companyID: companyID, companyName: c?.name ?? "", hostID: hid, hostName: host?.name ?? "", hostIsHolding: host?.type == "hold",
                          value: 0, cash: 0, staff: 0, summary: why)
        }
        guard let h = openHolding(s, holdingID) else { return no(Failure.notAHolding.reason) }
        guard let c = s.company(companyID), eligibleCompany(c, holdingID: holdingID, in: s) else { return no(Failure.notFound.reason) }
        guard let host = s.company(hid), host.status.isLive, host.id != c.id else { return no("That company is not available as the host.", c) }
        if host.type != "hold" {
            guard host.form == .limited, !isDivision(host), host.holdingID == holdingID, !s.isBranch(host) else { return no("\(host.name) must be a company the holding owns outright, and not itself a division.", c, host) }
        } else if host.id != h.id {
            return no("A division can only join this holding or one of its companies.", c, host)
        }
        guard c.holdingID == holdingID, c.ownership >= 99.9999, c.value("holders").array.isEmpty else {
            return no(sharePercent(of: c, holdingID: holdingID) >= 99.9999 ? "Merge \(c.name) into the holding first, so that nobody else owns shares." : "The holding must own all of \(c.name) first.", c, host)
        }
        guard c.countryCode == host.countryCode else { return no("A division must be in the same country as the company it joins.", c, host) }
        if !divisions(of: c.id, in: s).isEmpty { return no("\(c.name) has divisions of its own.", c, host) }
        if SaleListings.isListed(s, companyID: c.id) { return no("\(c.name) is on the market: withdraw that listing first.", c, host) }
        let v = Valuation.companyValue(c, state: s, trades: data.catalog)
        return DivisionTerms(allowed: true, reason: "", companyID: c.id, companyName: c.name, hostID: host.id, hostName: host.name, hostIsHolding: host.type == "hold", value: v, cash: c.cash,
                             staff: c.staff.count + (c.managerID != nil ? 1 : 0),
                             summary: "\(c.name) keeps its trade, staff, items and cash and becomes a division of \(host.name). It is no longer a separate company, so it shares one tax result with the group. Its value stays in the group.")
    }

    /// Make the company a division. Nothing is paid or moved: trade, staff, items, stock and cash stay where they are, the company's value stays in
    /// the holding's, and the company drops out of stake deals and the holding's share dealings.
    public static func makeDivision(_ s: inout GameState, holdingID: Int, companyID: Int, hostID: Int? = nil, data: GameData) -> Result<DivisionTerms, Failure> {
        let t = divisionTerms(s, holdingID: holdingID, companyID: companyID, hostID: hostID, data: data)
        guard t.allowed, let ci = s.companyIndex(companyID) else { return .failure(.refused(t.reason)) }
        s.companies[ci].set("div", .number(Double(t.hostID)))
        HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
        s.note("\(t.companyName) is now a division of \(t.hostName).", tone: "good", companyID: t.hostID)
        return .success(t)
    }

    // MARK: Board

    public struct SeatStatus: Equatable, Sendable {
        public var hasSeat: Bool
        public var canTake: Bool
        /// Why the seat cannot be taken (or is not needed).
        public var reason: String
        /// What the holding votes with at this board, in percent of the shares.
        public var votePercent: Double
    }

    public static func seatStatus(_ s: GameState, holdingID: Int, companyID: Int) -> SeatStatus {
        guard openHolding(s, holdingID) != nil, let c = s.company(companyID) else { return SeatStatus(hasSeat: false, canTake: false, reason: Failure.notFound.reason, votePercent: 0) }
        let pct = sharePercent(of: c, holdingID: holdingID)
        let t = tier(forPercent: pct)
        if c.holdingID == holdingID && line(c, holdingID) == nil { return SeatStatus(hasSeat: true, canTake: false, reason: "The holding owns the company outright and runs its board.", votePercent: pct) }
        guard let l = line(c, holdingID) else { return SeatStatus(hasSeat: false, canTake: false, reason: "The holding owns no shares of \(c.name).", votePercent: 0) }
        if t == .control || t == .squeezeOut || t == .whole { return SeatStatus(hasSeat: true, canTake: false, reason: "With control the holding always has the seat.", votePercent: l["pct"].double) }
        if l["seat"].bool { return SeatStatus(hasSeat: true, canTake: false, reason: "", votePercent: l["pct"].double) }
        return SeatStatus(hasSeat: false, canTake: t.canSitOnBoard, reason: t.canSitOnBoard ? "" : "A stake under \(Int(passiveBelow))% is passive: no board seat.", votePercent: 0)
    }

    public static func takeSeat(_ s: inout GameState, holdingID: Int, companyID: Int) -> Result<Void, Failure> {
        let st = seatStatus(s, holdingID: holdingID, companyID: companyID)
        guard st.canTake, let ci = s.companyIndex(companyID) else { return .failure(.refused(st.reason.isEmpty ? "The holding already has the seat." : st.reason)) }
        var list = s.companies[ci].value("holders").array
        guard let k = list.firstIndex(where: { $0["hid"].int == holdingID }) else { return .failure(.notFound) }
        list[k]["seat"] = true
        s.companies[ci].set("holders", .array(list))
        let hname = s.company(holdingID)?.name ?? "The holding", cname = s.companies[ci].name
        s.note("\(hname) now has a seat on the board of \(cname).", tone: "good", companyID: companyID)
        return .success(())
    }

    public static func leaveSeat(_ s: inout GameState, holdingID: Int, companyID: Int) -> Result<Void, Failure> {
        guard let ci = s.companyIndex(companyID), var list = Optional(s.companies[ci].value("holders").array),
              let k = list.firstIndex(where: { $0["hid"].int == holdingID && $0["seat"].bool }) else { return .failure(.refused("The holding has no chosen seat there.")) }
        list[k]["seat"] = false
        s.companies[ci].set("holders", .array(list))
        return .success(())
    }

    // MARK: Ends of a holding's life

    /// When a holding closes, fails or is sold its bought shares go back to you.
    public static func releaseLines(_ s: inout GameState, holdingID: Int) {
        for ci in s.companies.indices where s.companies[ci].value("holders").array.contains(where: { $0["hid"].int == holdingID }) {
            CapTable.normalise(&s, ci)
            let t = CapTable.read(s.companies[ci])
            var list = s.companies[ci].value("holders").array
            let back = list.filter { $0["hid"].int == holdingID }.reduce(0) { $0 + $1["sh"].int }
            list.removeAll { $0["hid"].int == holdingID }
            CapTable.sync(&s.companies[ci], total: t.total, me: t.you + back, holders: list)
        }
    }

    /// A company that is sold pays its price to every holding in proportion to the shares it holds as a stake (your own share is paid by the sale).
    public static func settleSale(_ s: inout GameState, company c: Company, price: Double) {
        for l in c.value("holders").array where l["hid"].int != 0 {
            let amt = jsRound(price * l["pct"].double / 100)
            guard amt > 0, let hi = s.companyIndex(l["hid"].int), s.companies[hi].status.isLive else { continue }
            Ledger.moveRaw(&s, .company(l["hid"].int), amt)
            s.companies[hi].addTransaction(week: s.week, amount: amt, label: "Sale of \(c.name)")
        }
    }

}
