import Foundation
import GameCore
import Countries
import Employees
import Finance

// Hiring rebuild (engine side): workplaces, per-worker promises with patience, the role catalog with real effects, the worker profile.

// MARK: Workplaces

/// How many people can work at a company's premises. `capacity` nil = no limit (shops, workshops, trade floors); `used` includes the owner when the owner
/// works there (no manager and owner hours above zero); `free` nil when unlimited.
public struct WorkplaceInfo: Equatable, Sendable {
    public var capacity: Int?
    public var used: Int
    public var free: Int?
    public var placeKind: String
    /// Words for the screen: "6 office places, 4 in use", or "No limit on people here".
    public var note: String
}

public enum Workplaces {
    /// Square metres per desk in an office (matches `PremisesExtras.wantedSquareMetres`, which sizes a place at 9 m² a head).
    public static let squareMetresPerPlace = 9.0
    /// A smallest rented office has this many places.
    public static let smallestOffice = 2
    /// Working from home: the kitchen table seats this many (a team of four has outgrown it, see `PremisesExtras.hasOutgrownHome`).
    public static let homePlaces = 3

    /// Where a role does its work. On-site roles sit at a desk or bench in the premises; mobile roles work at customers' sites, in vehicles or on the road;
    /// remote roles work from their own home. Only on-site roles take a place.
    public enum WorkMode: String, Sendable { case onSite, mobile, remote }

    static let mobileRoles: Set<String> = ["cleaner", "plumb", "elec", "labour", "carp", "foreman", "handy", "estate", "instr", "tutor", "event", "av", "engineer",
                                           "guard", "insadv", "mortadv", "sales", "photog", "carwash", "tcons", "consult", "farmh", "courier", "driver", "truckd"]
    static let remoteRoles: Set<String> = ["dev", "designer", "marketer", "acct", "lawyer", "paralegal", "projc", "hr", "architect", "analyst", "ittech"]

    public static func mode(role: String) -> WorkMode { mobileRoles.contains(role) ? .mobile : remoteRoles.contains(role) ? .remote : .onSite }
    public static func needsPlace(role: String) -> Bool { mode(role: role) == .onSite }

    /// The places a premises of this kind and size holds: offices by area, home by the table, everything else unlimited (nil).
    public static func places(kind: String, squareMetres m2: Double) -> Int? {
        switch kind {
        case "office": return max(smallestOffice, Int(saturating: (m2 / squareMetresPerPlace).rounded(.down)))
        case "home": return homePlaces
        default: return nil
        }
    }

    /// The kind of premises the company has now: its stored place, else the trade's own kind.
    static func kind(_ co: Company, _ bd: Trade?) -> String {
        let k = co.value("prem")["kind"]
        if let bd, PremisesExtras.isHomeTrade(bd) { return PremisesExtras.isAtHome(co, bd) ? "home" : PremisesExtras.placeKind(bd) }   // a home trade works at home until it rents a place
        if !k.isNull { return k.string }
        return bd?.premisesKind ?? "none"
    }

    static func area(_ co: Company, _ bd: Trade?) -> Double {
        let m2 = co.value("prem")["m2"].double
        if m2 > 0 { return m2 }
        guard let bd else { return 0 }
        return max(10, jsRound(bd.premisesM2 * co.size))
    }

    public static func info(_ co: Company, data: GameData) -> WorkplaceInfo {
        let bd = data.catalog[co.type]
        let k = kind(co, bd)
        let used = PremisesExtras.onSiteHeads(co)
        guard let cap = places(kind: k, squareMetres: area(co, bd)) else {
            return WorkplaceInfo(capacity: nil, used: used, free: nil, placeKind: k, note: "No limit on how many people work here.")
        }
        let word = k == "home" ? "places at home" : "office places"
        return WorkplaceInfo(capacity: cap, used: used, free: max(0, cap - used), placeKind: k, note: "\(cap) \(word), \(used) in use.")
    }

    /// Why one more person cannot be hired here (nil when there is room).
    /// A role that works at customers' sites or remotely is never blocked by a full office.
    public static func hireBlock(_ co: Company, role: String? = nil, data: GameData) -> String? {
        if let role, !needsPlace(role: role) { return nil }
        let i = info(co, data: data)
        guard let free = i.free, free <= 0 else { return nil }
        let at = i.placeKind == "home" ? "the home" : "the office"
        return "No free desk: \(at) seats \(i.capacity ?? 0) and all are taken. Move to bigger premises, or hire for a role that works at customers' sites or remotely."
    }

    /// The cheapest listing that seats everyone on site plus one more; nil when the company owns its place or no listing is big enough.
    public static func roomListing(_ s: GameState, companyID: Int, data: GameData) -> CompanySetup.Listing? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], !co.value("prem")["owned"].bool else { return nil }
        let after = PremisesExtras.isHomeTrade(bd) ? PremisesExtras.placeKind(bd) : kind(co, bd)
        let need = PremisesExtras.onSiteHeads(co) + 1
        let fits = CompanySetup.listings(for: co, bd, World(state: s, data: data)).filter { l in
            guard let n = places(kind: after, squareMetres: l.squareMetres) else { return true }
            return n >= need && l.squareMetres > co.value("prem")["m2"].double
        }
        return fits.min { $0.squareMetres * $0.rentFactor < $1.squareMetres * $1.rentFactor }
    }
}

// MARK: Promises per worker, with patience

public struct WorkerPromise: Equatable, Sendable, Identifiable {
    public var id: Int
    public var personID: Int
    public var companyID: Int
    public var kind: String
    public var text: String
    public var dueWeek: Int
    public var dueDate: GameCalendar.Date
    /// How many times they have agreed to wait.
    public var waits: Int
    /// How many more times they will agree to wait (0: the next delay is not accepted and patience is gone).
    public var patienceLeft: Int
    /// "Pending", "Due", "Fulfilled", "Broken" or "Renegotiated".
    public var status: String
    public var isOpen: Bool
}

/// A worker brings up a promise within two weeks of its date. With a manager the question is the manager's (`Delegation.level` puts it at the manager's rank,
/// `GameEngine.routeFreshDecisions` answers it); otherwise it lands in the owner's inbox. "Keep it now" does the thing; "Ask to wait" moves the date by
/// `waitWeeks` and costs patience: after `maxWaits` waits the worker is out of patience (mood mark, and a deterministic chance they hand in notice).
public enum PromiseReminders {
    public static let action = "prmr"
    public static let reminderWeeks = 2
    public static let waitWeeks = 3
    public static let maxWaits = 2
    /// Chance (deterministic per promise) that a worker whose patience has run out hands in notice.
    public static let quitChance = 0.3

    static func worker(_ p: StaffPromises.Promise) -> WorkerPromise {
        WorkerPromise(id: p.id, personID: p.personID, companyID: p.companyID, kind: p.kind.title, text: p.text, dueWeek: p.dueWeek, dueDate: p.dueDate,
                      waits: p.renegotiations, patienceLeft: p.isOpen ? max(0, maxWaits - p.renegotiations) : 0, status: p.status.rawValue, isOpen: p.isOpen)
    }

    public static func promises(_ s: GameState, personID: Int, companyID: Int) -> [WorkerPromise] {
        StaffPromises.promises(s, personID: personID).filter { $0.companyID == companyID }.map(worker)
    }

    /// Weekly: remind about every open promise that falls due within `reminderWeeks`, once per date.
    public static func weekly(_ s: inout GameState, data: GameData) {
        let ids = s.people.values.filter { $0.raw[StaffPromises.key] != nil }.map { $0.id }.sorted()
        for id in ids {
            guard let n = s.people[id] else { continue }
            let seen = Set(n.value("prmR").array.map { $0.string })
            var fresh: [String] = []
            for (p, _) in StaffPromises.records(n) where p.isOpen && p.companyID != 0 && s.week >= p.dueWeek - reminderWeeks {
                let tag = "\(p.id):\(p.dueWeek)"
                guard !seen.contains(tag), let co = s.company(p.companyID), (co.status == .open || co.status == .setup),
                      !StaffPromises.isGroup(s, companyID: p.companyID, personID: id),
                      co.managerID == id || co.staff.contains(where: { $0.id == id }) else { continue }
                fresh.append(tag)
                let left = max(0, maxWaits - p.renegotiations)
                let first = ManagerModelNames.first(n.name)
                var options: [JSONValue] = [.option("Keep it now", "Do what was promised.", effects: ["rep": .number(2)])]
                options.append(left > 0
                               ? .option("Ask to wait", "Moves the date by \(waitWeeks) weeks. \(first) loses some patience: \(left) wait\(left == 1 ? "" : "s") left.", effects: ["rep": .number(-1)])
                               : .option("Let it slide", "\(first) has waited long enough. They will feel let down and may leave.", effects: ["rep": .number(-5)]))
                s.addMessage(kind: "ask", from: n.name, title: "\(first) asks about your promise",
                             body: "\(first) was promised: \(p.text) It is due \(GameCalendar.dateString(week: p.dueWeek)).\(left == 0 ? " They have already waited twice." : "")",
                             companyID: p.companyID, tone: "n", status: "open", options: options, action: action,
                             data: .object(["pid": .number(Double(id)), "prid": .number(Double(p.id))]))
            }
            if !fresh.isEmpty, var n2 = s.people[id] {
                var all = n2.value("prmR").array
                all.append(contentsOf: fresh.map { .string($0) })
                if all.count > 24 { all.removeFirst(all.count - 24) }
                n2.set("prmR", .array(all))
                s.people[id] = n2
            }
        }
    }

    /// The inbox answer: option 0 keeps it, option 1 asks to wait (or lets it slide when patience is gone).
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        let d = m.value("data")
        let pid = d["pid"].int, prid = d["prid"].int
        if idx == 0 { _ = keepNow(&s, personID: pid, promiseID: prid, data: data) } else { _ = askToWait(&s, personID: pid, promiseID: prid, data: data) }
    }

    public enum Outcome: Equatable, Sendable { case kept, waited(newDueWeek: Int, patienceLeft: Int), letSlide, notPossible(String) }

    /// Do what was promised, as far as the engine can do it by itself (a raise, a course); promises about a new post or conditions are marked kept with a
    /// modest pay step standing for the new duties. Returns `.kept`.
    @discardableResult
    public static func keepNow(_ s: inout GameState, personID: Int, promiseID: Int, data: GameData) -> Outcome {
        guard let n = s.people[personID], let rec = StaffPromises.records(n).first(where: { $0.0.id == promiseID && $0.0.isOpen }) else { return .notPossible("That promise is not open.") }
        let p = rec.0
        if let ci = s.companyIndex(p.companyID), s.companies[ci].staff.contains(where: { $0.id == personID }) {
            switch p.kind {
            case .salaryReview: StaffTalks.keptPromiseRaise(&s, companyIndex: ci, staffID: personID, percent: 0.05, data: data)
            case .promotion, .responsibility: StaffTalks.keptPromiseRaise(&s, companyIndex: ci, staffID: personID, percent: 0.04, data: data)
            case .training:
                if let c = StaffProfile.courses(s.companies[ci], data: data).first { _ = StaffProfile.takeCourse(&s, companyID: p.companyID, staffID: personID, courseID: c.id, data: data) }
            default: break
            }
        }
        StaffPromises.noticeChange(&s, companyID: p.companyID)
        if let n2 = s.people[personID] {
            var list = StaffPromises.records(n2)
            if let i = list.firstIndex(where: { $0.0.id == promiseID && $0.0.isOpen }) {
                var q = list[i].0
                q.status = .fulfilled; q.resolvedWeek = s.week
                list[i].0 = q
                StaffPromises.store(list, &s, personID: personID)
                StaffPromises.kept(&s, q, n2)
            }
        }
        return .kept
    }

    /// Ask the worker to wait. Allowed `maxWaits` times; each costs their cheer, and the last one leaves them out of patience.
    @discardableResult
    public static func askToWait(_ s: inout GameState, personID: Int, promiseID: Int, data: GameData) -> Outcome {
        guard let n = s.people[personID] else { return .notPossible("This person is gone.") }
        var list = StaffPromises.records(n)
        guard let i = list.firstIndex(where: { $0.0.id == promiseID && $0.0.isOpen }) else { return .notPossible("That promise is not open.") }
        var p = list[i].0
        if p.renegotiations >= maxWaits { return letSlide(&s, personID: personID, promiseID: promiseID, data: data) }
        p.renegotiations += 1
        p.dueWeek = max(p.dueWeek, s.week) + waitWeeks
        p.status = .pending
        if let r = p.text.range(of: " by ") { p.text = String(p.text[..<r.lowerBound]) + " by " + GameCalendar.dateString(week: p.dueWeek) + " (moved)." }
        list[i].0 = p
        StaffPromises.store(list, &s, personID: personID)
        let left = maxWaits - p.renegotiations
        if let ci = s.companyIndex(p.companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == personID }) {
            var st = s.companies[ci].staff
            st[k].happyUntilWeek = min(st[k].happyUntilWeek, s.week)   // a delay ends any cheer
            if left == 0 { st[k].set("denied", s.week) }               // patience is gone: the existing mood mark and quit risk
            s.companies[ci].staff = st
            if left == 0 {
                s.note("\(n.name) has run out of patience with the promise made to them.", tone: "bad", companyID: p.companyID)
                maybeQuit(&s, companyIndex: ci, personID: personID, promiseID: promiseID, data: data)
            }
        }
        return .waited(newDueWeek: p.dueWeek, patienceLeft: left)
    }

    /// Patience was already gone and the answer is still "not now": the promise is broken now.
    @discardableResult
    static func letSlide(_ s: inout GameState, personID: Int, promiseID: Int, data: GameData) -> Outcome {
        guard let n = s.people[personID] else { return .notPossible("This person is gone.") }
        var list = StaffPromises.records(n)
        guard let i = list.firstIndex(where: { $0.0.id == promiseID && $0.0.isOpen }) else { return .notPossible("That promise is not open.") }
        var p = list[i].0
        p.status = .broken; p.resolvedWeek = s.week
        list[i].0 = p
        StaffPromises.store(list, &s, personID: personID)
        StaffPromises.broken(&s, p, n)
        if let ci = s.companyIndex(p.companyID) { maybeQuit(&s, companyIndex: ci, personID: personID, promiseID: promiseID, data: data) }
        return .letSlide
    }

    static func maybeQuit(_ s: inout GameState, companyIndex ci: Int, personID: Int, promiseID: Int, data: GameData) {
        guard s.companies[ci].staff.contains(where: { $0.id == personID && $0.noticeWeeks == 0 }) else { return }
        if HashedRandom.first("prq:\(promiseID):\(personID)") < quitChance { StaffRoutine.handle(&s, companyIndex: ci, .quit(staffID: personID), data: data) }
    }
}

// MARK: Role catalog with real effects

/// One role a company can fill: the core jobs of the trade and the recommended extras. `effect` says in words what a filled extra does.
public struct RoleOption: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var isCore: Bool
    /// What it does when someone fills it ("Cuts losses from theft by 30 percent"); empty for core roles.
    public var effect: String
    public var filled: Bool
}

public enum RoleEffects {
    /// Security guard: shop and venue losses (the trade's shrink) are this share of what they would be; staff theft grows half as fast.
    public static let guardLossFactor = 0.55
    /// Marketing responsible: campaigns gain this much more awareness; more while the owner works somewhere else (fewer than `ownerAwayHours` here).
    public static let marketingGain = 0.15
    public static let marketingGainOwnerAway = 0.30
    public static let ownerAwayHours = 20.0
    /// Developer: development projects take this share of the weeks (rounded up).
    public static let developerWeeksFactor = 0.75
    /// Accountant and cleaner: less chance an inspection finds something (probability points).
    public static let accountantInspection = 0.10
    public static let cleanerInspection = 0.08
    /// Receptionist: more awareness from the front door.
    public static let receptionistGain = 0.08

    struct Extra { var id: String; var effect: String }
    static let table: [String: Extra] = [
        "guard": Extra(id: "guard", effect: "Cuts losses from theft and shrinkage by 45 percent."),
        "marketer": Extra(id: "marketer", effect: "Campaigns reach 15 percent more people, 30 percent while you work somewhere else."),
        "advisor": Extra(id: "advisor", effect: "Shows what a new product or service would do to profit and market share."),
        "dev": Extra(id: "dev", effect: "Development projects take a quarter less time."),
        "acct": Extra(id: "acct", effect: "Inspections find fewer faults (10 points lower chance)."),
        "cleaner": Extra(id: "cleaner", effect: "Inspections find fewer faults (8 points lower chance)."),
        "recept": Extra(id: "recept", effect: "The front door brings 8 percent more awareness."),
    ]

    /// Recommended extra roles per kind of trade (by trade family; a developer only where there is something to develop).
    public static func extraIDs(forTrade bd: Trade) -> [String] {
        var out: [String]
        switch bd.family {
        case "svc": out = ["marketer", "acct", "recept", "cleaner"]
        case "venue": out = ["guard", "cleaner", "marketer", "recept", "acct"]
        case "retail": out = ["guard", "marketer", "cleaner", "acct"]
        case "logi", "rent": out = ["guard", "acct", "marketer", "recept"]
        case "project", "prod": out = ["acct", "marketer", "guard", "cleaner"]
        default: out = ["acct", "marketer", "recept"]
        }
        if ["startup", "webdev", "mktg", "engcons"].contains(bd.id) { out.insert("dev", at: 0) }
        if !["hold", "fin", "energy"].contains(bd.family) { out.append("advisor") }
        return out
    }

    /// Someone is filling the role: hired for it, or given it as their duty. People on notice do not count.
    public static func filled(_ co: Company, _ roleID: String) -> Bool {
        co.staff.contains { $0.noticeWeeks == 0 && ($0.role == roleID || $0.str("duty") == roleID) }
    }

    public static func catalog(for co: Company, data: GameData) -> [RoleOption] {
        guard let bd = data.catalog[co.type] else { return [] }
        let t = data.catalog.tables.roles
        var seen = Set<String>()
        var out: [RoleOption] = []
        for (r, _) in bd.standardStaff where seen.insert(r).inserted {
            out.append(RoleOption(id: r, name: t[r]?.name ?? r, isCore: true, effect: "", filled: co.staff.contains { $0.role == r }))
        }
        for r in extraIDs(forTrade: bd) where seen.insert(r).inserted {
            out.append(RoleOption(id: r, name: t[r]?.name ?? r, isCore: false, effect: table[r]?.effect ?? "", filled: filled(co, r)))
        }
        return out
    }

    // The hooks (each is one multiplication or subtraction at the place the effect already lives).
    public static func shrinkFactor(_ co: Company) -> Double { filled(co, "guard") ? guardLossFactor : 1 }
    public static func awarenessFactor(_ co: Company) -> Double {
        var f = 1.0
        if filled(co, "marketer") { f += co.ownerHours < ownerAwayHours ? marketingGainOwnerAway : marketingGain }
        if filled(co, "recept") { f += receptionistGain }
        return f
    }
    public static func developmentWeeks(_ weeks: Int, _ co: Company) -> Int { filled(co, "dev") ? max(1, Int(saturating: (Double(weeks) * developerWeeksFactor).rounded(.up))) : weeks }
    public static func inspectionRelief(_ co: Company) -> Double { (filled(co, "acct") ? accountantInspection : 0) + (filled(co, "cleaner") ? cleanerInspection : 0) }
    public static func theftGrowthFactor(_ co: Company) -> Double { filled(co, "guard") ? 0.5 : 1 }

    /// Give a hired person a duty (a role from the company's catalog; nil or empty clears it). "Seat him in my office while he does marketing."
    @discardableResult
    public static func setDuty(_ s: inout GameState, companyID: Int, employeeID: Int, duty: String?, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == employeeID }) else { return false }
        var st = s.companies[ci].staff
        if let d = duty, !d.isEmpty {
            guard catalog(for: s.companies[ci], data: data).contains(where: { $0.id == d }) else { return false }
            st[k].set("duty", d)
        } else {
            st[k].set("duty", .null)
        }
        s.companies[ci].staff = st
        return true
    }
}

// MARK: Worker profile

public struct WorkerProfile: Equatable, Sendable {
    public var employeeID: Int
    public var name: String
    public var role: String
    public var roleName: String
    public var duty: String?
    public var monthlyWage: Double
    public var payBasis: String
    public var contract: EmploymentContract.Summary?
    public var hoursPerWeek: Double
    /// Contracted hours since they started (absences are not deducted).
    public var hoursWorked: Double
    public var weeksEmployed: Int
    public var promises: [WorkerPromise]
    /// "Leaving", "Unhappy", "Happy", "Mixed" or "Content", and the reasons.
    public var mood: String
    public var moodGood: [String]
    public var moodBad: [String]
    /// What the work is worth now (their skill with what they have learned, 0 to 100), what the pay leads you to expect, and whether it is met.
    public var performance: Double
    public var expectedPerformance: Double
    public var meetsExpectation: Bool
    public var performanceNote: String
}

public enum WorkerProfiles {
    /// The skill the pay should buy: what the person earns against the going pay for the role, on a scale where the going pay buys 55.
    public static func expected(wage: Double, market: Double) -> Double { clamp(55 * wage / max(1, market), 20, 90) }

    public static func profile(_ s: GameState, companyID: Int, employeeID: Int, data: GameData) -> WorkerProfile? {
        guard let co = s.company(companyID), let m = co.staff.first(where: { $0.id == employeeID }), let n = s.people[employeeID] else { return nil }
        let mood = StaffProfile.mood(s, companyID: companyID, staffID: employeeID, data: data)
        let hours = m.weeklyHours ?? StaffModel.fullWeekHours
        let weeks = max(0, s.week - m.hiredWeek)
        let perf = StaffModel.skill(m, person: n, salesRoles: data.catalog.tables.salesRoles)
        let market = StaffProfile.marketPay(s, co, m, data: data)
        let exp = expected(wage: m.monthlyWage + m.num("bnEma"), market: market)
        let met = perf >= exp - 5
        let note = perf >= exp + 10 ? "Doing better than the pay leads you to expect." : met ? "About what the pay leads you to expect." : "Below what the pay leads you to expect."
        return WorkerProfile(employeeID: employeeID, name: n.name, role: m.role, roleName: data.catalog.tables.roles[m.role]?.name ?? m.role,
                             duty: m.value("duty").isNull ? nil : m.str("duty"), monthlyWage: m.monthlyWage, payBasis: m.payBasis,
                             contract: EmploymentContract.summary(s, companyID: companyID, personID: employeeID, data: data), hoursPerWeek: hours,
                             hoursWorked: Double(weeks) * hours, weeksEmployed: weeks, promises: PromiseReminders.promises(s, personID: employeeID, companyID: companyID),
                             mood: mood?.word ?? "Content", moodGood: mood?.good ?? [], moodBad: mood?.bad ?? [], performance: perf, expectedPerformance: exp,
                             meetsExpectation: met, performanceNote: note)
    }
}
