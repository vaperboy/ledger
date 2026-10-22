import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// More of the trophy wall, for systems the first port did not have: acquisitions, chains, franchise units, review counts, R&D,
/// luxury pieces, gifts, long tenure, the main office, and sales from abroad. Original: features/player/moments_and_trophies.js (round 28a and 56).
/// They are added to `Trophies.all` and kept in the same record (`rest["ach28"]`), so saves are unchanged.
///
/// Still not ported: No. 1 in a market, country rank and "a management team" (market shares and rank lists of your own, and the CEO and
/// department-head team of one company, are not in the native game yet).
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
        L += ladder("ch", "trades", [("3", "A chain of three", 3), ("10", "A chain of ten", 10), ("25", "A chain of twenty-five", 25)],
                    { Double(chainMax($0.s)) }, text: { "One of your chains has \(Int($0)) stores." })
        L += ladder("fr", "trades", [("1", "First franchisee", 1), ("5", "Five franchise units", 5), ("25", "Twenty-five franchise units", 25), ("100", "A hundred franchise units", 100)],
                    { Double(franchiseUnits($0)) }, text: { "\(Int($0)) \($0 == 1 ? "franchisee runs" : "franchise units run") under your name." })
        return L
    }()
}
