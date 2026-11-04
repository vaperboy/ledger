import Foundation
import GameCore
import Countries
import Finance

/// The middle-man trades that earn commission on what others make (owner brief, 4 Nov 2026): the travel agency (`travel`), the insurance broker
/// (`insbroker`) and the finance and mortgage broker (`finbroker`). They hold no stock. A sale is a deal placed with a supplier (an operator, an airline,
/// a hotel, an insurer, a lender), and the money comes from that supplier, later, as commission. All figures are in `Resources/brokers.json`.
///
/// * Travel: customers book weeks ahead (deposit, then balance); the agency passes the money on and the supplier pays the commission after the trip
///   (8 to 12 percent on packages, 5 to 9 on flights and hotels). A booking can be cancelled before the trip: no commission, only a small handling fee.
///   Flights and hotels are placed with the player's own airline or hotel company when there is one in the country (that company pays the commission,
///   a real transfer through `Payments`), else with generic operators.
/// * Insurance: the broker earns first-year commission when the policy starts and renewal commission each year it is kept. A policy that is cancelled in
///   the first year is clawed back by the insurer (the unearned part). Each yearly renewal keeps only part of the book (retention).
/// * Finance: an application can be declined or fall through. A completed loan pays a procuration commission (a share of the loan) and the lender and
///   client fees, then a trail commission on the balance each quarter. A loan repaid early in its first two years is clawed back.
///
/// State on the company: `brk` = { deals: [...], cohorts: [...], st: {...} } (a save without it starts empty).
public enum Brokers {
    public static let tradeIDs: Set<String> = ["travel", "insbroker", "finbroker"]
    public static func handles(_ bd: Trade) -> Bool { tradeIDs.contains(bd.id) }

    /// The data file (`brokers.json`), read once.
    static let config: JSONValue = {
        guard let url = Bundle.module.url(forResource: "brokers", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    // MARK: Records

    /// A deal waiting to pay: a booking before the trip, or a loan application before completion.
    struct Deal: Equatable {
        var id: Int
        var line: String
        var due: Int
        /// Week a booking is cancelled (0 = it is not)
        var cancelWeek: Int
        /// What the customer buys: the trip, the loan
        var value: Double
        /// Commission to come
        var commission: Double
        /// Fees that come with a completed loan (lender fee and client fee)
        var fee: Double
        /// The company that pays the commission, when it is one of the player's own (0 = a generic supplier)
        var supplier: Int
        /// The part of the commission that is clawed back on early repayment
        var procuration: Double
        /// Trail commission rate a year
        var trail: Double
        var sold: Int

        var json: JSONValue {
            .object(["i": JSONValue(id), "l": JSONValue(line), "d": JSONValue(due), "x": JSONValue(cancelWeek), "v": JSONValue(value), "c": JSONValue(commission),
                     "f": JSONValue(fee), "s": JSONValue(supplier), "k": JSONValue(procuration), "t": JSONValue(trail), "w": JSONValue(sold)])
        }
        init(id: Int, line: String, due: Int, cancelWeek: Int, value: Double, commission: Double, fee: Double, supplier: Int, procuration: Double, trail: Double, sold: Int) {
            self.id = id; self.line = line; self.due = due; self.cancelWeek = cancelWeek; self.value = value; self.commission = commission
            self.fee = fee; self.supplier = supplier; self.procuration = procuration; self.trail = trail; self.sold = sold
        }
        init(_ j: JSONValue) {
            self.init(id: j["i"].int, line: j["l"].string, due: j["d"].int, cancelWeek: j["x"].int, value: j["v"].double, commission: j["c"].double, fee: j["f"].double,
                      supplier: j["s"].int, procuration: j["k"].double, trail: j["t"].double, sold: j["w"].int)
        }
    }

    /// Everything placed in one week on one line, kept together: policies in force, or loans on the books. For a policy `premium` is the yearly
    /// premium, `first` the first-year commission and `recurring` the renewal commission at that premium. For a loan `premium` is the balance,
    /// `first` the procuration commission already paid and `recurring` the trail commission a year.
    struct Cohort: Equatable {
        var line: String
        var start: Int
        var count: Double
        var premium: Double
        var first: Double
        var recurring: Double
        var index: Double

        var json: JSONValue {
            .object(["l": JSONValue(line), "w": JSONValue(start), "n": JSONValue(count), "P": JSONValue(premium), "F": JSONValue(first), "R": JSONValue(recurring), "ix": JSONValue(index)])
        }
        init(line: String, start: Int, count: Double, premium: Double, first: Double, recurring: Double, index: Double) {
            self.line = line; self.start = start; self.count = count; self.premium = premium; self.first = first; self.recurring = recurring; self.index = index
        }
        init(_ j: JSONValue) {
            self.init(line: j["l"].string, start: j["w"].int, count: j["n"].double, premium: j["P"].double, first: j["F"].double, recurring: j["R"].double, index: j["ix"].double)
        }
    }

    struct Book {
        var deals: [Deal] = []
        var cohorts: [Cohort] = []
        var stat: [String: Double] = [:]
        mutating func count(_ k: String, _ by: Double = 1) { stat[k, default: 0] += by }
    }

    static func read(_ co: Company) -> Book {
        let j = co.value("brk")
        var b = Book()
        b.deals = j["deals"].array.map { Deal($0) }
        b.cohorts = j["cohorts"].array.map { Cohort($0) }
        for (k, v) in j["st"].object { b.stat[k] = v.double }
        return b
    }

    static func write(_ b: Book, to co: inout Company) {
        var st: [String: JSONValue] = [:]
        for (k, v) in b.stat { st[k] = JSONValue(v) }
        co.set("brk", .object(["deals": .array(b.deals.map { $0.json }), "cohorts": .array(b.cohorts.map { $0.json }), "st": .object(st)]))
    }

    // MARK: What the owner sees

    /// The book of business at a glance (for the company screens).
    public struct Summary: Equatable, Sendable {
        /// Policies in force, or loans on the books
        public var inForce: Double
        /// Yearly premium of the policies, or balance of the loans
        public var bookValue: Double
        /// What the book pays a year with no new business: renewal commission, or trail commission
        public var recurringYearly: Double
        /// Commission still to come on deals placed (bookings before the trip, applications before completion)
        public var pendingCommission: Double
        /// Customers' money for trips not yet taken, passed on to suppliers (what the travel bond protects)
        public var customerMoneyHeld: Double
        public var placed: Double
        public var cancelled: Double
        public var declined: Double
        public var commissionEarned: Double
        public var clawedBack: Double
    }

    public static func summary(_ co: Company, week: Int) -> Summary {
        let b = read(co)
        let cfg = config["trades"][co.type]
        var held = 0.0
        for d in b.deals where d.cancelWeek == 0 && co.type == "travel" {
            let line = cfg["lines"].array.first { $0["id"].string == d.line }
            let dep = line?["deposit"].double ?? 1, bw = line?["balanceWeeks"].int ?? 0
            held += d.value * (week >= d.due - bw ? 1 : dep)
        }
        return Summary(inForce: b.cohorts.reduce(0) { $0 + $1.count }, bookValue: b.cohorts.reduce(0) { $0 + $1.premium },
                       recurringYearly: b.cohorts.reduce(0) { $0 + $1.recurring }, pendingCommission: b.deals.filter { $0.cancelWeek == 0 }.reduce(0) { $0 + $1.commission },
                       customerMoneyHeld: held, placed: b.stat["sold"] ?? 0, cancelled: b.stat["cancel"] ?? 0, declined: b.stat["decl"] ?? 0,
                       commissionEarned: b.stat["paid"] ?? 0, clawedBack: b.stat["claw"] ?? 0)
    }

    // MARK: Helpers

    static func lines(_ bd: Trade) -> [JSONValue] { config["trades"][bd.id]["lines"].array }

    static func gauss(_ r: inout HashedRandom) -> Double {
        let u1 = max(1e-9, r.next()), u2 = r.next()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    static func between(_ range: JSONValue, _ p: Double) -> Double {
        range[0].double + (range[1].double - range[0].double) * p
    }

    /// The ids of the options switched on in the company's choices.
    static func activeOptionIDs(_ co: Company, _ bd: Trade) -> Set<String> {
        var out = Set<String>()
        for k in bd.knobs { for o in Knobs.activeOptions(co, k) { out.insert(o.id) } }
        return out
    }

    /// New business by line: the trade's mix times what the chosen focus does to each line.
    static func lineWeights(_ bd: Trade, active: Set<String>) -> [Double] {
        let cfg = config["trades"][bd.id]
        let ls = lines(bd)
        var ws = ls.map { $0["mix"].double }
        for opt in active.sorted() {
            let m = cfg["focus"][opt]
            if m.isNull { continue }
            for k in ls.indices {
                let f = m[ls[k]["id"].string]
                if !f.isNull { ws[k] *= f.double }
            }
        }
        return ws
    }

    static func pick(_ weights: [Double], _ r: Double) -> Int {
        let total = weights.reduce(0, +)
        var x = r * total
        for (k, w) in weights.enumerated() { if x < w { return k }; x -= w }
        return max(0, weights.count - 1)
    }

    /// How good the company is at the work, 0 to 1 (service quality), which moves the commission terms it gets and how many customers it keeps.
    static func skill(_ co: Company) -> Double { co.quality / 100 }

    /// Commission from add-ons switched on (travel insurance sold with the trip, protection cover with the mortgage).
    static func addOnCommission(_ cfg: JSONValue, line: String, active: Set<String>, scale: Double, _ rnd: inout HashedRandom) -> Double {
        var extra = 0.0
        for a in cfg["addons"].array where active.contains(a["option"].string) && a["lines"].array.contains(where: { $0.string == line }) {
            if rnd.next() < a["attach"].double { extra += a["value"].double * scale * a["rate"].double }
        }
        return extra
    }

    /// One of the player's own companies of this trade in the same country, which can pay the commission.
    static func ownSupplier(_ s: GameState, buyer co: Company, trade: String) -> Int {
        s.companies.first { $0.id != co.id && $0.type == trade && $0.status == .open && $0.countryCode == co.countryCode }?.id ?? 0
    }

    // MARK: Week

    /// The week of a broker: money from deals placed earlier arrives, the book earns and lapses, and new deals are placed. Returns the usual
    /// week figures for `CompanyWeek.book`: revenue is the commission and fees earned from generic suppliers (a commission paid by the player's own
    /// company moves between the two companies at once and is already booked).
    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        let w = World(state: s, data: data)
        let co0 = s.companies[i]
        let id = co0.id
        let cfg = config["trades"][bd.id]
        var D = DemandModel.compute(co0, bd, w).customers
        let cap = CapacityModel.compute(co0, bd, w).capacity
        if bd.id == "finbroker" { D *= exp(-cfg["rateSensitivity"].double * (s.economy.policyRate - 0.04)) }
        let scale = Pricing.ticket(co0, bd, w) / max(1, bd.ticket)
        let q = skill(co0)
        let active = activeOptionIDs(co0, bd)
        var rnd = HashedRandom("brk:\(s.seed):\(s.week):\(id)")
        var book = read(co0)
        var rev = 0.0

        rev += settle(&s, i, bd, cfg, &book, scale: scale, quality: q, active: active)

        // New business.
        var units = max(0, min(D, cap) * (1 + gauss(&rnd) * 0.045))
        var n = Int(units.rounded(.down))
        if rnd.next() < units - Double(n) { n += 1 }
        units = Double(n)
        let ws = lineWeights(bd, active: active)
        let ls = lines(bd)
        for _ in 0..<n where !ls.isEmpty {
            let line = ls[pick(ws, rnd.next())]
            book.count("sold")
            rev += place(&s, co0, bd, cfg, line, &book, scale: scale, quality: q, active: active, &rnd)
        }

        book.count("paid", rev)
        var co = s.companies[i]
        write(book, to: &co)
        s.companies[i] = co
        let util = cap > 0 ? units / cap : 0
        return CompanyWeek.WeekContext(units: units, rev: rev, cogs: rev * bd.costOfSales, D: D, cap: cap, util: util, price: units > 0 ? rev / units : 0, paidDuringWeek: 0)
    }

    /// Deals that fall due and the book of earlier business. Returns the revenue that goes through the week's books.
    static func settle(_ s: inout GameState, _ i: Int, _ bd: Trade, _ cfg: JSONValue, _ book: inout Book, scale: Double, quality q: Double, active: Set<String>) -> Double {
        let id = s.companies[i].id
        let week = s.week
        var rev = 0.0
        var kept: [Deal] = []
        for d in book.deals {
            if d.cancelWeek != 0 && d.cancelWeek <= week {
                rev += d.value * cfg["cancelFee"].double
                book.count("cancel")
                continue
            }
            guard d.cancelWeek == 0 && d.due <= week else { kept.append(d); continue }
            if bd.id == "finbroker" {
                rev += d.commission + d.fee
                book.cohorts.append(Cohort(line: d.line, start: week, count: 1, premium: d.value, first: d.procuration, recurring: d.value * d.trail, index: s.economy.inflationIndex))
                book.count("completed")
                continue
            }
            // A booking whose trip has been taken: the supplier pays.
            if d.supplier != 0, let si = s.companyIndex(d.supplier), s.companies[si].status.isLive {
                let amount = jsRound(d.commission)
                let agency = s.companies[i].name, supplier = s.companies[si].name
                Payments.companyPays(&s, companyID: d.supplier, amount: amount, category: "mkt", label: "Travel commission to \(agency)")
                Payments.companyReceives(&s, companyID: id, amount: amount, category: "rev", label: "Commission from \(supplier)")
                book.count("direct", amount)
            } else {
                rev += d.commission
            }
        }
        book.deals = kept
        if bd.id == "insbroker" { rev += settleInsurance(&s, i, cfg, &book, quality: q, active: active) }
        if bd.id == "finbroker" { rev += settleLoans(&s, i, cfg, &book) }
        return rev
    }

    /// Policies in force: first-year cancellations are clawed back, and each year the book renews with part of it kept.
    static func settleInsurance(_ s: inout GameState, _ i: Int, _ cfg: JSONValue, _ book: inout Book, quality q: Double, active: Set<String>) -> Double {
        let week = s.week
        let ix = s.economy.inflationIndex
        var rev = 0.0, claw = 0.0
        var bonus = 0.0
        for (opt, add) in cfg["retentionOption"].object where active.contains(opt) { bonus += add.double }
        for k in book.cohorts.indices {
            let line = cfg["lines"].array.first { $0["id"].string == book.cohorts[k].line } ?? .null
            let age = week - book.cohorts[k].start
            if age >= 1 && age < 52 {
                let f = line["cancel"].double / 52
                claw += f * book.cohorts[k].first * (1 - Double(age) / 52)
                book.cohorts[k].count *= 1 - f; book.cohorts[k].premium *= 1 - f; book.cohorts[k].first *= 1 - f; book.cohorts[k].recurring *= 1 - f
            } else if age >= 52 && age % 52 == 0 {
                let keep = line["retention"].double + bonus + 0.1 * (q - 0.5)
                let g = ix / max(0.0001, book.cohorts[k].index)
                rev += book.cohorts[k].recurring * keep * g
                book.cohorts[k].count *= keep
                book.cohorts[k].premium *= keep * g
                book.cohorts[k].recurring *= keep * g
                book.cohorts[k].first = 0
                book.cohorts[k].index = ix
                book.count("renewed", book.cohorts[k].count)
            }
        }
        book.cohorts.removeAll { $0.count < 0.01 }
        if claw > 0 { payClawback(&s, i, claw, &book) }
        return rev
    }

    /// Loans on the books: they amortise, some are repaid early (clawback in the first two years), and trail commission is paid each quarter.
    static func settleLoans(_ s: inout GameState, _ i: Int, _ cfg: JSONValue, _ book: inout Book) -> Double {
        let week = s.week
        var rev = 0.0, claw = 0.0
        for k in book.cohorts.indices {
            let line = cfg["lines"].array.first { $0["id"].string == book.cohorts[k].line } ?? .null
            let age = week - book.cohorts[k].start
            if age < 1 { continue }
            let am = 1 - line["amort"].double / 52
            book.cohorts[k].premium *= am; book.cohorts[k].recurring *= am
            let early = age < 104
            let h = (early ? line["redeem"].double : line["redeemLater"].double) / 52
            if early { claw += h * book.cohorts[k].first * (1 - Double(age) / 104) }
            book.cohorts[k].count *= 1 - h; book.cohorts[k].premium *= 1 - h; book.cohorts[k].first *= 1 - h; book.cohorts[k].recurring *= 1 - h
            if age % 13 == 0 { rev += book.cohorts[k].recurring / 4; book.count("trail", book.cohorts[k].recurring / 4) }
        }
        book.cohorts.removeAll { $0.count < 0.01 }
        if claw > 0 { payClawback(&s, i, claw, &book) }
        return rev
    }

    static func payClawback(_ s: inout GameState, _ i: Int, _ amount: Double, _ book: inout Book) {
        let id = s.companies[i].id
        let a = jsRound(amount)
        if a <= 0 { return }
        Payments.companyPays(&s, companyID: id, amount: a, category: "cogs", label: "Commission clawback")
        book.count("claw", a)
    }

    /// Place one new deal. Returns revenue that comes at once (the first-year commission of a policy).
    static func place(_ s: inout GameState, _ co: Company, _ bd: Trade, _ cfg: JSONValue, _ line: JSONValue, _ book: inout Book, scale: Double, quality q: Double,
                      active: Set<String>, _ rnd: inout HashedRandom) -> Double {
        let week = s.week
        let value = line["value"].double * scale * (0.6 + 0.8 * rnd.next())
        let p = clamp(0.2 + 0.6 * q + (rnd.next() - 0.5) * 0.4, 0, 1)
        let lineID = line["id"].string
        switch bd.id {
        case "travel":
            let lead = Int(between(line["lead"], rnd.next()).rounded())
            var cancel = 0
            let stress = max(0, 1 - s.economy.demand)
            if rnd.next() < line["cancel"].double * (1 + cfg["disruptionCancel"].double * stress) { cancel = week + 1 + Int(rnd.next() * Double(max(1, lead - 1))) }
            var sup = 0
            let supTrade = line["supplier"].string
            if !supTrade.isEmpty, rnd.next() < cfg["supplierShare"].double { sup = ownSupplier(s, buyer: co, trade: supTrade) }
            let com = value * between(line["com"], p) + addOnCommission(cfg, line: lineID, active: active, scale: scale, &rnd)
            book.deals.append(Deal(id: s.makeID(), line: lineID, due: week + lead, cancelWeek: cancel, value: value, commission: com, fee: 0, supplier: sup, procuration: 0, trail: 0, sold: week))
            return 0
        case "insbroker":
            let first = value * between(line["com"], p), renew = value * between(line["ren"], p)
            if let k = book.cohorts.firstIndex(where: { $0.line == lineID && $0.start == week }) {
                book.cohorts[k].count += 1; book.cohorts[k].premium += value; book.cohorts[k].first += first; book.cohorts[k].recurring += renew
            } else {
                book.cohorts.append(Cohort(line: lineID, start: week, count: 1, premium: value, first: first, recurring: renew, index: s.economy.inflationIndex))
            }
            return first
        default:
            let stress = 1 + cfg["declineStress"].double * max(0, s.economy.policyRate - 0.04)
            let declineP = line["decline"].double * stress * (1.25 - 0.5 * q)
            let r = rnd.next()
            if r < declineP { book.count("decl"); return 0 }
            if r < declineP + line["fallThrough"].double { book.count("fell"); return 0 }
            let lag = Int(between(line["lag"], rnd.next()).rounded())
            let proc = value * between(line["com"], p)
            let extra = addOnCommission(cfg, line: lineID, active: active, scale: scale, &rnd)
            let fees = (line["lenderFee"].double + line["clientFee"].double) * scale
            book.deals.append(Deal(id: s.makeID(), line: lineID, due: week + lag, cancelWeek: 0, value: value, commission: proc + extra, fee: fees, supplier: 0, procuration: proc,
                                   trail: between(line["trail"], p), sold: week))
            return 0
        }
    }
}
