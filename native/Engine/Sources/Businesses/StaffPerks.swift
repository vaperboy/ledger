import Foundation
import GameCore
import Countries
import Finance

public enum StaffPerks {

    public struct RoleGroup: Identifiable, Equatable, Sendable {
        public var id: String, name: String
        public var includesManager: Bool
        public var roles: Set<String>
        public var isRest: Bool
    }

    public enum CostBasis: String, Sendable { case person, wage }

    public struct Perk: Identifiable, Equatable, Sendable {
        public var id: String, name: String, detail: String
        public var monthlyCost: Double
        public var costBasis: CostBasis
        public var groups: [String]
        public var quitFactor: Double
        public var pull: Double
        public var tiredness: Double
        public var managerMood: Double
        public var worth: Double

        public var keysOnly: Bool { groups == ["keys"] }
    }

    struct Catalogue: Sendable {
        var groups: [RoleGroup] = []
        var perks: [Perk] = []
    }

    static let catalogue: Catalogue = {
        var c = Catalogue()
        guard let url = Bundle.module.url(forResource: "staff_perks", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return c }
        c.groups = j["roleGroups"].array.map {
            RoleGroup(id: $0["id"].string, name: $0["name"].string, includesManager: $0["manager"].bool, roles: Set($0["roles"].array.map { $0.string }), isRest: $0["rest"].bool)
        }
        c.perks = j["perks"].array.map {
            Perk(id: $0["id"].string, name: $0["name"].string, detail: $0["detail"].string, monthlyCost: $0["monthlyCost"].double,
                 costBasis: CostBasis(rawValue: $0["costBasis"].string) ?? .person, groups: $0["groups"].array.map { $0.string },
                 quitFactor: $0["quitFactor"].isNull ? 1 : $0["quitFactor"].double, pull: $0["pull"].double, tiredness: $0["tiredness"].double,
                 managerMood: $0["managerMood"].double, worth: $0["worth"].double)
        }
        return c
    }()

    public static var all: [Perk] { catalogue.perks }
    public static var roleGroups: [RoleGroup] { catalogue.groups }
    public static func perk(_ id: String) -> Perk? { all.first { $0.id == id } }
    public static func roleGroup(_ id: String) -> RoleGroup? { roleGroups.first { $0.id == id } }

    public static func group(ofRole role: String, isManager: Bool = false) -> String {
        if isManager { return roleGroups.first { $0.includesManager }?.id ?? "" }
        if let g = roleGroups.first(where: { $0.roles.contains(role) }) { return g.id }
        return roleGroups.first { $0.isRest }?.id ?? ""
    }
    public static func eligibleGroups(_ p: Perk) -> [RoleGroup] { p.groups.compactMap { roleGroup($0) } }

    public static func isOn(_ co: Company, _ id: String) -> Bool {
        guard let p = perk(id) else { return false }
        return p.groups.contains { covers(co, p, group: $0) }
    }
    public static func onPerks(_ co: Company) -> [Perk] { all.filter { isOn(co, $0.id) } }

    public static func covers(_ co: Company, _ p: Perk, group: String) -> Bool {
        guard p.groups.contains(group) else { return false }
        let f = co.value("perks58")[p.id]
        if case .object(let o) = f { return o[group]?.double ?? 0 != 0 }
        return f.double != 0
    }
    public static func isOnForAll(_ co: Company, _ id: String) -> Bool {
        guard let p = perk(id) else { return false }
        return p.groups.allSatisfy { covers(co, p, group: $0) }
    }
    public static func covers(_ co: Company, _ p: Perk, member m: StaffMember) -> Bool { covers(co, p, group: group(ofRole: m.role)) }
    public static func coversManager(_ co: Company, _ p: Perk) -> Bool { co.managerID != nil && covers(co, p, group: group(ofRole: "", isManager: true)) }

    public static func perks(for m: StaffMember, in co: Company) -> [Perk] { all.filter { covers(co, $0, member: m) } }

    public static func keyPeople(_ co: Company) -> Int { (co.managerID != nil ? 1 : 0) + co.staff.filter { $0.role == "lead" }.count }
    public static func headcount(_ co: Company) -> Int { co.staff.count + (co.managerID != nil ? 1 : 0) }
    public static func people(_ co: Company, group: String) -> Int {
        co.staff.filter { self.group(ofRole: $0.role) == group }.count + (coversManagerGroup(group) && co.managerID != nil ? 1 : 0)
    }
    static func coversManagerGroup(_ g: String) -> Bool { roleGroup(g)?.includesManager ?? false }

    public static func covered(_ co: Company, _ p: Perk) -> Int {
        p.groups.filter { covers(co, p, group: $0) }.reduce(0) { $0 + people(co, group: $1) }
    }
    public static func eligibleCount(_ co: Company, _ p: Perk) -> Int { p.groups.reduce(0) { $0 + people(co, group: $1) } }

    public static func monthlyCost(_ co: Company, _ p: Perk, currency cur: Currency) -> Double {
        if p.id == "car" { return CompanyCarPerk.monthlyCost(co, currency: cur) }
        let on = p.groups.filter { covers(co, p, group: $0) }
        let groups = on.isEmpty ? p.groups : on
        let staff = co.staff.filter { groups.contains(group(ofRole: $0.role)) }
        let managerIn = co.managerID != nil && groups.contains(group(ofRole: "", isManager: true))
        switch p.costBasis {
        case .person: return cur.scaledPrice(p.monthlyCost) * Double(staff.count + (managerIn ? 1 : 0))
        case .wage: return p.monthlyCost * (staff.reduce(0) { $0 + $1.monthlyWage } + (managerIn ? co.managerMonthlyWage : 0))
        }
    }
    public static func totalMonthlyCost(_ co: Company, currency cur: Currency) -> Double {
        onPerks(co).reduce(0) { $0 + monthlyCost(co, $1, currency: cur) }
    }
    public static func worthMonthly(_ co: Company, _ m: StaffMember, currency cur: Currency) -> Double {
        perks(for: m, in: co).reduce(0) { sum, p in
            sum + p.worth * (p.costBasis == .person ? cur.scaledPrice(p.monthlyCost) : p.monthlyCost * m.monthlyWage)
        }
    }
    public static func pull(_ co: Company) -> Double { onPerks(co).reduce(0) { $0 + $1.pull } }
    public static func pull(_ co: Company, role: String) -> Double {
        let g = group(ofRole: role)
        return all.filter { covers(co, $0, group: g) }.reduce(0) { $0 + $1.pull }
    }

    public static func quitFactor(_ co: Company, _ m: StaffMember) -> Double {
        guard !co.value("perks58").isNull else { return 1 }
        var f = 1.0
        for p in perks(for: m, in: co) { f *= p.quitFactor }
        return f
    }
    public static func fewerLeavePercent(_ co: Company) -> Double { (1 - onPerks(co).reduce(1) { $0 * $1.quitFactor }) * 100 }

    @discardableResult
    public static func set(_ s: inout GameState, companyID: Int, perk id: String, on: Bool, group g: String? = nil) -> Bool {
        guard let i = s.companyIndex(companyID), let p = perk(id) else { return false }
        if let g, !p.groups.contains(g) { return false }
        let co = s.companies[i]
        var state: [String: Bool] = [:]
        for x in p.groups { state[x] = covers(co, p, group: x) }
        if let g { state[g] = on } else { for x in p.groups { state[x] = on } }
        var f = co.value("perks58")
        if f.isNull { f = .object([:]) }
        if state.values.allSatisfy({ $0 }) { f[id] = .number(1) }
        else if !state.values.contains(true) { f[id] = .number(0) }
        else { f[id] = .object(state.mapValues { .number($0 ? 1 : 0) }) }
        s.companies[i].set("perks58", f)
        if id == "car", !isOn(s.companies[i], "car") { CompanyCarPerk.release(&s, companyIndex: i) }
        StaffPromises.noticeChange(&s, companyID: companyID)
        return true
    }

    @discardableResult
    public static func toggle(_ s: inout GameState, companyID: Int, perk id: String, data: GameData? = nil) -> Bool? {
        guard let i = s.companyIndex(companyID), perk(id) != nil else { return nil }
        let now = !isOn(s.companies[i], id)
        guard set(&s, companyID: companyID, perk: id, on: now) else { return nil }
        if id == "car", now, let data { CompanyCarPerk.sync(&s, companyIndex: i, data: data) }
        return now
    }

    @discardableResult
    public static func toggle(_ s: inout GameState, companyID: Int, perk id: String, group g: String) -> Bool? {
        guard let i = s.companyIndex(companyID), let p = perk(id), p.groups.contains(g) else { return nil }
        let now = !covers(s.companies[i], p, group: g)
        return set(&s, companyID: companyID, perk: id, on: now, group: g) ? now : nil
    }

    static func playerCurrency(_ s: GameState, _ data: GameData) -> Currency {
        Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        let w = World(state: s, data: data)
        for i in s.companies.indices where s.companies[i].status == .open && !s.companies[i].value("perks58").isNull {
            CompanyCarPerk.sync(&s, companyIndex: i, data: data)
            let co = s.companies[i]
            let on = onPerks(co)
            if on.isEmpty { continue }
            let monthly = on.filter { $0.id != "car" }.reduce(0) { $0 + monthlyCost(co, $1, currency: w.currency(co)) }
            let country = w.country(co)
            if monthly > 0 { Payments.companyPays(&s, companyID: co.id, amount: monthly * 12 / 52 * (1 + country.employerOnCost(monthlyWage: country.medianMonthlyWage)), category: "wages", label: "Staff perks") }
            if on.contains(where: { $0.tiredness > 0 }) {
                var staff = s.companies[i].staff
                for k in staff.indices where staff[k].tiredness > 0 {
                    let ease = perks(for: staff[k], in: co).reduce(0) { $0 + $1.tiredness }
                    if ease > 0 { staff[k].tiredness = max(0, staff[k].tiredness - ease) }
                }
                s.companies[i].staff = staff
            }
            let lift = on.filter { coversManager(co, $0) }.reduce(0) { $0 + $1.managerMood }
            if co.managerID != nil && lift > 0 {
                let mood = co.value("mood").isNull ? 60 : co.num("mood")
                s.companies[i].set("mood", clamp(mood + lift * max(0, 1 - mood / 85), 0, 100))
            }
            if isOn(co, "trips") && (s.week + co.id) % 52 == 30 && headcount(co) >= 2 {
                s.note("The team at \(co.name) is away on its yearly trip.", tone: "good", companyID: co.id)
            }
        }
        lentPiecesComeBack(&s)
    }

    public static func hosted(_ s: GameState, _ key: String) -> Double {
        guard let h = s.rest["host58"]?[key], !h.isNull, s.week - h["w"].int <= 13 else { return 0 }
        return h["s"].double
    }

    public static func rivalFactor(_ s: GameState, rivalID: Int) -> Double { 1 + 0.05 * hosted(s, "r:\(rivalID)") }

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

    static func away(_ x: JSONValue, week: Int) -> Bool {
        (!x["lent58"].isNull && x["lent58"]["until"].int > week) || ["charter", "rent", "museum"].contains(x["use"].string)
    }

    public static func venues(_ s: GameState, data: GameData) -> [Luxury.Piece] {
        let cur = playerCurrency(s, data)
        let ids = Set(Luxury.record(s).filter { venue($0, cur) != nil && !away($0, week: s.week) }.map { $0["id"].int })
        return Luxury.pieces(s).filter { ids.contains($0.id) }
    }
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
    public static func guests(_ s: GameState) -> [GuestOption] {
        var out: [GuestOption] = []
        let selling = !(s.rest["sales"]?.array ?? []).isEmpty || s.companies.contains { $0.status == .open }
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

    static let lendTable: [String: (weeks: Int, mood: Double, loyal: Int)] = [
        "cars": (26, 10, 26), "homes": (2, 12, 26), "yachts": (1, 15, 26), "estates": (1, 15, 26),
    ]

    public static func lendable(_ s: GameState) -> [Luxury.Piece] {
        let ids = Set(Luxury.record(s).filter { canLend($0, week: s.week) }.map { $0["id"].int })
        return Luxury.pieces(s).filter { ids.contains($0.id) }
    }
    static func canLend(_ x: JSONValue, week: Int) -> Bool {
        guard x["co"].int == 0, let it = Luxury.item(x["k"].string), lendTable[it.category] != nil else { return false }
        return !away(x, week: week)
    }
    public static func lentTo(_ s: GameState, pieceID: Int) -> (name: String, until: Int)? {
        guard let x = Luxury.record(s).first(where: { $0["id"].int == pieceID }), !x["lent58"].isNull, x["lent58"]["until"].int > s.week else { return nil }
        return (x["lent58"]["name"].string, x["lent58"]["until"].int)
    }

    public struct Reward: Identifiable, Equatable, Sendable {
        public var id: String { "\(companyID):\(staffID ?? 0)" }
        public var companyID: Int, staffID: Int?, personID: Int
        public var name: String, companyName: String, isManager: Bool, note: String, rewardedLately: Bool
    }
    public static func rewards(_ s: GameState) -> [Reward] {
        var out: [Reward] = []
        for co in s.companies where co.status == .open {
            if let mid = co.managerID, let n = s.people[mid] {
                out.append(Reward(companyID: co.id, staffID: nil, personID: mid, name: n.name, companyName: co.name, isManager: true, note: "Runs the business", rewardedLately: lately(n, s)))
            }
            for m in co.staff { if let n = s.people[m.id], n.skill >= 75 || n.flag("super") {
                out.append(Reward(companyID: co.id, staffID: m.id, personID: m.id, name: n.name, companyName: co.name, isManager: false, note: "Stands out in their work", rewardedLately: lately(n, s)))
            } }
        }
        return Array(out.prefix(14))
    }
    static func lately(_ n: Person, _ s: GameState) -> Bool { !n.value("rw58").isNull && s.week - n.int("rw58") < 26 }

    public enum LendResult: Equatable, Sendable { case ok(name: String), none }

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
        list[at]["val"] = .number(jsRound(list[at]["val"].double * (it.category == "cars" ? 0.98 : 0.995)))
        Luxury.save(&s, list)
        if staffID == nil {
            let mood = s.companies[ci].value("mood").isNull ? 60 : s.companies[ci].num("mood")
            s.companies[ci].set("mood", clamp(mood + L.mood * f, 0, 100))
            n.set("ret27", Double(max(Int(n.num("ret27")), s.week + L.loyal)))
        } else if let k = s.companies[ci].staff.firstIndex(where: { $0.id == pid }) {
            var m = s.companies[ci].staff[k]
            m.happyUntilWeek = max(m.happyUntilWeek, s.week + Int(saturating: jsRound(Double(L.loyal) * f)))
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
