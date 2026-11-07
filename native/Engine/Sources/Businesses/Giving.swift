import Foundation
import GameCore
import Countries
import Finance

/// Giving back: sponsor the club, fund a scholarship, build a park or a hospital wing, start a foundation. Each leaves a named mark,
/// raises your standing in a city (a little more demand there) and adds to your legacy.
/// Originals: `GIVE`, `giveTo`, `giveWeek`, `ACT.give28`, `ACT.found28`, the 'gifts to the city' demand step
/// (features/player/giving_and_goals.js).
public enum Giving {
    public struct Gift: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var yearly: Bool
        public var baseCost: Double
        public var standing: Double
        public var legacy: Double
        public var imageKey: String
        public var imageGain: Double
        public var detail: String
    }

    public static let gifts: [Gift] = [
        Gift(id: "club", name: "Sponsor the local football club", yearly: true, baseCost: 250000, standing: 8, legacy: 15, imageKey: "care", imageGain: 2, detail: "Your name on the shirts and around the pitch. Everyone in town sees it every weekend."),
        Gift(id: "fest", name: "Sponsor the summer festival", yearly: true, baseCost: 400000, standing: 6, legacy: 12, imageKey: "bold", imageGain: 2, detail: "Bars, restaurants and shops in town feel it too."),
        Gift(id: "food", name: "Support the food bank", yearly: true, baseCost: 120000, standing: 3, legacy: 8, imageKey: "care", imageGain: 4, detail: "Quiet, steady help. People notice who shows up every year."),
        Gift(id: "schol", name: "Found a scholarship", yearly: false, baseCost: 2e6, standing: 4, legacy: 60, imageKey: "care", imageGain: 6, detail: "Pays for young people to study. Your staff are proud of it."),
        Gift(id: "park", name: "Build a park and playground", yearly: false, baseCost: 6e6, standing: 12, legacy: 90, imageKey: "care", imageGain: 4, detail: "A place families use every day."),
        Gift(id: "gallery", name: "Fund a museum gallery", yearly: false, baseCost: 15e6, standing: 10, legacy: 180, imageKey: "trust", imageGain: 3, detail: "Art, history, and your name above the door."),
        Gift(id: "wing", name: "Build a hospital wing", yearly: false, baseCost: 40e6, standing: 25, legacy: 400, imageKey: "trust", imageGain: 8, detail: "The biggest thing most people ever give. It will outlast every company you own."),
    ]
    public static func gift(_ id: String) -> Gift? { gifts.first { $0.id == id } }

    public struct Place: Equatable, Sendable { public var countryCode: String; public var cityID: String; public var name: String; public var key: String; public var standing: Double }
    public enum Result: Equatable, Sendable { case ok, notEnoughCash, unknown, alreadyDone }

    static func key(_ cc: String, _ city: String) -> String { cc + "|" + city }
    static func state(_ s: GameState) -> JSONValue { s.rest["give28"] ?? .object(["marks": .array([]), "rep": .object([:]), "yearly": .array([]), "found": .null]) }
    static func surname(_ s: GameState) -> String { s.player.name.split(separator: " ").last.map(String.init) ?? "You" }
    static func cost(_ g: Gift, _ s: GameState, _ data: GameData) -> Double {
        let cur = Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
        return roundTo(cur.scaledPrice(g.baseCost), step: 1000)
    }
    public static func cost(of id: String, _ s: GameState, _ data: GameData) -> Double { gift(id).map { cost($0, s, data) } ?? 0 }
    static func cityName(_ cc: String, _ city: String, _ data: GameData) -> String { data.countries[cc]?.city(city)?.name ?? city }

    /// The mark's text, with the city. Original: `g.mark(city)`.
    public static func markText(_ id: String, city: String, _ s: GameState) -> String {
        let sur = surname(s)
        switch id {
        case "club": return "\(city) FC, sponsored by \(sur)"
        case "fest": return "The \(city) summer festival, presented by \(sur)"
        case "food": return "Main supporter of the \(city) food bank"
        case "schol": return "The \(sur) Scholarship"
        case "park": return "\(sur) Park, \(city)"
        case "gallery": return "The \(sur) Gallery at the \(city) museum"
        default: return "The \(sur) Wing, \(city) Hospital"
        }
    }

    /// Cities where you work (and home), with your standing in each. Original: `cities()`.
    public static func places(_ s: GameState, _ data: GameData) -> [Place] {
        var seen: [String: (String, String)] = [:]
        for c in s.companies where c.status == .open { seen[key(c.countryCode, c.cityID)] = (c.countryCode, c.cityID) }
        if !s.player.cityID.isEmpty { seen[key(s.homeCountryCode, s.player.cityID)] = seen[key(s.homeCountryCode, s.player.cityID)] ?? (s.homeCountryCode, s.player.cityID) }
        let rep = state(s)["rep"]
        return seen.keys.sorted().map { k in Place(countryCode: seen[k]!.0, cityID: seen[k]!.1, name: cityName(seen[k]!.0, seen[k]!.1, data), key: k, standing: rep[k].double) }
    }

    public static func marks(_ s: GameState) -> [(name: String, yearly: Bool, week: Int)] { state(s)["marks"].array.map { ($0["name"].string, $0["y"].bool, $0["w"].int) } }
    public static func count(_ s: GameState) -> Int { state(s)["marks"].array.count + (state(s)["found"].isNull ? 0 : 1) }
    public static func isDone(_ s: GameState, giftID: String, placeKey: String) -> Bool { state(s)["marks"].array.contains { $0["k"].string == giftID && $0["key"].string == placeKey } }
    public static func foundation(_ s: GameState) -> (capital: Double, given: Double)? { let f = state(s)["found"]; return f.isNull ? nil : (f["cap"].double, f["given"].double) }
    public static func standing(_ s: GameState, countryCode: String, cityID: String) -> Double { state(s)["rep"][key(countryCode, cityID)].double }

    /// Give. Original: `giveTo(k, cc, city, fromFound)`.
    @discardableResult
    public static func give(_ s: inout GameState, giftID: String, countryCode cc: String, cityID city: String, data: GameData, fromFoundation: Bool = false) -> Result {
        guard let g = gift(giftID) else { return .unknown }
        let c = cost(g, s, data), nm = cityName(cc, city, data), k = key(cc, city)
        if !fromFoundation {
            if s.cash < c { return .notEnoughCash }
            Payments.playerPays(&s, c, label: "\(g.name) (\(nm))")
        }
        var st = state(s)
        var rep = st["rep"]; rep[k] = .number(min(100, rep[k].double + g.standing)); st["rep"] = rep
        s.rest["give28"] = st
        Press.moveImage(&s, g.imageKey, by: g.imageGain)
        Ambitions.addLegacy(&s, points: g.legacy, text: markText(g.id, city: nm, s), path: "give")
        let live = s.companies.indices.filter { s.companies[$0].status == .open }
        if g.id == "schol" { for i in live { s.companies[i].set("mood", min(100, (s.companies[i].value("mood").isNull ? 60 : s.companies[i].num("mood")) + 3)) } }
        if g.id == "fest" { for i in live where s.companies[i].cityID == city && ["venue", "retail"].contains(data.catalog[s.companies[i].type]?.family ?? "") { s.companies[i].awareness = min(100, s.companies[i].awareness + 4) } }
        if g.id == "club" { for i in live where s.companies[i].cityID == city { s.companies[i].awareness = min(100, s.companies[i].awareness + 3) } }
        st = state(s)
        var marks = st["marks"].array
        if !marks.contains(where: { $0["k"].string == g.id && $0["key"].string == k }) {
            marks.insert(.object(["k": .string(g.id), "key": .string(k), "cc": .string(cc), "city": .string(city), "w": .number(Double(s.week)), "name": .string(markText(g.id, city: nm, s)), "y": .bool(g.yearly)]), at: 0)
        }
        var yearly = st["yearly"].array
        if g.yearly && !fromFoundation && !yearly.contains(where: { $0["k"].string == g.id && $0["key"].string == k }) {
            yearly.append(.object(["k": .string(g.id), "key": .string(k), "cc": .string(cc), "city": .string(city), "next": .number(Double(s.week + 52))]))
        }
        st["marks"] = .array(marks); st["yearly"] = .array(yearly); s.rest["give28"] = st
        Press.add(&s, priority: g.yearly ? 3 : 4.5, head: g.yearly ? "\(s.player.name) backs \(markText(g.id, city: nm, s).lowercased())" : "\(markText(g.id, city: nm, s)) opens",
                  deck: g.yearly ? "" : "A gift from \(s.player.name) to \(nm).")
        return .ok
    }

    /// Put money into a foundation that gives about 4 % a year. Original: `ACT.found28`.
    @discardableResult
    public static func startFoundation(_ s: inout GameState, amount: Double, data: GameData) -> Result {
        guard foundation(s) == nil else { return .alreadyDone }
        if amount <= 0 { return .unknown }
        if s.cash < amount { return .notEnoughCash }
        let sur = surname(s)
        Payments.playerPays(&s, amount, label: "Endowment: the \(sur) Foundation")
        var st = state(s); st["found"] = .object(["cap": .number(amount), "w": .number(Double(s.week)), "next": .number(Double(s.week + 4)), "given": 0]); s.rest["give28"] = st
        let cur = Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
        Ambitions.addLegacy(&s, points: jsRound(min(500, amount / cur.scaledPrice(1e6) * 3)), text: "Started the \(sur) Foundation", path: "give")
        Press.moveImage(&s, "care", by: 6); Press.moveImage(&s, "trust", by: 4)
        Press.add(&s, priority: 5, head: "The \(sur) Foundation is born", deck: "\(s.player.name) gives a foundation its first endowment.")
        return .ok
    }

    /// Demand factor from standing in the company's city (up to +6 %). Original: the 'gifts to the city' step.
    public static func demandFactor(_ co: Company, _ s: GameState) -> Double {
        let v = state(s)["rep"][key(co.countryCode, co.cityID)].double
        return v > 0 ? 1 + min(0.06, v * 0.0008) : 1
    }

    /// Yearly sponsorships renew, standing fades, the foundation gives. Original: `giveWeek`.
    public static func weekly(_ s: inout GameState, data: GameData) {
        guard s.rest["give28"] != nil else { return }
        var st = state(s)
        var rep = st["rep"], marks = st["marks"].array
        var keep: [JSONValue] = []
        for y in st["yearly"].array {
            guard Double(s.week) >= y["next"].double, let g = gift(y["k"].string) else { keep.append(y); continue }
            let c = cost(g, s, data), nm = cityName(y["cc"].string, y["city"].string, data)
            if s.cash < c {
                s.note("You could not renew \(g.name.lowercased()) in \(nm). The sponsorship has ended.", tone: "bad")
                marks.removeAll { $0["k"].string == y["k"].string && $0["key"].string == y["key"].string }
                continue
            }
            Payments.playerPays(&s, c, label: "\(g.name) (\(nm))")
            rep[y["key"].string] = .number(min(100, rep[y["key"].string].double + g.standing * 0.6))
            Ambitions.addLegacy(&s, points: jsRound(g.legacy * 0.6), text: markText(g.id, city: nm, s) + ", another year", path: "give")
            var n = y; n["next"] = .number(Double(s.week + 52)); keep.append(n)
        }
        st["yearly"] = .array(keep); st["marks"] = .array(marks)
        if s.week % 13 == 0 { for (k, v) in rep.object { rep[k] = .number(max(0, v.double * 0.975)) } }
        st["rep"] = rep
        s.rest["give28"] = st
        if !st["found"].isNull, Double(s.week) >= st["found"]["next"].double {
            var f = st["found"]
            let grant = f["cap"].double * 0.04
            let cs = places(s, data)
            let cur = Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
            let mil = cur.scaledPrice(1e6)
            st = state(s); rep = st["rep"]
            for p in cs { rep[p.key] = .number(min(100, rep[p.key].double + min(10, grant / mil * 1.5 / Double(cs.count)))) }
            st["rep"] = .object(rep.object)
            f["given"] = .number(f["given"].double + grant); f["next"] = .number(Double(s.week + 52)); st["found"] = f; s.rest["give28"] = st
            let sur = surname(s)
            Ambitions.addLegacy(&s, points: jsRound(min(200, grant / mil * 4)), text: "The \(sur) Foundation gave \(cur.display(grant))", path: "give")
            Press.moveImage(&s, "care", by: 2)
            s.addMessage(kind: "info", from: "The \(sur) Foundation", title: "The foundation gave \(cur.display(grant)) this year",
                         body: "Grants to schools, clubs and people in need in \(cs.map { $0.name }.joined(separator: ", ")).", tone: "good")
        }
    }
}
