import Foundation
import GameCore
import Countries
import Employees

/// Portraits for the people who work in companies. A portrait is a `FaceKey` ("c12.0") stored on the person record (`face`), so it is saved
/// and loaded with the game and an old save (no `face` anywhere) loads as it is.
///
/// Faces are exclusive. A key held by a living person, or listed in `faceLocks`, is never given to anyone else.
/// - A candidate gets a face when created (`assign`) and holds it as a lease: if the person is never hired, the face goes back to the pool after
///   `leaseWeeks` weeks (or when they take a job elsewhere, or `release` is called). Candidates made for automatic hires get none until hired.
/// - Once a person is hired (`Person.everHired`), the key is added to `faceLocks` and stays locked for ever, even after the person leaves.
/// - When every portrait is taken, nobody gets one and the screens show initials. A key is never reused.
/// Nothing here draws from the game's random generator, so it changes no simulation outcome.
public enum FaceBook {
    /// Weeks an unhired candidate keeps a portrait before it is given back.
    public static let leaseWeeks = 8
    static let locksKey = "faceLocks"

    // MARK: Which sheet

    /// Trades whose staff wear suits, by family (finance, property, holdings) ...
    static let suitFamilies: Set<String> = ["fin", "rent", "hold"]
    /// ... and by trade: consulting, agencies, law, accounting, estate, hotels (front desk), project developers, car sales, studios.
    static let suitTrades: Set<String> = ["cons", "webdev", "mktg", "law", "acctfirm", "staffing", "estate", "hotel", "realdev", "engcons", "event", "cardealer", "gamestudio"]
    /// Hands-on jobs that stay in casual dress even in a suit trade.
    static let handsOnRoles: Set<String> = ["cleaner", "helper", "caretaker", "guard", "driver", "handy", "labour", "housek", "cook", "chef", "chefP", "baker", "butcher",
                                            "whw", "mech", "carwash", "groom", "driverB", "truckd", "courier"]
    /// In a hotel only the front of house wears a suit.
    static let hotelSuitRoles: Set<String> = ["recept", "hm", "pm", "sales", "acct", "hr", "buyer", "consult", "projc", "dispatch", "compl"]

    /// Whether the people of a business wear suits: from its family and trade in the engine data.
    public static func suitTrade(_ trade: Trade?) -> Bool {
        guard let trade else { return false }
        return suitFamilies.contains(trade.family) || suitTrades.contains(trade.id)
    }

    /// The sheet for a person: managers, assistants and head-office people always the suit sheet; others by their business and job.
    /// `trade` is the business they work in (nil: group level, head office).
    public static func sheet(for person: Person, trade: Trade?) -> FaceSheetID {
        if person.role == "manager" || person.role == "fin" || !person.str("mtype").isEmpty { return .suits }
        guard let trade else { return .suits }
        guard suitTrade(trade) else { return .casual }
        if trade.id == "hotel" { return hotelSuitRoles.contains(person.role) ? .suits : .casual }
        return handsOnRoles.contains(person.role) ? .casual : .suits
    }

    // MARK: State

    /// Keys locked for ever (every person who was ever hired).
    public static func locks(_ s: GameState) -> Set<String> { Set((s.rest[locksKey]?.array ?? []).map { $0.string }) }

    static func setLocks(_ s: inout GameState, _ keys: Set<String>) { s.rest[locksKey] = .array(keys.sorted().map { .string($0) }) }

    /// Every key somebody holds or has locked.
    static func taken(_ s: GameState) -> Set<String> {
        var t = locks(s)
        for p in s.people.values { if let k = p.faceKey { t.insert(k) } }
        return t
    }

    /// The portrait of a person, if they hold one.
    public static func key(of personID: Int, in s: GameState) -> FaceKey? { FaceKey(s.people[personID]?.faceKey) }

    // MARK: Giving and taking back

    /// Give a person a portrait if they have none. Returns it (nil when none is free, or the person is unknown). A hired person's key is locked at once.
    @discardableResult
    public static func assign(personID: Int, countryCode: String?, sheet: FaceSheetID, state s: inout GameState) -> FaceKey? {
        guard var p = s.people[personID] else { return nil }
        if let k = FaceKey(p.faceKey) { return k }
        var used = taken(s)
        let traits = FaceTraits.of(p, countryCode: countryCode)
        guard let key = FaceCatalog.pick(traits, sheet: sheet, isTaken: { used.contains($0.string) }) else { return nil }
        used.insert(key.string)
        p.set("face", key.string); p.set("faceW", s.week)
        s.people[personID] = p
        if p.everHired || (p.employerID != 0 && p.employerID != -9) { var l = locks(s); l.insert(key.string); setLocks(&s, l) }
        return key
    }

    /// Give back the portrait of a person who was never hired (a candidate who is dropped). A hired person keeps theirs.
    public static func release(personID: Int, state s: inout GameState) {
        guard var p = s.people[personID], p.faceKey != nil, !p.everHired, p.employerID == 0 || p.employerID == -9 else { return }
        p.raw.removeValue(forKey: "face"); p.raw.removeValue(forKey: "faceW")
        s.people[personID] = p
    }

    /// Once a week: lock the portrait of everyone ever hired (giving a portrait to a hired person who has none), and take back the portraits
    /// of candidates who took a job elsewhere or were not hired within `leaseWeeks`.
    public static func sweep(_ s: inout GameState, data: GameData) {
        var used = taken(s)
        var l = locks(s)
        for id in s.people.keys.sorted() {
            guard var p = s.people[id] else { continue }
            let employed = p.employerID != 0 && p.employerID != -9
            if employed && !p.everHired { p.set("everHired", true); s.people[id] = p }
            if employed || p.everHired {
                if let k = p.faceKey { l.insert(k) }
                else {
                    let co = s.company(p.employerID)
                    let trade = co.flatMap { data.catalog[$0.type] }
                    let code = co?.countryCode ?? s.homeCountryCode
                    let traits = FaceTraits.of(p, countryCode: code)
                    if let key = FaceCatalog.pick(traits, sheet: sheet(for: p, trade: trade), isTaken: { used.contains($0.string) }) {
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
