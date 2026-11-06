import SwiftUI
import GameCore
import Businesses
import Simulation

/// Last-seen markers of the Phone apps, kept in UserDefaults. `ints` holds message ids per app ("m.bank") and the highest market event id
/// ("market"); `texts` holds the newest news line ("news") and the weather warnings ("weather").
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

/// The apps whose updates are told by messages, and how a message finds its app.
enum UpdateFeed {
    static let messageApps: [PhoneApp] = [.inbox, .bank, .accounting, .market, .news, .weather, .stats, .airStay, .techPro, .atlas, .marketplace]

    /// The app a message belongs to, from who sent it. Anything unknown stays in the Inbox.
    static func app(of m: Message) -> PhoneApp {
        let f: String = m.from.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { (w: String) -> Bool in f.contains(w) } }
        if has(["airstay"]) { return .airStay }
        if has(["techpro"]) { return .techPro }
        if has(["atlas", "insurer"]) { return .atlas }
        if has(["marketplace"]) { return .marketplace }
        if has(["weather"]) { return .weather }
        if has(["bank", "creditor"]) { return .bank }
        if has(["payroll", "tax", "accountant", "finance manager"]) { return .accounting }
        if has(["market", "competition", "consumer authority", "tourism", "industry association", "business broker", "customers"]) { return .market }
        if has(["news"]) { return .news }
        if has(["trophy", "award", "ambition"]) { return .stats }
        return .inbox
    }

    static func maxMessageID(_ e: GameEngine) -> Int { e.state.inbox.map { (m: Message) -> Int in m.id }.max() ?? 0 }
    static func maxMarketID(_ e: GameEngine) -> Int { e.marketEvents(limit: 1).first?.id ?? 0 }
    /// Listings posted after the marker (the day of the newest listing seen), over every live company.
    static func freshListings(_ e: GameEngine, marks: UpdateMarks) -> Int {
        guard let seen = marks.ints["marketplace"] else { return 0 }
        return MarketplaceBridge.newestDay(e, after: seen).count
    }
    static func newsKey(_ n: NewsItem) -> String { "\(n.week)|\(n.text)" }
    static func newsSignature(_ e: GameEngine) -> String { e.news.first.map { (n: NewsItem) -> String in newsKey(n) } ?? "" }
    static func weatherSignature(_ e: GameEngine) -> String { e.bigWeatherWarnings().map { (w: WeatherEvents.BigWarning) -> String in w.title }.joined(separator: "|") }

    /// News lines newer than the marker (newest first; a marker that is gone counts the list, at most 9).
    static func freshNews(_ e: GameEngine, marks: UpdateMarks) -> [NewsItem] {
        let all: [NewsItem] = e.news
        guard let sig = marks.texts["news"] else { return [] }
        let idx: Int = all.firstIndex(where: { (n: NewsItem) -> Bool in newsKey(n) == sig }) ?? min(all.count, 9)
        return Array(all.prefix(idx))
    }

    /// A notice the owner should hear about: addressed to the owner, or to a desk with nobody handling it.
    static func ownerRelevant(_ m: Message) -> Bool { m.isOwnerAddressed || m.handledBy.isEmpty }

    static func freshMessages(_ e: GameEngine, _ app: PhoneApp, marks: UpdateMarks) -> [Message] {
        guard let seen = marks.ints["m." + app.rawValue] else { return [] }
        return e.state.inbox.filter { (m: Message) -> Bool in m.id > seen && Self.app(of: m) == app }
    }

    static func freshMarket(_ e: GameEngine, marks: UpdateMarks) -> [MarketEvent] {
        guard let seen = marks.ints["market"] else { return [] }
        return e.marketEvents(limit: 30).filter { (m: MarketEvent) -> Bool in m.id > seen }
    }

    /// The badge of one app against a set of markers; never negative.
    @MainActor static func count(_ e: GameEngine, _ app: PhoneApp, marks: UpdateMarks) -> Int {
        switch app {
        case .inbox:
            return e.state.inbox.filter { (m: Message) -> Bool in
                (m.status == "open" && m.isOwnerAddressed) || (!m.isRead && m.severity >= 2 && ownerRelevant(m))
            }.count
        case .market:
            return freshMarket(e, marks: marks).count + freshMessages(e, app, marks: marks).count
        case .news:
            return freshNews(e, marks: marks).count + freshMessages(e, app, marks: marks).count
        case .accounting:
            return PhoneAlerts.payroll(engine: e).count + freshMessages(e, app, marks: marks).count
        case .weather:
            let seenSig: String? = marks.texts["weather"]
            let unseen: Bool = seenSig != nil && seenSig != weatherSignature(e)
            return (unseen ? e.bigWeatherWarnings().count : 0) + freshMessages(e, app, marks: marks).count
        case .marketplace:
            return freshListings(e, marks: marks) + freshMessages(e, app, marks: marks).count
        case .bank, .stats, .airStay, .techPro, .atlas:
            return freshMessages(e, app, marks: marks).count
        default:
            return 0
        }
    }
}

extension GameStore {
    /// The update count behind an app's red badge: new since the app was last opened (Inbox: unread and open decisions).
    func appBadge(_ app: PhoneApp) -> Int {
        guard let e = engine else { return 0 }
        return max(0, UpdateFeed.count(e, app, marks: seenMarks))
    }

    /// Every launcher app with a badge above zero.
    var phoneBadges: [PhoneApp: Int] {
        var out: [PhoneApp: Int] = [:]
        for app in PhoneApp.launcher {
            let n: Int = appBadge(app)
            if n > 0 { out[app] = n }
        }
        return out
    }

    /// The number on the Phone tab: every badge added up.
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
        for k in ["reviews", "tr.stats", "tr.achievements"] {
            let old: Int? = m.ints[k]
            if old == nil || old! > e.state.week { m.ints[k] = e.state.week }
        }
        if m.ints["docrev"] == nil {
            m.ints["docrev"] = 1
            for k in reviewDocKeys(e) { m.texts["dr." + k] = "1" }
        }
        for co in e.state.companies where co.status == .open && co.type != "hold" {
            let k: String = "rv.\(co.id)"
            if m.texts[k] == nil { m.texts[k] = rivalIDList(e, co) }
        }
    }

    /// Seeds missing (or stale, from another game) markers to "now", so old items never replay as updates.
    func seedUpdateMarks() {
        guard let e = engine else { return }
        var s: UpdateMarks = seenMarks
        var a: UpdateMarks = announcedMarks
        fill(&s, e)
        fill(&a, e)
        if s != seenMarks { seenMarks = s; s.save("seen") }
        if a != announcedMarks { announcedMarks = a; a.save("announced") }
    }

    /// The player opened the app: everything up to now counts as seen.
    func markSeen(_ app: PhoneApp) {
        guard let e = engine else { return }
        var s: UpdateMarks = seenMarks
        refreshVisit(app, before: s)
        switch app {
        case .market:
            s.ints["market"] = UpdateFeed.maxMarketID(e)
            for co in e.state.companies where co.status == .open && co.type != "hold" { s.texts["rv.\(co.id)"] = rivalIDList(e, co) }
        case .reviews: s.ints["reviews"] = e.state.week
        case .stats, .achievements: s.ints["tr." + app.rawValue] = e.state.week
        case .news: s.texts["news"] = UpdateFeed.newsSignature(e)
        case .weather: s.texts["weather"] = UpdateFeed.weatherSignature(e)
        case .marketplace: s.ints["marketplace"] = MarketplaceBridge.newestPostedDay(e)
        default: break
        }
        if UpdateFeed.messageApps.contains(app) { s.ints["m." + app.rawValue] = UpdateFeed.maxMessageID(e) }
        if s != seenMarks { seenMarks = s; s.save("seen") }
    }

    private func isOpen(_ app: PhoneApp) -> Bool {
        guard tab == .phone, case .app(let a)? = phonePath.last else { return false }
        return a == app
    }

    private struct UpdateCandidate {
        var app: PhoneApp
        var severity: Int
        var count: Int
        var title: String
        var body: String
        var isAlert: Bool
        var target: BannerTarget = .none
        var hasOwnTarget = false
        /// The newest message of the app's update (0 = none) and the company it concerns (0 = none): the banner opens it directly.
        var newestID: Int = 0
        var companyID: Int = 0
    }

    /// A tap on an "N updates in <App>" banner: the app on its newest item, no question. Inbox: that message's popup; Bank: the account;
    /// Accounting: payroll; Market: News; Stats: Goals; the shops: the company's page.
    func openUpdate(_ app: PhoneApp, messageID: Int, companyID cid: Int) {
        switch app {
        case .inbox:
            if messageID != 0 { openMessage(messageID) } else { openApp(.inbox) }
        case .bank:
            openBank(cid != 0 ? BankAccountID.company(cid) : BankAccountID.personal)
        case .accounting:
            if cid != 0 { openAccounting(companyID: cid, payroll: true) } else { openApp(.accounting) }
        case .market:
            marketNewsPending = true
            openApp(.market, request: .market(companyID: 0))
        case .stats:
            openApp(.goals)
        case .airStay:
            openAirStay(companyID: cid)
        case .techPro:
            if cid != 0 { openTechPro(companyID: cid) } else { openApp(.techPro) }
        case .atlas:
            if cid != 0 { openAtlas(companyID: cid) } else { openApp(.atlas) }
        default:
            openApp(app)
        }
    }

    /// After a simulated day: one banner per app with new updates, the most severe first, at most two a day. Open decisions, payroll and
    /// weather warnings are standing alerts and come through the alert path, not here.
    func postUpdateBanners(_ e: GameEngine) {
        var found: [UpdateCandidate] = []
        for app in UpdateFeed.messageApps {
            let all: [Message] = UpdateFeed.freshMessages(e, app, marks: announcedMarks)
            // Routine (severity 1) notices and ones a desk already handled stay quiet: they are in the Inbox, not banners.
            let msgs: [Message] = all.filter { (m: Message) -> Bool in
                !(m.status == "open" && !m.options.isEmpty) && e.severityLevel(of: m) >= 2 && UpdateFeed.ownerRelevant(m)
            }
            var events: [BannerItem] = []
            if app == .market { events = marketBannerItems(e, after: announcedMarks.ints["market"] ?? Int.max) }
            let news: [NewsItem] = app == .news ? UpdateFeed.freshNews(e, marks: announcedMarks) : []
            let n: Int = msgs.count + events.count + news.count
            if n == 0 || isOpen(app) { continue }
            var sev = 1
            var alert = false
            for m in msgs {
                sev = max(sev, e.severityLevel(of: m))
                if e.severityLevel(of: m) >= 4 { alert = true }
            }
            for b in events { sev = max(sev, b.severity) }
            var c = UpdateCandidate(app: app, severity: sev, count: n, title: "\(n) updates in \(app.title)", body: "", isAlert: alert && sev >= 4)
            if let m = msgs.first {
                let t: String = e.displayText(m.title, companyID: m.companyID).tidyText
                if n == 1 { c.title = t; c.body = m.from } else { c.body = t }
                let newest: Message = msgs.max { (a: Message, b: Message) -> Bool in a.id < b.id } ?? m
                c.newestID = newest.id
                c.companyID = newest.companyID
            } else if let b = events.first {
                if n == 1 { c.title = b.title; c.body = b.body; c.target = b.target; c.hasOwnTarget = true } else { c.body = b.title }
            } else if let nw = news.first {
                if n == 1 { c.title = nw.text.tidyText } else { c.body = nw.text.tidyText }
            }
            found.append(c)
        }
        let ranked: [UpdateCandidate] = found.sorted { (a: UpdateCandidate, b: UpdateCandidate) -> Bool in a.severity > b.severity }
        let store: GameStore = self
        for c in ranked.prefix(2) {
            var item = BannerItem(key: "upd-\(c.app.rawValue)", source: c.app.title, title: c.title, body: c.body, glyph: c.app.glyph)
            item.severity = c.severity
            item.isAlert = c.isAlert
            item.lifetime = 4
            let app: PhoneApp = c.app
            let newestID: Int = c.newestID
            let cid: Int = c.companyID
            item.target = c.hasOwnTarget ? c.target : .place(app.title, { store.openUpdate(app, messageID: newestID, companyID: cid) })
            banners.post(item)
        }
        var a: UpdateMarks = UpdateMarks()
        fill(&a, e)
        if a != announcedMarks { announcedMarks = a; a.save("announced") }
    }
}
