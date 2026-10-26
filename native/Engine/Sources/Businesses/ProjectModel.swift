import Foundation
import GameCore
import Countries
import Finance

/// Project businesses: plumber, electrician, construction firm, engineering office, event agency (jobs measured in hours)
/// and the real-estate developer (land, zoning, building, selling units).
///
/// Originals: `FAM.project` / `FAM.dev` (engine/company/family_project.js), `R41` "trades work in hours"
/// (features/sales/trades_in_hours.js, which replaces the old contract-backlog model for every trade except the developer),
/// the event agency's bookings (features/screens/tidier_screens_and_monthly_bills.js, section 10) and public tenders
/// (features/sales/public_tenders.js).
///
/// How a job trade works (day by day, see `ProjectWeek.runDay`):
///  * requests arrive on the weekdays (more on Monday to Friday) in proportion to demand; a request is turned away
///    when the firm is booked more than three weeks ahead or the job is more than twelve weeks of work;
///  * the firm's hours (what its people and kit can deliver) go to the oldest job first; an event agency prepares
///    the nearest date first, and an event takes place on its day, ready or not;
///  * a job is paid when it is finished; big or long jobs pay 30% at the start, 40% halfway and 30% at the end
///    (milestones); an event pays 30% at booking and the rest after the event;
///  * business customers pay later (`terms` weeks, the usual receivable and a small chance of never paying);
///  * materials and subcontractors cost a share of what is paid (`cf`, with a random overrun per job).
public enum ProjectModel {
    // MARK: What each trade sells (R41.HT)

    /// Size classes are small, medium, big. `hv` is what one working hour brings in (labour and materials) in accounting units,
    /// before local prices. `mix` is how the three classes are shared out for each business choice ("Focus").
    public struct HoursSpec {
        public let hv: Double
        public let classes: [(Double, Double)]
        public let what: [[String]]
        public let mix: [String: [Double]]
        /// Same keys as `mix`, in the order the original lists them (the fallback is the second).
        public let mixOrder: [String]
        public let premium: [String: Double]
        /// An event agency: jobs have a fixed day.
        public let isEvent: Bool
        /// Native calibration (not in the original): what the work is priced at relative to the original's hour value, and how many
        /// requests a firm of this trade gets relative to the original's formula. They keep margins in the range real firms of the
        /// trade have (see docs/BALANCE_PARITY.md, "Project businesses").
        public let priceFactor: Double
        public let demandFactor: Double
    }

    public static let specs: [String: HoursSpec] = [
        "plumber": HoursSpec(
            hv: 1500, classes: [(4, 10), (10, 18), (30, 45)],
            what: [["Leaking tap", "Blocked drain", "New toilet", "Water heater swap", "Pipe repair", "Radiator fix"],
                   ["Kitchen plumbing", "Heat pump connection", "Underfloor heating", "New water pipes"], ["Bathroom renovation"]],
            mix: ["em": [0.9, 0.1, 0], "mix": [0.55, 0.3, 0.15], "bath": [0.1, 0.2, 0.7]], mixOrder: ["em", "mix", "bath"],
            premium: ["em": 1.3], isEvent: false, priceFactor: 1.15, demandFactor: 1.0),
        "electrician": HoursSpec(
            hv: 1650, classes: [(3, 8), (8, 16), (28, 45)],
            what: [["Fuse box check", "New sockets", "Light fittings", "Fault finding", "EV charger install"],
                   ["Kitchen rewiring", "Solar panels", "Smart home setup"], ["Full house rewiring", "Commercial installation"]],
            mix: ["home": [0.85, 0.15, 0], "mix": [0.55, 0.3, 0.15], "ind": [0.1, 0.3, 0.6]], mixOrder: ["home", "mix", "ind"],
            premium: [:], isEvent: false, priceFactor: 1.1, demandFactor: 1.0),
        "construction": HoursSpec(
            hv: 1500, classes: [(40, 120), (300, 700), (2000, 5000)],
            what: [["Terrace", "Garage", "Small extension", "Facade repair"], ["House extension", "Loft conversion", "Detached house"],
                   ["Apartment block", "Office building", "School building"]],
            mix: ["house": [0.55, 0.4, 0.05], "comm": [0.25, 0.5, 0.25], "pub": [0.05, 0.35, 0.6]], mixOrder: ["house", "comm", "pub"],
            premium: [:], isEvent: false, priceFactor: 1.27, demandFactor: 3.2),
        "engcons": HoursSpec(
            hv: 1700, classes: [(12, 40), (60, 160), (400, 1000)],
            what: [["Structural check", "Survey report", "Permit drawings", "Energy assessment"], ["House design", "Renovation project", "Extension drawings"],
                   ["Office building design", "Bridge study", "Housing project design"]],
            mix: ["res": [0.85, 0.15, 0], "bld": [0.6, 0.35, 0.05], "inf": [0.2, 0.5, 0.3]], mixOrder: ["res", "bld", "inf"],
            premium: [:], isEvent: false, priceFactor: 1.1, demandFactor: 1.25),
        "event": HoursSpec(
            hv: 2000, classes: [(12, 30), (40, 90), (150, 300)],
            what: [["party"], ["conference"], ["festival"]],
            mix: ["corp": [0.5, 0.4, 0.1], "conc": [0.1, 0.4, 0.5], "wed": [0.75, 0.25, 0]], mixOrder: ["corp", "conc", "wed"],
            premium: [:], isEvent: true, priceFactor: 0.82, demandFactor: 1.0),
    ]

    /// Trades that sell whole jobs in hours. Original: `R41.isHT`.
    public static func sellsHours(_ bd: Trade) -> Bool { bd.family == "project" && !bd.hasTrait("dev") && specs[bd.id] != nil }
    /// The real-estate developer. Original: `bd.tw.dev`.
    public static func isDeveloper(_ bd: Trade) -> Bool { bd.family == "project" && bd.hasTrait("dev") }

    /// The business choice "Focus" (knob `seg`) the company has picked. Original: `segOf`.
    static func segment(_ co: Company, _ bd: Trade) -> String {
        guard let k = bd.knobs.first(where: { $0.id == "seg" }), let o = Knobs.activeOptions(co, k).first else { return "mix" }
        return o.id
    }

    /// Share of small, medium and big jobs. A small firm gets more small jobs: clients with very big projects rarely ask a firm
    /// that would need half a year for them. Original: `mixOf`.
    static func mix(_ co: Company, _ bd: Trade) -> [Double] {
        let t = specs[bd.id]!
        let m0 = t.mix[segment(co, bd)] ?? t.mix["mix"] ?? t.mix[t.mixOrder[1]]!
        let hw = co.value("fm")["hw41"].double
        if !(hw > 0) { return m0 }
        let m = m0.enumerated().map { (i, p) -> Double in
            let a = (t.classes[i].0 + t.classes[i].1) / 2
            return a <= 3 * hw ? p : p * pow(3 * hw / a, 1.5)
        }
        let tot = m.reduce(0, +)
        return tot > 0 ? m.map { $0 / tot } : m0
    }

    /// Average hours of a request for a mix. Original: `avgOf`.
    static func averageHours(_ t: HoursSpec, _ m: [Double]) -> Double {
        var a = 0.0
        for (i, p) in m.enumerated() { a += p * (t.classes[i].0 + t.classes[i].1) / 2 }
        return a
    }

    /// What one hour is worth where you work: local prices, your own price level and reputation; emergency work pays extra.
    /// Original: `hvLocal`.
    static func hourValue(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let t = specs[bd.id]!
        let tk = Knobs.effect(co, bd, "t", w)
        let pl = Pricing.ticketMultiplier(co, bd, w) / max(0.01, Pricing.jobScale(co) * tk)
        return t.hv * pl * (1 + (co.reputation - 50) / 500) * (t.premium[segment(co, bd)] ?? 1) * t.priceFactor
    }

    /// Hours the firm can bill in a week: what its people and equipment can deliver. Original: `hoursWeek`.
    static func hoursPerWeek(_ bd: Trade, capacity: Double) -> Double {
        max(0, capacity * bd.ticket / specs[bd.id]!.hv)
    }

    // MARK: Jobs

    /// One job on the order book (a record in `fm.jobs`; the field names are the original's).
    public struct Job: JSONRecord, Identifiable {
        public var raw: [String: JSONValue]
        public init(raw: [String: JSONValue]) { self.raw = raw }
        public var id: Int { int("id") }
        /// Worked out in hours (every job is, after `normalise`).
        public var inHours: Bool { get { flag("h41") } set { set("h41", newValue) } }
        /// 0 small, 1 medium, 2 big
        public var sizeClass: Int { get { int("cls") } set { set("cls", newValue) } }
        public var what: String { get { str("what") } set { set("what", newValue) } }
        public var client: String { get { str("client") } set { set("client", newValue) } }
        /// Hours first quoted, and hours it will really take (an overrun makes it more).
        public var quotedHours: Double { get { num("hq") } set { set("hq", newValue) } }
        public var hours: Double { get { num("h") } set { set("h", newValue) } }
        public var hoursDone: Double { get { num("done") } set { set("done", newValue) } }
        public var contractValue: Double { get { num("v") } set { set("v", newValue) } }
        public var paid: Double { get { num("paid") } set { set("paid", newValue) } }
        /// Retention held back by the client on the milestone payments so far (net of VAT); paid after completion and the defect period.
        public var retained: Double { get { num("ret") } set { set("ret", newValue) } }
        /// Materials and subcontractors as a share of what the client pays.
        public var costShare: Double { get { num("cf") } set { set("cf", newValue) } }
        /// Working days the job is held up (an event can do this).
        public var delay: Double { get { num("delay") } set { set("delay", newValue) } }
        public var startWeek: Int { get { int("w0") } set { set("w0", newValue) } }
        public var progress: Double { get { num("p") } set { set("p", newValue) } }
        public var weeks: Int { get { int("wks") } set { set("wks", newValue) } }
        /// Milestone payments (30% / 40% / 30%): nil until the first hour is worked.
        public var milestones: Bool? { get { value("st41").isNull ? nil : flag("st41") } set { raw["st41"] = newValue.map { .bool($0) } ?? .null } }
        public var dueDay: Int? { get { value("dueD").isNull ? nil : int("dueD") } set { raw["dueD"] = newValue.map { .number(Double($0)) } ?? .null } }
        public var dueWeek: Int { get { int("due") } set { set("due", newValue) } }
        public var source: String { get { str("src") } set { set("src", newValue) } }
        public var from: String { get { str("from") } set { set("from", newValue) } }
        public var isPublic: Bool { flag("pub") }
        public var remainingHours: Double { max(0, hours - hoursDone) }
        public var remainingPayment: Double { contractValue - paid }
    }

    static func jobs(_ fm: JSONValue) -> [Job] { fm["jobs"].array.map { Job(raw: $0.object) } }
    static func jsonJobs(_ jobs: [Job]) -> JSONValue { .array(jobs.map { .object($0.raw) }) }

    /// Jobs from older saves and tenders that were won are turned into hours. Original: `norm`.
    static func normalise(_ j: inout Job, _ bd: Trade, hourValue hvl: Double, week: Int, random r: inout DeterministicRandom) {
        if j.inHours { return }
        let t = specs[bd.id]!
        let h = max(1, jsRound(j.contractValue / max(1, hvl)))
        let c = h > t.classes[1].1 ? 2 : h > t.classes[0].1 ? 1 : 0
        j.inHours = true; j.sizeClass = c; j.hours = h; j.quotedHours = h
        j.hoursDone = jsRound(h * j.progress); j.paid = jsRound(j.contractValue * j.progress)
        if j.what.isEmpty { j.what = r.pick(t.what[c]) }
        if j.client.isEmpty { j.client = "a client" }
        if t.isEvent && j.dueDay == nil { j.dueDay = max(week + 1, j.dueWeek != 0 ? j.dueWeek : week + 2) * 7 + 3 }
    }

    /// The names of the people and firms that ask. Original: `clientName` (+ `personName`, `brandCoName`).
    static func clientName(_ co: Company, _ cls: Int, _ country: Country, _ r: inout DeterministicRandom) -> String {
        if cls == 0 || (cls == 1 && r.next() < 0.6) {
            let last = country.lastNames
            return "the " + (last.isEmpty ? "Smith" : last[Int((r.next() * Double(last.count)).rounded(.down))]) + " family"
        }
        return r.pick(["a housing co-op", "the municipality", "a developer", "a retail chain", "the school board", "an office owner", "a hotel", "a landlord"])
    }

    /// A new request for work of the class the mix picks. Original: `newJob` (trades_in_hours.js).
    static func newJob(_ s: inout GameState, _ co: Company, _ bd: Trade, hourValue hvl: Double, country: Country) -> Job {
        let t = specs[bd.id]!, m = mix(co, bd)
        var x = s.random.next(), c = 0
        while c < 2 { x -= m[c]; if x > 0 { c += 1 } else { break } }
        let r = t.classes[c]
        let hq = jsRound(r.0 + s.random.next() * (r.1 - r.0))
        let tw = bd.traits
        let over = (tw["over"] ?? 0.07) * (c == 2 ? 2.5 : 1.6)
        let h = max(1, jsRound(hq * max(0.7, 1 + s.random.gauss() * over + 0.02)))
        let base = ((tw["mat"] ?? 0) + (tw["sub"] ?? 0)) * DemandModel.modifier(co, "price") * (s.economy.materials * 0.5 + 0.5) * (1 + s.random.gauss() * (tw["over"] ?? 0.07))
        let step: Double = hq * hvl >= 20000 ? 1000 : 100
        var j = Job(raw: [:])
        j.set("id", s.makeID())
        j.inHours = true; j.sizeClass = c
        j.what = s.random.pick(t.what[c])
        j.client = clientName(co, c, country, &s.random)
        j.quotedHours = hq; j.hours = h; j.hoursDone = 0
        j.contractValue = max(step, jsRound(hq * hvl / step) * step)
        j.paid = 0; j.costShare = max(0.05, base); j.delay = 0; j.startWeek = s.week; j.progress = 0
        j.weeks = Int(max(1, jsRound(h / 37.5)))
        return j
    }

    // MARK: The day's log (stored as fm.d41)

    struct DayLog {
        var week: Int
        var days: Set<Int> = []
        var requests = 0.0, took = 0.0, lost = 0.0, big = 0.0, tooBig = 0.0
        var used = 0.0, hoursAvailableToday = 0.0, hoursPerWeekSum = 0.0, requestedHours = 0.0
        var rev = 0.0, cogs = 0.0, paid = 0.0, units = 0.0
        var finished = [0.0, 0.0, 0.0]
        var names: [String] = []
        /// Retention withheld on milestone payments this week (job id: net amount), and the jobs completed this week that had some.
        var held: [Int: Double] = [:]
        var released: [Int] = []

        init(week: Int) { self.week = week }
        init(json j: JSONValue) {
            week = j["w"].int
            days = Set(j["days"].object.keys.compactMap { Int($0) })
            requests = j["req"].double; took = j["took"].double; lost = j["lost"].double; big = j["big"].double; tooBig = j["tooBig"].double
            used = j["used"].double; hoursAvailableToday = j["H"].double; hoursPerWeekSum = j["Hw"].double; requestedHours = j["Dh"].double
            rev = j["rev"].double; cogs = j["cogs"].double; paid = j["paid"].double; units = j["units"].double
            finished = (0..<3).map { j["fin"][$0].double }
            names = j["names"].array.map { $0.string }
            held = Dictionary(uniqueKeysWithValues: j["held"].object.compactMap { k, v in Int(k).map { ($0, v.double) } })
            released = j["rel"].array.map { $0.int }
        }
        var json: JSONValue {
            var d: [String: JSONValue] = [:]
            for k in days { d[String(k)] = 1 }
            return .object(["w": .number(Double(week)), "days": .object(d), "req": .number(requests), "took": .number(took), "lost": .number(lost),
                            "big": .number(big), "tooBig": .number(tooBig), "used": .number(used), "H": .number(hoursAvailableToday),
                            "Hw": .number(hoursPerWeekSum), "Dh": .number(requestedHours), "rev": .number(rev), "cogs": .number(cogs),
                            "paid": .number(paid), "units": .number(units), "fin": .array(finished.map { .number($0) }),
                            "names": .array(names.map { .string($0) }),
                            "held": .object(Dictionary(uniqueKeysWithValues: held.map { (String($0.key), JSONValue.number($0.value)) })),
                            "rel": .array(released.map { .number(Double($0)) })])
        }
    }

    // MARK: Reviews (small: a finished job may be reviewed)

    /// How often a customer writes a review (shared with every trade: `Reviews.rate`).
    static func reviewRate(_ bd: Trade) -> Double { Reviews.rate(bd) }

    /// One more review, written by the shared review system (`Reviews`). Original: `addReviews`.
    static func addReview(_ s: inout GameState, _ i: Int, bias: Double) { Reviews.add(&s, i, bias: bias) }

    /// Average of the real reviews (the rating until there are some). Original: `avgRv`.
    public static func averageRating(_ co: Company) -> Double { Reviews.rating(co) }

    // MARK: Events

    /// What an event does to the work: a cost overrun, a defect claim, a delay. Original: `FAM.project.fx` (the developer's own and,
    /// for job trades, the hours version of trades_in_hours.js).
    public static func applyEffect(_ s: inout GameState, _ i: Int, _ fx: JSONValue, bd: Trade) {
        let id = s.companies[i].id
        let fm = s.companies[i].value("fm")
        if isDeveloper(bd) {
            var list = ProjectDeveloper.projects(s.companies[i])
            guard let k = list.firstIndex(where: { $0.stage == "build" }) else { return }
            if fx["ovr"].double != 0 { list[k].overrun += list[k].build * fx["ovr"].double }
            if fx["delay"].double != 0 { list[k].delay += Int(fx["delay"].double) }
            ProjectDeveloper.setProjects(&s, i, list)
            return
        }
        guard sellsHours(bd) else { return }
        var all = jobs(fm)
        let idx = all.indices.filter { all[$0].inHours }
        if fx["ovr"].double != 0 && !idx.isEmpty {
            let k = s.random.pick(idx)
            all[k].hours = jsRound(all[k].hours * (1 + min(0.5, fx["ovr"].double * 2)))
        }
        if fx["defect"].double != 0 && fm["done"].double != 0 {
            let hvl = fm["hvl41"].double != 0 ? fm["hvl41"].double : 1000
            Payments.companyPays(&s, companyID: id, amount: jsRound(hvl * 6 * fx["defect"].double), category: "loss", label: "Fixing a finished job")
        }
        if !fx["delay"].isNull && !idx.isEmpty {
            let k = s.random.pick(idx)
            all[k].delay += fx["delay"].double
        }
        var f2 = s.companies[i].value("fm")
        f2["jobs"] = jsonJobs(all)
        s.companies[i].set("fm", f2)
    }
}
