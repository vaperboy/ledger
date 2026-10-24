import Foundation
import GameCore
import Countries

/// How the other side of a discussion answers an offer. ONE module for every pay, price or terms discussion in the game
/// (hiring, pay raises, selling a company ...); callers supply the numbers, this decides the answer.
///
/// The other side has two figures the player never sees: where it opens (`opening`) and the worst it would settle for
/// (`reservation`). Its answer to an offer is one of
///  - accept: the offer meets the reservation;
///  - counter: it names a figure between its opening and its reservation, closer to the reservation each round, so the talk
///    usually moves towards a deal. Now and then the counter is unrealistic (`overreach`): well beyond the opening, in its own
///    favour, which the player has to judge against what the thing is normally worth;
///  - refuse: the offer is so far off that it is an insult (`insult`); no figure is named, but the round is used up;
///  - walk away: its patience is gone. The deal is off; the caller says so in words and, for a person, the person is gone.
///
/// Patience (rounds tolerated) rises with the level of the post (a senior person has more patience than a junior one) and with
/// the person's temperament; both come from `Resources/negotiation.json`, as do the temperaments, the insult line, the chance and
/// size of unrealistic counters and how long a talk is remembered. Nothing here is specific to a country, a role or a trade.
///
/// A talk that is still open is kept on the record it concerns (`State`, key `neg`; the key exists only while a talk is open), so a
/// saved game keeps it. The random numbers come from the game's own stream, so a talk replays exactly from the same seed.
public enum Negotiation {
    /// The way the other side wants the figure to go: a wage or a selling price up (`higher`), a buying price down (`lower`).
    public enum Direction: Sendable { case higher, lower }

    public struct Counter: Equatable, Sendable {
        public var amount: Double
        /// "My last word": the next failed offer ends the talk.
        public var isFinal: Bool
        public init(amount: Double, isFinal: Bool) { self.amount = amount; self.isFinal = isFinal }
    }

    public enum Answer: Equatable, Sendable { case accept, counter(Counter), refuse, walkAway }

    /// The answer, and (for tests and the audit trail, never for the screens) whether a counter was an unrealistic one.
    public struct Response: Equatable, Sendable {
        public var answer: Answer
        public var unrealistic = false
        public init(_ answer: Answer, unrealistic: Bool = false) { self.answer = answer; self.unrealistic = unrealistic }
    }

    /// The other side's hidden numbers.
    public struct Position: Equatable, Sendable {
        public var opening: Double
        public var reservation: Double
        public var direction: Direction
        public init(opening: Double, reservation: Double, direction: Direction) { self.opening = opening; self.reservation = reservation; self.direction = direction }

        /// Does the offer give them at least what they would settle for?
        public func accepts(_ offer: Double) -> Bool {
            let slack = max(abs(reservation), 1) * 1e-9
            return direction == .higher ? offer >= reservation - slack : offer <= reservation + slack
        }
        /// How close the offer is to the reservation, 1 = at it, less = worse for them.
        func fraction(of offer: Double) -> Double {
            guard offer > 0, reservation > 0 else { return direction == .higher ? 0 : 1 }
            return direction == .higher ? offer / reservation : reservation / offer
        }
    }

    // MARK: Data

    public struct Temperament: Equatable, Sendable {
        public var id: String
        /// Multiplies the rounds of patience.
        public var patience: Double
        /// More than 1: gives ground late; less than 1: early.
        public var stubbornness: Double
        /// Chance that a counter is unrealistic.
        public var overreach: Double
        /// The share of its opening it would settle for lies somewhere in this range (a different point for each person).
        public var reservation: ClosedRange<Double>
    }

    struct Tables {
        var base = 2.0, perLevel = 0.8
        var ranks: [String: Int] = [:]
        var temperaments: [String: Temperament] = [:]
        var order: [String] = []
        var byPersonality: [String: String] = [:]
        var overreach: ClosedRange<Double> = 0.25...0.8
        var insult = 0.7
        var memoryWeeks = 8
    }

    /// The raw data file (AutoHire reads its own section from it).
    static let data: JSONValue = {
        guard let url = Bundle.module.url(forResource: "negotiation", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return json
    }()

    static let tables: Tables = {
        let j = data
        var t = Tables()
        t.base = j["patience"]["base"].double; t.perLevel = j["patience"]["perLevel"].double
        t.ranks = j["ranks"].object.mapValues { $0.int }
        for (id, v) in j["temperaments"].object {
            let r = v["reservation"].array.map { $0.double }
            t.temperaments[id] = Temperament(id: id, patience: v["patience"].double, stubbornness: v["stubbornness"].double, overreach: v["overreach"].double,
                                             reservation: (r.first ?? 1)...(r.last ?? 1))
        }
        t.order = t.temperaments.keys.sorted()
        t.byPersonality = j["personality"].object.mapValues { $0.string }
        let o = j["overreach"].array.map { $0.double }
        if o.count == 2 { t.overreach = o[0]...o[1] }
        t.insult = j["insult"].double
        t.memoryWeeks = j["memoryWeeks"].int
        return t
    }()

    public static var temperamentIDs: [String] { tables.order }
    public static var insultLine: Double { tables.insult }
    public static var memoryWeeks: Int { tables.memoryWeeks }
    public static func temperament(id: String) -> Temperament? { tables.temperaments[id] }
    /// The chance that a counter from this temperament is unrealistic.
    public static func overreachChance(of t: Temperament) -> Double { t.overreach }

    /// How senior a post is, 0 and up (workers lowest). Unknown ranks count as the lowest.
    public static func level(of rank: String) -> Int { tables.ranks[rank] ?? 0 }

    /// A person's temperament follows their personality (the same in every talk); a counterpart without one gets a stable pick by `key`.
    public static func temperament(personality: String?, key: String) -> Temperament {
        if let p = personality, let id = tables.byPersonality[p], let t = tables.temperaments[id] { return t }
        let ids = tables.order
        guard !ids.isEmpty else { return Temperament(id: "none", patience: 1, stubbornness: 1, overreach: 0, reservation: 1...1) }
        let k = Int(HashedRandom.first("temper:\(key)") * Double(ids.count)) % ids.count
        return tables.temperaments[ids[k]]!
    }

    /// How many offers the other side will answer before it walks away.
    public static func patience(rank: String, temperament t: Temperament) -> Int {
        max(1, Int(((tables.base + tables.perLevel * Double(level(of: rank))) * t.patience).rounded()))
    }

    /// The other side's hidden position, from where it opens: the reservation is a stable point (per person, `key`) in its temperament's range.
    public static func position(opening: Double, direction: Direction, temperament t: Temperament, key: String) -> Position {
        let share = t.reservation.lowerBound + (t.reservation.upperBound - t.reservation.lowerBound) * HashedRandom.first("res:\(key)")
        let reservation = direction == .higher ? opening * share : opening / max(share, 0.01)
        return Position(opening: opening, reservation: reservation, direction: direction)
    }

    // MARK: A talk that is open

    public struct State: Equatable, Sendable {
        /// Who is across the table from them (the company that offers the job, ...); a talk with someone else starts afresh.
        public var party = 0
        /// Offers answered so far.
        public var round = 0
        public var lastOffer = 0.0
        /// The standing counter, 0 if none.
        public var counter = 0.0
        public var week = 0
        public init() {}
        public var isOpen: Bool { round > 0 }

        public var json: JSONValue {
            .object(["p": .number(Double(party)), "n": .number(Double(round)), "o": .number(lastOffer), "c": .number(counter), "w": .number(Double(week))])
        }
        public init(json j: JSONValue) {
            party = j["p"].int; round = j["n"].int; lastOffer = j["o"].double; counter = j["c"].double; week = j["w"].int
        }
        /// A talk remembered from `record` (key `neg`): kept if it was with the same party and not long ago, else a fresh one.
        public static func resume<R: JSONRecord>(_ record: R, party: Int, week: Int) -> State {
            let v = record.value("neg")
            guard !v.isNull else { var s = State(); s.party = party; return s }
            var s = State(json: v)
            if s.party != party || week - s.week > tables.memoryWeeks { s = State(); s.party = party }
            return s
        }
        /// Keep the talk on the record, or remove the key when nothing is open.
        public func store<R: JSONRecord>(in record: inout R) {
            if isOpen { record.set("neg", json) } else { record.raw.removeValue(forKey: "neg") }
        }
    }

    // MARK: The answer

    /// Answer one offer. `state` is updated (a round used, the standing counter); when the answer is accept or walk away the caller
    /// closes the talk (`State()`), and on a walk away tells the player in words. `currency`/`about` round a counter to a tidy figure
    /// in the other side's favour, so accepting it is always accepted.
    public static func respond(offer: Double, position p: Position, temperament t: Temperament, rank: String, state: inout State, week: Int,
                               currency: Currency, about: Double, random: inout DeterministicRandom) -> Response {
        if p.accepts(offer) { return Response(.accept) }
        let patience = patience(rank: rank, temperament: t)
        if state.round >= patience { return Response(.walkAway) }
        state.round += 1
        state.lastOffer = offer
        state.week = week
        let isFinal = state.round >= patience
        if p.fraction(of: offer) < tables.insult {
            state.counter = 0
            return Response(.refuse)
        }
        let progress = pow(Double(state.round) / Double(patience), t.stubbornness)
        var figure = p.opening + (p.reservation - p.opening) * progress
        var unrealistic = false
        if random.chance(t.overreach) {
            unrealistic = true
            let extra = random.range(tables.overreach.lowerBound, tables.overreach.upperBound)
            figure = p.direction == .higher ? figure * (1 + extra) : figure / (1 + extra)
        }
        let step = currency.stepSize(about: about)
        figure = p.direction == .higher ? (figure / step).rounded(.up) * step : (figure / step).rounded(.down) * step
        state.counter = figure
        return Response(.counter(Counter(amount: figure, isFinal: isFinal)), unrealistic: unrealistic)
    }
}
