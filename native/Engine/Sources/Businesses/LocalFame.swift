import Foundation
import GameCore
import Countries

public enum LocalFame {
    static let key = "fame"
    public static let demandCap = 0.05
    static let deadBand = 12.0
    static let pull = 0.12
    static let fineHit = 20.0
    static let pressLine = 40.0
    static let rivalLine = 70.0

    public struct Reading: Equatable, Sendable {
        public var cityID: String
        public var city: String
        public var score: Double
        public var word: String
        public var note: String
    }

    public static func score(_ s: GameState, city: String) -> Double { s.rest[key]?[city].double ?? 0 }

    public static func demandFactor(_ s: GameState, city: String) -> Double {
        let x = score(s, city: city)
        return x == 0 ? 1 : 1 + clamp(x, -100, 100) / 100 * demandCap
    }

    public static func word(_ x: Double) -> String {
        x >= 70 ? "Beloved" : x >= 40 ? "Well regarded" : x >= 15 ? "Liked" : x > -15 ? "Unknown" : x > -40 ? "Doubted" : x > -70 ? "Poor name" : "Shunned"
    }

    static func note(_ x: Double) -> String {
        let pct = Int(saturating: (abs(demandFactor(forScore: x) - 1) * 100).rounded())
        if x >= 15 { return "Customers lean your way: about +\(pct)% demand." }
        if x <= -15 { return "Customers hold back: about -\(pct)% demand." }
        return "No effect on demand yet."
    }

    static func demandFactor(forScore x: Double) -> Double { 1 + clamp(x, -100, 100) / 100 * demandCap }

    public static func target(reputations: [Double], fined: Int) -> Double {
        guard !reputations.isEmpty else { return 0 }
        let avg = reputations.reduce(0, +) / Double(reputations.count)
        let gap = avg - 50
        // Past the dead band the lean spans the whole scale: a perfect reputation reaches the top, the worst the bottom.
        let lean = abs(gap) <= deadBand ? 0 : (gap > 0 ? gap - deadBand : gap + deadBand) * 100 / (50 - deadBand)
        return clamp(lean - Double(fined) * fineHit, -100, 100)
    }

    public static func step(_ x: Double, toward t: Double) -> Double {
        let next = x + (t - x) * pull
        return (next * 100).rounded() / 100
    }

    public static func reading(_ s: GameState, _ co: Company, data: GameData) -> Reading? {
        guard !co.cityID.isEmpty else { return nil }
        let x = score(s, city: co.cityID)
        let name = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? co.cityID
        return Reading(cityID: co.cityID, city: name, score: x, word: word(x), note: note(x))
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        var cities: [String: [Company]] = [:]
        for co in s.companies where co.status == .open && !co.cityID.isEmpty { cities[co.cityID, default: []].append(co) }
        var book = s.rest[key] ?? .object([:])
        let known = Set(book.object.keys).union(cities.keys)
        for id in known.sorted() {
            let old = book[id].double
            let here = cities[id] ?? []
            let fined = here.filter { ($0.books.week["fine"] ?? 0) > 0 }.count
            let goal = here.isEmpty ? 0 : target(reputations: here.map { $0.reputation }, fined: fined)
            let new = step(old, toward: goal)
            if new == 0 && book[id].isNull { continue }
            book[id] = .number(new)
            report(&s, city: id, old: old, new: new, company: here.first, data: data)
        }
        if !book.object.isEmpty { s.rest[key] = book }
    }

    static func report(_ s: inout GameState, city id: String, old: Double, new: Double, company: Company?, data: GameData) {
        guard let co = company else { return }
        let name = data.countries.city(id, preferring: co.countryCode)?.city.name ?? id
        if old < pressLine && new >= pressLine {
            s.news("The local press in \(name) now speaks well of your businesses.", tone: "good", companyID: co.id)
        } else if old > -pressLine && new <= -pressLine {
            s.news("People in \(name) are talking badly about your businesses.", tone: "bad", companyID: co.id)
        }
        if old < rivalLine && new >= rivalLine {
            s.note("Rivals in \(name) now treat you as the name to beat.", tone: "good", companyID: co.id)
        } else if old > -rivalLine && new <= -rivalLine {
            s.note("Rivals in \(name) are using your bad name to win customers.", tone: "bad", companyID: co.id)
        }
    }
}
