import SwiftUI
import GameCore
import Businesses
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

    func markItemSeen(_ app: PhoneApp, _ id: String) {
        let k: String = itemKey(app, id)
        if seenMarks.texts[k] != nil { return }
        var s: UpdateMarks = seenMarks
        s.texts[k] = "1"
        seenMarks = s
        s.save("seen")
    }
}
