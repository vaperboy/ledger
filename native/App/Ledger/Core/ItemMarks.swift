import SwiftUI
import GameCore
import Businesses
import Events
import Simulation

/// In-app markers: which rows of a Phone app are new since the player last opened it. The launcher badge reads the same feeds
/// (`UpdateFeed`), measured against the marks as they were when the app was opened (`visitBaselines`), so the two never disagree.
/// Item ids: messages "m<id>", market events "e<id>", news "n<week>|<text>", listings "l<id>", weather "w<title>".
/// A marker is cleared by `markItemSeen` (kept in `seenMarks.texts` as "i.<app>.<id>"; the keys are dropped when the launcher shows).
extension GameStore {
    private func itemKey(_ app: PhoneApp, _ id: String) -> String { "i." + app.rawValue + "." + id }

    /// The ids of one app that are newer than `base` (the marks as of the visit's start).
    func freshItemIDs(_ e: GameEngine, _ app: PhoneApp, base: UpdateMarks) -> Set<String> {
        var out: Set<String> = []
        for m in UpdateFeed.freshMessages(e, app, marks: base) { out.insert("m\(m.id)") }
        switch app {
        case .market:
            for ev in UpdateFeed.freshMarket(e, marks: base) { out.insert("e\(ev.id)") }
            for co in e.state.companies where co.status == .open && co.type != "hold" {
                guard let known = base.texts["rv.\(co.id)"] else { continue }
                let have: Set<String> = Set(known.split(separator: ",").map { (s: Substring) -> String in String(s) })
                for r in e.rivalRows(co) where !have.contains(String(r.id)) { out.insert("r\(co.id).\(r.id)") }
            }
        case .reviews:
            if let seen = base.ints["reviews"] {
                for co in ReviewsApp.companies(e) {
                    for l in e.reviewSummary(co, limit: 30).lines where e.state.week - l.weeksAgo > seen { out.insert(ReviewsApp.lineKey(e, co, l)) }
                }
            }
        case .stats, .achievements:
            if let seen = base.ints["tr." + app.rawValue] {
                for t in Trophies.entries(e.state) where !t.before {
                    if let w = t.reachedWeek, w > seen { out.insert("t" + t.id) }
                }
            }
        case .accounting:
            if base.ints["docrev"] != nil {
                for k in reviewDocKeys(e) where base.texts["dr." + k] == nil { out.insert(k) }
            }
        case .news:
            for n in UpdateFeed.freshNews(e, marks: base) { out.insert("n" + UpdateFeed.newsKey(n)) }
        case .marketplace:
            if let seen = base.ints["marketplace"] {
                for l in MarketplaceBridge.newestDay(e, after: seen) { out.insert("l" + l) }
            }
        case .weather:
            let sig: String? = base.texts["weather"]
            if sig != nil && sig != UpdateFeed.weatherSignature(e) {
                for w in e.bigWeatherWarnings() { out.insert("w" + w.title) }
            }
        default:
            break
        }
        return out
    }

    /// Called when an app is open: keeps the visit's starting marks and the ids that were new then (and any that arrived since).
    func refreshVisit(_ app: PhoneApp, before marks: UpdateMarks) {
        guard let e = engine else { return }
        if visitBaselines[app.rawValue] == nil { visitBaselines[app.rawValue] = marks }
        let base: UpdateMarks = visitBaselines[app.rawValue] ?? marks
        let ids: Set<String> = freshItemIDs(e, app, base: base)
        if visitFresh[app.rawValue] != ids { visitFresh[app.rawValue] = ids }
    }

    /// The launcher is showing: no app is open, so the next visit starts from fresh marks.
    func endVisits() {
        if !visitBaselines.isEmpty { visitBaselines = [:] }
        if !visitFresh.isEmpty { visitFresh = [:] }
        let stale: [String] = seenMarks.texts.keys.filter { (k: String) -> Bool in k.hasPrefix("i.") }
        if !stale.isEmpty {
            var s: UpdateMarks = seenMarks
            for k in stale { s.texts.removeValue(forKey: k) }
            seenMarks = s
            s.save("seen")
        }
    }

    /// True while the item was new when the app was opened and has not been seen since.
    func isNew(_ app: PhoneApp, _ id: String) -> Bool {
        guard visitFresh[app.rawValue]?.contains(id) == true else { return false }
        return seenMarks.texts[itemKey(app, id)] == nil
    }

    /// True when any item of the app whose id starts with `prefix` is still new (a tab or segment dot).
    func hasNew(_ app: PhoneApp, prefix: String) -> Bool {
        guard let ids = visitFresh[app.rawValue] else { return false }
        return ids.contains { (id: String) -> Bool in id.hasPrefix(prefix) && seenMarks.texts[itemKey(app, id)] == nil }
    }

    /// Ids of this app's fresh messages (optionally of one company; 0 = the player), so a row can carry one marker for its messages.
    func messageItemIDs(_ app: PhoneApp, companyID: Int?) -> [String] {
        guard let e = engine, let ids = visitFresh[app.rawValue] else { return [] }
        let hits: [Message] = e.state.inbox.filter { (m: Message) -> Bool in
            ids.contains("m\(m.id)") && (companyID == nil || m.companyID == companyID!)
        }
        return hits.map { (m: Message) -> String in "m\(m.id)" }
    }

    /// The ids of every rival of a company, comma separated (the rivals already known, so a new one can be marked).
    func rivalIDList(_ e: GameEngine, _ co: Company) -> String {
        e.rivalRows(co).map { (r: RivalRow) -> String in String(r.id) }.sorted().joined(separator: ",")
    }

    /// Accounting document rows under review, approved or declined ("d<company>.<doc>.<status>"): a changed status is a new key.
    func reviewDocKeys(_ e: GameEngine) -> [String] {
        var out: [String] = []
        for co in e.state.companies where co.status.isLive {
            let docs: [AccountingDocument] = e.companyDocuments(companyID: co.id, group: .applications, user: nil) ?? []
            for d in docs where d.status != "Not applied" { out.append("d\(co.id).\(d.id).\(d.status)") }
        }
        return out
    }

    /// Loan messages of the Bank (optionally one company; 0 = the player) that are still new, for the Loans tab dot.
    func loanMessageIDs(companyID: Int) -> [String] {
        guard let e = engine else { return [] }
        let ids: [String] = messageItemIDs(.bank, companyID: companyID)
        let hits: [Message] = e.state.inbox.filter { (m: Message) -> Bool in
            ids.contains("m\(m.id)") && (m.title + " " + m.body).lowercased().contains("loan")
        }
        return hits.map { (m: Message) -> String in "m\(m.id)" }
    }

    func markItemSeen(_ app: PhoneApp, _ id: String) {
        let k: String = itemKey(app, id)
        if seenMarks.texts[k] != nil { return }
        var s: UpdateMarks = seenMarks
        s.texts[k] = "1"
        // A document row's status is remembered for good (the visit keys above are dropped when the launcher shows).
        if app == .accounting && id.hasPrefix("d") { s.texts["dr." + id] = "1" }
        seenMarks = s
        s.save("seen")
    }
}
