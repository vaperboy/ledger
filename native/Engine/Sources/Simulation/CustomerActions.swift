import Foundation
import GameCore
import Countries
import Finance
import Businesses

// MARK: Read models: reviews, business customers, rivals, price moves, market map, IT security

public struct ReviewLine: Identifiable, Equatable {
    public var id: Int
    public var who: String
    public var stars: Int
    public var text: String
    public var age: Int
    public var weeksAgo: Int
    /// Flag of the country a tourist writes from; empty for locals.
    public var flag: String = ""
}

public struct ReviewSummary: Equatable {
    public var rating: Double
    public var count: Int
    public var histogram: [Int]       // index 0 = one star
    public var lines: [ReviewLine]
    public var word: String
    /// Fewer than three reviews: the rating is not shown as a number yet.
    public var enough: Bool
}

public struct ReviewRow: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var companyID: Int?
    public var rivalID: Int?
    public var rating: Double
    public var count: Int
    public var mine: Bool
    public var rank: Int?
    public var of: Int?
}

public struct ReviewGroup: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var rows: [ReviewRow]
}

public struct RivalRow: Identifiable, Equatable {
    public var id: Int
    public var rival: Rivals.Rival
    public var priceGap: Double          // their price against yours, as a share
    public var sizeWord: String
    public var feel: String
    public var mood: String
    public var share: MarketMap.Estimate?
}

public struct Fact: Identifiable, Equatable {
    public var id: String { label }
    public var label: String
    public var value: String
    public var tone: String = ""
}

public struct RivalDetail: Equatable {
    public var rival: Rivals.Rival
    public var facts: [Fact]
    public var analyst: String?
    public var group: RivalGroups.Group?
    public var temperament: String
    public var moodWord: String
    public var nextMove: String
    public var price: Double
    public var reviewRating: Double
    public var reviewCount: Int
    public var reviews: [ReviewLine]
}

public struct PriceMovesInfo: Equatable {
    public var yourTicket: Double
    public var rivalsAverage: Double?
    public var margin: Double?
    public var againstMarket: Double          // your price level against the going price, as a share
    public var discountPercent: Int?
    public var discountWeeksLeft: Int
    public var discountOptions: [Int]
    public var raisedWeeksAgo: Int
    public var war: (rivalID: Int, weeksLeft: Int, loss: Double)?
    public var recentCut: Double
    public static func == (a: PriceMovesInfo, b: PriceMovesInfo) -> Bool {
        a.yourTicket == b.yourTicket && a.rivalsAverage == b.rivalsAverage && a.discountPercent == b.discountPercent && a.againstMarket == b.againstMarket && a.war?.rivalID == b.war?.rivalID && a.war?.weeksLeft == b.war?.weeksLeft
    }
}

public struct MarketRow: Identifiable, Equatable {
    public var id: String
    public var label: String
    public var shareText: String
    public var level: MarketMap.Knowledge.Level
    public var companyNames: [String]
}

public struct MarketPlayerRow: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var text: String
    public var detail: String
    public var rivalID: Int?
    public var companyID: Int
}

public struct MarketDetail: Equatable {
    public var key: String
    public var title: String
    public var subtitle: String
    public var level: MarketMap.Knowledge.Level
    public var analystName: String
    public var shareText: String
    public var sizeText: String?
    public var yourSales: Double
    public var history: [Double]
    public var players: [MarketPlayerRow]
    public var report: [String]
    public var firstCompanyID: Int
}

public struct CyberInfo: Equatable {
    public var status: Cyber.Status
    public var yearOdds: Double
    public var levelCosts: [Double]     // monthly, for each level
    public var backupsCost: Double
    public var trainingCost: Double
    public var insured: Bool
    public var monthlyNow: Double
    public var heads: Int
}

public extension GameEngine {
    // MARK: Reviews

    func reviewSummary(_ co: Company, limit: Int = 12) -> ReviewSummary {
        let country = data.countries.resolve(co.countryCode, orHome: state.homeCountryCode)
        let r = Reviews.rating(co), n = Reviews.count(co)
        return ReviewSummary(rating: r, count: n, histogram: Reviews.histogram(co),
                             lines: Reviews.latest(co, limit: limit).map { ReviewLine(id: $0.id, who: Reviews.reviewerName($0, country: $0.isTourist ? data.countries.resolve($0.origin, orHome: co.countryCode) : country), stars: $0.stars, text: $0.text, age: $0.age, weeksAgo: max(0, state.week - $0.week), flag: $0.isTourist ? data.countries[$0.origin]?.flag ?? "" : "") },
                             word: n < Reviews.minimumShown ? "No rating yet" : Reviews.word(r), enough: n >= Reviews.minimumShown)
    }

    /// Every business in your markets, best rated first: yours and your rivals'. Original: `reviewList`.
    func reviewBoard() -> [ReviewGroup] {
        var out: [ReviewGroup] = []
        var seen = Set<String>()
        for co in state.companies where co.status == .open {
            guard let bd = data.catalog[co.type], !["fin", "energy", "hold", "club"].contains(bd.family) else { continue }
            let k = Rivals.key(co)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            let w = World(state: state, data: data)
            var rows: [ReviewRow] = state.companies.filter { $0.status == .open && Rivals.key($0) == k }.map {
                ReviewRow(id: "c\($0.id)", name: $0.name, companyID: $0.id, rivalID: nil, rating: Reviews.rating($0), count: Reviews.count($0), mine: true, rank: nil, of: nil)
            }
            for r in Rivals.rivals(state, key: k) {
                rows.append(ReviewRow(id: "r\(r.id)", name: r.name, companyID: nil, rivalID: r.id, rating: Reviews.rivalRating(seed: state.seed, rivalID: r.id, size: r.size),
                                      count: Reviews.rivalReviewCount(bd, size: r.size, week: state.week), mine: false, rank: nil, of: nil))
            }
            let rated = rows.filter { $0.count >= Reviews.minimumShown }.sorted { $0.rating > $1.rating }
            rows = rows.sorted { ($0.count >= Reviews.minimumShown ? 1 : 0, $0.rating) > ($1.count >= Reviews.minimumShown ? 1 : 0, $1.rating) }.map { row in
                var r = row
                if let k = rated.firstIndex(where: { $0.id == row.id }) { r.rank = k + 1; r.of = rated.count }
                return r
            }
            _ = w
            out.append(ReviewGroup(id: k, title: "\(bd.name) · \(cityName(co))", rows: rows))
        }
        return out
    }

    // MARK: Business customers

    func keyAccountInfo(_ co: Company) -> (allowed: Bool, limit: Int, accounts: [KeyAccounts.Account]) {
        guard let bd = data.catalog[co.type] else { return (false, 0, []) }
        return (KeyAccounts.allowed(co, bd), KeyAccounts.maximum(co), KeyAccounts.accounts(co))
    }

    mutating func meetAccount(companyID: Int, accountID: Int) -> KeyAccounts.MeetResult {
        var r = KeyAccounts.MeetResult.missing
        update { s, d, _ in r = KeyAccounts.meet(&s, companyID: companyID, accountID: accountID, data: d) }
        return r
    }
    /// True when the key-account contract existed and is ended.
    @discardableResult
    mutating func dropAccount(companyID: Int, accountID: Int) -> Bool { var ok = false; update { s, _, _ in ok = KeyAccounts.drop(&s, companyID: companyID, accountID: accountID) }; return ok }
    mutating func setAccountDiscount(companyID: Int, accountID: Int, percent: Int) { update { s, _, _ in KeyAccounts.setDiscount(&s, companyID: companyID, accountID: accountID, percent: percent) } }

    // MARK: Rivals

    func rivalRows(_ co: Company) -> [RivalRow] {
        let w = World(state: state, data: data)
        guard let bd = w.trade(co) else { return [] }
        let t = MarketMap.markets(state, data: data).first { $0.companyIDs.contains(co.id) }
        let truth = t.map { MarketMap.truth(state, $0, data: data) }
        let know = t.map { MarketMap.knowledge(state, $0) }
        let mine = Pricing.ticket(co, bd, w)
        return Rivals.rivals(state, for: co).map { r in
            let gap = mine > 0 ? Rivals.price(co, r, w) / mine - 1 : 0
            let marginValue = Rivals.margin(bd, r, seed: state.seed)
            let feel = marginValue > 0.14 ? "Seems to be doing well" : marginValue > 0.05 ? "Getting by" : marginValue > 0 ? "Looks like thin margins" : "Looks like they are losing money"
            let sizeWord = r.size >= 1.15 ? "Large" : r.size >= 0.7 ? "Medium" : "Small"
            var est: MarketMap.Estimate?
            if let truth = truth, let know = know, let p = truth.players.first(where: { $0.rivalID == r.id }) { est = MarketMap.estimate(p.share, key: "rv" + p.id, know, seed: state.seed, week: state.week) }
            return RivalRow(id: r.id, rival: r, priceGap: gap, sizeWord: sizeWord, feel: feel, mood: Rivals.mood(r).word, share: est)
        }
    }

    func rivalDetail(companyID: Int, rivalID: Int) -> RivalDetail? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], let r = Rivals.rivals(state, for: co).first(where: { $0.id == rivalID }) else { return nil }
        let w = World(state: state, data: data)
        let cur = w.currency(co)
        let rev = Rivals.yearlyRevenue(bd, r, w, co)
        let margin = Rivals.margin(bd, r, seed: state.seed)
        let m = MarketMap.markets(state, data: data).first { $0.companyIDs.contains(co.id) }
        let know = m.map { MarketMap.knowledge(state, $0) } ?? MarketMap.Knowledge.nobody
        let run = Rivals.holdOut(r, seed: state.seed)
        let staff = Rivals.staffCount(bd, r)
        let myRev = MarketMap.annualRevenue(co)
        let share = m.flatMap { MarketMap.truth(state, $0, data: data).players.first { $0.rivalID == rivalID }?.share }
        var facts: [Fact] = []
        func range(_ v: Double, _ key: String, unit: Double, f: (Double) -> String) -> String {
            let a = HashedRandom.first("\(state.seed):\(key):\(rivalID):\(know.id)"), b = HashedRandom.first("\(state.seed):\(key)b:\(rivalID):\(know.id)")
            var wd: Double, c: Double
            let sk: Double = know.skill
            if sk >= 0.65 {
                let spread: Double = 0.06 + (1 - sk) * 0.12
                wd = abs(v) * spread + unit
                c = v * (1 + (a - 0.5) * 0.05)
            }
            else if b < 0.5 { wd = abs(v) * 0.08 + unit; c = v * (1 + (a - 0.5) * 0.28) }
            else { wd = abs(v) * 0.55 + unit * 4; c = v }
            return f(c - wd / 2) + "–" + f(c + wd / 2)
        }
        if know.level != .feeling {
            let short: (Double) -> String = { cur.short($0) }
            facts = [Fact(label: "Revenue a year", value: range(rev, "rv", unit: 0, f: short)), Fact(label: "Margin", value: range(margin * 100, "mg", unit: 1) { "\(Int($0.rounded()))" } + "%"),
                     Fact(label: "Profit a year", value: range(rev * margin, "pf", unit: 0, f: short)), Fact(label: "Staff", value: range(Double(staff), "st", unit: 1) { "\(max(1, Int($0.rounded())))" }),
                     Fact(label: "Cash lasts if they lose money", value: range(Double(run), "rn", unit: 2) { "\(max(1, Int($0.rounded())))" } + " weeks"),
                     Fact(label: "Market share", value: range((share ?? 0) * 100, "sh", unit: 2) { "\(max(0, Int($0.rounded())))" } + "%")]
        } else {
            facts = [Fact(label: "Size", value: MarketMap.sizeComparison(rival: rev, mine: myRev)),
                     Fact(label: "Money", value: margin > 0.14 ? "Seems to be doing well" : margin > 0.05 ? "Getting by" : margin > 0 ? "Looks like thin margins" : "Looks like they are losing money"),
                     Fact(label: "If it got tough", value: run >= 14 ? "Could hold out a long time" : run >= 9 ? "Could last a while" : "Money looks tight"),
                     Fact(label: "Staff", value: staff >= 10 ? "A big team" : staff >= 4 ? "A handful of people" : "Just a few")]
        }
        let gap = Pricing.ticket(co, bd, w) > 0 ? Rivals.price(co, r, w) / Pricing.ticket(co, bd, w) - 1 : 0
        facts.append(Fact(label: "Their price vs yours", value: abs(gap) < 0.03 ? "About the same" : (gap > 0 ? "Higher by about " : "Lower by about ") + "\(Int((abs(gap) * 100).rounded()))%"))
        let rating = Reviews.rivalRating(seed: state.seed, rivalID: r.id, size: r.size)
        let count = Reviews.rivalReviewCount(bd, size: r.size, week: state.week)
        let country = data.countries.resolve(co.countryCode, orHome: state.homeCountryCode)
        let lines = Reviews.rivalLines(seed: state.seed, rivalID: r.id, rating: rating, count: count, week: state.week, limit: 5)
            .map { ReviewLine(id: $0.id, who: Reviews.reviewerName($0, country: country), stars: $0.stars, text: $0.text, age: $0.age, weeksAgo: max(0, state.week - $0.week)) }
        return RivalDetail(rival: r, facts: facts, analyst: know.level == .feeling ? nil : know.name, group: RivalGroups.group(state, id: r.groupID),
                           temperament: Rivals.temperament(r).name + " · " + Rivals.temperament(r).text, moodWord: Rivals.mood(r).word, nextMove: Rivals.nextMove(r),
                           price: Rivals.price(co, r, w), reviewRating: rating, reviewCount: count, reviews: lines)
    }

    mutating func meetRival(companyID: Int, rivalID: Int) -> Rivals.MeetResult {
        var r = Rivals.MeetResult.missing
        update { s, d, _ in r = Rivals.meet(&s, companyID: companyID, rivalID: rivalID, data: d) }
        return r
    }

    /// What it would cost to buy a rival at a multiple of its value (the multiple 1.0 is the going price).
    func rivalValue(companyID: Int, rivalID: Int) -> Double {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], let r = Rivals.rivals(state, for: co).first(where: { $0.id == rivalID }) else { return 0 }
        return Rivals.value(bd, r, World(state: state, data: data), co)
    }

    func rivalStartupMoney(companyID: Int, rivalID: Int) -> Double {
        guard let co = state.company(companyID), let r = Rivals.rivals(state, for: co).first(where: { $0.id == rivalID }) else { return 0 }
        return Rivals.startupMoney(state, co, rival: r, data: data)
    }

    mutating func offerForRival(companyID: Int, rivalID: Int, multiple: Double) -> Rivals.OfferReply? {
        var r: Rivals.OfferReply?
        update { s, d, _ in r = Rivals.proposeBuy(&s, companyID: companyID, rivalID: rivalID, multiple: multiple, data: d) }
        return r
    }

    /// Complete a purchase the owner agreed to.
    mutating func buyRival(companyID: Int, rivalID: Int, price: Double) -> Rivals.AcquireResult {
        var r = Rivals.AcquireResult.failed("Nothing happened.")
        update { s, d, c in
            r = Rivals.acquire(&s, companyID: companyID, rivalID: rivalID, price: price, data: d, context: c)
            if case .ok = r { Ambitions.countEvent(&s, "buy") }   // counts for the market dominator ambition
        }
        return r
    }

    func warEstimate(companyID: Int, rivalID: Int, weeks: Int) -> Rivals.WarEstimate? {
        guard let co = state.company(companyID), let r = Rivals.rivals(state, for: co).first(where: { $0.id == rivalID }) else { return nil }
        return Rivals.warEstimate(state, co, rival: r, weeks: weeks, data: data)
    }

    mutating func startPriceWar(companyID: Int, rivalID: Int, weeks: Int) -> ActionResult {
        var msg: String?
        update { s, d, _ in msg = Rivals.startPriceWar(&s, companyID: companyID, rivalID: rivalID, weeks: weeks, data: d) }
        return msg.map { .refused($0) } ?? .done
    }
    mutating func endPriceWar(companyID: Int) { update { s, _, _ in Rivals.endPriceWar(&s, companyID: companyID) } }

    /// Groups that compete in the countries you are in.
    func rivalGroupsAround() -> [RivalGroups.Group] {
        Set(state.companies.filter { $0.status.isLive }.map { $0.countryCode } + [state.homeCountryCode]).sorted().flatMap { cc in
            RivalGroups.groups(state, country: cc).filter { g in !RivalGroups.members(state, groupID: g.id).isEmpty || !g.moves.isEmpty }
        }
    }

    func rivalsOfGroup(_ id: String) -> [(company: Company, rival: Rivals.Rival)] {
        RivalGroups.members(state, groupID: id).compactMap { m in
            let co = state.companies[m.companyIndex]
            guard let r = Rivals.rivals(state, for: co).first(where: { $0.id == m.rivalID }) else { return nil }
            return (co, r)
        }
    }

    // MARK: Price moves

    func priceMoves(_ co: Company) -> PriceMovesInfo? {
        let w = World(state: state, data: data)
        guard let bd = w.trade(co) else { return nil }
        let rs = Rivals.rivals(state, for: co)
        let avg = rs.isEmpty ? nil : rs.reduce(0) { $0 + Rivals.price(co, $1, w) } / Double(rs.count)
        let last = co.monthlyHistory.last { $0.revenue > 0 }
        let pw = co.value("flags")["pw"]
        return PriceMovesInfo(yourTicket: Pricing.ticket(co, bd, w), rivalsAverage: avg, margin: last.map { $0.profit / max(1, $0.revenue) },
                              againstMarket: data.balance.priceMultiplier(level: co.priceLevel) - 1,
                              discountPercent: Pricing.discount(co, state.week) > 0 ? co.value("camp16")["pct"].int : nil,
                              discountWeeksLeft: max(0, co.value("camp16")["end"].int - state.week), discountOptions: PriceMoves.discountOptions(co.type),
                              raisedWeeksAgo: PriceMoves.raisedWeeksAgo(co, week: state.week, balance: data.balance),
                              war: pw.isNull ? nil : (pw["rid"].int, max(0, pw["end"].int - state.week), pw["loss"].double),
                              recentCut: PriceMoves.recentCut(co, week: state.week, balance: data.balance))
    }

    /// Change the price by a share, e.g. +0.05. Returns the real change.
    @discardableResult
    mutating func changePrice(companyID: Int, byShare d: Double) -> Double? {
        var r: Double?
        update { s, data, _ in r = PriceMoves.changePrice(&s, companyID: companyID, byShare: d, data: data) }
        return r
    }
    mutating func startDiscount(companyID: Int, percent: Int, weeks: Int) -> ActionResult {
        var msg: String?
        update { s, d, _ in msg = PriceMoves.startCampaign(&s, companyID: companyID, percent: percent, weeks: weeks, data: d) }
        return msg.map { .refused($0) } ?? .done
    }
    mutating func endDiscount(companyID: Int) { update { s, _, _ in PriceMoves.endCampaign(&s, companyID: companyID) } }

    // MARK: Market map

    func marketRows() -> [MarketRow] {
        let all = MarketMap.markets(state, data: data)
        let many = Dictionary(grouping: all, by: { $0.type }).mapValues { $0.count > 1 }
        return all.map { m in
            let t = MarketMap.truth(state, m, data: data), k = MarketMap.knowledge(state, m)
            let e = MarketMap.estimate(t.share, key: "my" + m.id, k, seed: state.seed, week: state.week)
            return MarketRow(id: m.id, label: MarketMap.label(m, data: data, withCity: many[m.type] ?? false), shareText: MarketMap.text(e), level: k.level,
                             companyNames: m.companyIDs.compactMap { state.company($0)?.name })
        }
    }

    func marketDetail(key: String) -> MarketDetail? {
        guard let m = MarketMap.markets(state, data: data).first(where: { $0.id == key }), let first = m.companyIDs.first, let co = state.company(first) else { return nil }
        let t = MarketMap.truth(state, m, data: data), k = MarketMap.knowledge(state, m)
        let cur = currency(for: co)
        let e = MarketMap.estimate(t.share, key: "my" + m.id, k, seed: state.seed, week: state.week)
        var sizeText: String?
        if k.level != .feeling {
            let a = HashedRandom.first("\(state.seed):26:tot\(m.id):\(state.week / 4):\(k.id)")
            sizeText = k.level == .marketAnalyst ? "about " + cur.short(t.total * (1 + (a - 0.5) * 0.06 * (1 - k.skill))) : cur.short(t.total * (1 - 0.1)) + "–" + cur.short(t.total * 1.1)
        }
        let players = t.players.map { p -> MarketPlayerRow in
            let pe = MarketMap.estimate(p.share, key: "rv" + p.id, k, seed: state.seed, week: state.week)
            let detail = k.level == .feeling ? MarketMap.sizeComparison(rival: p.revenue, mine: t.mine) : (k.level == .marketAnalyst ? "sells \(cur.short(p.revenue))" + (m.kind == .local ? " a year" : "") : "")
            return MarketPlayerRow(id: p.id, name: p.name, text: MarketMap.text(pe), detail: detail, rivalID: p.rivalID, companyID: first)
        }
        return MarketDetail(key: key, title: MarketMap.label(m, data: data, withCity: true), subtitle: m.companyIDs.compactMap { state.company($0)?.name }.joined(separator: ", "),
                            level: k.level, analystName: k.name, shareText: MarketMap.text(e), sizeText: sizeText, yourSales: t.mine,
                            history: MarketMap.history(state, key: key).map { $0.share * 100 }, players: players,
                            report: k.level == .feeling ? [] : MarketMap.report(state, m, k, data: data), firstCompanyID: first)
    }

    // MARK: IT security

    func cyberInfo(_ co: Company) -> CyberInfo {
        let cur = currency(for: co)
        let st = Cyber.status(co)
        return CyberInfo(status: st, yearOdds: Cyber.yearOdds(co, week: state.week, trade: data.catalog[co.type]),
                         levelCosts: Cyber.levels.indices.map { Cyber.monthly(co, level: $0, backups: false, cur: cur) },
                         backupsCost: Cyber.monthly(co, level: 0, backups: true, cur: cur), trainingCost: Cyber.trainingCost(co, cur: cur), insured: co.value("ins")["cyber"].bool,
                         monthlyNow: Cyber.monthly(co, level: st.level, backups: st.backups, cur: cur), heads: Cyber.heads(co))
    }
    @discardableResult
    mutating func setCyberLevel(companyID: Int, level: Int) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.company(companyID)?.value("cy56") ?? .null }) { s, _, _ in Cyber.setLevel(&s, companyID: companyID, level: level) }
    }
    @discardableResult
    mutating func toggleBackups(companyID: Int) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.company(companyID)?.value("cy56") ?? .null }) { s, _, _ in Cyber.toggleBackups(&s, companyID: companyID) }
    }
    mutating func trainStaff(companyID: Int) -> ActionResult {
        var msg: String?
        update { s, d, _ in msg = Cyber.train(&s, companyID: companyID, data: d) }
        return msg.map { .refused($0) } ?? .done
    }
}

// MARK: Analysts, forecasts, rankings, the world around you, own software

public extension GameEngine {
    /// What a market analyst in this company would give you (the hire screen). Original: `R26.mktanHire`.
    func marketAnalystVerdict(companyID: Int) -> MarketMap.HireVerdict { MarketMap.analystHireVerdict(state, companyID: companyID, data: data) }
    var hasDataAnalyst: Bool { MarketMap.hasDataAnalyst(state) }
    mutating func dataAnalystCandidates() -> [Person] {
        var r: [Person] = []
        update { s, d, _ in r = MarketMap.dataAnalystCandidates(&s, data: d) }
        return r
    }
    mutating func hireDataAnalyst(personID: Int, monthlyWage: Double) -> MarketMap.HQHire {
        var r = MarketMap.HQHire.refused
        update { s, d, _ in r = MarketMap.hireDataAnalyst(&s, personID: personID, monthlyWage: monthlyWage, data: d) }
        return r
    }
    /// True when there was a data analyst to let go.
    @discardableResult
    mutating func fireDataAnalyst() -> Bool { var ok = false; update { s, _, _ in ok = MarketMap.fireDataAnalyst(&s) }; return ok }
    func economyWeight() -> MarketMap.Weight { MarketMap.weight(state, data: data) }
    /// Ask your market analyst for a report now (market map), or your data analyst for one on a company or all of them.
    mutating func orderMarketReport(marketKey: String) -> ActionResult {
        var msg: String?
        update { s, d, _ in msg = MarketMap.orderMarketReport(&s, marketKey: marketKey, data: d) }
        return msg.map { .refused($0) } ?? .done
    }
    mutating func orderAnalystReport(companyID: Int?) -> ActionResult {
        var msg: String?
        update { s, d, _ in msg = MarketMap.dataAnalystReport(&s, companyID: companyID, data: d) }
        return msg.map { .refused($0) } ?? .done
    }

    /// The forecast boxes of the price-move screen: customers and margin, as you or your analyst see them. Original: `est`, `fcBoxes`.
    func priceForecast(companyID: Int, byShare d: Double, campaignPercent cp: Int = 0) -> (forecast: PriceMoves.Forecast, text: PriceMoves.ForecastText)? {
        guard let f = PriceMoves.forecast(state, companyID: companyID, byShare: d, campaignPercent: cp, data: data) else { return nil }
        return (f, PriceMoves.forecastText(f, state, key: "p\(companyID):\(Int(jsRound(d * 100))):\(cp)", campaign: cp > 0))
    }

    /// The biggest companies by sales, profit, value or growth. Original: `R27.ranked`.
    func rankingBoard(scope: CompanyRanking.Scope, metric: CompanyRanking.Metric) -> CompanyRanking.Board { CompanyRanking.board(state, data: data, scope: scope, metric: metric) }
    func yourRanking(scope: CompanyRanking.Scope = .country, metric: CompanyRanking.Metric = .revenue) -> (rank: Int, of: Int)? {
        CompanyRanking.yourRank(state, data: data, scope: scope, metric: metric)
    }

    // MARK: IT security picked by the manager
    mutating func leaveCyberToManager(companyID: Int) { update { s, _, _ in Cyber.leaveToManager(&s, companyID: companyID) } }

    // MARK: World around you
    /// How each group sees you (press, city, bank ...), worked out from the same trust/bold/care numbers as `publicImage`.
    func worldImage() -> WorldAround.Image { WorldAround.image(state, data: data) }
    mutating func peopleYouKnow() -> [WorldAround.Contact] {
        var r: [WorldAround.Contact] = []
        update { s, d, _ in r = WorldAround.contacts(&s, data: d) }
        return r
    }
    func favours() -> [WorldAround.Favour] { WorldAround.favours(state) }
    mutating func keepPromise(favourID: Int) -> WorldAround.ActionResult {
        var r = WorldAround.ActionResult.refused("")
        update { s, d, _ in r = WorldAround.keepPromise(&s, favourID: favourID, data: d) }
        return r
    }
    mutating func callInFavour(favourID: Int) -> WorldAround.ActionResult {
        var r = WorldAround.ActionResult.refused("")
        update { s, d, _ in r = WorldAround.callIn(&s, favourID: favourID, data: d) }
        return r
    }
    mutating func askForFavour(contactID: String) -> WorldAround.ActionResult {
        var r = WorldAround.ActionResult.refused("")
        update { s, d, _ in r = WorldAround.askFavour(&s, contactID: contactID, data: d) }
        return r
    }
    func mapOwnership() -> [WorldAround.OwnershipNode] { WorldAround.ownership(state, data: data) }
    func mapPresence() -> [WorldAround.CountryPresence] { WorldAround.presence(state, data: data) }
    mutating func mapInfluence() -> WorldAround.Influence {
        var r = WorldAround.Influence(inner: [], allies: [], others: [], seenAs: "")
        update { s, d, _ in r = WorldAround.influence(&s, data: d) }
        return r
    }
    mutating func contactsSummary() -> String {
        var r = ""
        update { s, d, _ in r = WorldAround.contactsSummary(&s, data: d) }
        return r
    }
    var localPaperName: String? { WorldAround.paperName(state, data: data) }

    // MARK: Key accounts: what they sell
    func keyAccountProfile(_ a: KeyAccounts.Account) -> KeyAccounts.Profile { KeyAccounts.profile(a, data: data) }

    // MARK: Software of your own
    func softwareProduct(companyID: Int) -> SoftwareProducts.Product? { SoftwareProducts.product(state, companyID: companyID) }
    mutating func startSoftware(companyID: Int, type: String, model: String, name: String? = nil) -> Bool {
        var r = false
        update { s, d, _ in r = SoftwareProducts.start(&s, companyID: companyID, type: type, model: model, name: name, data: d) }
        return r
    }
    @discardableResult
    mutating func setSoftwareCoders(companyID: Int, coders: Int) -> SettingResult {
        applySetting(refuse: { s in
            guard let co = s.company(companyID), !co.value("swp").isNull else { return "This company has no software product." }
            if coders > 10 { return "Ten coders is the most." }
            if coders < 0 { return "There are no coders left to let go." }
            return nil
        }, probe: { $0.company(companyID)?.value("swp") ?? .null }) { s, _, _ in SoftwareProducts.setCoders(&s, companyID: companyID, coders: coders) }
    }
    mutating func setSoftwareSelfCoding(companyID: Int, on: Bool) { update { s, _, _ in SoftwareProducts.setSelfCoding(&s, companyID: companyID, on: on) } }
    @discardableResult
    mutating func setSoftwareModel(companyID: Int, model: String) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in SoftwareProducts.setModel(&s, companyID: companyID, model: model, data: d) }
    }
    mutating func setSoftwareInternalPercent(companyID: Int, percent: Int) { update { s, _, _ in SoftwareProducts.setInternalPercent(&s, companyID: companyID, percent: percent) } }
    func ownSoftwareOffers(buyerID: Int, equipmentName: String) -> [SoftwareProducts.Offer] { SoftwareProducts.offers(state, equipmentName: equipmentName, buyerID: buyerID) }
    mutating func useOwnSoftware(companyID: Int, equipmentID: String, producerID: Int) -> SoftwareProducts.AdoptResult {
        var r = SoftwareProducts.AdoptResult.notPossible
        update { s, d, _ in r = SoftwareProducts.adopt(&s, companyID: companyID, equipmentID: equipmentID, producerID: producerID, data: d) }
        return r
    }
}
