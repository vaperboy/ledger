import Foundation
import GameCore
import Countries
import Finance

/// Rival stories: the named rivals of your markets (`Rivals`) told slowly. Each week a rival now and then makes one small move (opens a
/// branch, cuts or raises prices, starts a campaign, loses staff, has a bad quarter ...), drawn from the seed so the same game tells the same
/// story. Every move really changes that rival's record (size, price, marketing, fortune), which `Rivals` already turns into your demand.
/// Now and then a move leads to a decision of yours: a struggling rival for sale, or a price cut by a bigger rival.
/// State `rest["rvs"]`: `tl` the timeline, newest first { w, rid, rn, co, t, e } (e: +1 good for you, -1 bad for you); `last` the week of the
/// last decision offered; `br` { "<rivalID>": branches opened }.
public enum RivalStories {
    public static let buyAction = "rvsbuy", warAction = "rvswar"
    public static func handlesAnswer(_ action: String) -> Bool { action == buyAction || action == warAction }

    /// The chance in a week that a given rival does something worth telling (about one move a rival every five months).
    public static let moveChance = 0.045
    /// Weeks between two decisions of this kind, so they stay rare.
    public static let decisionGap = 20
    /// A rival this far down is "in trouble" and may be offered for sale; its price is this share of what it is worth.
    public static let troubleFortune = 0.35, distressedPriceShare = 0.6
    /// A price-war answer: the discount matched for this many weeks, and the demand lost by ignoring a cut.
    public static let matchPercent = 10, matchWeeks = 2, ignoreLoss = 0.03, advertShare = 0.03
    static let timelineKept = 60

    public struct Move: Identifiable, Equatable, Sendable {
        public var id: String { "\(week)-\(rivalID)-\(text)" }
        public var week: Int, rivalID: Int, text: String
        /// +1 good for you, -1 bad for you.
        public var effect: Int
    }

    public struct Card: Identifiable, Equatable, Sendable {
        public var id: Int
        public var name: String, owner: String, trade: String, city: String
        /// How it stands against you, in words ("A little ahead of you").
        public var standing: String
        /// How it is doing by itself ("Steady", "Under pressure").
        public var health: String
        public var mood: String
        /// What the recent moves mean for you: 1 they favour you (green up), -1 they work against you (red down), 0 nothing clear.
        public var trend: Int
        public var forSale: Bool
        public var moves: [Move]
    }

    // MARK: Reading

    /// The timeline of one company's market, newest first.
    public static func timeline(_ s: GameState, companyID: Int? = nil, rivalID: Int? = nil, limit: Int = 12) -> [Move] {
        (s.rest["rvs"]?["tl"].array ?? []).filter {
            (companyID == nil || $0["co"].int == companyID) && (rivalID == nil || $0["rid"].int == rivalID)
        }.prefix(limit).map { Move(week: $0["w"].int, rivalID: $0["rid"].int, text: $0["rn"].string + " " + $0["t"].string, effect: $0["e"].int) }
    }

    /// Cards for the rivals of one company's market, strongest first.
    public static func cards(_ s: GameState, companyID: Int, data: GameData) -> [Card] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return [] }
        let w = World(state: s, data: data)
        let city = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? ""
        return Rivals.rivals(s, for: co).map { r in
            let moves = timeline(s, companyID: companyID, rivalID: r.id, limit: 5)
            let net = moves.filter { s.week - $0.week <= 26 }.reduce(0) { $0 + $1.effect }
            return Card(id: r.id, name: r.name, owner: r.owner, trade: bd.name, city: city, standing: standing(s, co, r, bd, w), health: health(r.fortune),
                        mood: Rivals.mood(r).word, trend: net > 0 ? 1 : net < 0 ? -1 : 0, forSale: r.forSale || r.fortune < troubleFortune, moves: moves)
        }.sorted { (a: Card, b: Card) -> Bool in a.id < b.id }
    }

    public static func health(_ fortune: Double) -> String {
        fortune > 1.5 ? "Thriving" : fortune > 0.8 ? "Steady" : fortune > troubleFortune ? "Under pressure" : "Struggling"
    }

    /// In words: how big this rival is against you, from yearly takings.
    static func standing(_ s: GameState, _ co: Company, _ r: Rivals.Rival, _ bd: Trade, _ w: World) -> String {
        let theirs = Rivals.yearlyRevenue(bd, r, w, co)
        let months = co.monthlyHistory.suffix(12)
        let yours = months.count >= 3 ? months.reduce(0.0) { $0 + $1.revenue } / Double(months.count) * 12 : Engagement.lastWeekRevenue(co) * 52
        guard yours > 0 else { return "Too early to compare" }
        let ratio = theirs / yours
        return ratio > 1.5 ? "Well ahead of you" : ratio > 1.1 ? "A little ahead of you" : ratio > 0.9 ? "About level with you"
            : ratio > 0.6 ? "A little behind you" : "Well behind you"
    }

    // MARK: Every week

    public static func weekly(_ s: inout GameState, data: GameData) {
        guard Unlocks.isOpen(s, "rivals") else { return }
        var done = Set<String>()
        for co in s.companies where co.status == .open && co.type != "hold" && co.type != "club" {
            let k = Rivals.key(co)
            guard done.insert(k).inserted else { continue }
            for r in Rivals.rivals(s, key: k) { move(&s, co: co, rival: r, key: k, data: data) }
        }
        offerSale(&s, data: data)
    }

    /// The rival's own price relative to the market (1 when an old record has none yet).
    static func priceOf(_ r: JSONValue) -> Double { r["pm16"].isNull ? 1 : r["pm16"].double }

    enum Kind: String, CaseIterable { case branch, cut, raise, campaign, staff, award, weak, recover }

    static func weights(_ r: Rivals.Rival) -> [(Kind, Double)] {
        let f = r.fortune
        return [
            (.branch, (r.strategy == "expander" ? 3 : 1) * (f > 1.1 && r.size < 1.9 ? 1 : 0)),
            (.cut, (r.strategy == "cheap" ? 3 : 1) * (r.priceFactor > 0.78 ? 1 : 0)),
            (.raise, (r.strategy == "premium" ? 3 : 1) * (r.priceFactor < 1.4 ? 1 : 0)),
            (.campaign, r.marketing ? 0 : 2),
            (.staff, r.size > 0.5 ? 1.5 : 0),
            (.award, (r.strategy == "quality" ? 3 : 1) * (f < 2.4 ? 1 : 0)),
            (.weak, f > 0.3 ? 1.5 : 0),
            (.recover, f < 0.9 ? 3 : 0),
        ]
    }

    static func move(_ s: inout GameState, co: Company, rival r: Rivals.Rival, key k: String, data: GameData) {
        var h = HashedRandom("\(s.seed):rvs:\(s.week):\(r.id)")
        guard h.next() < moveChance else { return }
        let table = weights(r), total = table.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return }
        var pick = h.next() * total
        var kind = table[0].0
        for (kd, wt) in table { if pick < wt { kind = kd; break }; pick -= wt }
        let week = s.week
        var text = "", effect = 0
        switch kind {
        case .branch:
            let country = data.countries[co.countryCode] ?? data.countries.countries[0]
            let others = country.cities.filter { $0.id != co.cityID }
            let town = others.isEmpty ? "a nearby town" : others[Int(h.next() * Double(others.count)) % others.count].name
            let n = (s.rest["rvs"]?["br"]["\(r.id)"].int ?? 0) + 1
            var st = s.rest["rvs"] ?? .object([:]); st["br"]["\(r.id)"] = .number(Double(n)); s.rest["rvs"] = st
            text = n == 1 ? "opened a second branch in \(town)." : "opened another site in \(town)."; effect = -1
            Rivals.mutate(&s, key: k, id: r.id) { $0["size"] = .number(min(1.9, jsRound(($0["size"].double + 0.08) * 100) / 100)); $0["fort"] = .number(Rivals.fortuneOf($0) - 0.05) }
        case .cut:
            text = "cut its prices by about 4%."; effect = -1
            Rivals.mutate(&s, key: k, id: r.id) { $0["pm16"] = .number(clamp(jsRound(priceOf($0) * 0.96 * 1000) / 1000, 0.7, 1.6)) }
        case .raise:
            text = "raised its prices by about 4%."; effect = 1
            Rivals.mutate(&s, key: k, id: r.id) { $0["pm16"] = .number(clamp(jsRound(priceOf($0) * 1.04 * 1000) / 1000, 0.7, 1.6)) }
        case .campaign:
            text = "started a local advertising push."; effect = -1
            Rivals.mutate(&s, key: k, id: r.id) { $0["mkt16"] = .number(Double(week + 4)) }
        case .staff:
            text = "lost two of its senior people to a competitor."; effect = 1
            Rivals.mutate(&s, key: k, id: r.id) { $0["size"] = .number(max(0.4, jsRound(($0["size"].double - 0.05) * 100) / 100)) }
        case .award:
            text = "won a local service award."; effect = -1
            Rivals.mutate(&s, key: k, id: r.id) { $0["fort"] = .number(Rivals.fortuneOf($0) + 0.15) }
        case .weak:
            text = "had a weak quarter and is cutting back."; effect = 1
            Rivals.mutate(&s, key: k, id: r.id) { $0["fort"] = .number(Rivals.fortuneOf($0) - 0.25) }
        case .recover:
            text = "landed a steady contract and is back on its feet."; effect = -1
            Rivals.mutate(&s, key: k, id: r.id) { $0["fort"] = .number(Rivals.fortuneOf($0) + 0.25) }
        }
        var st = s.rest["rvs"] ?? .object([:])
        var tl = st["tl"].array
        tl.insert(.object(["w": .number(Double(week)), "rid": .number(Double(r.id)), "rn": .string(r.name), "co": .number(Double(co.id)), "t": .string(text), "e": .number(Double(effect))]), at: 0)
        if tl.count > timelineKept { tl.removeLast(tl.count - timelineKept) }
        st["tl"] = .array(tl)
        s.rest["rvs"] = st
        if kind == .cut { offerWar(&s, co: co, rival: r, data: data) }
    }

    // MARK: Decisions

    static func decisionReady(_ s: GameState) -> Bool {
        let last = s.rest["rvs"]?["last"].int ?? -99
        return s.week - last >= decisionGap && !s.inbox.contains { $0.status == "open" && handlesAnswer($0.actionID) }
    }

    static func markDecision(_ s: inout GameState) {
        var st = s.rest["rvs"] ?? .object([:])
        st["last"] = .number(Double(s.week))
        s.rest["rvs"] = st
    }

    /// A bigger rival cuts its prices: match it for a short while, hold your price and advertise, or sit it out.
    static func offerWar(_ s: inout GameState, co: Company, rival r: Rivals.Rival, data: GameData) {
        guard decisionReady(s), r.size >= 1, HashedRandom.first("\(s.seed):rvswar:\(s.week):\(r.id)") < 0.5 else { return }
        let advert = Engagement.spend(s, co, share: advertShare, data: data)
        let canMatch = PriceMoves.maxDiscount(co.type) >= matchPercent
        var options: [JSONValue] = []
        options.append(.option(canMatch ? "Match it for \(matchWeeks) weeks" : "Hold your price and advertise",
                               canMatch ? "A \(matchPercent)% discount for \(matchWeeks) weeks. You keep your customers and give up some margin." : "A little marketing keeps your name in front of customers.",
                               effects: canMatch ? [:] : ["cash": .number(-advert)]))
        if canMatch { options.append(.option("Hold your price and advertise", "A little marketing keeps your name in front of customers.", effects: ["cash": .number(-advert)])) }
        options.append(.option("Sit it out", "No cost. Some customers will drift for a few weeks."))
        s.addMessage(kind: "ask", from: "Competition", title: "A rival is cutting its prices",
                     body: "\(r.name), run by \(r.owner), has cut its prices and is the bigger name in town. How do you answer?", companyID: co.id, tone: "n", status: "open",
                     options: options, action: warAction, data: .object(["co": .number(Double(co.id)), "rid": .number(Double(r.id)), "match": .bool(canMatch)]),
                     expiresWeek: s.week + 2, sev: 2)
        markDecision(&s)
    }

    /// A rival in real trouble, or already for sale, is offered to you at a reduced price.
    static func offerSale(_ s: inout GameState, data: GameData) {
        guard decisionReady(s) else { return }
        for co in s.companies where co.status == .open && co.type != "hold" && co.type != "club" {
            guard let bd = data.catalog[co.type] else { continue }
            let w = World(state: s, data: data)
            for r in Rivals.rivals(s, for: co) where r.fortune < troubleFortune || r.forSale {
                guard HashedRandom.first("\(s.seed):rvsbuy:\(s.week):\(r.id)") < 0.2 else { continue }
                let price = Rivals.roundTo(Rivals.value(bd, r, w, co) * distressedPriceShare, 1000)
                let startup = Rivals.startupMoney(s, co, rival: r, data: data)
                guard price > 0, Payments.liquid(s) >= (price + startup) * 1.2 else { continue }
                let cur = w.currency(co)
                s.addMessage(kind: "ask", from: "Business broker", title: "A rival is struggling",
                             body: "\(r.owner) wants out and would sell \(r.name) for \(cur.display(price)), plus about \(cur.display(startup)) of your own money to set it up. Its customers and people would be yours; a few bills may surface after.",
                             companyID: co.id, tone: "n", status: "open",
                             options: [.option("Buy it", "Pay \(cur.display(price)). Customers uneasy for a while.", effects: ["cash": .number(-price)]), .option("Not now", "It may find another buyer.")],
                             action: buyAction, data: .object(["co": .number(Double(co.id)), "rid": .number(Double(r.id)), "price": .number(price)]),
                             expiresWeek: s.week + 3, sev: 2)
                markDecision(&s)
                return
            }
        }
    }

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context: FinanceContext) {
        let d = m.value("data")
        let cid = d["co"].int
        guard let ci = s.companyIndex(cid), s.companies[ci].status == .open else { return }
        if m.actionID == buyAction {
            guard idx == 0 else { return }
            let res = Rivals.acquire(&s, companyID: cid, rivalID: d["rid"].int, price: d["price"].double, data: data, context: context)
            switch res {
            case .ok(let id): s.addMessage(from: "Business broker", title: "You bought a rival", body: "It now trades as a company of yours. Its customers are deciding whether to stay.", companyID: id, tone: "good")
            case .notEnoughCash: s.addMessage(from: "Business broker", title: "Not enough cash for the purchase", body: "The deal fell through. Nothing was paid.", companyID: cid, tone: "bad")
            case .failed(let why): s.addMessage(from: "Business broker", title: "The deal did not go through", body: why, companyID: cid)
            }
            return
        }
        let canMatch = d["match"].bool
        let pick = canMatch ? idx : idx + 1   // without a discount to match, the answers are advertise, sit it out
        let co = s.companies[ci]
        switch pick {
        case 0:
            if PriceMoves.startCampaign(&s, companyID: cid, percent: matchPercent, weeks: matchWeeks, data: data) != nil {
                Engagement.addModifier(&s, ci, key: "dem", multiplier: 1 - ignoreLoss, weeks: 4)   // a discount is already running: the cut still bites
            }
        case 1:
            _ = Payments.companyPays(&s, companyID: cid, amount: Engagement.spend(s, co, share: advertShare, data: data), category: "mkt", label: "Local advertising against a rival price cut")
            s.companies[ci].awareness = min(100, co.awareness + 2)
        default:
            Engagement.addModifier(&s, ci, key: "dem", multiplier: 1 - ignoreLoss, weeks: 4)
        }
    }
}
