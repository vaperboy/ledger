import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Makes sure every game day brings the player at least one event or small decision.
public enum DailyBeat {
    static let key = "beat"
    /// Set on the messages a filler event makes.
    public static let fillerKey = "filler"
    /// An event used to fill a quiet day waits this many weeks before it can fill another.
    public static let repeatWeeks = 4

    struct Pick {
        var index: Int
        var event: GameEvent
        var pack: PackEvent?
        var weight: Double
        var id: String { pack?.id ?? event.id }
    }

    /// When today brought the player nothing, fires one light event from the company event libraries.
    /// Returns the event's id, or nil when the day already had news or nothing fits.
    @discardableResult
    public static func ensure(_ s: inout GameState, fresh: [Message], library: EventLibrary, data: GameData, context fc: FinanceContext) -> String? {
        guard s.rest["ldr"] != nil, !s.isGameOver else { return nil }
        if fresh.contains(where: { (m: Message) -> Bool in m.isOwnerAddressed }) || !s.feedToday().isEmpty { return nil }
        let waiting: Bool = s.inbox.contains { (m: Message) -> Bool in m.status == "open" && m.isOwnerAddressed && !m.options.isEmpty }
        let pool: [Pick] = candidates(s, library: library, data: data, decisionsWaiting: waiting)
        guard let last = pool.last else { return nil }
        var h = HashedRandom("\(s.seed):beat:\(s.week):\(s.day)")
        let total: Double = pool.reduce(0) { (acc: Double, p: Pick) -> Double in acc + p.weight }
        var roll: Double = h.next() * total
        var pick: Pick = last
        for p in pool {
            roll -= p.weight
            if roll <= 0 { pick = p; break }
        }
        let before: Set<Int> = Set(s.inbox.map { (m: Message) -> Int in m.id })
        if let pe = pick.pack {
            EventPack.fire(&s, companyIndex: pick.index, pe, data: data, context: fc)
        } else {
            let co: Company = s.companies[pick.index]
            let ctx = EventEngine.context(for: co, data: data, country: World(state: s, data: data).country(co))
            EventEngine.fire(&s, companyIndex: pick.index, pick.event, ctx: ctx, data: data, context: fc)
        }
        // Marked, so the events' own odds and pacing can still be read apart from the filler.
        for k in s.inbox.indices where !before.contains(s.inbox[k].id) { s.inbox[k].set(fillerKey, true) }
        remember(&s, pick.id)
        return pick.id
    }

    /// Light events only: a small question while no other answer is waiting, or good news that changes nothing. Never bad news.
    /// Good news that brings money, customers or reputation keeps to its own odds: one on every quiet day would add up to a fortune.
    static func isLight(_ e: GameEvent, decisionsWaiting: Bool) -> Bool {
        guard e.tone != "bad", !e.text.isEmpty, !e.blocking, e.weight > 0 else { return false }
        if e.options.contains(where: { (o: GameEvent.Option) -> Bool in !o.effects["special"].isNull }) { return false }
        if e.options.isEmpty { return e.tone == "good" && !hasEffects(e.automaticEffects) }
        return !decisionsWaiting
    }

    static func hasEffects(_ fx: JSONValue) -> Bool {
        if case .object(let o) = fx { return !o.isEmpty }
        return !fx.isNull
    }

    static func candidates(_ s: GameState, library: EventLibrary, data: GameData, decisionsWaiting: Bool) -> [Pick] {
        let used: JSONValue = s.rest[key]?["used"] ?? .null
        func fresh(_ id: String) -> Bool { used[id].isNull || s.week - used[id].int >= repeatWeeks }
        var out: [Pick] = []
        for i in s.companies.indices where s.companies[i].status == .open {
            let co: Company = s.companies[i]
            guard let bd = data.catalog[co.type], CompanyWeek.isSupported(bd) else { continue }
            let solo: Bool = co.staff.isEmpty && co.managerID == nil
            let ctx = EventEngine.context(for: co, data: data, country: World(state: s, data: data).country(co))
            for id in bd.eventIDs where !library.special.contains(id) && fresh(id) {
                guard let e = library[id], isLight(e, decisionsWaiting: decisionsWaiting) else { continue }
                if e.minimumCompanyAgeWeeks > 0 && s.week - co.foundedWeek < e.minimumCompanyAgeWeeks { continue }
                if co.staff.isEmpty && EventEngine.mentionsStaff(e) { continue }
                if solo && !EventEngine.soloAllowed(id, co) { continue }
                let fit: Double = e.condition?.evaluate(ctx.variables) ?? 1
                guard fit > 0 else { continue }
                out.append(Pick(index: i, event: e, pack: nil, weight: e.weight * fit))
            }
            let hasInvoices: Bool = !co.receivables.isEmpty
            let hasLoan: Bool = s.loans.contains { (l: Loan) -> Bool in l.companyID == co.id && l.balance > 0 }
            let hasPremises: Bool = co.value("prem")["m2"].double > 0
            for pe in EventPack.events where pe.severity <= 1 && fresh(pe.id) {
                guard isLight(pe.event, decisionsWaiting: decisionsWaiting), !pe.countryWide, pe.weather.isEmpty, pe.months.isEmpty,
                      EventPack.appliesTo(pe, trade: bd, country: co.countryCode) else { continue }
                if pe.needsStaff && co.staff.isEmpty { continue }
                if solo && EventEngine.mentionsStaff(pe.event) { continue }
                if (pe.needsInvoices && !hasInvoices) || (pe.needsLoan && !hasLoan) || (pe.needsPremises && !hasPremises) { continue }
                out.append(Pick(index: i, event: pe.event, pack: pe, weight: pe.weight))
            }
        }
        return out
    }

    static func remember(_ s: inout GameState, _ id: String) {
        var b: JSONValue = s.rest[key] ?? .object([:])
        var used: [String: JSONValue] = b["used"].object
        used = used.filter { (pair: (key: String, value: JSONValue)) -> Bool in s.week - pair.value.int < repeatWeeks }
        used[id] = .number(Double(s.week))
        b["used"] = .object(used)
        b["n"] = .number(Double(b["n"].int + 1))
        s.rest[key] = b
    }
}
