import SwiftUI
import GameCore
import Businesses
import Simulation

struct UpdateMarks: Codable, Equatable {
    var ints: [String: Int] = [:]
    var texts: [String: String] = [:]

    static func load(_ name: String) -> UpdateMarks {
        guard let data = UserDefaults.standard.data(forKey: "updateMarks." + name), let m = try? JSONDecoder().decode(UpdateMarks.self, from: data) else { return UpdateMarks() }
        return m
    }

    func save(_ name: String) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "updateMarks." + name) }
    }
}

enum UpdateFeed {
    static let messageApps: [PhoneApp] = [.inbox, .bank, .market, .news, .airStay, .techPro, .atlas, .marketplace]

    static func app(of m: Message) -> PhoneApp {
        let f: String = m.from.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { (w: String) -> Bool in f.contains(w) } }
        if has(["airstay"]) { return .airStay }
        if has(["techpro"]) { return .techPro }
        if has(["atlas", "insurer"]) { return .atlas }
        if has(["marketplace"]) { return .marketplace }
        if has(["weather"]) { return .news }
        if has(["bank", "creditor"]) { return .bank }
        if has(["payroll", "tax", "accountant", "finance manager"]) { return .bank }
        if has(["market", "competition", "consumer authority", "tourism", "industry association", "business broker", "customers"]) { return .market }
        if has(["news"]) { return .news }
        return .inbox
    }

    static func maxMessageID(_ e: GameEngine) -> Int { e.state.inbox.map { (m: Message) -> Int in m.id }.max() ?? 0 }
    static func maxMarketID(_ e: GameEngine) -> Int { e.marketEvents(limit: 1).first?.id ?? 0 }
    static func freshListings(_ e: GameEngine, marks: UpdateMarks) -> Int {
        guard let seen = marks.ints["marketplace"] else { return 0 }
        return MarketplaceBridge.newestDay(e, after: seen).count
    }
    static func newsKey(_ n: NewsItem) -> String { "\(n.week)|\(n.text)" }
    static func newsSignature(_ e: GameEngine) -> String { e.news.first.map { (n: NewsItem) -> String in newsKey(n) } ?? "" }
    static func weatherSignature(_ e: GameEngine) -> String { e.bigWeatherWarnings().map { (w: WeatherEvents.BigWarning) -> String in w.title }.joined(separator: "|") }

    static func freshNews(_ e: GameEngine, marks: UpdateMarks) -> [NewsItem] {
        let all: [NewsItem] = e.news
        guard let sig = marks.texts["news"] else { return [] }
        let idx: Int = all.firstIndex(where: { (n: NewsItem) -> Bool in newsKey(n) == sig }) ?? min(all.count, 9)
        return Array(all.prefix(idx))
    }

    static func ownerRelevant(_ m: Message) -> Bool { m.isOwnerAddressed || m.handledBy.isEmpty }

    static func freshMessages(_ e: GameEngine, _ app: PhoneApp, marks: UpdateMarks) -> [Message] {
        guard let seen = marks.ints["m." + app.rawValue] else { return [] }
        return e.state.inbox.filter { (m: Message) -> Bool in m.id > seen && Self.app(of: m) == app }
    }

    static func freshMarket(_ e: GameEngine, marks: UpdateMarks) -> [MarketEvent] {
        guard let seen = marks.ints["market"] else { return [] }
        return e.marketEvents(limit: 30).filter { (m: MarketEvent) -> Bool in m.id > seen }
    }

    @MainActor static func count(_ e: GameEngine, _ app: PhoneApp, marks: UpdateMarks) -> Int {
        switch app {
        case .inbox:
            return e.state.inbox.filter { (m: Message) -> Bool in
                (m.status == "open" && m.isOwnerAddressed) || (!m.isRead && m.severity >= 2 && ownerRelevant(m))
            }.count
        case .market:
            return freshMarket(e, marks: marks).count + freshMessages(e, app, marks: marks).count
        case .news:
            let seenSig: String? = marks.texts["weather"]
            let unseen: Bool = seenSig != nil && seenSig != weatherSignature(e)
            return freshNews(e, marks: marks).count + (unseen ? e.bigWeatherWarnings().count : 0) + freshMessages(e, app, marks: marks).count
        case .marketplace:
            return freshListings(e, marks: marks) + freshMessages(e, app, marks: marks).count
        case .bank, .airStay, .techPro, .atlas:
            return freshMessages(e, app, marks: marks).count
        default:
            return 0
        }
    }
}

extension GameStore {
    /// Read from the cached badge table, which is rebuilt only when the game or the seen marks change.
    func appBadge(_ app: PhoneApp) -> Int {
        guard engine != nil else { return 0 }
        if let n = phoneBadges[app] { return n }
        return PhoneApp.launcher.contains(app) ? 0 : freshBadge(app)
    }

    private func freshBadge(_ app: PhoneApp) -> Int {
        guard let e = engine else { return 0 }
        return max(0, UpdateFeed.count(e, app, marks: seenMarks))
    }

    var phoneBadges: [PhoneApp: Int] {
        memo("badges") { (_: GameEngine) -> [PhoneApp: Int] in
            var out: [PhoneApp: Int] = [:]
            for app in PhoneApp.launcher {
                let n: Int = freshBadge(app)
                if n > 0 { out[app] = n }
            }
            return out
        } ?? [:]
    }

    var waitingCount: Int { phoneBadges.values.reduce(0, +) }

    private func fill(_ m: inout UpdateMarks, _ e: GameEngine) {
        let maxID: Int = UpdateFeed.maxMessageID(e)
        for app in UpdateFeed.messageApps {
            let k: String = "m." + app.rawValue
            if let v = m.ints[k], v <= maxID { continue }
            m.ints[k] = maxID
        }
        let ev: Int = UpdateFeed.maxMarketID(e)
        let oldEv: Int? = m.ints["market"]
        if oldEv == nil || oldEv! > ev { m.ints["market"] = ev }
        let posted: Int = MarketplaceBridge.newestPostedDay(e)
        let oldPosted: Int? = m.ints["marketplace"]
        if oldPosted == nil || oldPosted! > posted { m.ints["marketplace"] = posted }
        let oldNews: String? = m.texts["news"]
        let known: Bool = e.news.contains { (n: NewsItem) -> Bool in UpdateFeed.newsKey(n) == oldNews }
        if !known { m.texts["news"] = UpdateFeed.newsSignature(e) }
        if m.texts["weather"] == nil { m.texts["weather"] = UpdateFeed.weatherSignature(e) }
        for k in ["reviews"] {
            let old: Int? = m.ints[k]
            if old == nil || old! > e.state.week { m.ints[k] = e.state.week }
        }
        for co in e.state.companies where co.status == .open {
            let k: String = "rv.\(co.id)"
            if m.texts[k] == nil { m.texts[k] = rivalIDList(e, co) }
        }
    }

    func seedUpdateMarks() {
        guard let e = engine else { return }
        var s: UpdateMarks = seenMarks
        fill(&s, e)
        if s != seenMarks { seenMarks = s; s.save("seen") }
    }

    func markSeen(_ app: PhoneApp) {
        guard let e = engine else { return }
        var s: UpdateMarks = seenMarks
        refreshVisit(app, before: s)
        switch app {
        case .market: s.ints["market"] = UpdateFeed.maxMarketID(e)
        case .competition:
            s.ints["reviews"] = e.state.week
            for co in e.state.companies where co.status == .open { s.texts["rv.\(co.id)"] = rivalIDList(e, co) }
        case .news:
            s.texts["news"] = UpdateFeed.newsSignature(e)
            s.texts["weather"] = UpdateFeed.weatherSignature(e)
        case .marketplace: s.ints["marketplace"] = MarketplaceBridge.newestPostedDay(e)
        default: break
        }
        if UpdateFeed.messageApps.contains(app) { s.ints["m." + app.rawValue] = UpdateFeed.maxMessageID(e) }
        if s != seenMarks { seenMarks = s; s.save("seen") }
    }
}
