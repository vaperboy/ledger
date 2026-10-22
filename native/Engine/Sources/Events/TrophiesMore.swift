import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// More of the trophy wall, for systems the first port did not have: acquisitions, chains, franchise units, review counts, R&D,
/// luxury pieces, gifts, long tenure, the main office, and sales from abroad. Original: features/player/moments_and_trophies.js (round 28a and 56).
/// They are added to `Trophies.all` and kept in the same record (`rest["ach28"]`), so saves are unchanged.
enum TrophiesMore {
    static func ladder(_ pre: String, _ group: String, _ rungs: [(String, String, Double)], _ value: @escaping (Trophies.Facts) -> Double, text: @escaping (Double) -> String) -> [Trophies.Trophy] {
        Trophies.ladder(pre, group, rungs, test: { f, v in value(f) >= v }, text: { _, v in text(v) })
    }

    static func chainMax(_ s: GameState) -> Int { Chains.all(s).map { Chains.stores(s, $0).count }.max() ?? 0 }
    static func franchiseUnits(_ f: Trophies.Facts) -> Int { f.live.reduce(0) { $0 + $1.value("fr")["units"].array.count } }
    static func owned(_ s: GameState, _ test: (Luxury.Piece) -> Bool) -> Bool { Luxury.pieces(s).contains(where: test) }
    static func tenure(_ f: Trophies.Facts) -> Int { f.live.flatMap { $0.staff }.map { f.s.week - $0.hiredWeek }.max() ?? 0 }
    static func reviewed(_ f: Trophies.Facts, reviews: Int, stars: Double) -> Company? {
        f.live.first { $0.int("rvN") >= reviews && Reviews.rating($0) >= stars }
    }

    /// Your place among companies in your country by sales (nil without a ranking). Original: `R27.myRank('cc','rev')`.
    static func rankInCountry(_ f: Trophies.Facts) -> Int? { CompanyRanking.yourRank(f.s, data: f.data, scope: .country, metric: .revenue)?.rank }
    static func countryName(_ f: Trophies.Facts) -> String { f.data.countries.resolve(f.s.homeCountryCode, orHome: f.s.homeCountryCode).name }

    static let list: [Trophies.Trophy] = {
        var L: [Trophies.Trophy] = []
        func one(_ id: String, _ name: String, _ group: String, _ t: @escaping (Trophies.Facts) -> String?) { L.append(Trophies.Trophy(id: id, name: name, group: group, test: t)) }
        one("acq", "First acquisition", "first") { f in (f.s.rest["amb27"]?["cnt"]["buy"].double ?? 0) > 0 ? "You bought a competitor." : nil }
        one("give", "First gift to the city", "first") { f in Giving.count(f.s) > 0 ? "Your name is on something that is not a business." : nil }
        one("g10", "A city remembers", "legacy") { f in Giving.count(f.s) >= 10 ? "Ten gifts to the places you work in." : nil }
        one("stars", "A 4.5-star business", "market") { f in reviewed(f, reviews: 50, stars: 4.5).map { "Customers rate \($0.name) \(String(format: "%.1f", Reviews.rating($0))) stars." } }
        one("st48", "Loved by customers", "market") { f in reviewed(f, reviews: 500, stars: 4.8) != nil ? "A company with 4.8 stars from more than 500 reviews." : nil }
        one("tyall", "Every trade", "trades") { f in let n = f.data.catalog.order.filter { $0 != "hold" }.count; return f.types >= n ? "You have run \(n) different kinds of business." : nil }
        one("rd", "Something new", "trades") { f in f.live.contains { !Development.finished($0).isEmpty } ? "A company of yours developed something new that customers wanted." : nil }
        one("ten10", "Ten years with you", "people") { f in tenure(f) >= 520 ? "Someone on your staff has worked with you for ten years." : nil }
        one("mgr10", "A manager for ten years", "people") { f in
            f.live.first { $0.managerID != nil && !$0.value("mgrW0").isNull && f.s.week - $0.int("mgrW0") >= 520 }
                .map { c in "\(f.s.people[c.managerID!]?.name ?? "Your manager") has run \(c.name) for ten years." } }
        one("hq5", "A real main office", "people") { f in (f.s.rest["office"]?["staff"].array.count ?? 0) >= 5 ? "Five people work at your main office." : nil }
        one("abr50", "More abroad than at home", "world") { f in Ambitions.abroadShare(f.s, f.data) >= 0.5 ? "Half your sales now come from abroad." : nil }
        one("lx1", "Something beautiful", "legacy") { f in owned(f.s) { _ in true } ? "Your first piece from Aurum." : nil }
        one("lxj", "Wheels up", "legacy") { f in owned(f.s) { $0.item.category == "jets" } ? "You have your own jet." : nil }
        one("lxy", "On the water", "legacy") { f in owned(f.s) { $0.item.category == "yachts" } ? "You have a yacht." : nil }
        one("lxe", "Land of your own", "legacy") { f in owned(f.s) { $0.item.category == "estates" } ? "You own an estate." : nil }
        one("lxi", "An island", "legacy") { f in owned(f.s) { $0.item.id == "e2" } ? "A whole island is yours." : nil }
        one("lxm", "On the museum wall", "legacy") { f in owned(f.s) { $0.use == "museum" } ? "A work from your collection hangs in a museum." : nil }
        one("lxw", "Paid for itself", "legacy") { f in owned(f.s) { $0.use == "charter" || $0.use == "rent" } ? "Something you own earns its keep." : nil }
        one("lxc5", "A car collection", "legacy") { f in Luxury.pieces(f.s).filter { $0.item.category == "cars" }.count >= 5 ? "Five cars in the garage." : nil }
        one("no1", "No. 1 in a market", "market") { f in
            Ambitions.marketsLed(f.s, f.data).first.map { m in
                m.kind == .national ? "Nobody sells more here than you."
                    : "Nobody sells more \(MarketMap.label(m, data: f.data, withCity: false).lowercased()) in \(f.data.countries.city(m.cityID, preferring: m.countryCode)?.city.name ?? m.cityID) than you." } }
        one("top10", "Top 10 in your country", "market") { f in
            rankInCountry(f).flatMap { $0 <= 10 ? "Only \($0 - 1) \($0 == 2 ? "company" : "companies") in \(countryName(f)) sell more than you." : nil } }
        one("team56", "A management team", "people") { f in
            f.live.contains { c in
                let slots = ManagerModel.teamSlots(f.s, companyID: c.id, data: f.data).filter { $0.personID != nil }
                return slots.contains { $0.key == "ceo" } && slots.filter { ManagerModel.teamRoles.contains(where: { r in r.key == $0.key }) }.count >= 2
            } ? "A company with a managing director and its own department heads." : nil }
        L += ladder("n1", "market", [("3", "No. 1 in three markets", 3), ("10", "No. 1 in ten markets", 10)],
                    { Double(Ambitions.marketsLed($0.s, $0.data).count) }, text: { "Nobody sells more than you in \(Int($0)) markets." })
        L += Trophies.ladder("rk", "market", [("50", "Top 50 in the country", 50), ("3", "Top 3 in the country", 3), ("1", "The biggest in the country", 1)],
                             test: { f, v in Double(rankInCountry(f) ?? Int.max) <= v },
                             text: { f, v in v == 1 ? "No company in \(countryName(f)) sells more than you." : "Your group is among the \(Int(v)) biggest in \(countryName(f))." })
        L += ladder("ch", "trades", [("3", "A chain of three", 3), ("10", "A chain of ten", 10), ("25", "A chain of twenty-five", 25)],
                    { Double(chainMax($0.s)) }, text: { "One of your chains has \(Int($0)) stores." })
        L += ladder("fr", "trades", [("1", "First franchisee", 1), ("5", "Five franchise units", 5), ("25", "Twenty-five franchise units", 25), ("100", "A hundred franchise units", 100)],
                    { Double(franchiseUnits($0)) }, text: { "\(Int($0)) \($0 == 1 ? "franchisee runs" : "franchise units run") under your name." })
        return L
    }()
}
