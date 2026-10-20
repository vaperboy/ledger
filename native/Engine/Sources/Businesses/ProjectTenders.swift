import Foundation
import GameCore
import Countries
import Finance

/// Tenders for building and design work: a market of its own. Original: features/sales/public_tenders.js ("Round 56").
///
/// A buyer (the municipality, the county, the road authority) puts work out to tender. A tender has a scope (one big job), how the
/// bids are scored (price against quality), requirements (a minimum rating, a year in business), a deadline and an award date.
/// The company bids a price against its list price and a quality commitment, and pays for writing the bid whether it wins or not.
/// Scoring: price points = the lowest price / your price; quality points from the company's rating, reputation, earlier public work
/// and the commitment; the buyer's weights decide; the rivals' bids are drawn around the market price from a seed, so the result does
/// not depend on the order of play. A won tender becomes a job on the order book. A manager bids at list price when the company has
/// room and the bid is within its limits (switch it off to be asked).
///
/// Only the trades below can win tenders here. The original also lets services, shops and carriers tender for volume contracts;
/// those need the business-customer contract model (not ported), so they are not offered.
public enum ProjectTenders {
    public struct Offer { public let title: String; public let buyer: String; public let local: Bool }

    /// What each trade can win: title, kind of buyer, whether the work is local. Original: `W`.
    public static let catalog: [String: [Offer]] = [
        "construction": [Offer(title: "A school extension", buyer: "muni", local: true), Offer(title: "A new fire station", buyer: "muni", local: true),
                         Offer(title: "Upgrading a county road", buyer: "road", local: false)],
        "electrician": [Offer(title: "Electrical service for municipal buildings", buyer: "muni", local: true),
                        Offer(title: "Charging points for the county fleet", buyer: "county", local: false)],
        "plumber": [Offer(title: "Plumbing service for municipal housing", buyer: "muni", local: true), Offer(title: "Bathrooms in a nursing home", buyer: "muni", local: true)],
        "engcons": [Offer(title: "Design of a sports hall", buyer: "muni", local: true), Offer(title: "A bridge study", buyer: "road", local: false)],
        "event": [Offer(title: "The county’s annual conference", buyer: "county", local: false)],
    ]

    public struct Bid: JSONRecord {
        public var raw: [String: JSONValue]
        public init(raw: [String: JSONValue]) { self.raw = raw }
        public var companyID: Int { int("co") }
        /// Price as a share of the list price.
        public var priceFactor: Double { num("pf", 1) }
        public var higherQuality: Bool { flag("q") }
    }

    public struct Tender: JSONRecord, Identifiable {
        public var raw: [String: JSONValue]
        public init(raw: [String: JSONValue]) { self.raw = raw }
        public var id: Int { int("id") }
        public var countryCode: String { str("cc") }
        public var cityID: String? { value("city").isNull ? nil : str("city") }
        public var trade: String { str("type") }
        public var title: String { str("title") }
        public var buyerKind: String { str("bk") }
        public var buyer: String { str("buyer") }
        /// Weight of price in the score; 1 = price alone.
        public var priceWeight: Double { num("wP", 1) }
        public var minimumRating: Double { num("minR") }
        public var minimumYears: Double { num("minY") }
        public var openedWeek: Int { int("w0") }
        public var closesWeek: Int { int("due") }
        public var awardWeek: Int { int("award") }
        public var rivals: Int { int("rivals") }
        public var worth: Double { num("val") }
        /// What writing the bid costs.
        public var bidCost: Double { num("cost") }
        /// nil = open; "won", "lost" or "gone" (nobody bid).
        public var outcome: String? { value("st").isNull ? nil : str("st") }
        public var winnerCompanyID: Int { int("win") }
        public var isPublicBuyer: Bool { buyerKind != "priv" }
        public var bids: [Bid] { get { records("bids") } set { setRecords("bids", newValue) } }
        public func bid(of companyID: Int) -> Bid? { bids.first { $0.companyID == companyID } }
    }

    public struct Qualification: Equatable { public var ok: Bool; public var reason: String? }

    // MARK: State

    struct Store {
        var list: [Tender]
        var history: [String: JSONValue]
        var auto: [String: JSONValue]
    }

    static func load(_ s: GameState) -> Store {
        let t = s.rest["tnd56"] ?? .null
        return Store(list: t["L"].array.map { Tender(raw: $0.object) }, history: t["hist"].object, auto: t["auto"].object)
    }
    static func save(_ s: inout GameState, _ st: Store) {
        s.rest["tnd56"] = .object(["L": .array(st.list.map { .object($0.raw) }), "hist": .object(st.history), "auto": .object(st.auto)])
    }

    public static func isEligible(_ co: Company) -> Bool { co.status == .open && catalog[co.type] != nil }

    /// Tenders still open for bids that suit this company (its trade, country and, for local ones, city). Original: `open`.
    public static func openTenders(_ s: GameState, for co: Company) -> [Tender] {
        load(s).list.filter { $0.outcome == nil && s.week < $0.closesWeek && $0.trade == co.type && $0.countryCode == co.countryCode && ($0.cityID == nil || $0.cityID == co.cityID) }
    }
    /// Every tender this company bid for, newest first.
    public static func tenders(_ s: GameState, bidBy co: Company) -> [Tender] {
        load(s).list.filter { $0.bid(of: co.id) != nil }
    }
    /// Does the manager bid by himself? Original: `auto`.
    public static func managerBids(_ s: GameState, companyID: Int) -> Bool { load(s).auto[String(companyID)]?.double != 0 }
    public static func setManagerBids(_ s: inout GameState, companyID: Int, on: Bool) {
        var st = load(s); st.auto[String(companyID)] = on ? 1 : 0; save(&s, st)
    }

    // MARK: Requirements and scoring

    public static func qualification(_ t: Tender, _ co: Company, week: Int) -> Qualification {
        let years = Double(week - co.foundedWeek) / 52
        let r = co.int("rvN") >= 5 ? Pricing.rating(co) : 0
        if t.minimumYears > 0 && years < t.minimumYears { return Qualification(ok: false, reason: "Needs a year in business") }
        if t.minimumRating > 0 && r < t.minimumRating { return Qualification(ok: false, reason: String(format: "Needs %.1f stars", t.minimumRating)) }
        return Qualification(ok: true, reason: nil)
    }

    /// Quality points: rating, reputation, how the company delivered for public buyers before, and what it promises. Original: `qScore`.
    public static func qualityScore(_ co: Company, higher q: Bool, history: [String: JSONValue]) -> Double {
        let h = history[String(co.id)] ?? .object([:])
        let r = co.int("rvN") >= 5 ? (Pricing.rating(co) - 2.5) / 2.5 : 0.35
        return clamp(0.15 + r * 0.4 + (co.reputation - 50) / 200 + min(0.15, h["ok"].double * 0.05) - h["bad"].double * 0.12 + (q ? 0.12 : 0), 0.05, 1)
    }

    // MARK: Making tenders

    static func buyerName(_ kind: String, _ co: Company, _ w: World) -> String {
        switch kind {
        case "muni": return (w.city(co)?.name ?? "The") + " municipality"
        case "county": return "The county council"
        case "health": return "The regional health trust"
        case "road": return "The road authority"
        case "uni": return "The university"
        case "state": return "A state agency"
        default: return "A large buyer"
        }
    }

    /// A new tender for what this company's trade can win. Original: `make`.
    static func make(_ s: inout GameState, _ co: Company, data: GameData, home: Currency) -> Tender {
        let w = World(state: s, data: data)
        let bd = data.catalog[co.type]!
        let list = catalog[co.type]!
        let offer = list[Int((s.random.next() * Double(list.count)).rounded(.down))]
        let priceOnly = s.random.next() < 0.46
        var t = Tender(raw: [:])
        t.set("id", s.makeID())
        t.set("cc", co.countryCode); t.set("city", offer.local ? .string(co.cityID) : .null); t.set("type", co.type)
        t.set("title", offer.title); t.set("bk", offer.buyer); t.set("buyer", buyerName(offer.buyer, co, w)); t.set("kind", "job")
        t.set("wP", priceOnly ? 1 : jsRound((0.4 + s.random.next() * 0.3) * 20) / 20)
        t.set("minR", s.random.next() < 0.4 ? 3.5 + jsRound(s.random.next() * 6) / 10 : 0)
        t.set("minY", s.random.next() < 0.5 ? 1 : 0)
        t.set("w0", s.week)
        t.set("due", s.week + 3 + Int((s.random.next() * 4).rounded(.down)))
        t.set("rivals", s.random.next() < 0.28 ? 0 : 1 + Int((s.random.next() * 5).rounded(.down)))
        t.set("bids", .array([]))
        t.set("award", t.closesWeek + 2 + Int((s.random.next() * 3).rounded(.down)))
        let val = home.roundedStep(bd.ticket * Pricing.ticketMultiplier(co, bd, w) * (2 + s.random.next() * 4), about: 1000)
        t.set("val", val); t.set("yrs", 0); t.set("ext", 0)
        t.set("cost", home.roundedStep(max(w.currency(co).scaledPrice(4000), val * 0.004), about: 500))
        return t
    }

    // MARK: Bidding

    public enum BidResult: Equatable { case sent, notEnoughCash, closed, notQualified(String) }

    /// Write and send a bid (a second bid replaces the first; writing it again costs again). Original: `bid`.
    @discardableResult
    public static func placeBid(_ s: inout GameState, companyID: Int, tenderID: Int, priceFactor: Double, higherQuality: Bool, data: GameData) -> BidResult {
        var st = load(s)
        guard let ti = st.list.firstIndex(where: { $0.id == tenderID }), let co = s.company(companyID) else { return .closed }
        let t = st.list[ti]
        guard t.outcome == nil, s.week < t.closesWeek, isEligible(co), t.trade == co.type else { return .closed }
        let q = qualification(t, co, week: s.week)
        if !q.ok { return .notQualified(q.reason ?? "") }
        if co.cash < t.bidCost { return .notEnoughCash }
        Payments.companyPays(&s, companyID: companyID, amount: t.bidCost, category: "oth", label: "Tender bid: \(t.title)")
        var bids = t.bids.filter { $0.companyID != companyID }
        bids.append(Bid(raw: ["co": .number(Double(companyID)), "pf": .number(priceFactor), "q": .bool(higherQuality), "w": .number(Double(s.week))]))
        st.list[ti].bids = bids
        save(&s, st)
        return .sent
    }

    /// Take the bid back (until the deadline); the writing cost is gone. Original: `tnd56re`.
    public static func withdrawBid(_ s: inout GameState, companyID: Int, tenderID: Int) {
        var st = load(s)
        guard let ti = st.list.firstIndex(where: { $0.id == tenderID }), st.list[ti].outcome == nil, s.week < st.list[ti].closesWeek else { return }
        st.list[ti].bids = st.list[ti].bids.filter { $0.companyID != companyID }
        save(&s, st)
    }

    // MARK: The week

    /// New tenders, managers' bids and the awards. Original: week.after 'tenders: new ones, awards, contracts' (prio 57).
    public static func weekly(_ s: inout GameState, data: GameData, context: FinanceContext) {
        guard s.companies.contains(where: { isEligible($0) }) || !load(s).list.isEmpty else { return }
        var st = load(s)
        let home = context.homeCurrency(s)
        // Each trade you run sees about one relevant tender every two months in its country.
        var seen = Set<String>()
        for co in s.companies where isEligible(co) {
            let local = catalog[co.type]?.contains { $0.local } ?? false
            let k = "\(co.countryCode):\(co.type):\(local ? co.cityID : "")"
            if seen.contains(k) { continue }
            seen.insert(k)
            if s.random.next() < 1.0 / 9, st.list.filter({ $0.trade == co.type && $0.countryCode == co.countryCode && $0.outcome == nil }).count < 3 {
                st.list.append(make(&s, co, data: data, home: home))
            }
        }
        // Managers bid at list price when the company has the money and meets the requirements.
        for ti in st.list.indices where st.list[ti].outcome == nil && s.week < st.list[ti].closesWeek {
            let t = st.list[ti]
            for c in s.companies where isEligible(c) && c.type == t.trade && c.countryCode == t.countryCode && (t.cityID == nil || c.cityID == t.cityID)
                && c.managerID != nil && s.people[c.managerID!] != nil && st.auto[String(c.id)]?.double != 0 {
                if t.bid(of: c.id) != nil || !qualification(t, c, week: s.week).ok { continue }
                if c.cash < t.bidCost * 3 { continue }
                Payments.companyPays(&s, companyID: c.id, amount: t.bidCost, category: "oth", label: "Tender bid: \(t.title)")
                var bids = st.list[ti].bids
                bids.append(Bid(raw: ["co": .number(Double(c.id)), "pf": 1, "q": false, "w": .number(Double(s.week))]))
                st.list[ti].bids = bids
            }
        }
        for ti in st.list.indices where st.list[ti].outcome == nil && s.week >= st.list[ti].awardWeek { award(&s, &st, ti, data: data) }
        st.list = st.list.filter { $0.outcome == nil || s.week - $0.awardWeek < 26 }
        save(&s, st)
    }

    /// The award. The rivals' bids come from a seed made of the tender, so the result is the same whatever else happened.
    /// Original: `award`.
    static func award(_ s: inout GameState, _ st: inout Store, _ ti: Int, data: GameData) {
        let t = st.list[ti]
        var R = HashedRandom("\(s.seed):tnd:\(t.id)")
        struct Entry { var pf: Double; var qv: Double; var me: Int? = nil; var higher = false; var score = 0.0 }
        var all: [Entry] = []
        for _ in 0..<t.rivals {
            let pf = clamp(0.95 + (R.next() - 0.5) * 0.18, 0.78, 1.15)
            let q = clamp(0.55 + (R.next() - 0.5) * 0.4, 0.15, 0.95)
            all.append(Entry(pf: pf, qv: q))
        }
        var mine: [Entry] = []
        for b in t.bids {
            guard let co = s.company(b.companyID), co.status == .open else { continue }
            mine.append(Entry(pf: b.priceFactor, qv: qualityScore(co, higher: b.higherQuality, history: st.history), me: co.id, higher: b.higherQuality))
        }
        if mine.isEmpty { st.list[ti].set("st", "gone"); return }
        all += mine
        let low = all.map { $0.pf }.min() ?? 1
        for k in all.indices { all[k].score = t.priceWeight * (low / all[k].pf) + (1 - t.priceWeight) * all[k].qv }
        // A stable ordering: best score first, the earlier entry wins a tie.
        let order = all.indices.sorted { (all[$0].score, -$0) > (all[$1].score, -$1) }
        let win = all[order[0]]
        st.list[ti].set("st", win.me != nil ? "won" : "lost")
        st.list[ti].set("win", win.me ?? 0)
        let w = World(state: s, data: data)
        for (idx, e) in all.enumerated() {
            guard let cid = e.me, let co = s.company(cid) else { continue }
            let place = order.firstIndex(of: idx)! + 1
            let pts = Int(jsRound(e.score * 100))
            if idx == order[0] {
                startJob(&s, t, co, priceFactor: e.pf, data: data)
                s.addMessage(from: t.buyer, title: "Award: \(t.title)",
                             body: "\(co.name) won with \(pts) points out of 100 (\(all.count) \(all.count == 1 ? "bid" : "bids")). Work starts now.",
                             companyID: cid, tone: "good", status: "done")
            } else {
                let weights = t.priceWeight >= 1 ? ", on price alone." : ". Price counted \(Int(jsRound(t.priceWeight * 100)))%, quality \(Int(jsRound((1 - t.priceWeight) * 100)))%."
                s.addMessage(from: t.buyer, title: "Not awarded: \(t.title)",
                             body: "\(co.name) came \(ordinal(place)) of \(all.count) with \(pts) points. The winner had \(Int(jsRound(win.score * 100)))\(weights)",
                             companyID: cid, tone: "bad", status: "done")
            }
            _ = w
        }
    }

    static func ordinal(_ n: Int) -> String { "\(n)" + (n == 1 ? "st" : n == 2 ? "nd" : n == 3 ? "rd" : "th") }

    /// The won tender becomes a job on the order book. Original: `start`.
    static func startJob(_ s: inout GameState, _ t: Tender, _ co: Company, priceFactor pf: Double, data: GameData) {
        guard let i = s.companyIndex(co.id), let bd = data.catalog[co.type] else { return }
        let tw = bd.traits
        var fm = s.companies[i].value("fm")
        var jobs = fm["jobs"].array
        let wks = max(2, jsRound((tw["wks"] ?? 6) * (1.2 + s.random.next() * 0.6)))
        let cf = max(0.05, (((tw["mat"] ?? 0.5) + (tw["sub"] ?? 0)) * (1 + s.random.gauss() * (tw["over"] ?? 0.1))) / pf)
        let job: [String: JSONValue] = ["id": .number(Double(s.makeID())), "v": .number(jsRound(t.worth * pf)), "wks": .number(wks), "p": 0, "cf": .number(cf),
                                       "delay": 0, "w0": .number(Double(s.week)), "client": .string(t.buyer), "pub": .number(t.isPublicBuyer ? 1 : 0)]
        jobs.append(.object(job))
        fm["jobs"] = .array(jobs)
        s.companies[i].set("fm", fm)
    }
}
