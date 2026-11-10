import SwiftUI
import GameCore
import Businesses
import Events
import Simulation

extension GameStore {
    private func itemKey(_ app: PhoneApp, _ id: String) -> String { "i." + app.rawValue + "." + id }

    func freshItemIDs(_ e: GameEngine, _ app: PhoneApp, base: UpdateMarks) -> Set<String> {
        var out: Set<String> = []
        for m in UpdateFeed.freshMessages(e, app, marks: base) { out.insert("m\(m.id)") }
        switch app {
        case .competition:
            for co in e.state.companies where co.status == .open {
                guard let known = base.texts["rv.\(co.id)"] else { continue }
                let have: Set<String> = Set(known.split(separator: ",").map { (s: Substring) -> String in String(s) })
                for r in e.rivalRows(co) where !have.contains(String(r.id)) { out.insert("r\(co.id).\(r.id)") }
            }
            if let seen = base.ints["reviews"] {
                for co in CompetitionApp.reviewCompanies(e) {
                    for l in e.reviewSummary(co, limit: 30).lines where e.state.week - l.weeksAgo > seen { out.insert(CompetitionApp.lineKey(e, co, l)) }
                }
            }
        case .news:
            for n in UpdateFeed.freshNews(e, marks: base) { out.insert("n" + UpdateFeed.newsKey(n)) }
            let sig: String? = base.texts["weather"]
            if sig != nil && sig != UpdateFeed.weatherSignature(e) {
                for w in e.bigWeatherWarnings() { out.insert("w" + w.title) }
            }
        case .marketplace:
            if let seen = base.ints["marketplace"] {
                for l in MarketplaceBridge.newestDay(e, after: seen) { out.insert("l" + l) }
            }
        default:
            break
        }
        return out
    }

    func refreshVisit(_ app: PhoneApp, before marks: UpdateMarks) {
        guard let e = engine else { return }
        if visitBaselines[app.rawValue] == nil { visitBaselines[app.rawValue] = marks }
        let base: UpdateMarks = visitBaselines[app.rawValue] ?? marks
        let ids: Set<String> = freshItemIDs(e, app, base: base)
        if visitFresh[app.rawValue] != ids { visitFresh[app.rawValue] = ids }
    }

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

    func isNew(_ app: PhoneApp, _ id: String) -> Bool {
        guard visitFresh[app.rawValue]?.contains(id) == true else { return false }
        return seenMarks.texts[itemKey(app, id)] == nil
    }

    func messageItemIDs(_ app: PhoneApp, companyID: Int?) -> [String] {
        guard let e = engine, let ids = visitFresh[app.rawValue] else { return [] }
        let hits: [Message] = e.state.inbox.filter { (m: Message) -> Bool in
            ids.contains("m\(m.id)") && (companyID == nil || m.companyID == companyID!)
        }
        return hits.map { (m: Message) -> String in "m\(m.id)" }
    }

    func rivalIDList(_ e: GameEngine, _ co: Company) -> String {
        e.rivalRows(co).map { (r: RivalRow) -> String in String(r.id) }.sorted().joined(separator: ",")
    }

    func loanMessageIDs() -> [String] {
        guard let e = engine else { return [] }
        let ids: [String] = messageItemIDs(.bank, companyID: nil)
        let hits: [Message] = e.state.inbox.filter { (m: Message) -> Bool in
            ids.contains("m\(m.id)") && (m.title + " " + m.body).lowercased().contains("loan")
        }
        return hits.map { (m: Message) -> String in "m\(m.id)" }
    }

    func markItemSeen(_ app: PhoneApp, _ id: String) {
        let k: String = itemKey(app, id)
        if seenMarks.texts[k] != nil || pendingSeen.contains(k) { return }
        pendingSeen.append(k)
        guard !seenFlushScheduled else { return }
        seenFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self?.flushSeenItems()
        }
    }

    private func flushSeenItems() {
        seenFlushScheduled = false
        guard !pendingSeen.isEmpty else { return }
        var s: UpdateMarks = seenMarks
        for k in pendingSeen { s.texts[k] = "1" }
        pendingSeen.removeAll()
        Motion.animate(Motion.quickAnimation) { seenMarks = s }
        s.save("seen")
    }
}
