import Foundation
import GameCore
import Countries
import Finance

/// What the weather brings besides customers: storm warnings, storm damage, securing your places, weather notices, tourist news
/// (a festival, a travel guide, a scare), and the forecast for the screen. The weather itself is `Weather`.
/// Originals: the 'weather warnings, storm damage, tourist news' step, `ACTS.wx56prep`, `X.stormName`, forecast part of `V.wx56`
/// (features/world/weather_and_tourism.js).
public enum WeatherEvents {
    public static let prepareAction = "wx56prep"
    public static func stormName(_ cc: String) -> String { CountryTraits.text(cc, "stormName") ?? "a storm" }
    static func cap(_ t: String) -> String { t.prefix(1).uppercased() + t.dropFirst() }
    public static let kindWords = ["sun": "Sunny", "mixed": "Mixed", "rain": "Rainy", "snow": "Snow", "heat": "Heatwave", "cold": "Cold snap", "storm": "Storm"]

    static func state(_ s: GameState) -> JSONValue { s.rest["wx56"] ?? .object(["ev": .array([]), "prep": .object([:]), "sent": .object([:])]) }

    // MARK: Reading

    public struct Forecast: Equatable, Sendable { public var week: Int; public var temperatureLow: Double; public var temperatureHigh: Double; public var kind: String; public var uncertain: Bool }

    /// This week and the next three, in a country. The third week is uncertain. Original: `V.wx56` forecast.
    public static func forecast(_ s: GameState, _ data: GameData, country cc: String) -> (now: WeekWeather, ahead: [Forecast]) {
        let t = data.balance.weather, seed = s.seed
        let now = Weather.draw(country: cc, week: s.week, seed: seed, tables: t)
        var out: [Forecast] = []
        for i in 1...3 {
            let y = Weather.draw(country: cc, week: s.week + i, seed: seed, tables: t)
            let sp = Double(i)
            let unsure = i == 3 && y.kind != "storm" && HashedRandom.first("\(seed):fc:\(cc):\(s.week + i)") < 0.3
            out.append(Forecast(week: s.week + i, temperatureLow: y.temperature - sp, temperatureHigh: y.temperature + sp, kind: unsure ? "mixed" : y.kind, uncertain: unsure))
        }
        return (now, out)
    }


    // MARK: Big event warning

    public struct BigWarning: Equatable, Sendable {
        public var countryCode: String
        public var week: Int
        /// "storm", "heat" or "flood"
        public var kind: String
        public var companyIDs: [Int]
        public var title: String
    }

    /// Storms, heatwaves and floods (a week of near-constant heavy rain) due this week or in the next two, per country where an open
    /// company stands, with the companies that can be hit. Reads the same draws as `forecast`; changes nothing.
    public static func bigWarnings(_ s: GameState, _ data: GameData) -> [BigWarning] {
        let t = data.balance.weather
        let open = s.companies.filter { $0.status == .open }
        var out: [BigWarning] = []
        for cc in Array(Set(open.map { $0.countryCode })).sorted() {
            for i in 0...2 {
                let w = Weather.draw(country: cc, week: s.week + i, seed: s.seed, tables: t)
                let kind = w.kind == "storm" ? "storm" : w.kind == "heat" ? "heat" : (w.kind == "rain" && w.rainyDays >= 6) ? "flood" : ""
                guard !kind.isEmpty else { continue }
                let hit = open.filter { $0.countryCode == cc && (kind == "heat" || physical($0, data)) }
                guard !hit.isEmpty else { continue }
                let name = kind == "storm" ? cap(stormName(cc)) : kind == "heat" ? "A heatwave" : "Flooding"
                let when = i == 0 ? "this week" : i == 1 ? "next week" : "in two weeks"
                out.append(BigWarning(countryCode: cc, week: s.week + i, kind: kind, companyIDs: hit.map { $0.id }, title: "\(name) \(when) in \(data.countries[cc]?.name ?? cc)"))
                break
            }
        }
        return out
    }

    /// Tourist events running in a country. Original: `S.wx56.ev`.
    public static func touristEvents(_ s: GameState, country cc: String) -> [(text: String, factor: Double, from: Int, until: Int, city: String?)] {
        state(s)["ev"].array.filter { $0["cc"].string == cc && $0["end"].int > s.week }.map { ($0["t"].string, $0["f"].double, $0["w0"].int, $0["end"].int, $0["city"].isNull ? nil : $0["city"].string) }
    }

    /// How a company is moved this week: weather and tourists, as shares against normal. Original: the line on the "This week" card.
    public static func companyLine(_ s: GameState, _ data: GameData, companyID: Int) -> (weather: Double, tourists: Double, workingTime: Double, kind: String)? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return nil }
        let e = Weather.effect(for: co, trade: bd, week: s.week, seed: s.seed, tables: data.balance.weather)
        let w = World(state: s, data: data)
        let ts = DemandModel.touristShare(co, bd, w)
        let tf = ts > 0.01 ? 1 + ts * (DemandModel.touristSeason(co, w) - 1) : 1
        return (e.demand, tf, e.capacity, Weather.draw(country: co.countryCode, week: s.week, seed: s.seed, tables: data.balance.weather).kind)
    }

    static func physical(_ co: Company, _ data: GameData) -> Bool {
        co.value("prem")["m2"].double > 0 && !["fin", "hold", "club"].contains(data.catalog[co.type]?.family ?? "")
    }

    // MARK: Weekly

    public static func weekly(_ s: inout GameState, data: GameData) {
        let ccs = Array(Set(s.companies.filter { $0.status == .open }.map { $0.countryCode })).sorted()
        let t = data.balance.weather
        for cc in ccs {
            let L = s.companies.filter { $0.status == .open && $0.countryCode == cc }
            let cur = Currency(country: data.countries.resolve(cc, orHome: cc), rates: ExchangeRates(drift: s.exchangeRates.values))
            // the storm that just passed
            let now = Weather.draw(country: cc, week: s.week, seed: s.seed, tables: t)
            let key = "\(cc):\(s.week)"
            if now.kind == "storm" {
                let prep = state(s)["prep"][key].bool
                var hit = 0
                for co in L where physical(co, data) {
                    guard s.random.chance(prep ? 0.04 : 0.22) else { continue }
                    let amt = roundTo(cur.scaledPrice(8000 + s.random.range(0, 1) * 52000) * pow(max(0.5, co.size), 0.7), step: 500)
                    loss(&s, companyID: co.id, amount: amt, data: data)
                    hit += 1
                    s.note("\(cap(stormName(cc))) damaged \(co.name): about \(cur.display(amt))\(co.value("ins")["prop"].bool ? ", mostly paid by the insurance" : " (not insured)").", tone: "bad", companyID: co.id)
                }
                if hit == 0 && prep && !L.isEmpty { s.note("The storm passed. Your places were secured and nothing was damaged.", tone: "good") }
                var st = state(s); var p = st["prep"]; p[key] = .null; st["prep"] = p; s.rest["wx56"] = st
            }
            // next week's weather: a warning when it matters
            let nx = Weather.draw(country: cc, week: s.week + 1, seed: s.seed, tables: t)
            let nkey = "\(cc):\(s.week + 1)"
            if state(s)["sent"][nkey].bool { continue }
            let countryName = data.countries[cc]?.name ?? cc
            if nx.kind == "storm" && L.contains(where: { physical($0, data) }) {
                var st = state(s); var sent = st["sent"]; sent[nkey] = true; st["sent"] = sent; s.rest["wx56"] = st
                let P = L.filter { physical($0, data) }
                let cost = roundTo(P.reduce(0) { $0 + cur.scaledPrice(3500) * pow(max(0.5, $1.size), 0.7) }, step: 500)
                s.addMessage(kind: "ask", from: "Weather service", title: "\(cap(stormName(cc))) is coming to \(countryName) next week",
                             body: "Strong winds and heavy rain are forecast. Places that are not secured can be damaged: roofs, windows, signs, stock and equipment. Securing \(P.count) \(P.count > 1 ? "places" : "place") (shutters, sandbags, moving stock and equipment) costs about \(cur.display(cost)). Outdoor work and travel will slow down either way.",
                             companyID: P[0].id, tone: "bad", status: "open",
                             options: [.option("Secure the places", "\(cur.display(cost))"), .option("Take the risk", "")],
                             action: prepareAction, data: .object(["cos": .array(P.map { .number(Double($0.id)) }), "cost": .number(cost), "k": .string(nkey)]), expiresWeek: s.week + 1)
            } else if nx.kind == "heat" || nx.kind == "cold" || (nx.kind == "snow" && !nx.snowIsNormal) {
                let aff = L.filter { co in
                    guard let bd = data.catalog[co.type] else { return false }
                    let e = Weather.effect(for: co, trade: bd, week: s.week + 1, seed: s.seed, tables: t)
                    return abs(e.demand - 1) >= 0.08 || e.capacity < 0.95
                }
                guard !aff.isEmpty else { continue }
                var st = state(s); var sent = st["sent"]; sent[nkey] = true; st["sent"] = sent; s.rest["wx56"] = st
                let lines = aff.prefix(4).map { co -> String in
                    let e = Weather.effect(for: co, trade: data.catalog[co.type]!, week: s.week + 1, seed: s.seed, tables: t)
                    var txt = ""
                    if abs(e.demand - 1) >= 0.08 { txt += e.demand > 1 ? "about \(Int(jsRound((e.demand - 1) * 100)))% more customers" : "about \(Int(jsRound((1 - e.demand) * 100)))% fewer customers" }
                    if e.capacity < 0.95 { txt += (txt.isEmpty ? "" : ", ") + "less working time" }
                    return "\(co.name): \(txt)."
                }
                s.addMessage(kind: "info", from: "Weather service", title: "\(kindWords[nx.kind] ?? nx.kind) in \(countryName) next week (\(Int(nx.temperature))°)",
                             body: lines.joined(separator: " "), companyID: aff[0].id, tone: "n")
            }
            // tourist news: about one a year per country, only where visitors matter to you
            let T = L.filter { co in data.catalog[co.type].map { DemandModel.touristShare(co, $0, World(state: s, data: data)) >= 0.06 } ?? false }
            if !T.isEmpty && !state(s)["ev"].array.contains(where: { $0["cc"].string == cc && $0["end"].int > s.week }) && s.random.chance(1.0 / 45) {
                let co = T[Int(s.random.range(0, 1) * Double(T.count))], city = data.countries.city(co.cityID, preferring: cc)?.city.name ?? "town"
                let cur2 = data.countries[cc]?.currencyCode ?? "local currency"
                let kinds: [(String, Double, Int, [String], Bool)] = [
                    ("fest", 1.45, 2, ["\(city) hosts a big music festival", "a major sports final comes to \(city)", "\(city) hosts an international trade fair", "a famous food festival comes to \(city)"], true),
                    ("guide", 1.15, 16, ["\(city) is named one of the places to visit this year in an international travel guide"], true),
                    ("scare", 0.75, 5, ["A travel warning keeps visitors away from \(countryName)", "An airline strike cancels flights to \(countryName)"], false),
                    ("cheap", 1.12, 12, ["The \(cur2) is weak, so \(countryName) is cheap for visitors"], false)]
                let k = kinds[Int(s.random.range(0, 1) * Double(kinds.count))]
                let text = k.3[Int(s.random.range(0, 1) * Double(k.3.count))]
                var st = state(s)
                var ev = st["ev"].array
                ev.append(.object(["cc": .string(cc), "city": k.4 ? .string(co.cityID) : .null, "f": .number(k.1), "w0": .number(Double(s.week + 1)), "end": .number(Double(s.week + 1 + k.2)), "t": .string(text)]))
                ev = ev.filter { $0["end"].int > s.week - 52 }
                st["ev"] = .array(ev); s.rest["wx56"] = st
                let who = T.filter { !k.4 || $0.cityID == co.cityID }.prefix(4).map { c -> String in
                    "\(c.name) (\(Int(jsRound(DemandModel.touristShare(c, data.catalog[c.type]!, World(state: s, data: data)) * 100)))% of its customers are visitors)" }
                s.addMessage(kind: "info", from: "Tourism board", title: cap(text),
                             body: "\(k.1 > 1 ? "More visitors than usual" : "Fewer visitors than usual") for about \(k.2) weeks\(k.4 ? " in \(city)" : ""). \(who.joined(separator: ", ")).", companyID: co.id, tone: k.1 > 1 ? "good" : "bad")
            }
        }
        var st = state(s); var sent = st["sent"]
        for (k, _) in sent.object { if let w = Int(k.split(separator: ":").last ?? ""), w < s.week - 2 { sent[k] = .null } }
        st["sent"] = sent; if s.rest["wx56"] != nil || !st["ev"].array.isEmpty { s.rest["wx56"] = st }
    }

    /// An insured loss: property insurance pays all but the excess. Original: `applyFx({ loss }, { cat: 'prop' })`.
    static func loss(_ s: inout GameState, companyID: Int, amount amt: Double, data: GameData) {
        guard let i = s.companyIndex(companyID) else { return }
        if s.companies[i].value("ins")["prop"].bool {
            let cur = World(state: s, data: data).currency(s.companies[i])
            let paid0 = amt - min(amt, cur.scaledPrice(10000))
            let paid = Advisers.claimPaid(&s, i, paid: paid0)
            if paid > 0 { Payments.companyReceives(&s, companyID: companyID, amount: paid, category: nil, label: "Insurance payout"); Payments.book(&s, companyID: companyID, category: "loss", amount: -paid) }
        }
        Payments.companyPays(&s, companyID: companyID, amount: amt, category: "loss", label: "Storm damage")
    }

    /// Answer the storm warning: secure the places (option 0) or take the risk. Original: `ACTS.wx56prep`.
    public static func answerPrepare(_ s: inout GameState, data: GameData, message m: Message, option idx: Int) {
        guard idx == 0 else { return }
        let d = m.value("data")
        let P = d["cos"].array.compactMap { s.company($0.int) }.filter { $0.status == .open }
        guard !P.isEmpty else { return }
        let each = d["cost"].double / Double(P.count)
        for co in P { Payments.companyPays(&s, companyID: co.id, amount: each, category: "oth", label: "Securing for the storm") }
        var st = state(s); var p = st["prep"]; p[d["k"].string] = true; st["prep"] = p; s.rest["wx56"] = st
    }
}
