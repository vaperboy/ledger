import Foundation
import GameCore
import Countries
import Finance

/// Staff perks company by company, deals hosted on what you own, and rewards lent from it.
/// Original: features/people/perks_and_hosting.js (`PK58`).
///
/// * Perks (company car, gym, health insurance, a team trip, free lunch) cost a set amount a person a month, paid with the weekly
///   wages; each makes people stay longer (quit odds, hooked in `StaffRoutine`), draws better applicants (`Hiring.generateCandidate`),
///   eases long weeks (gym, lunch) and lifts the manager's mood (car, trips). Stored as `co.perks58` like the original.
/// * Hosting: an evening on your island, castle, yacht or jet costs money and counts for 13 weeks (`rest["host58"]`): a rival owner
///   takes your offers more seriously (`Rivals.proposeBuy`), buyers for what you sell come sooner and pay a little more
///   (`CompanySale.weekly`), franchise applicants come sooner and keener (`Franchising.applicantsWeek`).
/// * Lending: a car, villa, yacht or estate goes to a manager or star worker for a while; the piece is away and wears a little.
public enum StaffPerks {
    // MARK: Perks

    public struct Perk: Identifiable, Equatable, Sendable {
        public var id: String, name: String, detail: String
        /// Per person (per car for `keysOnly`) a month, at the reference price level.
        public var monthlyCost: Double
        /// Multiplies the weekly quit odds of the people it covers.
        public var quitFactor: Double
        /// How much it draws better applicants (0 to 1 over all perks).
        public var pull: Double
        /// Only the manager and team leads get it.
        public var keysOnly: Bool
    }

    public static let all: [Perk] = [
        Perk(id: "car", name: "Company car", detail: "The manager and team leads drive one: they stay longer and the manager is happier.", monthlyCost: 5500, quitFactor: 0.82, pull: 0.15, keysOnly: true),
        Perk(id: "gym", name: "Gym membership", detail: "Fitter people: long weeks wear them down less.", monthlyCost: 450, quitFactor: 0.95, pull: 0.15, keysOnly: false),
        Perk(id: "health", name: "Health insurance", detail: "Private care: people feel looked after and better people apply.", monthlyCost: 650, quitFactor: 0.93, pull: 0.3, keysOnly: false),
        Perk(id: "trips", name: "A team trip each year", detail: "A few days away together: people stay, and the manager is happier.", monthlyCost: 350, quitFactor: 0.9, pull: 0.2, keysOnly: false),
        Perk(id: "lunch", name: "Free lunch", detail: "Lunch together every day: people stay and long days are easier.", monthlyCost: 1500, quitFactor: 0.94, pull: 0.25, keysOnly: false),
    ]
    public static func perk(_ id: String) -> Perk? { all.first { $0.id == id } }

    public static func isOn(_ co: Company, _ id: String) -> Bool { co.value("perks58")[id].double != 0 }
    public static func onPerks(_ co: Company) -> [Perk] { all.filter { isOn(co, $0.id) } }

    /// The manager and the team leads.
    public static func keyPeople(_ co: Company) -> Int { (co.managerID != nil ? 1 : 0) + co.staff.filter { $0.role == "lead" }.count }
    /// Everyone on the payroll, manager included.
    public static func headcount(_ co: Company) -> Int { co.staff.count + (co.managerID != nil ? 1 : 0) }

    /// What one perk costs a month in this company. Original: `perMonth`.
    public static func monthlyCost(_ co: Company, _ p: Perk, currency cur: Currency) -> Double {
        if p.id == "car" { return CompanyCarPerk.monthlyCost(co, currency: cur) }   // the leases of the real cars (CompanyCarPerk)
        return cur.scaledPrice(p.monthlyCost) * Double(p.keysOnly ? keyPeople(co) : headcount(co))
    }
    /// All perks that are on. Original: `PK.cost`.
    public static func totalMonthlyCost(_ co: Company, currency cur: Currency) -> Double {
        onPerks(co).reduce(0) { $0 + monthlyCost(co, $1, currency: cur) }
    }
    /// How much the perks draw better people to apply (0 to 1). Original: `PK.pull`.
    public static func pull(_ co: Company) -> Double { min(1, onPerks(co).reduce(0) { $0 + $1.pull }) }

    /// Multiplier on one person's quit odds. Original: the 'quitF' step.
    public static func quitFactor(_ co: Company, _ m: StaffMember) -> Double {
        guard !co.value("perks58").isNull else { return 1 }
        var f = 1.0
        for p in onPerks(co) where !p.keysOnly || m.role == "lead" { f *= p.quitFactor }
        return f
    }
    /// Share of people that would leave, in percent fewer (for a screen line).
    public static func fewerLeavePercent(_ co: Company) -> Double { (1 - onPerks(co).reduce(1) { $0 * $1.quitFactor }) * 100 }

    /// Switch a perk on or off. Returns the new state, nil for an unknown company or perk. Original: `ACT.pk58t`.
    @discardableResult
    public static func toggle(_ s: inout GameState, companyID: Int, perk id: String, data: GameData? = nil) -> Bool? {
        guard let i = s.companyIndex(companyID), perk(id) != nil else { return nil }
        var f = s.companies[i].value("perks58")
        if f.isNull { f = .object([:]) }
        let now = f[id].double == 0
        f[id] = .number(now ? 1 : 0)
        s.companies[i].set("perks58", f)
        if id == "car" { if let data { CompanyCarPerk.sync(&s, companyIndex: i, data: data) } else if !now { CompanyCarPerk.release(&s, companyIndex: i) } }
        return now
    }

    static func playerCurrency(_ s: GameState, _ data: GameData) -> Currency {
        Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
    }

    // MARK: Every week

    /// Perks are paid with the wages; long weeks ease; the manager is happier; lent pieces come back. Original: 'extraPay' and the two 'week.after' steps.
    public static func weekly(_ s: inout GameState, data: GameData) {
        let w = World(state: s, data: data)
        for i in s.companies.indices where s.companies[i].status == .open && !s.companies[i].value("perks58").isNull {
            CompanyCarPerk.sync(&s, companyIndex: i, data: data)   // the company-car perk is real leased cars: they bill themselves with the vehicles
            let co = s.companies[i]
            let on = onPerks(co)
            if on.isEmpty { continue }
            let monthly = on.filter { $0.id != "car" }.reduce(0) { $0 + monthlyCost(co, $1, currency: w.currency(co)) }
            if monthly > 0 { Payments.companyPays(&s, companyID: co.id, amount: monthly * 12 / 52, category: "wages", label: "Staff perks") }
            let ease = (isOn(co, "gym") ? 1.0 : 0) + (isOn(co, "lunch") ? 0.5 : 0)
            if ease > 0 {
                var staff = s.companies[i].staff
                for k in staff.indices where staff[k].tiredness > 0 { staff[k].tiredness = max(0, staff[k].tiredness - ease) }
                s.companies[i].staff = staff
            }
            if co.managerID != nil && (isOn(co, "car") || isOn(co, "trips")) {
                let mood = co.value("mood").isNull ? 60 : co.num("mood")
                let lift = ((isOn(co, "car") ? 0.25 : 0) + (isOn(co, "trips") ? 0.2 : 0)) * max(0, 1 - mood / 85)
                s.companies[i].set("mood", clamp(mood + lift, 0, 100))
            }
            if isOn(co, "trips") && (s.week + co.id) % 52 == 30 && headcount(co) >= 2 {
                s.note("The team at \(co.name) is away on its yearly trip.", tone: "good", companyID: co.id)
            }
        }
        lentPiecesComeBack(&s)
    }

    // MARK: Hosting

    /// How much a hosted evening still counts (0 when it is over 13 weeks ago). Keys: "inv", "fr", "r:<rival id>". Original: `PK.hosted`.
    public static func hosted(_ s: GameState, _ key: String) -> Double {
        guard let h = s.rest["host58"]?[key], !h.isNull, s.week - h["w"].int <= 13 else { return 0 }
        return h["s"].double
    }

    /// A rival owner you hosted judges your offer a little better. Original: step 'proposeBuy.terms'.
    public static func rivalFactor(_ s: GameState, rivalID: Int) -> Double { 1 + 0.05 * hosted(s, "r:\(rivalID)") }

    /// Where you can host, and what an evening costs there: island and castle best, then a yacht, then a jet. Original: `venue`.
    struct Venue { var strength: Double, cost: Double, word: String }

    static func venue(_ x: JSONValue, _ cur: Currency) -> Venue? {
        guard x["co"].int == 0, let it = Luxury.item(x["k"].string) else { return nil }
        if it.category == "estates" && (it.id == "e2" || it.id == "e5") {
            return Venue(strength: 1, cost: cur.scaledPrice(it.id == "e2" ? 45000 : 25000), word: it.id == "e2" ? "the island" : "the castle")
        }
        if it.category == "yachts" { return Venue(strength: 0.85, cost: max(cur.scaledPrice(15000), jsRound(x["val"].double * 0.002)), word: "the yacht") }
        if it.category == "jets" { return Venue(strength: 0.6, cost: cur.scaledPrice(30000), word: "the jet") }
        return nil
    }

    /// Out on charter, rented, at a museum, or lent. Original: `away`.
    static func away(_ x: JSONValue, week: Int) -> Bool {
        (!x["lent58"].isNull && x["lent58"]["until"].int > week) || ["charter", "rent", "museum"].contains(x["use"].string)
    }

    /// Your pieces that can host a deal now.
    public static func venues(_ s: GameState, data: GameData) -> [Luxury.Piece] {
        let cur = playerCurrency(s, data)
        let ids = Set(Luxury.record(s).filter { venue($0, cur) != nil && !away($0, week: s.week) }.map { $0["id"].int })
        return Luxury.pieces(s).filter { ids.contains($0.id) }
    }
    /// What an evening on this piece costs.
    public static func hostingCost(_ s: GameState, data: GameData, pieceID: Int) -> Double? {
        let cur = playerCurrency(s, data)
        return Luxury.record(s).first { $0["id"].int == pieceID }.flatMap { venue($0, cur)?.cost }
    }

    public enum HostGuest: Equatable, Sendable {
        case investors, franchise
        case rival(companyID: Int, rivalID: Int)
    }
    public struct GuestOption: Equatable, Sendable {
        public var guest: HostGuest, title: String, detail: String, hostedLately: Bool
    }
    /// Who you can invite: investors if you sell, franchise prospects if you franchise, and up to eight rival owners (biggest first).
    public static func guests(_ s: GameState) -> [GuestOption] {
        var out: [GuestOption] = []
        let selling = !(s.rest["sales"]?.array ?? []).isEmpty || s.companies.contains { $0.form == .limited && $0.status == .open }
        if selling {
            out.append(GuestOption(guest: .investors, title: "Investors", detail: "Buyers for what you sell come sooner and pay a little more", hostedLately: hosted(s, "inv") > 0))
        }
        if s.companies.contains(where: { $0.status == .open && $0.value("fr")["on"].bool }) {
            out.append(GuestOption(guest: .franchise, title: "Franchise prospects", detail: "Applicants come sooner, and keener", hostedLately: hosted(s, "fr") > 0))
        }
        var seen = Set<Int>(), rivals: [(Company, Rivals.Rival)] = []
        for co in s.companies where co.status == .open && co.type != "hold" {
            for r in Rivals.rivals(s, for: co) where !seen.contains(r.id) { seen.insert(r.id); rivals.append((co, r)) }
        }
        rivals.sort { $0.1.size > $1.1.size }
        for (co, r) in rivals.prefix(8) {
            out.append(GuestOption(guest: .rival(companyID: co.id, rivalID: r.id), title: r.owner, detail: "Owns \(r.name)", hostedLately: hosted(s, "r:\(r.id)") > 0))
        }
        return out
    }

    public enum HostResult: Equatable, Sendable { case ok(title: String, body: String), none, away, wait, notEnoughCash }

    /// Host an evening. The cost is paid from your cash. Original: `PK.host`.
    @discardableResult
    public static func host(_ s: inout GameState, data: GameData, pieceID: Int, guest: HostGuest) -> HostResult {
        let cur = playerCurrency(s, data)
        var list = Luxury.record(s)
        guard let at = list.firstIndex(where: { $0["id"].int == pieceID }), let v = venue(list[at], cur) else { return .none }
        if away(list[at], week: s.week) { return .away }
        if !list[at]["host58"].isNull, s.week - list[at]["host58"].int < 4 { return .wait }
        var rivalCo: Company?, rival: Rivals.Rival?
        if case .rival(let cid, let rid) = guest {
            rivalCo = s.company(cid)
            rival = rivalCo.flatMap { c in Rivals.rivals(s, for: c).first { $0.id == rid } }
            if rival == nil { return .none }
        }
        let cost = jsRound(v.cost)
        if s.cash < cost { return .notEnoughCash }
        Payments.playerPays(&s, cost, label: "Hosting on \(v.word)")
        list[at]["host58"] = .number(Double(s.week))
        Luxury.save(&s, list)
        var h = s.rest["host58"] ?? .object([:])
        let mark: JSONValue = .object(["w": .number(Double(s.week)), "s": .number(v.strength)])
        switch guest {
        case .rival(_, let rid):
            guard let co = rivalCo, let r = rival else { return .none }
            h["r:\(rid)"] = mark
            s.rest["host58"] = h
            let gain = jsRound(12 * v.strength), wk = s.week
            let memo = "Came to dinner on your \(v.word.replacingOccurrences(of: "the ", with: ""))."
            Rivals.mutate(&s, key: Rivals.key(co), id: rid) { rr in
                Rivals.remember(&rr, week: wk, text: memo, change: gain)
                rr["ign"] = .number(max(0, rr["ign"].double - 1))
            }
            let first = r.owner.split(separator: " ").first.map(String.init) ?? r.owner
            return .ok(title: "\(r.owner) came to \(v.word)",
                       body: "A long evening and a good talk. For the next three months \(first) takes your offers for \(r.name) more seriously.")
        case .investors:
            h["inv"] = mark
            s.rest["host58"] = h
            return .ok(title: "Investors on \(v.word)", body: "Bankers, funds and a few wealthy families. For the next three months buyers for what you sell come sooner and pay a little more.")
        case .franchise:
            h["fr"] = mark
            s.rest["host58"] = h
            return .ok(title: "Franchise prospects on \(v.word)", body: "People who want a business of their own. For the next three months applicants come sooner, and keener.")
        }
    }

    // MARK: Lending

    /// [weeks away, the manager's mood, weeks they stay loyal] by category. Original: `LEND`.
    static let lendTable: [String: (weeks: Int, mood: Double, loyal: Int)] = [
        "cars": (26, 10, 26), "homes": (2, 12, 26), "yachts": (1, 15, 26), "estates": (1, 15, 26),
    ]

    /// Pieces of yours that can be lent now.
    public static func lendable(_ s: GameState) -> [Luxury.Piece] {
        let ids = Set(Luxury.record(s).filter { canLend($0, week: s.week) }.map { $0["id"].int })
        return Luxury.pieces(s).filter { ids.contains($0.id) }
    }
    static func canLend(_ x: JSONValue, week: Int) -> Bool {
        guard x["co"].int == 0, let it = Luxury.item(x["k"].string), lendTable[it.category] != nil else { return false }
        return !away(x, week: week)
    }
    /// "Lent to Anna until week 120", or nil. Original: `PK.lentLine`.
    public static func lentTo(_ s: GameState, pieceID: Int) -> (name: String, until: Int)? {
        guard let x = Luxury.record(s).first(where: { $0["id"].int == pieceID }), !x["lent58"].isNull, x["lent58"]["until"].int > s.week else { return nil }
        return (x["lent58"]["name"].string, x["lent58"]["until"].int)
    }

    public struct Reward: Identifiable, Equatable, Sendable {
        public var id: String { "\(companyID):\(staffID ?? 0)" }
        public var companyID: Int, staffID: Int?, personID: Int
        public var name: String, companyName: String, isManager: Bool, skill: Double, rewardedLately: Bool
    }
    /// Managers and star workers you can reward (up to 14). Original: `people`.
    public static func rewards(_ s: GameState) -> [Reward] {
        var out: [Reward] = []
        for co in s.companies where co.status == .open {
            if let mid = co.managerID, let n = s.people[mid] {
                out.append(Reward(companyID: co.id, staffID: nil, personID: mid, name: n.name, companyName: co.name, isManager: true, skill: n.skill, rewardedLately: lately(n, s)))
            }
            for m in co.staff { if let n = s.people[m.id], n.skill >= 75 || n.flag("super") {
                out.append(Reward(companyID: co.id, staffID: m.id, personID: m.id, name: n.name, companyName: co.name, isManager: false, skill: n.skill, rewardedLately: lately(n, s)))
            } }
        }
        return Array(out.prefix(14))
    }
    static func lately(_ n: Person, _ s: GameState) -> Bool { !n.value("rw58").isNull && s.week - n.int("rw58") < 26 }

    public enum LendResult: Equatable, Sendable { case ok(name: String), none }

    /// Lend a piece to a company's manager (`staffID` nil) or to a star worker. A second reward within half a year counts half. Original: `PK.lend`.
    @discardableResult
    public static func lend(_ s: inout GameState, pieceID: Int, companyID: Int, staffID: Int?) -> LendResult {
        var list = Luxury.record(s)
        guard let at = list.firstIndex(where: { $0["id"].int == pieceID }), canLend(list[at], week: s.week), let it = Luxury.item(list[at]["k"].string),
              let L = lendTable[it.category], let ci = s.companyIndex(companyID) else { return .none }
        let pid = staffID ?? s.companies[ci].managerID ?? 0
        guard var n = s.people[pid] else { return .none }
        if staffID != nil && !s.companies[ci].staff.contains(where: { $0.id == pid }) { return .none }
        let f = lately(n, s) ? 0.5 : 1.0
        n.set("rw58", Double(s.week))
        list[at]["lent58"] = .object(["npc": .number(Double(pid)), "name": .string(n.name), "until": .number(Double(s.week + L.weeks))])
        list[at]["val"] = .number(jsRound(list[at]["val"].double * (it.category == "cars" ? 0.98 : 0.995)))   // a little wear
        Luxury.save(&s, list)
        if staffID == nil {
            let mood = s.companies[ci].value("mood").isNull ? 60 : s.companies[ci].num("mood")
            s.companies[ci].set("mood", clamp(mood + L.mood * f, 0, 100))
            n.set("ret27", Double(max(Int(n.num("ret27")), s.week + L.loyal)))   // rival headhunters leave a manager alone
        } else if let k = s.companies[ci].staff.firstIndex(where: { $0.id == pid }) {
            var m = s.companies[ci].staff[k]
            m.happyUntilWeek = max(m.happyUntilWeek, s.week + Int(jsRound(Double(L.loyal) * f)))
            m.tiredness = max(0, m.tiredness - 20 * f)
            s.companies[ci].staff[k] = m
        }
        s.people[pid] = n
        return .ok(name: n.name)
    }

    static func lentPiecesComeBack(_ s: inout GameState) {
        var list = Luxury.record(s)
        var changed = false
        for k in list.indices where !list[k]["lent58"].isNull && list[k]["lent58"]["until"].int <= s.week {
            let nm = list[k]["lent58"]["name"].string
            list[k]["lent58"] = .null
            changed = true
            s.note("\(nm) gave back the \(Luxury.item(list[k]["k"].string)?.name ?? "piece"). Thank you, they said.", tone: "good")
        }
        if changed { Luxury.save(&s, list) }
    }
}
