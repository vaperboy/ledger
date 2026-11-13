import Foundation
import GameCore
import Countries
import Employees

public enum FaceBook {
    public static let leaseWeeks = 8
    static let locksKey = "faceLocks"

    static let suitFamilies: Set<String> = ["fin", "rent"]
    static let suitTrades: Set<String> = ["cons", "webdev", "mktg", "law", "acctfirm", "staffing", "estate", "hotel", "realdev", "engcons", "event", "cardealer", "gamestudio"]
    static let handsOnRoles: Set<String> = ["cleaner", "helper", "caretaker", "guard", "driver", "handy", "labour", "housek", "cook", "chef", "chefP", "baker", "butcher",
                                            "whw", "mech", "carwash", "groom", "driverB", "truckd", "courier"]
    static let hotelSuitRoles: Set<String> = ["recept", "hm", "pm", "sales", "acct", "hr", "buyer", "consult", "projc", "dispatch", "compl"]

    public static func suitTrade(_ trade: Trade?) -> Bool {
        guard let trade else { return false }
        return suitFamilies.contains(trade.family) || suitTrades.contains(trade.id)
    }

    public static func style(for person: Person, trade: Trade?) -> FaceStyle {
        if person.role == "manager" || person.role == "fin" || !person.str("mtype").isEmpty { return .suit }
        guard let trade else { return .suit }
        guard suitTrade(trade) else { return .casual }
        if trade.id == "hotel" { return hotelSuitRoles.contains(person.role) ? .suit : .casual }
        return handsOnRoles.contains(person.role) ? .casual : .suit
    }

    public static func locks(_ s: GameState) -> Set<String> { Set((s.rest[locksKey]?.array ?? []).compactMap { FaceKey($0.string)?.string }) }

    static func setLocks(_ s: inout GameState, _ keys: Set<String>) { s.rest[locksKey] = .array(keys.sorted().map { .string($0) }) }

    static func taken(_ s: GameState) -> Set<String> {
        var t = locks(s)
        for p in s.people.values { if let k = FaceKey(p.faceKey) { t.insert(k.string) } }
        return t
    }

    public static func key(of personID: Int, in s: GameState) -> FaceKey? { FaceKey(s.people[personID]?.faceKey) }

    @discardableResult
    public static func assign(personID: Int, countryCode: String?, style: FaceStyle, state s: inout GameState) -> FaceKey? {
        guard var p = s.people[personID] else { return nil }
        if let k = FaceKey(p.faceKey) { return k }
        var used = taken(s)
        let traits = FaceTraits.of(p, countryCode: countryCode)
        guard let key = FaceCatalog.pick(traits, style: style, isTaken: { used.contains($0.string) }) else { return nil }
        used.insert(key.string)
        p.set("face", key.string); p.set("faceW", s.week)
        s.people[personID] = p
        if p.everHired || (p.employerID != 0 && p.employerID != -9) { var l = locks(s); l.insert(key.string); setLocks(&s, l) }
        return key
    }

    public static func release(personID: Int, state s: inout GameState) {
        guard var p = s.people[personID], p.faceKey != nil, !p.everHired, p.employerID == 0 || p.employerID == -9 else { return }
        p.raw.removeValue(forKey: "face"); p.raw.removeValue(forKey: "faceW")
        s.people[personID] = p
    }

    public static func sweep(_ s: inout GameState, data: GameData) {
        var used = taken(s)
        var l = locks(s)
        for id in s.people.keys.sorted() {
            guard var p = s.people[id] else { continue }
            let employed = p.employerID != 0 && p.employerID != -9
            let wear: String = employed ? Uniforms.id(trade: s.company(p.employerID).flatMap { data.catalog[$0.type] }, role: p.role) : ""
            if p.str("uni") != wear { p.set("uni", wear); s.people[id] = p }
            if employed && !p.everHired { p.set("everHired", true); s.people[id] = p }
            if employed || p.everHired {
                if let k = FaceKey(p.faceKey) { l.insert(k.string) }
                else {
                    let co = s.company(p.employerID)
                    let trade = co.flatMap { data.catalog[$0.type] }
                    let code = co?.countryCode ?? s.homeCountryCode
                    let traits = FaceTraits.of(p, countryCode: code)
                    if let key = FaceCatalog.pick(traits, style: style(for: p, trade: trade), isTaken: { used.contains($0.string) }) {
                        used.insert(key.string); l.insert(key.string)
                        p.set("face", key.string); p.set("faceW", s.week); s.people[id] = p
                    }
                }
            } else if p.faceKey != nil, p.employerID == -9 || s.week - p.int("faceW") >= leaseWeeks {
                p.raw.removeValue(forKey: "face"); p.raw.removeValue(forKey: "faceW")
                s.people[id] = p
            }
        }
        setLocks(&s, l)
    }
}
