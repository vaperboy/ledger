import Foundation
import GameCore
import Countries

/// Customer reviews: one system for every trade. A company's stars come from its quality and reputation; customers write a
/// review now and then (more often for big tickets); the average of the stored reviews is the rating everyone sees (tenders,
/// the reviews screen, the market map). Rivals have a rating of their own.
/// Originals: `rvRate`, `ratingOf`, `rvWeek`, `starDist`, `reviewsOf` (engine/company/reviews.js) and `addReviews`/`avgRv`
/// (features/sales/trades_in_hours.js). Not ported: tourists writing from their own country (flag, "heard about you at home").
public enum Reviews {
    static let positive = ["Friendly staff and good quality.", "Fast service, will come back.", "Fair price for what you get.", "Exactly what we hoped for.",
                           "Clean, well run and professional.", "Staff really went the extra mile.", "Great value, easy to recommend."]
    static let middling = ["Okay, nothing special.", "Decent, but nothing to write home about.", "Fine for the price.", "Good once, uneven the next time.",
                           "Average. Could be better organised."]
    static let negative = ["Long wait and an unhelpful answer.", "Not what was promised.", "Quality has gone down.", "Rude staff and no apology.",
                           "Would not use again.", "Messy and badly organised."]
    static let pricey = ["Good, but quite expensive.", "Overpriced for what it is.", "Too expensive for the quality."]
    static let cheap = ["Very cheap and still good.", "Great prices.", "Cheap, and you can tell."]

    /// Fewest reviews before a rating is shown as a number. Original: `RV_MIN`.
    public static let minimumShown = 3

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: Int           // the running number of the review
        public var week: Int
        public var stars: Int
        public var text: String
        public var age: Int
        public var female: Bool
        public var nameSeed: Int
    }

    // MARK: Rate

    /// How often a customer writes a review about this trade. Original: `rvRate`.
    public static func rate(_ bd: Trade) -> Double {
        if ["fin", "energy", "hold", "rent"].contains(bd.family) { return 0.0015 }
        let b2b: Set<String> = ["factory", "engcons", "construction", "shipping", "trucking", "courier", "salmon", "farm", "mktg", "webdev", "staffing",
                                "acctfirm", "cons", "oilgas", "power", "fund"]
        return min(0.3, (b2b.contains(bd.id) ? 0.0015 : 0.006) * max(1, (bd.ticket / 40).squareRoot()))
    }

    // MARK: Writing reviews

    /// A week's reviews for trades that do not review job by job. Original: `rvWeek`.
    static func weekly(_ s: inout GameState, _ i: Int, _ bd: Trade) {
        guard s.companies[i].status == .open, bd.family != "project", s.companies[i].value("lastW")["units"].double > 0 else { return }
        let u = s.companies[i].value("lastW")["units"].double
        let acc = s.companies[i].num("rvF") + min(u * rate(bd), 30 + 3 * u.squareRoot())
        let n = Int(acc.rounded(.down))
        s.companies[i].set("rvF", acc - Double(max(0, n)))
        if n > 0 { for _ in 0..<min(n, 60) { add(&s, i, bias: 0) } }
    }

    /// One more review. Stars follow the company's rating (plus `bias` for a job gone wrong); the text fits the stars and the price.
    /// Original: `addReviews` / `reviewsOf`.
    public static func add(_ s: inout GameState, _ i: Int, bias: Double) {
        let co = s.companies[i]
        let n = co.int("rvN") + 1
        let mu = clamp(Pricing.rating(co) + bias, 1.2, 4.95)
        var h = HashedRandom("\(s.seed):rv:\(co.id):\(n)")
        let st = pickStar(&h, mu: mu)
        var tx = st >= 4 ? pick(&h, positive) : st == 3 ? pick(&h, middling) : pick(&h, negative)
        let price = co.priceLevel
        if price > 0, st <= 4, h.next() < 0.5 { tx = pick(&h, pricey) }
        else if price < 0, st >= 4, h.next() < 0.5 { tx = pick(&h, cheap) }
        let sweet = 24 + Double(abs(co.type.hashValueStable) % 28) + (price > 0 ? 6 : price < 0 ? -4 : 0)
        let gz = (h.next() + h.next() + h.next() - 1.5) * 2
        var age = st >= 4 ? sweet + gz * 9 : st <= 2 ? sweet + (h.next() < 0.5 ? -1 : 1) * (10 + h.next() * 10) + gz * 6 : sweet + gz * 14
        age = jsRound(max(18, min(78, age)))
        let sum0 = co.value("rvS").isNull ? Pricing.rating(co) * Double(co.int("rvN")) : co.num("rvS")
        var list = co.value("rv41").array
        list.append(.object(["c": .number(Double(n)), "w": .number(Double(s.week)), "st": .number(Double(st)), "tx": .string(tx), "a": .number(age),
                             "f": .bool(h.next() < 0.5), "k": .number(Double(Int(h.next() * 1_000_000)))]))
        if list.count > 200 { list.removeFirst(list.count - 200) }
        s.companies[i].set("rvN", n)
        s.companies[i].set("rvS", sum0 + Double(st))
        s.companies[i].set("rv41", .array(list))
        if st >= 5 && n % 3 == 0 { s.note("A 5-star review for \(co.name).", tone: "good", companyID: co.id) }
        else if st <= 1 { s.note("An unhappy review for \(co.name).", tone: "bad", companyID: co.id) }
    }

    static func pick(_ h: inout HashedRandom, _ list: [String]) -> String { list[Int(h.next() * Double(list.count)) % list.count] }

    /// A star count that fits the true rating. Original: `starDist`, `pickStar`.
    static func starDistribution(_ mu: Double) -> [Double] {
        let w = (1...5).map { s -> Double in exp(-pow(Double(s) - mu, 2) / 1.5) + (s == 1 ? 0.05 : 0) + (s == 5 ? 0.06 : 0) }
        let t = w.reduce(0, +)
        return w.map { $0 / t }
    }

    static func pickStar(_ h: inout HashedRandom, mu: Double) -> Int {
        var x = h.next()
        for (k, p) in starDistribution(mu).enumerated() { if x < p { return k + 1 }; x -= p }
        return 5
    }

    // MARK: Reading

    /// Number of reviews written so far.
    public static func count(_ co: Company) -> Int { co.int("rvN") }

    /// The rating shown: the average of real reviews, the quality-and-reputation rating until there are some. Original: `avgRv`.
    public static func rating(_ co: Company) -> Double {
        let n = co.int("rvN")
        return n > 0 && !co.value("rvS").isNull ? jsRound(co.num("rvS") / Double(n) * 10) / 10 : Pricing.rating(co)
    }

    /// The latest reviews of a company, newest first.
    public static func latest(_ co: Company, limit: Int = 30) -> [Entry] {
        co.value("rv41").array.suffix(limit).reversed().map {
            Entry(id: $0["c"].int, week: $0["w"].int, stars: $0["st"].int, text: $0["tx"].string, age: $0["a"].int, female: $0["f"].bool, nameSeed: $0["k"].int)
        }
    }

    /// How the stars are spread over the stored reviews: index 0 is one star.
    public static func histogram(_ co: Company) -> [Int] {
        var h = [0, 0, 0, 0, 0]
        for r in co.value("rv41").array { let st = r["st"].int; if (1...5).contains(st) { h[st - 1] += 1 } }
        return h
    }

    /// A reviewer's name, drawn from the company's country. Original: first name and the initial of the last.
    public static func reviewerName(_ e: Entry, country: Country) -> String {
        var h = HashedRandom("name:\(e.nameSeed)")
        let first = country.firstNames.isEmpty ? "Alex" : country.firstNames[Int(h.next() * Double(country.firstNames.count)) % country.firstNames.count]
        let last = country.lastNames.isEmpty ? "Smith" : country.lastNames[Int(h.next() * Double(country.lastNames.count)) % country.lastNames.count]
        return first + " " + String(last.prefix(1)) + "."
    }

    /// What a rival's customers write: stars and texts drawn around its rating, the same every time. Original: `reviewsOf` for a rival.
    public static func rivalLines(seed: Int, rivalID: Int, rating mu: Double, count: Int, week: Int, limit: Int = 8) -> [Entry] {
        (0..<min(limit, count)).map { k in
            var h = HashedRandom("\(seed):rv:r\(rivalID):\(count - k)")
            let st = pickStar(&h, mu: mu)
            let tx = st >= 4 ? pick(&h, positive) : st == 3 ? pick(&h, middling) : pick(&h, negative)
            return Entry(id: count - k, week: week - k * 2, stars: st, text: tx, age: 24 + Int(h.next() * 40), female: h.next() < 0.5, nameSeed: Int(h.next() * 1_000_000))
        }
    }

    /// A word for a rating. Original: `rvComment`.
    public static func word(_ r: Double) -> String {
        r >= 4.6 ? "Outstanding" : r >= 4.2 ? "Very good" : r >= 3.8 ? "Good" : r >= 3.4 ? "Decent" : r >= 3 ? "Mixed" : r >= 2.5 ? "Poor" : "Avoid"
    }

    /// A rival's rating, the same every time for this game. Original: `rivalRating`.
    public static func rivalRating(seed: Int, rivalID: Int, size: Double) -> Double {
        var h = HashedRandom("\(seed):rr:\(rivalID)")
        return jsRound(clamp(2.6 + h.next() * 1.9 + (size - 1) * 0.4, 1.8, 4.8) * 10) / 10
    }

    /// Reviews a rival has gathered so far, as the screen shows them. Original: `reviewList` (rival rows).
    public static func rivalReviewCount(_ bd: Trade, size: Double, week: Int) -> Int {
        let per = min(((bd.normalDemand == 0 ? 30 : bd.normalDemand) * 7) * size * 0.5, 600) * rate(bd)
        return Int(((80 + Double(week)) * per * 0.6).rounded(.down))
    }
}

extension String {
    /// A hash that does not change between runs (Swift's own `hashValue` is randomised).
    var hashValueStable: Int { var h = 0; for u in unicodeScalars { h = (h &* 31 &+ Int(u.value)) % 1000 }; return h }
}
