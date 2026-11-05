import Foundation
import GameCore
import Countries
import Employees
import Finance

// Job ads and the agency. An ad costs a fee and brings applicants over the next four weeks, a few a week, more for a bigger
// company; an agency costs much more, brings suggestions at once and better ones later, and takes a share of the hired person's pay for 24 months.
// The 'network' search mode is deprecated (kept so old saves and the automatic hirers work; not offered to the player).

public enum JobAds {
    public enum PostResult: Equatable, Sendable {
        case posted(fee: Double, expectedApplicants: Int)
        case notEnoughCash(fee: Double)
        /// The company name or organisation number is missing.
        case missingRecord(String)
        case notPossible(String)
    }

    /// An ad runs this many days; applicants stay on the list for `keepWeeks` after arriving.
    public static let adDays = 28
    public static let keepWeeks = 8

    /// The organisation number a company advertises under. Registration stores none, so it is derived (stably) from the game seed and the company id:
    /// the same number every time, nothing to save.
    public static func orgNumber(_ s: GameState, companyID: Int) -> String {
        var r = HashedRandom("\(s.seed):org:\(companyID)")
        func digits(_ n: Int) -> String { (0..<n).map { _ in String(Int(r.next() * 10) % 10) }.joined() }
        return "55" + digits(4) + "-" + digits(4)
    }

    public static func form(_ s: GameState, companyID: Int) -> (companyName: String, orgNumber: String)? {
        guard let co = s.company(companyID) else { return nil }
        return (co.name, co.name.isEmpty ? "" : orgNumber(s, companyID: companyID))
    }

    /// The fee: bigger company and better-paid role cost more. Base fee scaled to the country, times 1 + 5 percent a head (up to 40 heads),
    /// times the role's pay against the lowest-paid role (0.6 to 3).
    public static func fee(_ s: GameState, companyID: Int, role: String, data: GameData) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        let cur = World(state: s, data: data).currency(co)
        return jsRound(cur.scaledPrice(800) * sizeFactor(co) * roleFactor(role, data: data))
    }

    static func sizeFactor(_ co: Company) -> Double { 1 + 0.05 * Double(min(40, PremisesExtras.heads(co))) }
    static func roleFactor(_ role: String, data: GameData) -> Double {
        let t = data.catalog.tables.roles
        let ref = max(1, t["helper"]?.baseMonthlyWage ?? 1)
        return clamp((t[role]?.baseMonthlyWage ?? ref) / ref, 0.6, 3)
    }

    /// How many people answer an ad over its run: a small company gets a few, a big, busy, well-regarded one many.
    /// 2 + half a person per head + reputation/25 + 1.2 per decade of weekly revenue (against a thousand units' worth), plus a deterministic -1..+1.
    public static func expectedApplicants(_ s: GameState, _ co: Company, data: GameData, salt: String = "") -> Int {
        let cur = World(state: s, data: data).currency(co)
        let heads = Double(min(40, PremisesExtras.heads(co)))
        let revenue = co.lastWeekRevenue > 0 ? log10(1 + co.lastWeekRevenue / max(1, cur.scaledPrice(1000))) * 1.2 : 0
        var r = HashedRandom("\(s.seed):adn:\(co.id):\(s.week):\(salt)")
        let jitter = Int(r.next() * 3) - 1
        return max(1, Int((2 + heads * 0.5 + co.reputation / 25 + revenue).rounded()) + jitter)
    }

    static func list(_ co: Company) -> [JSONValue] { co.value("apl").array }

    /// The people who have answered the company's ads and the agency, as person ids (still on the market and within `keepWeeks`).
    public static func applicantIDs(_ s: GameState, companyID: Int) -> [Int] {
        guard let co = s.company(companyID) else { return [] }
        return list(co).compactMap { e in
            guard let p = s.people[e["id"].int], p.employerID == 0, s.week - e["w"].int <= keepWeeks else { return nil }
            return p.id
        }
    }

    public static func post(_ s: inout GameState, companyID: Int, role: String, data: GameData) -> PostResult {
        guard let ci = s.companyIndex(companyID), (s.companies[ci].status == .open || s.companies[ci].status == .setup) else { return .notPossible("This company is not open.") }
        let r = role.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { return .notPossible("Name the role.") }
        guard let f = form(s, companyID: companyID), !f.companyName.isEmpty, !f.orgNumber.isEmpty else { return .missingRecord("The ad needs the company name and organisation number.") }
        if (s.companies[ci].value("ads").array).contains(where: { $0["role"].string == r && s.week * 7 + s.day - $0["d0"].int < adDays }) { return .notPossible("An ad for this role is already running.") }
        let fee = fee(s, companyID: companyID, role: r, data: data)
        guard s.companies[ci].cash >= fee else { return .notEnoughCash(fee: fee) }
        guard Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Job ad: \(r)") else { return .notEnoughCash(fee: fee) }
        let n = expectedApplicants(s, s.companies[ci], data: data, salt: r)
        var rnd = HashedRandom("\(s.seed):adt:\(companyID):\(s.week):\(s.day):\(r)")
        let days = (0..<n).map { _ in 1 + Int(rnd.next() * Double(adDays - 1)) }.sorted()
        var ads = s.companies[ci].value("ads").array
        ads.append(.object(["role": .string(r), "d0": .number(Double(s.week * 7 + s.day)), "at": .array(days.map { .number(Double($0)) }), "got": 0, "fee": .number(fee)]))
        if ads.count > 12 { ads.removeFirst(ads.count - 12) }
        s.companies[ci].set("ads", .array(ads))
        return .posted(fee: fee, expectedApplicants: n)
    }

    /// Daily: applicants whose day has come arrive, each with an inbox message routed like others (a manager's name when the company has one).
    public static func runDay(_ s: inout GameState, data: GameData) {
        let today = s.week * 7 + s.day
        for ci in s.companies.indices where (s.companies[ci].status == .open || s.companies[ci].status == .setup) && !s.companies[ci].value("ads").isNull {
            var ads = s.companies[ci].value("ads").array
            var changed = false
            for k in ads.indices {
                let at = ads[k]["at"].array.map { $0.int }
                var got = ads[k]["got"].int
                let elapsed = today - ads[k]["d0"].int
                while got < at.count, at[got] <= elapsed {
                    arrive(&s, companyIndex: ci, role: ads[k]["role"].string, agency: false, boost: 0, data: data)
                    got += 1; changed = true
                }
                ads[k]["got"] = .number(Double(got))
            }
            let live = ads.filter { $0["got"].int < $0["at"].array.count || today - $0["d0"].int < adDays }
            if changed || live.count != ads.count {
                s.companies[ci].set("ads", .array(live))
            }
        }
    }

    /// One applicant comes in: a person is made on the market, put on the company's list, and the inbox is told.
    static func arrive(_ s: inout GameState, companyIndex ci: Int, role: String, agency: Bool, boost: Double, data: GameData) {
        let co = s.companies[ci]
        var p = Hiring.generateCandidate(role: role, company: co, tier: agency ? "mid" : nil, faces: true, state: &s, data: data)
        if agency {
            p.skill = min(97, p.skill + boost); p.claimedSkill = min(98, p.claimedSkill + boost)
            p.set("ag", 1)
            s.people[p.id] = p
        }
        var l = s.companies[ci].value("apl").array
        l.append(.object(["id": .number(Double(p.id)), "w": .number(Double(s.week)), "role": .string(role), "ag": .number(agency ? 1 : 0)]))
        l.removeAll { s.week - $0["w"].int > keepWeeks || (s.people[$0["id"].int]?.employerID ?? 0) != 0 }
        s.companies[ci].set("apl", .array(l))
        let roleName = data.catalog.tables.roles[role]?.name ?? role
        let mid = s.companies[ci].managerID
        let id = s.addMessage(kind: "info", from: p.name, title: "\(p.name) applied for \(roleName)", body: "\(p.name) answered your \(agency ? "agency search" : "ad") for \(roleName) at \(s.companies[ci].name). See the applicants.",
                              companyID: co.id, tone: "n", status: "done", data: .object(["pid": .number(Double(p.id)), "kind": "applicant"]))
        if let mid, let mgr = s.people[mid], let k = s.inbox.firstIndex(where: { $0.id == id }) { s.inbox[k].handledBy = "\(mgr.name), manager" }
    }
}

public enum Agency {
    public enum EngageResult: Equatable, Sendable {
        case engaged(fee: Double, suggestions: [Int])
        case notEnoughCash(fee: Double)
        case missingRecord(String)
        case notPossible(String)
    }

    /// Share of the hired person's monthly pay the agency keeps, for the first `months` months. (Cheaper to find someone yourself in the long run.)
    public static let salaryShare = 0.08
    public static let months = 24
    /// Suggestions at once, and the better ones that follow (one a week for `laterWeeks` weeks, each with more skill than the last).
    public static let immediate = 3
    public static let laterWeeks = 3
    public static let skillBoostImmediate = 6.0
    public static let skillBoostLater = 12.0

    /// The upfront fee: eight times an ad's fee for the same role and company.
    public static let feeMultiple = 8.0
    public static func fee(_ s: GameState, companyID: Int, role: String, data: GameData) -> Double {
        jsRound(JobAds.fee(s, companyID: companyID, role: role, data: data) * feeMultiple)
    }

    public static func engage(_ s: inout GameState, companyID: Int, role: String, data: GameData) -> EngageResult {
        guard let ci = s.companyIndex(companyID), (s.companies[ci].status == .open || s.companies[ci].status == .setup) else { return .notPossible("This company is not open.") }
        let r = role.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { return .notPossible("Name the role.") }
        guard let f = JobAds.form(s, companyID: companyID), !f.companyName.isEmpty else { return .missingRecord("The agency needs the company name and organisation number.") }
        let fee = fee(s, companyID: companyID, role: r, data: data)
        guard s.companies[ci].cash >= fee, Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Agency: \(r)") else { return .notEnoughCash(fee: fee) }
        var ids: [Int] = []
        for _ in 0..<immediate {
            let before = Set(s.people.keys)
            JobAds.arrive(&s, companyIndex: ci, role: r, agency: true, boost: skillBoostImmediate, data: data)
            ids.append(contentsOf: s.people.keys.filter { !before.contains($0) })
        }
        var ag = s.companies[ci].value("agency").array
        ag.append(.object(["role": .string(r), "d0": .number(Double(s.week * 7 + s.day)), "got": 0]))
        if ag.count > 8 { ag.removeFirst(ag.count - 8) }
        s.companies[ci].set("agency", .array(ag))
        return .engaged(fee: fee, suggestions: ids.sorted())
    }

    /// Daily: the better-fitted candidates arrive one a week.
    public static func runDay(_ s: inout GameState, data: GameData) {
        let today = s.week * 7 + s.day
        for ci in s.companies.indices where (s.companies[ci].status == .open || s.companies[ci].status == .setup) && !s.companies[ci].value("agency").isNull {
            var ag = s.companies[ci].value("agency").array
            for k in ag.indices {
                var got = ag[k]["got"].int
                let elapsed = today - ag[k]["d0"].int
                while got < laterWeeks, elapsed >= 7 * (got + 1) {
                    JobAds.arrive(&s, companyIndex: ci, role: ag[k]["role"].string, agency: true, boost: skillBoostLater + 2 * Double(got), data: data)
                    got += 1
                }
                ag[k]["got"] = .number(Double(got))
            }
            s.companies[ci].set("agency", .array(ag.filter { $0["got"].int < laterWeeks }))
        }
    }

    /// At a hire: a person who came through the agency carries the fee obligation for `months` months.
    static func markHire(_ m: inout StaffMember, person n: Person, week: Int) {
        guard !n.value("ag").isNull, n.int("ag") == 1 else { return }
        m.set("agPct", salaryShare)
        m.set("agEnd", week + Int((Double(months) * 52 / 12).rounded()))
    }

    /// Month end: the agency's share of each agency hire's monthly wage, booked as an expense.
    public static func monthly(_ s: inout GameState, data: GameData) {
        for ci in s.companies.indices where (s.companies[ci].status == .open || s.companies[ci].status == .setup) {
            let due = s.companies[ci].staff.filter { $0.num("agPct") > 0 && s.week < $0.int("agEnd") }
            for m in due {
                let amount = jsRound(m.monthlyWage * m.num("agPct"))
                guard amount > 0 else { continue }
                let name = s.people[m.id]?.name ?? "staff"
                Payments.companyPays(&s, companyID: s.companies[ci].id, amount: amount, category: "oth", label: "Agency fee: \(name)")
            }
        }
    }
}
