import Foundation
import GameCore
import Businesses
import Events

final class MockStartupMarketService: StartupMarketService {
    var onChange: (() -> Void)?

    private struct Book: Codable {
        var startups: [CrowdStartup] = []
        var holdings: [CrowdHolding] = []
        var taken: [String] = []
        var seeded = false
        var processedWeek: Int?
        var viralTold: [String] = []
        var lastToday = 0
    }

    private var book = Book()
    private var save: ((Data) -> Void)?
    private var activity = false
    let myLinkKeys: Set<String> = [CrowdStartups.me]

    init() {}

    init(restoring data: Data?, save: @escaping (Data) -> Void) {
        self.save = save
        if let data, let b = try? JSONDecoder().decode(Book.self, from: data) { book = b }
    }

    var hasActivity: Bool { activity }

    private func roll(_ key: String) -> Double { HashedRandom.first("startupmock:" + key) }
    private func persist() {
        if let save, let d = try? JSONEncoder().encode(book) { save(d) }
        onChange?()
    }

    func startups() -> [CrowdStartup] { book.startups }
    func startup(_ id: String) -> CrowdStartup? { book.startups.first { $0.id == id } }
    func myHoldings() -> [CrowdHolding] { book.holdings }

    func offers(startupID: String) -> [StartupShareOffer] {
        guard let st = startup(startupID), st.status == .live || st.status == .raising, st.milestones >= 1 else { return [] }
        var byInvestor: [String: [CrowdStartupRules.Investment]] = [:]
        for inv in st.investments where inv.released && inv.investorID.hasPrefix("inv") { byInvestor[inv.investorID, default: []].append(inv) }
        var out: [StartupShareOffer] = []
        for (id, lines) in byInvestor.sorted(by: { $0.key < $1.key }).prefix(2) {
            let offerID = "O-\(startupID)-\(id)"
            guard !book.taken.contains(offerID) else { continue }
            let pct = lines.reduce(0) { $0 + $1.percent } * 0.5
            let paid = lines.reduce(0) { $0 + $1.amount } * 0.5
            let day = lines.map { $0.day }.min() ?? 0
            let h = CrowdHolding(startupID: startupID, ownerID: id, linkKey: id, percent: pct, paid: paid, boughtDay: day)
            let factor = 0.9 + 0.25 * roll("price" + offerID)
            out.append(StartupShareOffer(id: offerID, startupID: startupID, sellerID: id, sellerName: "Investor " + String(id.dropFirst(3)), sellerLinkKey: id, holding: h, percent: pct,
                                         price: (CrowdStartupRules.fairPrice(st, percent: pct) * factor).rounded()))
        }
        return out
    }

    func buyer(startupID: String) -> StartupBuyer? {
        guard let st = startup(startupID), st.status == .live || st.status == .raising else { return nil }
        let n = Int(roll("buyer" + startupID) * 30)
        return StartupBuyer(id: "inv\(100 + n)", name: "Investor \(100 + n)", linkKey: "inv\(100 + n)", accountWeeks: 40)
    }

    func list(_ s: CrowdStartup) {
        activity = true
        if let i = book.startups.firstIndex(where: { $0.id == s.id }) { book.startups[i] = s } else { book.startups.insert(s, at: 0) }
        persist()
    }

    func update(_ s: CrowdStartup) {
        guard let i = book.startups.firstIndex(where: { $0.id == s.id }) else { return }
        book.startups[i] = s
        persist()
    }

    func commitInvestment(_ s: CrowdStartup, holding: CrowdHolding) {
        activity = true
        update(s)
        CrowdStartups.add(holding, to: &book.holdings)
        persist()
    }

    func commitPurchase(offerID: String, startup s: CrowdStartup, holding: CrowdHolding) {
        activity = true
        book.taken.append(offerID)
        CrowdStartups.add(holding, to: &book.holdings)
        update(s)
        persist()
    }

    func commitSale(startupID: String, remaining: CrowdHolding) {
        activity = true
        if let i = book.holdings.firstIndex(where: { $0.startupID == startupID && $0.ownerID == CrowdStartups.me }) {
            if remaining.percent <= 1e-9 { book.holdings.remove(at: i) } else { book.holdings[i] = remaining }
        }
        persist()
    }

    func advance(today: Int, scale: Double, own: [String: CrowdStartups.Progress]) -> [StartupMarketEvent] {
        if !book.seeded { seed(today: today, scale: scale) }
        book.lastToday = today
        let week = today / 7
        guard let last = book.processedWeek else { book.processedWeek = week; persist(); return [] }
        guard week > last else { return [] }
        var events: [StartupMarketEvent] = []
        for w in (last + 1)...min(week, last + 4) { events += step(week: w) }
        book.processedWeek = week
        persist()
        return events
    }

    private static let investorPool = 60

    private func mockInvest(_ st: inout CrowdStartup, key: String, day: Int, count: Int) {
        for k in 0..<count {
            guard let stage = st.openStage else { return }
            let id = "inv\(Int(roll(key + "who\(k)") * Double(Self.investorPool)))"
            let room = CrowdStartupRules.stageTarget(st.plan, stage: stage) - st.raised(stage: stage)
            let want = max(CrowdStartupRules.minTicket(st.plan, stage: stage), room * (0.1 + 0.3 * roll(key + "amt\(k)")))
            let amount = (min(want, room) / 100).rounded(.down) * 100
            if case .ok(let q) = CrowdStartupRules.investCheck(st, investorID: id, linkKeys: [id], accountWeeks: 40, amount: amount, today: day) {
                st.investments.append(.init(id: "\(st.id)-\(st.investments.count)", investorID: id, linkKey: id, stage: q.stage, amount: amount, percent: q.percent, day: day))
            }
        }
    }

    private func step(week: Int) -> [StartupMarketEvent] {
        var events: [StartupMarketEvent] = []
        let day = week * 7
        for i in book.startups.indices {
            var st = book.startups[i]
            guard st.status == .raising || st.status == .live else { continue }
            let mine = st.founderID == CrowdStartups.me
            let key = "\(st.id):\(week):"
            let myLines = st.investments.filter { $0.investorID == CrowdStartups.me }
            let wasViral = st.viral(today: day)
            if st.openStage != nil {
                let burst = roll(key + "burst") < 0.025
                mockInvest(&st, key: key, day: day, count: burst ? 6 : Int(roll(key + "n") * (mine ? 3.5 : 2.6)))
            }
            if !wasViral && st.viral(today: day) && !book.viralTold.contains(st.id) {
                book.viralTold.append(st.id)
                events.append(.viral(startupID: st.id, name: st.name, mine: mine))
            }
            if !mine {
                let fragile = roll("fragile" + st.id) < 0.3
                if st.milestones < 3, roll(key + "fail") < (fragile ? 0.02 : 0.006) {
                    let back = CrowdStartupRules.fail(&st)
                    let mineBack = back.filter { $0.investorID == CrowdStartups.me }.reduce(0) { $0 + $1.amount }
                    if !myLines.isEmpty {
                        if mineBack > 0 { events.append(.refund(startupID: st.id, name: st.name, amount: mineBack)) }
                        events.append(.failed(startupID: st.id, name: st.name, mine: false, refunded: mineBack))
                    }
                } else if let stage = st.openStage, st.raised(stage: stage) > 0, roll(key + "mile") < 0.08 {
                    _ = CrowdStartupRules.reachMilestone(&st, today: day)
                    if myLines.contains(where: { $0.stage == stage }) { events.append(.milestone(startupID: st.id, name: st.name, stage: stage, mine: false)) }
                } else if !CrowdStartupRules.expire(&st, today: day).isEmpty {
                    let mineBack = st.investments.filter { $0.investorID == CrowdStartups.me && $0.refunded }.reduce(0) { $0 + $1.amount }
                    if mineBack > 0 { events.append(.refund(startupID: st.id, name: st.name, amount: mineBack)); events.append(.failed(startupID: st.id, name: st.name, mine: false, refunded: mineBack)) }
                }
                if st.status == .live && st.milestones >= 2 {
                    let swing = st.plan.cost * (st.milestones == 3 ? 0.004 : -0.002) * (0.6 + 0.8 * roll(key + "profit"))
                    st.weeklyProfit = Array((st.weeklyProfit + [swing]).suffix(CrowdStartupRules.recentProfitWeeks))
                    st.assets = max(0, st.assets + swing)
                }
            }
            book.startups[i] = st
        }
        return events
    }

    private static let trades = ["Software", "Bakery chain", "Brewery", "Fitness studios", "Games", "Clean energy", "Delivery", "Health clinic", "Fashion", "Food truck", "Farm tech", "Education"]
    private static let words = ["Nova", "Mint", "Harbor", "Lumen", "Pixel", "Orchard", "Kite", "Ember", "Atlas", "Fable", "Quill", "Tidal", "Oak", "Spark"]
    private static let pitches = ["Sells to small shops that have no online presence.", "Wants to open its first three sites in one city.", "Builds a tool people pay for every month.",
                                  "Serves a trade that still works on paper.", "Has a first customer waiting.", "Takes a proven idea to a new region."]

    private func seed(today: Int, scale: Double) {
        book.seeded = true
        let players = OnlineDirectoryCache.players
        let count = 14
        for i in 0..<count {
            let linked = i == 5
            let p = players.isEmpty ? nil : players[(i * 3) % players.count]
            let founderID = linked ? "me2" : (p?.id ?? "f\(i)")
            let founderName = linked ? "Mira Vance (your other account)" : (p?.displayName ?? "Founder \(i + 1)")
            let cost = ((150_000 + roll("cost\(i)") * 900_000) * scale / 1_000).rounded() * 1_000
            let put = (cost * (1.0 / 3.0 + 0.15 * roll("put\(i)")) / 1_000).rounded(.up) * 1_000
            let plan = CrowdStartupRules.Plan(cost: cost, founderPutIn: min(cost, put))
            var st = CrowdStartup(id: "M\(i)", name: Self.words[i % Self.words.count] + (i < Self.words.count ? "" : " 2"), trade: Self.trades[i % Self.trades.count],
                                  pitch: Self.pitches[i % Self.pitches.count], founderID: founderID, founderName: founderName, founderLinkKey: linked ? CrowdStartups.me : founderID,
                                  founderExits: i % 4 == 0 ? 1 : 0, founderFails: i % 5 == 1 ? 1 : 0, plan: plan, createdDay: today - 30 - i * 11)
            let target = [0, 1, 0, 2, 3, 1, 0, 2, 1, 0, 3, 1, 2, 0][i % 14]
            var d = st.createdDay + 3
            for stage in 0...target {
                if stage > 3 { break }
                guard st.openStage == stage else { break }
                let fill = stage < target ? 1.0 : (0.2 + 0.7 * roll("fill\(i)"))
                var n = 0
                while st.raised(stage: stage) < CrowdStartupRules.stageTarget(plan, stage: stage) * fill - 1, n < 14 {
                    let room = CrowdStartupRules.stageTarget(plan, stage: stage) * fill - st.raised(stage: stage)
                    let amount = (min(room, CrowdStartupRules.perInvestorCap(plan) * 0.6) / 100).rounded(.down) * 100
                    let id = "inv\((i * 7 + n * 3 + stage) % Self.investorPool)"
                    if case .ok(let q) = CrowdStartupRules.investCheck(st, investorID: id, linkKeys: [id], accountWeeks: 40, amount: amount, today: d) {
                        st.investments.append(.init(id: "\(st.id)-\(st.investments.count)", investorID: id, linkKey: id, stage: stage, amount: amount, percent: q.percent, day: d))
                    }
                    d += 2 + Int(roll("gap\(i)\(n)") * 3)
                    n += 1
                }
                if stage < target { _ = CrowdStartupRules.reachMilestone(&st, today: d); d += 10 }
            }
            if target >= 2 {
                let v = plan.cost * (target == 3 ? 0.004 : -0.002)
                st.weeklyProfit = (0..<13).map { _ in v * (0.7 + 0.6 * roll("wp\(i)")) }
                st.assets = max(plan.founderPutIn, st.assets)
            }
            if i == 2 || i == 9 {
                for k in 0..<6 {
                    guard let stage = st.openStage else { break }
                    let id = "inv\(40 + k + i)"
                    let amount = max(CrowdStartupRules.minTicket(plan, stage: stage), 500)
                    if case .ok(let q) = CrowdStartupRules.investCheck(st, investorID: id, linkKeys: [id], accountWeeks: 40, amount: amount, today: today - 1 - k / 3) {
                        st.investments.append(.init(id: "\(st.id)-\(st.investments.count)", investorID: id, linkKey: id, stage: stage, amount: amount, percent: q.percent, day: today - 1 - k / 3))
                    }
                }
                book.viralTold.append(st.id)
            }
            if i == 13 {
                _ = CrowdStartupRules.fail(&st)
                st.founderFails += 1
            }
            book.startups.append(st)
        }
    }
}
