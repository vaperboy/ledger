import Foundation
import GameCore
import Countries
import Finance

/// Volume contracts with business customers: a customer takes a set number of units every week for a set number of weeks, at a
/// price below (or, rarely, above) your list price, and pays after a delay. Originals: the 'contract' and 'offer' ways to sell in
/// features/sales/trade_sales_mechanics.js (`weekly`, `decide`, `ACTS.sw33`), the running of tender contracts in
/// features/sales/public_tenders.js (`contractsWeek`, `start`) and the contract page `ACT.ct56` (ui/company/deals.js).
///
/// Where it lives: the contracts are the original's `co.sw33.ct` list (one-off orders: `co.sw33.one`), so saves from the old game
/// load as they are and `Demand.applyWaysToSell` already adds the contracts' units to the week's customers. A contract adds, beside
/// the original's fields (`n who u d end pub tnd ext warn q`): `id`, `w0`, `term` (weeks), `pay` (weeks until the customer pays) and
/// `cr` (how reliable the customer is, 0.4 - 1).
///
/// What a contract does:
///  * demand and capacity: the units are part of the week's demand. A shop that cannot serve them (served below 85 %) gets a warning;
///    at six warnings a penalty, at twelve the contract is cancelled and the reputation falls;
///  * revenue: the discount is taken off the week's revenue and cash (the till booked list price); the part of the contract's money
///    that came in as cash now becomes a receivable that falls due after `pay` weeks, with the usual chance of never being paid
///    (a less reliable customer and a longer delay raise it). The money moves through `Payments`, so the books balance;
///  * risk: a customer can go under (its unpaid invoices are lost, the contract ends), walk away from poor quality, or not renew.
///
/// Volume tenders (`VolumeTenders`) feed `sign` with a tender's id (`tnd`). The other ways to sell (platforms, memberships ...) are in `SalesWays`.
public enum VolumeContracts {
    public static let action = "ctv"
    static let termChoices = [13, 26, 52]

    public struct Terms: Equatable, Sendable {
        public var name: String
        public var customer: String
        /// Units a week
        public var units: Double
        /// Below your list price (negative = above)
        public var discount: Double
        public var weeks: Int
        /// Weeks until the customer pays
        public var paymentWeeks: Int
        /// 0.4 shaky ... 1 solid
        public var reliability: Double
        public var isPublic = false
        public var tenderID: Int? = nil
        public var extensions = 0
        public var higherQuality = false
        public init(name: String, customer: String, units: Double, discount: Double, weeks: Int, paymentWeeks: Int, reliability: Double,
                    isPublic: Bool = false, tenderID: Int? = nil, extensions: Int = 0, higherQuality: Bool = false) {
            self.name = name; self.customer = customer; self.units = units; self.discount = discount; self.weeks = weeks; self.paymentWeeks = paymentWeeks
            self.reliability = reliability; self.isPublic = isPublic; self.tenderID = tenderID; self.extensions = extensions; self.higherQuality = higherQuality
        }
    }

    public struct Contract: Identifiable, Equatable, Sendable {
        public var id: Int
        public var name: String
        public var customer: String
        public var units: Double
        public var discount: Double
        public var startWeek: Int
        public var endWeek: Int
        public var isPublic: Bool
        public var tenderID: Int?
        public var extensionsLeft: Int
        public var warnings: Double
        public var higherQuality: Bool
        public var paymentWeeks: Int
        public var reliability: Double
        /// Position in the list (the original's `ct56` index)
        public var index: Int
        public var reliabilityWord: String { reliability >= 0.85 ? "Solid" : reliability >= 0.65 ? "Average" : "Shaky" }
    }

    public struct Detail: Equatable, Sendable {
        public var contract: Contract
        /// What they pay for one unit now (list price less the discount)
        public var price: Double
        public var worthAYear: Double
        public var weeksLeft: Int
        /// Unpaid invoices of this contract
        public var outstanding: Double
    }

    // MARK: Reading

    static func store(_ co: Company) -> JSONValue {
        let v = co.value("sw33")
        return v.isNull ? .object(["on": .object([:]), "ct": .array([]), "one": .array([]), "ref": 0, "mem": 0, "peak": .object([:]), "last": -99, "log": .array([])]) : v
    }

    static func contract(_ j: JSONValue, index: Int, week: Int) -> Contract {
        Contract(id: j["id"].int, name: j["n"].string, customer: j["who"].string, units: j["u"].double, discount: j["d"].double, startWeek: j["w0"].int,
                 endWeek: j["end"].int, isPublic: j["pub"].bool, tenderID: j["tnd"].isNull ? nil : j["tnd"].int, extensionsLeft: j["ext"].int, warnings: j["warn"].double,
                 higherQuality: j["q"].bool, paymentWeeks: j["pay"].int, reliability: j["cr"].isNull ? 0.8 : j["cr"].double, index: index)
    }

    public static func contracts(_ co: Company, week: Int = 0) -> [Contract] {
        store(co)["ct"].array.enumerated().map { contract($0.element, index: $0.offset, week: week) }
    }

    /// Orders from companies that are booked for a week still to come (or this one). Original: `sw33.one` with `w >= S.week`.
    public static func bookedOrders(_ co: Company, week: Int) -> [(customer: String, units: Double, week: Int)] {
        store(co)["one"].array.filter { $0["w"].int >= week }.map { ($0["who"].string, $0["u"].double, $0["w"].int) }
    }

    /// Units a week that contracts take. Original: `sum(s.ct, c => c.u)`.
    public static func committedUnits(_ co: Company) -> Double { store(co)["ct"].array.reduce(0) { $0 + $1["u"].double } }

    /// The share of the company's capacity the contracts take, from last week's figures.
    public static func capacityShare(_ co: Company) -> Double {
        let cap = co.value("lastW")["cap"].double
        return cap > 0 ? committedUnits(co) / cap : 0
    }

    public static func detail(_ s: GameState, companyID: Int, contractID: Int, data: GameData) -> Detail? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type],
              let k = contracts(co).firstIndex(where: { $0.id == contractID }) else { return nil }
        let c = contracts(co)[k]
        let price = Pricing.ticket(co, bd, World(state: s, data: data)) * (1 - c.discount)
        let open = co.receivables.filter { $0.int("ct") == contractID }.reduce(0) { $0 + $1.amount }
        return Detail(contract: c, price: price, worthAYear: price * c.units * 52, weeksLeft: max(0, c.endWeek - s.week), outstanding: open)
    }

    // MARK: Signing and ending

    static func addLog(_ sw: inout JSONValue, week: Int, _ text: String) {
        var l = sw["log"].array
        l.insert(.object(["w": .number(Double(week)), "t": .string(text)]), at: 0)
        if l.count > 12 { l.removeLast(l.count - 12) }
        sw["log"] = .array(l)
    }

    /// Put a contract on the company's list (the owner said yes, a manager signed, or a tender was won). Original: `decide` / `start`.
    @discardableResult
    public static func sign(_ s: inout GameState, companyID: Int, terms t: Terms, signedBy manager: String? = nil) -> Int? {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open, t.units > 0, t.weeks > 0 else { return nil }
        var sw = store(s.companies[i])
        let id = s.makeID()
        var c: [String: JSONValue] = ["id": .number(Double(id)), "n": .string(t.name), "who": .string(t.customer), "u": .number(t.units), "d": .number(t.discount),
                                      "w0": .number(Double(s.week)), "term": .number(Double(t.weeks)), "end": .number(Double(s.week + t.weeks)),
                                      "pay": .number(Double(t.paymentWeeks)), "cr": .number(t.reliability), "warn": 0, "ext": .number(Double(t.extensions))]
        if t.isPublic { c["pub"] = 1 }
        if t.higherQuality { c["q"] = 1 }
        if let tid = t.tenderID { c["tnd"] = .number(Double(tid)) }
        var list = sw["ct"].array
        list.append(.object(c))
        sw["ct"] = .array(list)
        let verb = manager.map { $0 + " signed" } ?? "Signed"
        addLog(&sw, week: s.week, "\(verb) \(t.name.lowercased()) with \(t.customer).")
        s.companies[i].set("sw33", sw)
        return id
    }

    /// End a contract early: a penalty of 10 % of four weeks' business and a small blow to the name; the customer finds another supplier.
    @discardableResult
    public static func terminate(_ s: inout GameState, companyID: Int, contractID: Int, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return false }
        var sw = store(s.companies[i])
        var list = sw["ct"].array
        guard let k = list.firstIndex(where: { $0["id"].int == contractID }) else { return false }
        let c = list[k]
        let tk = Pricing.ticket(s.companies[i], bd, World(state: s, data: data))
        let fine = c["u"].double * tk * 4 * 0.1
        list.remove(at: k)
        sw["ct"] = .array(list)
        addLog(&sw, week: s.week, "Ended \(c["n"].string.lowercased()) with \(c["who"].string) early.")
        s.companies[i].set("sw33", sw)
        Payments.companyPays(&s, companyID: companyID, amount: fine, category: "fine", label: "Early end of contract: \(c["n"].string)")
        s.companies[i].reputation = max(0, s.companies[i].reputation - 2)
        return true
    }

    // MARK: Offers

    /// How the answer to an offer in the inbox is applied. Original: `ACTS.sw33`.
    public static func answer(_ s: inout GameState, message m: Message, option: Int) {
        guard option == 0, let i = s.companyIndex(m.companyID), s.companies[i].status == .open else { return }
        let d = m.value("data")
        if d["k"].string == "offer" {
            var sw = store(s.companies[i])
            var one = sw["one"].array
            one.append(.object(["w": d["when"], "u": d["u"], "who": d["who"]]))
            sw["one"] = .array(one)
            addLog(&sw, week: s.week, "Took an order from \(d["who"].string).")
            s.companies[i].set("sw33", sw)
        } else {
            sign(&s, companyID: m.companyID, terms: terms(from: d))
        }
    }

    static func terms(from d: JSONValue) -> Terms {
        Terms(name: d["name"].string, customer: d["who"].string, units: d["u"].double, discount: d["d"].double, weeks: d["wk"].int, paymentWeeks: d["pay"].int,
              reliability: d["cr"].isNull ? 0.8 : d["cr"].double)
    }

    static func json(_ t: Terms) -> JSONValue {
        .object(["k": "contract", "name": .string(t.name), "who": .string(t.customer), "u": .number(t.units), "d": .number(t.discount), "wk": .number(Double(t.weeks)),
                 "pay": .number(Double(t.paymentWeeks)), "cr": .number(t.reliability)])
    }

    static func ratingFactor(_ co: Company) -> Double { clamp((co.int("rvN") >= 5 ? Pricing.rating(co) : 3.8) - 3, 0, 1.5) / 1.5 }

    /// A customer comes with an offer now and then, more often when people know you. A manager decides at once, the owner is asked.
    /// Original: the end of `weekly` in trade_sales_mechanics.js.
    static func offers(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[i]
        var sw = store(co)
        if s.week - sw["last"].int < 6 && !sw["last"].isNull { return }
        guard let ways = World(state: s, data: data).balance.salesWays[co.type] else { return }
        let kinds = ways.filter { $0.kind == "contract" || $0.kind == "offer" }
        if kinds.isEmpty { return }
        var h = HashedRandom("\(s.seed):vct:\(s.week):\(co.id)")
        if h.next() >= 0.12 * (0.6 + (co.awareness == 0 ? 20 : co.awareness) / 60) * (0.5 + ratingFactor(co)) { return }
        let way = kinds[min(kinds.count - 1, Int(h.next() * Double(kinds.count)))]
        sw["last"] = .number(Double(s.week))
        s.companies[i].set("sw33", sw)
        let w = World(state: s, data: data)
        let dc = max(0.3, bd.normalDemand * (w.city(co)?.demand ?? 1))
        let lw = co.value("lastW")
        let real = max(0.5, min(dc, max(lw["D"].double, lw["units"].double, dc * 0.15)))
        let tk = Pricing.ticket(co, bd, w)
        let country = data.countries[co.countryCode] ?? data.countries.countries[0]
        var nameRandom = DeterministicRandom(seed: Int(h.next() * 1_000_000_000))
        let who = CompanySetup.generateName(country: country, family: "svc", &nameRandom)
        let util = lw["util"].double
        let manager = co.managerID.flatMap { s.people[$0]?.name }
        if way.kind == "contract" {
            let units = max(0.2, jsRound(real * (0.08 + 0.14 * h.next()) * 10) / 10)
            let reliability = jsRound((0.4 + 0.6 * h.next()) * 100) / 100
            // A shaky customer tempts with a better price; a big one pays late.
            let discount = jsRound((0.05 + 0.10 * h.next() + (reliability < 0.65 ? 0.02 : 0)) * 100) / 100
            let weeks = termChoices[min(2, Int(h.next() * 3))]
            let pay = [0, 4, 8, 13][min(3, Int(h.next() * 4))]
            let t = Terms(name: way.name, customer: who, units: units, discount: discount, weeks: weeks, paymentWeeks: pay, reliability: reliability)
            if let m = manager {
                // A manager takes it when there is room, the discount is modest and the customer is not shaky.
                if discount <= 0.12 && (lw.isNull || util < 0.92) && reliability >= 0.6 { sign(&s, companyID: co.id, terms: t, signedBy: m) }
                return
            }
            let total = units * tk * (1 - discount) * Double(weeks)
            let worth = w.currency(co).display(total)
            let perWeek = jsRound(units * 10) / 10
            let percent = Int(jsRound(discount * 100))
            let paid = pay == 0 ? "on delivery" : "\(pay) weeks after delivery"
            let look = reliability >= 0.85 ? "solid" : reliability >= 0.65 ? "average" : "shaky"
            let body = "About \(perWeek) a week for \(weeks) weeks, at \(percent)% below your price, paid \(paid). Worth about \(worth) in total. The customer looks \(look)."
            s.addMessage(kind: "ask", from: co.name, title: "\(who) offers \(way.name.lowercased())", body: body,
                         companyID: co.id, tone: "n", status: "open", options: [.option("Accept"), .option("Decline")], action: action, data: json(t), expiresWeek: s.week + 2)
        } else {
            let units = max(1, jsRound(real * (0.1 + 0.2 * h.next())))
            let when = s.week + 1 + Int(h.next() * 3)
            if let m = manager {
                if lw.isNull || util < 0.85 {
                    var sw2 = store(s.companies[i])
                    var one = sw2["one"].array
                    one.append(.object(["w": .number(Double(when)), "u": .number(units), "who": .string(who)]))
                    sw2["one"] = .array(one)
                    addLog(&sw2, week: s.week, "\(m) took an order from \(who).")
                    s.companies[i].set("sw33", sw2)
                }
                return
            }
            s.addMessage(kind: "ask", from: co.name, title: "\(who) asks about \(way.name.lowercased())",
                         body: "\(Int(units)) in the week of \(when), about \(w.currency(co).display(units * tk)). You need room that week.",
                         companyID: co.id, tone: "n", status: "open", options: [.option("Accept"), .option("Decline")], action: action,
                         data: .object(["k": "offer", "who": .string(who), "u": .number(units), "when": .number(Double(when))]), expiresWeek: s.week + 2)
        }
    }

    /// A tender contract that ended well (or was cancelled) counts for or against the company in later tenders. Original: `s.hist[co.id]`.
    static func recordDelivery(_ s: inout GameState, companyID: Int, ok: Bool) {
        var st = ProjectTenders.load(s)
        let key = String(companyID)
        var h = st.history[key] ?? .object([:])
        let field = ok ? "ok" : "bad"
        h[field] = .number(h[field].double + 1)
        st.history[key] = h
        ProjectTenders.save(&s, st)
    }

    // MARK: The week

    /// Called for every open company after its week (the till has booked last week's sales). Original: `weekly` (discounts, ends),
    /// `contractsWeek` (delivery, warnings), plus the payment delay and the customer's own risks.
    static func weekly(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[i]
        guard co.status == .open else { return }
        if !store(co)["ct"].array.isEmpty || !store(co)["one"].array.isEmpty {
            settle(&s, i, bd, data: data)
            serviceAndRisk(&s, i, bd, data: data)
            endings(&s, i, data: data)
        }
        offers(&s, i, bd, data: data)
    }

    /// The discount and the payment delay, on the units the contracts took last week.
    static func settle(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[i]
        let units = co.value("lastW")["units"].double
        let list = store(co)["ct"].array
        guard units > 0, !list.isEmpty else { return }
        let w = World(state: s, data: data)
        let tk = Pricing.ticket(co, bd, w)
        let vr = w.country(co).usesSalesTax ? 0 : Vat.rate(co, bd, w)
        let bs = bd.businessShare, cs = 1 - bs
        let careful = co.value("flags")["ccheck"].bool
        let slump = s.economy.demand < 0.97
        var remaining = units
        for c in list {
            let u = min(c["u"].double, remaining)
            remaining -= u
            if u <= 0 { continue }
            let listValue = u * tk
            let x = jsRound(listValue * c["d"].double)                 // the discount (negative = a surcharge)
            let pay = c["pay"].int
            if x != 0 { Payments.book(&s, companyID: co.id, category: "rev", amount: -x) }
            // The standard business-customer receivable booked by the till carries the discount's share for the invoiced part.
            if x != 0, bs > 0 {
                var recv = s.companies[i].receivables
                if let last = recv.lastIndex(where: { $0.value("ct").isNull }) {
                    let cut = x > 0 ? min(recv[last].amount, x * bs * (1 + vr)) : x * bs * (1 + vr)
                    recv[last].amount -= cut
                    s.companies[i].receivables = recv
                }
            }
            let cashList = listValue * cs * (1 + vr)
            let cashNet = max(0, (listValue - x) * cs * (1 + vr))
            if pay > 0 && cashNet > 0 {
                // What came in as cash is invoiced instead: it comes in after the delay, unless the customer never pays.
                Payments.companyPays(&s, companyID: co.id, amount: cashList, category: nil)
                let reliability = c["cr"].isNull ? 0.8 : c["cr"].double
                var h = HashedRandom("\(s.seed):vctp:\(s.week):\(c["id"].int)")
                let odds = (0.004 + 0.03 * (1 - reliability)) * (1 + Double(pay) / 8) * (slump ? 2 : 1) * (careful ? 0.3 : 1)
                var r = Receivable(amount: jsRound(cashNet), dueWeek: s.week + pay, willDefault: h.next() < odds)
                r.set("ct", c["id"].int)
                var recv = s.companies[i].receivables
                recv.append(r)
                s.companies[i].receivables = recv
            } else if cashList != 0 || x != 0 {
                // Paid on delivery: only the discount comes off the cash that came in.
                let cut = x * cs * (1 + vr)
                if cut > 0 { Payments.companyPays(&s, companyID: co.id, amount: cut, category: nil) }
                else if cut < 0 { Payments.companyReceives(&s, companyID: co.id, amount: -cut, category: nil, label: nil) }
            }
        }
    }

    /// Delivery, warnings, penalties, a customer who goes under or walks away. Original: `contractsWeek`.
    static func serviceAndRisk(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        var co = s.companies[i]
        var sw = store(co)
        let list = sw["ct"].array
        guard !list.isEmpty else { return }
        let lw = co.value("lastW")
        let served = lw["D"].double > 0 ? min(1, lw["units"].double / lw["D"].double) : 1
        let tk = Pricing.ticket(co, bd, World(state: s, data: data))
        let slump = s.economy.demand < 0.97
        var keep: [JSONValue] = []
        var badTender = false
        for var c in list {
            var h = HashedRandom("\(s.seed):vctr:\(s.week):\(c["id"].int)")
            let name = c["n"].string, who = c["who"].string
            var gone = false
            if served < 0.85 {
                c["warn"] = .number(c["warn"].double + 1)
                let warn = c["warn"].double
                if warn == 2 {
                    s.addMessage(from: who, title: "Warning: \(name)", body: "\(co.name) is not delivering what the contract says. Another month like this brings a fine.", companyID: co.id, tone: "bad")
                } else if warn == 6 {
                    let fine = jsRound(c["u"].double * tk * 4 * 0.1)
                    s.companies[i] = co
                    Payments.companyPays(&s, companyID: co.id, amount: fine, category: "fine", label: "Contract penalty: \(name)")
                    co = s.companies[i]
                    s.addMessage(from: who, title: "Penalty: \(name)", body: "A penalty for missed deliveries. If it goes on, the contract is cancelled.", companyID: co.id, tone: "bad")
                } else if warn >= 12 {
                    co.reputation = max(0, co.reputation - 4)
                    s.addMessage(from: who, title: "Contract cancelled: \(name)", body: "The customer has cancelled the contract with \(co.name) for poor delivery.", companyID: co.id, tone: "bad")
                    if !c["tnd"].isNull { badTender = true }
                    addLog(&sw, week: s.week, "\(who) cancelled \(name.lowercased()) for poor delivery.")
                    gone = true
                }
            } else if c["warn"].double > 0 {
                c["warn"] = .number(max(0, c["warn"].double - 0.25))
            }
            if !gone && !c["pub"].bool {
                let reliability = c["cr"].isNull ? 0.8 : c["cr"].double
                // The customer goes under: its unpaid invoices are lost and the volume disappears.
                if h.next() < (0.0004 + 0.0016 * (1 - reliability)) * (slump ? 2 : 1) {
                    var recv = co.receivables
                    var owed = 0.0
                    for k in recv.indices where recv[k].int("ct") == c["id"].int { recv[k].willDefault = true; owed += recv[k].amount }
                    co.receivables = recv
                    var body = "The \(name.lowercased()) ends with it."
                    if owed > 0 {
                        let shown = World(state: s, data: data).currency(co).display(owed)
                        body += " The unpaid invoices (about \(shown)) will probably never be paid."
                    }
                    s.addMessage(from: co.name, title: "\(who) has gone under", body: body, companyID: co.id, tone: "bad")
                    addLog(&sw, week: s.week, "\(who) went under.")
                    gone = true
                }
                // The customer finds a better supplier when quality is poor.
                else if co.quality < 35 && h.next() < 0.01 {
                    s.addMessage(from: who, title: "Contract ended: \(name)", body: "\(who) has found a supplier with better quality and ends the contract with \(co.name).", companyID: co.id, tone: "bad")
                    addLog(&sw, week: s.week, "\(who) left for a better supplier.")
                    gone = true
                }
            }
            if !gone { keep.append(c) }
        }
        sw["ct"] = .array(keep)
        co.set("sw33", sw)
        s.companies[i] = co
        if badTender { recordDelivery(&s, companyID: co.id, ok: false) }
    }

    /// The end of a term: a tender contract with extensions left is extended for a year when delivery was good; another contract is
    /// renewed if the customer was satisfied (more likely with a good rating), otherwise it ends. Original: `contractsWeek`, `weekly`.
    static func endings(_ s: inout GameState, _ i: Int, data: GameData) {
        let co = s.companies[i]
        var sw = store(co)
        let list = sw["ct"].array
        guard list.contains(where: { s.week >= $0["end"].int }) else { return }
        var keep: [JSONValue] = []
        for var c in list {
            guard s.week >= c["end"].int else { keep.append(c); continue }
            let good = c["warn"].double < 2
            var h = HashedRandom("\(s.seed):vcte:\(s.week):\(c["id"].int)")
            if !c["tnd"].isNull {
                if good && c["ext"].int > 0 {
                    c["ext"] = .number(Double(c["ext"].int - 1)); c["end"] = .number(Double(c["end"].int + 52))
                    s.addMessage(from: c["who"].string, title: "Extended: \(c["n"].string)", body: "The buyer extends the contract with \(co.name) by a year.", companyID: co.id, tone: "good")
                    keep.append(c)
                    continue
                }
                if good { recordDelivery(&s, companyID: co.id, ok: true) }
                VolumeTenders.newRound(&s, contract: c, companyID: co.id, data: data)
            } else if good && h.next() < 0.45 + 0.3 * ratingFactor(co) {
                let term = c["term"].isNull ? 26 : c["term"].int
                c["end"] = .number(Double(s.week + term)); c["warn"] = 0
                s.addMessage(from: c["who"].string, title: "Renewed: \(c["n"].string)", body: "\(c["who"].string) is happy with \(co.name) and renews the contract for \(term) weeks on the same terms.", companyID: co.id, tone: "good")
                keep.append(c)
                continue
            }
            addLog(&sw, week: s.week, "\(c["n"].string) with \(c["who"].string) ended.")
            s.note("\(c["n"].string) with \(c["who"].string) has ended at \(co.name).", tone: "n", companyID: co.id)
        }
        sw["ct"] = .array(keep)
        sw["one"] = .array(sw["one"].array.filter { $0["w"].int >= s.week })
        s.companies[i].set("sw33", sw)
    }
}
