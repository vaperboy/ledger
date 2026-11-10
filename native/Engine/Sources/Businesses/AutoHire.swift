import Foundation
import GameCore
import Countries

public enum AutoHire {
    public struct Hirer: Equatable, Sendable {
        public var reading: Double
        public var push: Double
        public var breadth: Double
        public init(reading: Double, push: Double, breadth: Double) { self.reading = reading; self.push = push; self.breadth = breadth }
    }

    struct Tables {
        var owner = Hirer(reading: 0, push: 0, breadth: 0)
        var experienceFull = 1.0
        var readingPeople = 0.0, readingExperience = 0.0
        var pushFin = 0.0, pushSales = 0.0, pushExperience = 0.0
        var weigh = (0.0, 1.0), open = (1.0, 1.0), meet = (1.0, 1.0), raise = (0.0, 0.0)
        var ceiling = 1.0
        var minSkill = 0.0
    }

    static let tables: Tables = {
        let j = Negotiation.data["autoHire"]
        func pair(_ k: String) -> (Double, Double) { let a = j[k].array.map { $0.double }; return (a.first ?? 0, a.last ?? 0) }
        var t = Tables()
        t.owner = Hirer(reading: j["owner"]["reading"].double, push: j["owner"]["push"].double, breadth: j["owner"]["breadth"].double)
        t.experienceFull = max(1, j["experienceFull"].double)
        t.readingPeople = j["reading"]["people"].double; t.readingExperience = j["reading"]["experience"].double
        t.pushFin = j["push"]["fin"].double; t.pushSales = j["push"]["sales"].double; t.pushExperience = j["push"]["experience"].double
        t.weigh = pair("weigh"); t.open = pair("open"); t.meet = pair("meet"); t.raise = pair("raise")
        t.ceiling = j["ceiling"].double
        t.minSkill = j["minSkill"].double
        return t
    }()

    static func lerp(_ r: (Double, Double), _ t: Double) -> Double { r.0 + (r.1 - r.0) * t }

    public static var ownerHirer: Hirer { tables.owner }

    public static func hirer(person n: Person?) -> Hirer {
        guard let n = n, !n.value("stats").isNull else { return tables.owner }
        let st = n.value("stats")
        let t = tables
        let exp = min(1, n.num("exp") / t.experienceFull)
        return Hirer(reading: clamp(t.readingPeople * st["people"].double / 100 + t.readingExperience * exp, 0, 1),
                     push: clamp(t.pushFin * st["fin"].double / 100 + t.pushSales * st["sales"].double / 100 + t.pushExperience * exp, 0, 1),
                     breadth: clamp(ManagerModel.leadership(n), 0, 1))
    }

    public static func hirer(of co: Company, state s: GameState) -> Hirer {
        hirer(person: co.managerID.flatMap { s.people[$0] })
    }

    public struct Deal: Equatable {
        public var person: Person
        public var price: Double
        public var perceived: Double
        public var rounds: Int
    }

    static func perceivedSkill(_ p: Person, _ h: Hirer) -> Double { p.skill + (p.claimedSkill - p.skill) * (1 - h.reading) }

    static func weighed(_ n: Int, _ h: Hirer) -> Int { min(n, max(1, Int(saturating: (Double(n) * lerp(tables.weigh, h.breadth)).rounded(.up)))) }

    static func bestDeal(_ candidates: [Person], hirer h: Hirer, rank: String, floor: Double, currency: Currency, about: Double,
                         fair: (Person, Double) -> Double, factor: (Person) -> Double, state s: inout GameState) -> Deal? {
        let pool = Array(candidates.prefix(weighed(candidates.count, h)))
        let seen = pool.map { ($0, perceivedSkill($0, h)) }
        let able = seen.filter { $0.1 >= tables.minSkill }
        var best: Deal?
        for (p, perceived) in (able.isEmpty ? seen : able) {
            guard let (price, rounds) = haggle(p, fair: fair(p, perceived), floor: floor, hirer: h, rank: rank, factor: factor(p), currency: currency, about: about, state: &s) else { continue }
            let deal = Deal(person: p, price: price, perceived: perceived, rounds: rounds)
            if best == nil || Hiring.valueScore(skill: perceived, price: price) > Hiring.valueScore(skill: best!.perceived, price: best!.price) { best = deal }
        }
        return best
    }

    static func haggle(_ p: Person, fair: Double, floor: Double, hirer h: Hirer, rank: String, factor: Double, currency: Currency, about: Double,
                       state s: inout GameState) -> (price: Double, rounds: Int)? {
        let t = tables
        let step = currency.stepSize(about: about)
        func up(_ x: Double) -> Double { (x / step).rounded(.up) * step }
        let ceiling = max(up(fair * t.ceiling), floor)
        let meet = lerp(t.meet, h.push), raise = lerp(t.raise, h.push)
        var offer = max(floor, currency.roundedStep(fair * lerp(t.open, h.push), about: about))
        var talk = Negotiation.State()
        for _ in 0..<64 {
            offer = min(offer, ceiling)
            let reply = Hiring.probe(p, offer: offer, factor: factor, rank: rank, talk: &talk, currency: currency, about: about, state: &s)
            switch reply.answer {
            case .accept: return (offer, talk.round + 1)
            case .walkAway: return nil
            case .refuse:
                if offer >= ceiling { return nil }
                offer = max(offer + step, up(offer * (1 + raise)))
            case .counter(let c):
                if c.amount <= ceiling {
                    let next = offer + (c.amount - offer) * meet
                    if c.isFinal || meet >= 1 || next >= c.amount { return (c.amount, talk.round + 1) }
                    offer = max(offer + step, up(next))
                } else {
                    if offer >= ceiling || c.isFinal { return nil }
                    offer = max(offer + step, up(offer + (ceiling - offer) * meet))
                }
            }
        }
        return nil
    }

    @discardableResult
    public static func hireWorker(role: String, companyID: Int, candidates: [Person], hirer given: Hirer? = nil, terms: Hiring.Terms = Hiring.Terms(),
                                  state s: inout GameState, data: GameData) -> Person? {
        guard let ci = s.companyIndex(companyID), !candidates.isEmpty else { return nil }
        let co = s.companies[ci]
        let h = given ?? hirer(of: co, state: s)
        let world = World(state: s, data: data)
        let market = Hiring.marketWage(role: role, company: co, state: s, data: data)
        var factors: [Int: Double] = [:]
        for p in candidates { factors[p.id] = Hiring.talkFactor(person: p, terms: terms, company: co, state: s, data: data) }
        let deal = bestDeal(candidates, hirer: h, rank: "worker", floor: world.minimumWage(co), currency: world.currency(co), about: 100,
                            fair: { p, perceived in market * Hiring.askSpread(skill: perceived, experience: p.num("exp")) },
                            factor: { factors[$0.id] ?? 1 }, state: &s)
        guard let d = deal, Hiring.hire(d.person.id, into: companyID, monthlyWage: d.price, state: &s, data: data, terms: terms) == .ok else { return nil }
        return s.people[d.person.id]
    }

    public static func bestManagerDeal(candidates: [Person], companyID: Int, hirer given: Hirer? = nil, state s: inout GameState, data: GameData) -> Deal? {
        guard let ci = s.companyIndex(companyID), !candidates.isEmpty else { return nil }
        let co = s.companies[ci]
        let h = given ?? hirer(of: co, state: s)
        let world = World(state: s, data: data)
        let cityWage = world.city(co)?.wage ?? 1, infl = world.inflationIndex, heads = Double(co.staff.count)
        return bestDeal(candidates, hirer: h, rank: "manager", floor: world.minimumWage(co), currency: world.currency(co), about: 500,
                        fair: { p, perceived in ManagerModel.askingPay(heads: heads, skill: perceived, tier: p.value("tier").isNull ? "mid" : p.str("tier"), experience: p.num("exp"), cityWage: cityWage, inflation: infl) },
                        factor: { _ in 1 }, state: &s)
    }
}
