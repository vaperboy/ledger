import Foundation
import GameCore
import Countries
import Finance

/// What owning things does besides their value: fame, rest, a cheaper start abroad with a jet, serious buyers, the yacht dinner,
/// the tax office looking at an oversized company car, the bank's margin call on a loan against the collection, your own wine in
/// your restaurants; and your own tiredness (long weeks, burn-out) which a home of your own eases.
/// Originals: `perks`, the 'fame', 'window.abroadFee', 'proposeBuy.terms' steps, `dinner`, the year-end and loan checks of the
/// `week.after` step (features/player/lifestyle.js); the vineyard and castle steps (estates.js); `fatigueWeek`, `capHours`
/// (features/people/owner_hours_clients_assistants.js).
public extension Luxury {
    struct Perks: Equatable, Sendable {
        public var home: Bool, jet: Bool, yacht: Bool, serious: Bool, museum: Bool
        public var fame: Double
    }

    /// Original: `LIFE.perks()`.
    static func perks(_ s: GameState) -> Perks {
        let list = record(s).compactMap { x in item(x["k"].string).map { (x, $0) } }
        let home = list.contains { $0.1.category == "homes" && $0.0["co"].int == 0 && $0.0["use"].string != "rent" }
        let jet = list.contains { $0.1.category == "jets" }, yacht = list.contains { $0.1.category == "yachts" }
        let serious = list.contains { ($0.1.category == "cars" && $0.1.price >= 2500000) || ($0.1.category == "watches" && $0.1.price >= 1000000) }
        let museum = list.contains { $0.1.category == "art" && $0.0["use"].string == "museum" }
        return Perks(home: home, jet: jet, yacht: yacht, serious: serious, museum: museum,
                     fame: (home ? 3 : 0) + (jet ? 2 : 0) + (yacht ? 2 : 0) + (serious ? 1 : 0) + (museum ? 1 : 0))
    }

    /// Added to how well known you are: what you own, plus a castle open for events. Original: the two 'fame' steps.
    static func fameBonus(_ s: GameState) -> Double {
        let castleOpen = record(s).contains { $0["k"].string == "e5" && $0["co"].int == 0 && $0["mode"].string != "private" }
        return perks(s).fame + (castleOpen ? 2 : 0)
    }

    /// A private jet: you fly in to meetings abroad yourself, so starting abroad costs less. Original: step 'window.abroadFee'.
    static func abroadFee(_ fee: Double, _ s: GameState) -> Double { perks(s).jet && fee > 0 ? roundTo(fee * 0.85, step: 1000) : fee }

    /// Owners take a serious buyer more seriously: their offer is judged 2 % better. Original: step 'proposeBuy.terms'.
    static func offerBonus(_ s: GameState) -> Double { perks(s).serious ? 1.02 : 1 }

    /// Your restaurants, cafes, hotels and bars pour your own wine. Original: the 'your own wine on the menu' demand step.
    static func wineFactor(_ co: Company, _ s: GameState) -> Double {
        ["restaurant", "cafe", "hotel", "nightclub", "casino"].contains(co.type) && co.countryCode == s.homeCountryCode
            && record(s).contains(where: { $0["k"].string == "e1" && $0["co"].int == 0 }) ? 1.015 : 1
    }

    enum DinnerResult: Equatable, Sendable { case ok(guests: [String]), none, wait, notEnoughCash }

    /// A dinner on your yacht warms the people you know: suppliers you deal with. Once a month. Original: `LIFE.dinner`.
    static func hostDinner(_ s: inout GameState, data: GameData) -> DinnerResult {
        guard let y = record(s).filter({ item($0["k"].string)?.category == "yachts" }).max(by: { $0["val"].double < $1["val"].double }) else { return .none }
        if let last = s.rest["din56"], !last.isNull, s.week - last.int < 4 { return .wait }
        let cur = Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
        let cost = max(cur.scaledPrice(15000), jsRound(y["val"].double * 0.002))
        if s.cash < cost { return .notEnoughCash }
        Payments.playerPays(&s, cost, label: "Dinner on the yacht")
        s.rest["din56"] = .number(Double(s.week))
        let guests = Suppliers.known(s, data: data).sorted { $0.relationship < $1.relationship }.prefix(3)
        for g in guests { Suppliers.bumpPublic(&s, g.id, by: 6) }
        let names = guests.map { $0.owner.split(separator: " ").first.map(String.init) ?? $0.owner }
        s.addMessage(kind: "info", from: "Dinner on the yacht", title: names.isEmpty ? "A quiet evening on board" : names.joined(separator: ", ") + " came aboard",
                     body: names.isEmpty ? "You need people you know to invite." : "They will remember the evening.", tone: "good")
        return .ok(guests: names)
    }

    /// Year-end and weekly risk checks. Original: the last parts of the lifestyle `week.after` step.
    static func riskChecks(_ s: inout GameState, data: GameData) {
        // The tax office looks at a company car or jet far too big for the company.
        if GameCalendar.isYearEnd(week: s.week) {
            for x in record(s) where x["co"].int != 0 {
                guard let it = item(x["k"].string), let ci = s.companyIndex(x["co"].int) else { continue }
                let rev = s.companies[ci].books.year["rev"] ?? 0
                if rev < x["price"].double * 1.5 && s.random.chance(0.35) {
                    let dep = book["depreciation"][it.category].isNull ? book["depreciation"]["default"].double : book["depreciation"][it.category].double
                    let fine = roundTo(x["price"].double * dep * 0.5, step: 1000)
                    let id = s.companies[ci].id
                    Payments.companyPays(&s, companyID: id, amount: fine, category: "fine", label: "Tax office: \(it.name)")
                    let kind = it.category == "jets" ? "jet" : "car"
                    s.addMessage(kind: "info", from: "The tax office", title: "A company \(kind) too big for \(s.companies[ci].name)",
                                 body: "Sales of \(Int(rev)) a year do not need a \(kind) that cost \(Int(x["price"].double)). Part of the write-down is refused: \(Int(fine)) in back tax and a surcharge.",
                                 companyID: id, tone: "bad")
                }
            }
        }
        // A loan against the collection: if what it stands on is worth less, the bank wants the difference back.
        let loans = s.loans.indices.filter { s.loans[$0].companyID == 0 && s.loans[$0].kind == "lomb" }
        if !loans.isEmpty {
            let owed = loans.reduce(0) { $0 + s.loans[$1].balance }
            let cap = collateral(s) * 1.1
            let slack = Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values)).scaledPrice(1000)
            if owed > cap + slack {
                let due = jsRound(min(owed - cap * 0.95, max(0, s.cash)))
                if due > 0 {
                    var left = due
                    for k in loans { let a = min(s.loans[k].balance, left); s.loans[k].balance -= a; left -= a }
                    Payments.playerPays(&s, due, label: "Margin call: loan against your collection")
                    s.loans.removeAll { $0.balance <= 1 }
                    s.addMessage(kind: "info", from: "Your bank", title: "The bank wants its share back",
                                 body: "What your loan stands on is now worth less than the loan allows. \(Int(due)) was taken from your account to bring it back in line.", tone: "bad")
                }
            }
        }
    }

    // MARK: Your own tiredness

    /// Tiredness, doctor's warnings, sickness and burn-out; a home of your own helps you rest. Original: `fatigueWeek`, 'a home of your own: rest'.
    static func ownerWeek(_ s: inout GameState) {
        let t = CapacityModel.ownerHoursCommitted(s)
        var fat = clamp((s.rest["fat"]?.double ?? 0) + (t > 55 ? (t - 55) * 1.2 : t < 45 ? -12 : -6), 0, 100)
        if let off = s.rest["offW56"], !off.isNull, s.week == off.int { fat = 0 }
        s.rest["fat"] = .number(fat)
        let burning = (s.rest["burnUntil"]?.double).map { Double(s.week) < $0 } ?? false
        if !burning {
            if t > 65 && !(s.rest["fatWarn"]?.bool ?? false) {
                s.rest["fatWarn"] = true
                s.addMessage(kind: "info", from: "Your doctor", title: "You are working \(Int(t)) hours a week",
                             body: "That pace wears anyone down. Above 55 hours you make more mistakes, and you risk getting sick or burning out.", tone: "bad")
            }
            if t <= 55 { s.rest["fatWarn"] = false }
            if fat >= 100 {
                s.rest["burnUntil"] = .number(Double(s.week + 3)); s.rest["fat"] = 45
                s.addMessage(kind: "info", from: "Your doctor", title: "You burned out", body: "You need three weeks of rest. You can barely work until then, so companies without staff or a manager will struggle.", tone: "bad")
            } else if fat > 50 && s.random.chance((fat - 50) / 220) {
                s.rest["sickW"] = .number(Double(s.week + 1))
                s.addMessage(kind: "info", from: "Your doctor", title: "You are sick next week", body: "Too many long weeks. You will not be able to work next week.", tone: "bad")
            }
        }
        // a home of your own: you recover from long weeks faster
        if (s.rest["fat"]?.double ?? 0) > 0 && perks(s).home { s.rest["fat"] = .number(max(0, s.rest["fat"]!.double - 4)) }
    }
    /// "Rested", "Tired", "Exhausted" or "Burned out". Original: `fatWord`.
    static func tirednessWord(_ s: GameState) -> String {
        let f = s.rest["fat"]?.double ?? 0
        if let b = s.rest["burnUntil"], !b.isNull, Double(s.week) < b.double { return "Burned out" }
        return f >= 70 ? "Exhausted" : f >= 40 ? "Tired" : "Rested"
    }
}
