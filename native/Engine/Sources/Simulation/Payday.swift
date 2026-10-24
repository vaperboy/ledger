import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// Payroll and bills on their real days. Original: features/company/payday.js ("Round 29: payday").
///
///  - Each company has a payday (default the 25th; a weekend payday moves to the Friday before) when payroll leaves
///    the company's cash in one go, with a message.
///  - Rent and supplier bills leave on the last day of the month.
///  - An owner-run company's payroll is the owner's job: a reminder arrives seven days ahead and the owner approves it.
///    If payday passes without approval the staff are not paid (morale falls, people leave, a wage claim follows).
///  - An accountant (per payslip) or a manager with payroll software (monthly fee) can run it automatically.
///  - A sole trader's own withdrawals never go through payroll; a limited company owner's salary is a normal payslip.
public enum Payday {
    public enum Mode: String, CaseIterable, Sendable { case manual, accountant = "acc", manager = "mgr", inHouse = "inhouse" }

    // MARK: Dates

    public static func dayNumber(week: Int, day: Int) -> Int { GameCalendar.startDay + week * 7 + day }
    static func civil(_ n: Int) -> (year: Int, month: Int, day: Int) { GameCalendar.civilFromDays(n) }
    /// 0 = Monday ... 6 = Sunday (1970-01-01 was a Thursday).
    static func weekday(_ n: Int) -> Int { ((n % 7) + 7 + 3) % 7 }
    /// Days in a month. `m` is 0-based (0 = January), like the original's `getUTCMonth`; every caller passes `civil(..).month - 1`.
    static func lastDay(_ y: Int, _ m: Int) -> Int { GameCalendar.daysFromCivil(year: m == 11 ? y + 1 : y, month: m == 11 ? 1 : m + 2, day: 1) - GameCalendar.daysFromCivil(year: y, month: m + 1, day: 1) }
    static func monthNumber(_ n: Int) -> Int { let c = civil(n); return c.year * 12 + (c.month - 1) }

    /// The real payment date in a month (day number). A weekend payday moves to the Friday before, or the Monday
    /// after if that would leave the month.
    static func payDate(config: PayrollConfig, year y: Int, month m: Int) -> Int {
        let ld = lastDay(y, m)
        let dd = config.day == 0 ? ld : min(config.day, ld)
        let d = GameCalendar.daysFromCivil(year: y, month: m + 1, day: dd)
        let wd = weekday(d)
        if wd == 5 || wd == 6 {
            let back = d - (wd == 5 ? 1 : 2)
            return civil(back).month == m + 1 ? back : d + (wd == 5 ? 2 : 1)
        }
        return d
    }
    /// Monthly late interest on rent and supplier bills left unpaid: the country's own rule when its data has one, else the game's default
    /// (`SupplyTerms.lateMonthlyRate`).
    static func billDate(year y: Int, month m: Int) -> Int { GameCalendar.daysFromCivil(year: y, month: m + 1, day: lastDay(y, m)) }

    // MARK: Per-company settings (stored as `pr29` in the company)

    public struct PayrollConfig: Equatable, Sendable {
        public var day = 25            // day of month; 0 = last day
        /// A pay day change waiting for this month's payroll to be paid (original `nday`). nil = none.
        public var nextDay: Int?
        public var mode: Mode?         // nil = default for the company
        public var paidMonth = -1      // last month index whose payday was paid
        public var approvedMonth = -1  // month index the owner approved
        public var reminderMonth = -1
        public var billsMonth = -1
        public var ownerPaidMonth = -1
        public var lateSince: Int?     // day number the payroll is late since
        public var lateWhy = ""
        public var lateMonth = -1
        public var lateOwed = 0.0
        public var lateDays = 0
        public var billShortMonths = 0
        /// What was still unpaid on rent ("rent") and suppliers ("other") after the last month-end bills; it earns late interest.
        public var arrears: [String: Double] = [:]

        init(json j: JSONValue = .null, defaultsFor monthIndex: Int? = nil, paidThisMonth: Bool = false) {
            if j.isNull {
                if let mi = monthIndex {
                    paidMonth = paidThisMonth ? mi : mi - 1
                    billsMonth = mi - 1
                    ownerPaidMonth = paidMonth
                }
                return
            }
            day = j["day"].isNull ? 25 : j["day"].int
            nextDay = j["nday"].isNull ? nil : j["nday"].int
            mode = j["mode"].isNull ? nil : Mode(rawValue: j["mode"].string)
            paidMonth = j["pm"].isNull ? -1 : j["pm"].int
            approvedMonth = j["ok"].isNull ? -1 : j["ok"].int
            reminderMonth = j["rem"].isNull ? -1 : j["rem"].int
            billsMonth = j["bm"].isNull ? -1 : j["bm"].int
            ownerPaidMonth = j["om"].isNull ? -1 : j["om"].int
            billShortMonths = j["bs"].int
            for (k, v) in j["arr"].object { arrears[k] = v.double }
            let late = j["late"]
            if !late.isNull {
                lateSince = Int(late["d0"].double)
                lateWhy = late["why"].string
                lateMonth = late["mi"].int
                lateOwed = late["owe"].double
                lateDays = late["n"].int
            }
        }
        public var json: JSONValue {
            var o: [String: JSONValue] = ["day": .number(Double(day)), "pm": .number(Double(paidMonth)), "ok": .number(Double(approvedMonth)),
                                          "rem": .number(Double(reminderMonth)), "bm": .number(Double(billsMonth)), "om": .number(Double(ownerPaidMonth)),
                                          "bs": .number(Double(billShortMonths))]
            if let nd = nextDay { o["nday"] = .number(Double(nd)) }
            if !arrears.isEmpty { o["arr"] = .object(arrears.mapValues { .number($0) }) }
            if let m = mode { o["mode"] = .string(m.rawValue) }
            if let d0 = lateSince {
                o["late"] = .object(["d0": .number(Double(d0)), "why": .string(lateWhy), "mi": .number(Double(lateMonth)), "owe": .number(lateOwed), "n": .number(Double(lateDays))])
            } else { o["late"] = .null }
            return .object(o)
        }
    }

    /// A queued pay day change takes effect once the payroll that was due has been dealt with. Original: `applyNewDay`.
    static func applyNewDay(_ cfg: inout PayrollConfig) {
        if let nd = cfg.nextDay { cfg.day = nd; cfg.nextDay = nil }
    }

    /// The pay days a company can choose (0 = the last day of the month). Original: `DAYS`.
    public static let paydayChoices = [1, 5, 10, 12, 15, 20, 25, 28, 0]

    public enum PaydayChange: Equatable, Sendable {
        case changedNow(day: Int)       // this month's payroll is already paid: the new day applies from next month
        case queued(day: Int)           // applies once this month's payroll has been paid
        case queueCleared               // chose the current day again: the waiting change was dropped
        case unchanged                  // already the pay day
        case invalidDay, noCompany
    }

    /// Change a company's pay day. Original: `ACT.pr29day`. If this month's payroll is paid and nothing is late the day changes
    /// now (the next payday is next month's, so nothing is paid twice or skipped); otherwise the change waits for the payroll.
    static func setPayday(_ s: inout GameState, companyID: Int, day: Int, today t: Int) -> PaydayChange {
        guard paydayChoices.contains(day) else { return .invalidDay }
        guard let i = s.companyIndex(companyID) else { return .noCompany }
        var cfg = config(s.companies[i], today: t)
        let mi = monthNumber(t)
        let result: PaydayChange
        if cfg.paidMonth >= mi && cfg.lateSince == nil {
            if cfg.day == day && cfg.nextDay == nil { return .unchanged }
            cfg.day = day; cfg.nextDay = nil
            result = .changedNow(day: day)
        } else if day == cfg.day {
            if cfg.nextDay == nil { return .unchanged }
            cfg.nextDay = nil
            result = .queueCleared
        } else {
            cfg.nextDay = day
            result = .queued(day: day)
        }
        cfg.reminderMonth = -1
        s.companies[i].set("pr29", cfg.json)
        return result
    }

    public static func config(_ co: Company, today: Int) -> PayrollConfig {
        let j = co.value("pr29")
        if !j.isNull { return PayrollConfig(json: j) }
        let c = civil(today)
        var cfg = PayrollConfig()
        let pd = payDate(config: cfg, year: c.year, month: c.month - 1)
        cfg = PayrollConfig(json: .null, defaultsFor: monthNumber(today), paidThisMonth: today >= pd)
        return cfg
    }

    // MARK: Who runs payroll

    static let inHouseFamilies: Set<String> = ["fin", "club", "hold", "energy"]

    public static func mode(of co: Company, trade: Trade, config: PayrollConfig) -> Mode {
        if inHouseFamilies.contains(trade.family) { return .inHouse }
        var m = config.mode ?? (co.managerID != nil ? .manager : .manual)
        if m == .manager && co.managerID == nil { m = .manual }
        return m
    }

    static func ownerOnPayroll(_ co: Company) -> Bool { co.form == .limited && co.ownerMonthlySalary > 0 && co.status == .open }
    static func payslips(_ co: Company) -> Int { co.staff.count + (co.managerID != nil ? 1 : 0) + (ownerOnPayroll(co) ? 1 : 0) }
    static func hasPayroll(_ co: Company) -> Bool { payslips(co) > 0 || (co.payables["wages"] ?? 0) > 1 }

    /// What payroll costs in a week. Original: `weekWages`.
    static func weeklyWageCost(_ co: Company, employerFactor oc: Double) -> Double {
        (co.staff.reduce(0) { $0 + $1.monthlyWage } + co.managerMonthlyWage) * 12 / 52 * oc
    }

    /// Fee when the accountant or the manager's software runs payroll. Original: `feeOf`.
    static func fee(for mode: Mode, co: Company, currency: Currency, hasAccountingHQ: Bool) -> Double {
        let n = Double(max(1, payslips(co)))
        switch mode {
        case .accountant: return max(currency.scaledPrice(900), currency.scaledPrice(165) * n) * (hasAccountingHQ ? 0.5 : 1)
        case .manager: return currency.scaledPrice(450) + currency.scaledPrice(40) * n
        default: return 0
        }
    }

    /// A manager with a weak head for numbers misses a payroll now and then. Original: `mgrSlip`.
    static func managerSlipChance(_ co: Company, people: [Int: Person]) -> Double {
        guard let id = co.managerID, let n = people[id] else { return 0 }
        let st = n.value("stats")
        let skill = st.isNull ? 60 : (st["fin"].double + st["risk"].double) / 2
        return max(0, (65 - skill) / 300)
    }

    // MARK: Running payroll and bills

    public struct PayrollResult { public var paid: Double; public var short: Double; public var slips: Int; public var fee: Double }

    @discardableResult
    static func runPayroll(_ s: inout GameState, _ i: Int, how: Mode, today t: Int, data: GameData, context: FinanceContext) -> PayrollResult {
        var co = s.companies[i]
        var cfg = config(co, today: t)
        let country = context.country(of: co, s)
        let mi = monthNumber(t)
        let payMonth = cfg.lateSince != nil ? cfg.lateMonth : mi
        if cfg.ownerPaidMonth != payMonth && ownerOnPayroll(co) {
            cfg.ownerPaidMonth = payMonth
            let cost = co.ownerMonthlySalary * country.employerCostFactor
            s.companies[i].addPayable("wages", cost)
            Payments.book(&s, companyID: co.id, category: "wages", amount: cost)
            co = s.companies[i]
            let tax = Taxes.personalIncomeTax(co.ownerMonthlySalary * 12, kind: .wage, in: country) / 12
            co.set("ownPend", .object(["sal": .number(co.ownerMonthlySalary), "tax": .number(tax)]))
            s.companies[i] = co
        }
        co = s.companies[i]
        let fee = Payday.fee(for: how, co: co, currency: context.currency(co.countryCode, s), hasAccountingHQ: s.hasHeadOffice("acc"))
        if fee > 0 { Payments.companyPays(&s, companyID: co.id, amount: fee, category: "acc", label: how == .accountant ? "Payroll service" : "Payroll software") }
        co = s.companies[i]
        let due = co.payables["wages"] ?? 0
        let room = context.overdraftRoom(co, s)
        let spare = max(0, co.cash + room)
        let p = min(due, spare)
        if p > 0 {
            Ledger.moveRaw(&s, .company(co.id), -p)
            co = s.companies[i]
            co.payables["wages"] = due - p
            co.addTransaction(week: s.week, amount: -jsRound(p), label: "Payroll · \(payslips(co)) \(payslips(co) == 1 ? "payslip" : "payslips")")
        }
        let short = max(0, due - p)
        cfg.paidMonth = max(cfg.paidMonth, payMonth)
        let c = civil(t)
        if t >= payDate(config: cfg, year: c.year, month: c.month - 1) { cfg.paidMonth = max(cfg.paidMonth, mi) }
        cfg.approvedMonth = -1
        applyNewDay(&cfg)
        co.wageShortfall = short
        let cur = context.currency(co.countryCode, s)
        if short > 1 {
            cfg.lateSince = cfg.lateSince ?? t
            cfg.lateWhy = "cash"; cfg.lateMonth = payMonth; cfg.lateOwed = short
            s.companies[i] = co
            s.addMessage(kind: "ask", from: co.name, title: "Payroll short at \(co.name)",
                         body: "Only \(cur.display(p)) of \(cur.display(due)) could be paid. \(cur.display(short)) is still owed to staff. Put money in and they are paid back automatically.",
                         companyID: co.id, tone: "bad", status: "open", options: [.option("Understood")], action: "pay29", data: .object(["k": "late"]))
        } else {
            cfg.lateSince = nil; cfg.lateWhy = ""
            if let pend = co.value("ownPend") as JSONValue?, !pend.isNull {
                s.companies[i] = co
                payOwner(&s, companyIndex: i, salary: pend["sal"].double, tax: pend["tax"].double)
                co = s.companies[i]
                co.raw["ownPend"] = .null
            }
        }
        co.set("pr29", cfg.json)
        s.companies[i] = co
        return PayrollResult(paid: jsRound(p), short: jsRound(short), slips: payslips(co), fee: jsRound(fee))
    }

    static func payOwner(_ s: inout GameState, companyIndex i: Int, salary: Double, tax: Double) {
        s.tax.salary += salary
        s.tax.withheld += tax
        Payments.playerReceives(&s, salary - tax, label: "Salary from \(s.companies[i].name)", companyID: s.companies[i].id)
    }

    /// Back pay after a short payroll, whenever cash allows. Original: `backPay`.
    static func backPay(_ s: inout GameState, _ i: Int, today t: Int) {
        var co = s.companies[i]
        var cfg = config(co, today: t)
        guard cfg.lateSince != nil, cfg.lateWhy == "cash" else { return }
        let p = min(cfg.lateOwed, co.payables["wages"] ?? 0, max(0, co.cash))
        if p < 1 { return }
        Ledger.moveRaw(&s, .company(co.id), -p)
        co = s.companies[i]
        co.payables["wages"] = (co.payables["wages"] ?? 0) - p
        co.addTransaction(week: s.week, amount: -jsRound(p), label: "Back pay to staff")
        cfg.lateOwed -= p
        if cfg.lateOwed < 1 {
            cfg.lateSince = nil; cfg.lateWhy = ""; co.wageShortfall = 0
            s.companies[i] = co
            if let pend = co.value("ownPend") as JSONValue?, !pend.isNull {
                payOwner(&s, companyIndex: i, salary: pend["sal"].double, tax: pend["tax"].double)
                s.companies[i].raw["ownPend"] = .null
            }
            s.note("Back pay sent at \(co.name). Everyone is paid in full.", tone: "good", companyID: co.id)
            co = s.companies[i]
        }
        co.set("pr29", cfg.json)
        s.companies[i] = co
    }

    /// Rent and supplier bills on the last day of the month. Original: `payBills`.
    @discardableResult
    static func payBills(_ s: inout GameState, _ i: Int, today t: Int, context: FinanceContext, data: GameData? = nil) -> (paid: Double, short: Double) {
        var co = s.companies[i]
        var left = max(0, co.cash + context.overdraftRoom(co, s))
        var short = 0.0, paid = 0.0
        var cfg = config(co, today: t)
        // Late interest on what was left unpaid last month (rent and suppliers): added to the supplier bill, booked as interest.
        let overdue = (cfg.arrears["rent"] ?? 0) + (cfg.arrears["other"] ?? 0)
        let carried = min(overdue, (co.payables["rent"] ?? 0) + (co.payables["other"] ?? 0))
        let lateFee = jsRound(carried * SupplyTerms.lateMonthlyRate(country: context.country(of: co, s), policyRate: s.economy.policyRate))
        if lateFee > 0 {
            co.addPayable("other", lateFee)
            var b = co.books; b.add("int", lateFee); co.books = b
            s.companies[i] = co
            s.addMessage(from: co.name, title: "Late fees at \(co.name)",
                         body: "Rent and supplier bills left unpaid last month now carry late interest of \(context.currency(co.countryCode, s).display(lateFee)).",
                         companyID: co.id, tone: "bad")
        }
        for k in ["rent", "other"] {
            let due = co.payables[k] ?? 0
            if due <= 0 { cfg.arrears[k] = nil; continue }
            let p = min(due, left)
            if p > 0 {
                // Keep what the first bill already changed (rent paid): re-reading the company without writing it back first
                // would forget it, the rent would stay "owed" and be paid again, in full and growing, every month.
                s.companies[i] = co
                Ledger.moveRaw(&s, .company(co.id), -p)
                co = s.companies[i]
                let used = !co.value("f30").object.isEmpty
                co.addTransaction(week: s.week, amount: -jsRound(p), label: k == "rent" ? "Rent" : (used ? "Monthly bills: suppliers, insurance, leasing, fees" : "Suppliers and costs"))
                // The landlord company is paid when the tenant really pays: the same period and the same amount.
                if k == "rent" { s.companies[i] = co; PremisesExtras.payLandlord(&s, tenantIndex: i, paid: p); co = s.companies[i] }
            }
            cfg.arrears[k] = jsRound(due - p) < 1 ? nil : jsRound(due - p)
            co.payables[k] = due - p
            left -= p
            short += due - p
            paid += p
        }
        if (co.payables["other"] ?? 0) < 1 { co.set("f30", .object([:])) }
        s.companies[i] = co
        let wasCut = co.int("supCut")
        if short > context.currency(co.countryCode, s).scaledPrice(1500) {
            // The suppliers you could not pay think less of you (the relationship their discounts come from).
            if let d = data { SupplyTerms.billsMissed(&s, companyIndex: i, data: d) }
            cfg.billShortMonths += 1
            if cfg.billShortMonths == 1 {
                let cur = context.currency(co.countryCode, s)
                s.addMessage(from: co.name, title: "Could not pay all bills at \(co.name)",
                             body: "Missing \(cur.display(short)) for rent and suppliers this month. Put money in or cut costs, or suppliers will stop delivering.", companyID: co.id, tone: "bad")
            }
            if cfg.billShortMonths >= 2 { s.companies[i].reputation = clamp(s.companies[i].reputation - 1, 0, 100) }
        } else { cfg.billShortMonths = 0 }
        // Repeated misses: suppliers tighten terms (2 months: stock only against cash in the account) and then stop delivering stock (3 months).
        let level = cfg.billShortMonths >= 3 ? 2 : cfg.billShortMonths >= 2 ? 1 : 0
        // Bills and invoices each cut suppliers off; stock buying reads the stricter of the two (`SupplyTerms.refreshCut`).
        if level > 0 || s.companies[i].raw["supCutB"] != nil { s.companies[i].set("supCutB", level); if level == 0 { s.companies[i].raw.removeValue(forKey: "supCutB") } }
        let level2 = max(level, SupplyTerms.invoiceCutLevel(s.companies[i], week: s.week))
        s.companies[i].set("supCut", level2)
        if level2 > wasCut {
            s.addMessage(from: co.name, title: level2 == 1 ? "Suppliers want cash at \(co.name)" : "Suppliers stop delivering to \(co.name)",
                         body: level2 == 1 ? "After repeated missed bills suppliers only deliver stock against cash in the account. Pay what is overdue to get credit terms back."
                                          : "Suppliers refuse new stock until the overdue bills are paid. Sales will suffer.",
                         companyID: co.id, tone: "bad")
        } else if level2 == 0 && wasCut > 0 {
            s.addMessage(from: co.name, title: "Suppliers deliver normally again", body: "The overdue bills at \(co.name) are paid. Suppliers are back on normal terms.", companyID: co.id, tone: "good")
        }
        s.companies[i].set("pr29", cfg.json)
        return (jsRound(paid), jsRound(short))
    }

    /// Bills (rent, suppliers) short for four months running, or tax unpaid for six: the company can no longer pay. Used by `Failure`.
    static func unpaidForMonths(_ co: Company, today t: Int) -> Bool {
        config(co, today: t).billShortMonths >= 4 || co.unpaidMonths >= 6
    }

    /// One more day with wages owed: people quit, word gets out, a wage claim follows. Original: `lateDay`.
    static func lateDay(_ s: inout GameState, _ i: Int, today t: Int, data: GameData, context: FinanceContext) {
        var co = s.companies[i]
        var cfg = config(co, today: t)
        guard let d0 = cfg.lateSince else { return }
        if cfg.lateWhy == "cash" { backPay(&s, i, today: t) }
        co = s.companies[i]
        cfg = config(co, today: t)
        guard let since = cfg.lateSince else { return }
        _ = since
        let n = t - d0
        if n <= cfg.lateDays { return }
        cfg.lateDays = n
        let mood = co.value("mood").isNull ? 60 : co.num("mood")
        co.set("mood", clamp(mood - 1.5, 0, 100))
        if n == 3 { s.note("Staff at \(co.name) are three days without full pay.", tone: "bad", companyID: co.id) }
        if n >= 3 {
            for m in co.staff where s.random.chance(0.04) {
                s.note("\(s.people[m.id]?.name ?? "A worker") quit \(co.name) over late wages.", tone: "bad", companyID: co.id)
                if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p }
                co.staff = co.staff.filter { $0.id != m.id }
            }
        }
        if n == 7 {
            co.reputation = clamp(co.reputation - 2, 0, 100)
            s.note("Word is out that \(co.name) pays late. Good people will think twice before joining.", tone: "bad", companyID: co.id)
        }
        co.set("pr29", cfg.json)
        s.companies[i] = co
        if n == 14 {
            let cur = context.currency(co.countryCode, s)
            let f = cur.scaledPrice(5000) + cfg.lateOwed * 0.02
            Payments.companyPays(&s, companyID: co.id, amount: f, category: "fine", label: "Wage claim and late interest")
            s.addMessage(from: "Lawyer for the staff", title: "Wage claim against \(co.name)",
                         body: "Staff took the unpaid wages to a lawyer. Legal costs and late interest: \(cur.display(f)). The wages are still owed.", companyID: co.id, tone: "bad")
        }
    }

    // MARK: The day

    /// Everything that happens to payroll and bills on one day. Original: `onDay` / `dayCo`.
    public static func onDay(_ s: inout GameState, data: GameData, context: FinanceContext) {
        if !s.dayMode || s.isGameOver { return }
        let t = dayNumber(week: s.week, day: s.day)
        let c = civil(t)
        let mi = monthNumber(t)
        var paidToday: [(String, Double)] = []
        var needApproval: [(Int, Double, Int)] = []   // company index, estimate, payday
        for i in s.companies.indices where s.companies[i].status.isLive {
            guard let bd = data.catalog[s.companies[i].type] else { continue }
            var cfg = config(s.companies[i], today: t)
            let pd = payDate(config: cfg, year: c.year, month: c.month - 1)
            let md = mode(of: s.companies[i], trade: bd, config: cfg)
            // Payday
            if cfg.paidMonth < mi && t >= pd && cfg.lateSince == nil {
                if !hasPayroll(s.companies[i]) {
                    cfg.paidMonth = mi
                    applyNewDay(&cfg)
                    s.companies[i].set("pr29", cfg.json)
                } else if md == .manual {
                    // The owner's standing policy approves payroll the company can pay, even when the reminder window was missed.
                    if cfg.approvedMonth == mi || (s.policy.autoPayroll && s.companies[i].cash >= (s.companies[i].payables["wages"] ?? 0)) {
                        let r = runPayroll(&s, i, how: .manual, today: t, data: data, context: context)
                        paidToday.append((s.companies[i].name, r.paid))
                    } else {
                        cfg.lateSince = t; cfg.lateWhy = "notrun"; cfg.lateMonth = mi; cfg.lateDays = 0
                        s.companies[i].set("pr29", cfg.json)
                        s.addMessage(kind: "ask", from: "Payroll", title: "Payday at \(s.companies[i].name): wages not approved",
                                     body: "Today is payday and the payroll was not approved. Staff are waiting. Run it now to pay everyone.",
                                     companyID: s.companies[i].id, tone: "bad", status: "open",
                                     options: [.option("Run payroll now", "Pay everyone today")], action: "pay29", data: .object(["k": "late"]))
                    }
                } else if md == .manager, s.random.chance(managerSlipChance(s.companies[i], people: s.people)) {
                    let d = s.random.chance(0.5) ? 1 : 2
                    cfg.lateSince = t; cfg.lateWhy = "slip"; cfg.lateMonth = mi; cfg.lateDays = 0; cfg.lateOwed = Double(t + d)
                    s.companies[i].set("pr29", cfg.json)
                    s.addMessage(from: s.people[s.companies[i].managerID ?? 0]?.name ?? "Manager", title: "Payroll late at \(s.companies[i].name)",
                                 body: "Sorry, I missed a step in the payroll software. Wages go out \(d == 1 ? "tomorrow" : "in two days"). The staff are not happy.",
                                 companyID: s.companies[i].id, tone: "bad")
                } else {
                    let r = runPayroll(&s, i, how: md == .inHouse ? .inHouse : md, today: t, data: data, context: context)
                    paidToday.append((s.companies[i].name, r.paid))
                }
            }
            cfg = config(s.companies[i], today: t)
            if cfg.lateSince != nil {
                if cfg.lateWhy == "slip" {
                    if t >= Int(cfg.lateOwed) {
                        cfg.lateSince = nil; s.companies[i].set("pr29", cfg.json)
                        let r = runPayroll(&s, i, how: .manager, today: t, data: data, context: context)
                        paidToday.append((s.companies[i].name, r.paid))
                    }
                } else if cfg.lateWhy == "notrun" && md != .manual {
                    let r = runPayroll(&s, i, how: md, today: t, data: data, context: context)
                    paidToday.append((s.companies[i].name, r.paid))
                } else {
                    lateDay(&s, i, today: t, data: data, context: context)
                }
            }
            // Seven days ahead: ask the owner to approve (manual) or tell them (automatic).
            cfg = config(s.companies[i], today: t)
            let np = nextPay(s.companies[i], config: cfg, today: t)
            let leftDays = np - t
            let key = monthNumber(np)
            if leftDays >= 1 && leftDays <= 7 && cfg.reminderMonth != key && cfg.paidMonth < key && hasPayroll(s.companies[i]) {
                cfg.reminderMonth = key
                s.companies[i].set("pr29", cfg.json)
                let country = context.country(of: s.companies[i], s)
                let est = (s.companies[i].payables["wages"] ?? 0) + weeklyWageCost(s.companies[i], employerFactor: country.employerCostFactor) * Double(max(0, (np - dayNumber(week: s.week, day: 0)) / 7))
                if md == .manual && cfg.approvedMonth != key {
                    if s.policy.autoPayroll && s.companies[i].cash >= est {
                        // Routine payroll the company can pay: approved by the owner's standing policy, no question asked.
                        cfg.approvedMonth = key
                        s.companies[i].set("pr29", cfg.json)
                        s.note("Payroll at \(s.companies[i].name) approved automatically (\(context.homeCurrency(s).short(est))). It goes out on payday.", tone: "good", companyID: s.companies[i].id)
                    } else { needApproval.append((i, est, np)) }
                }
            }
            // Rent and supplier bills: last day of the month.
            let bd2 = billDate(year: c.year, month: c.month - 1)
            cfg = config(s.companies[i], today: t)
            if cfg.billsMonth < mi - 1 {
                cfg.billsMonth = mi - 1
                s.companies[i].set("pr29", cfg.json)
                payBills(&s, i, today: t, context: context, data: data)
            }
            cfg = config(s.companies[i], today: t)
            if cfg.billsMonth < mi && t >= bd2 {
                cfg.billsMonth = mi
                s.companies[i].set("pr29", cfg.json)
                payBills(&s, i, today: t, context: context, data: data)
            }
        }
        // One approval message for all companies that need it.
        if !needApproval.isEmpty {
            let cur = context.homeCurrency(s)
            let total = needApproval.reduce(0) { $0 + $1.1 }
            let lines = needApproval.map { "\(s.companies[$0.0].name): about \(cur.display($0.1))" }.joined(separator: "\n")
            let ids = needApproval.map { s.companies[$0.0].id }
            s.addMessage(kind: "ask", from: "Payroll", title: "Approve payroll: \(cur.short(total))", body: lines + "\nIf you do not approve it, staff are not paid on payday.",
                         tone: "n", status: "open", options: [.option("Approve", "Payroll goes out on payday"), .option("Not now", "Staff will not be paid")],
                         action: "pay29all", data: .object(["ids": .array(ids.map { .number(Double($0)) }), "mi": .number(Double(monthNumber(needApproval[0].2)))]), expiresWeek: s.week + 2)
        }
        if !paidToday.isEmpty {
            let cur = context.homeCurrency(s)
            let total = paidToday.reduce(0) { $0 + $1.1 }
            if total > 0 {
                let id = s.addMessage(from: "Payroll", title: "Payday: \(cur.display(total)) paid",
                                      body: paidToday.map { "\($0.0): \(cur.display($0.1))" }.joined(separator: " · "))
                if let k = s.inbox.firstIndex(where: { $0.id == id }) { s.inbox[k].isRead = true }
            }
        }
    }

    /// The next payday that is not yet paid. Original: `nextPay`.
    static func nextPay(_ co: Company, config cfg: PayrollConfig, today t: Int) -> Int {
        let c = civil(t)
        let mi = monthNumber(t)
        if let _ = cfg.lateSince, cfg.lateMonth >= 0 { return payDate(config: cfg, year: cfg.lateMonth / 12, month: cfg.lateMonth % 12) }
        if cfg.paidMonth < mi { return payDate(config: cfg, year: c.year, month: c.month - 1) }
        let nextMonth = c.month == 12 ? (c.year + 1, 0) : (c.year, c.month)
        return payDate(config: cfg, year: nextMonth.0, month: nextMonth.1)
    }

    /// The player's answer to a payroll message.
    public static func answer(_ s: inout GameState, action: String, data: JSONValue, option: Int, companyID: Int, data gd: GameData, context: FinanceContext) {
        let t = dayNumber(week: s.week, day: s.day)
        if action == "pay29all" {
            guard option == 0 else { return }
            let mi = data["mi"].int
            for idv in data["ids"].array {
                guard let i = s.companyIndex(idv.int) else { continue }
                var cfg = config(s.companies[i], today: t)
                if cfg.paidMonth < mi && cfg.lateSince == nil { cfg.approvedMonth = mi; s.companies[i].set("pr29", cfg.json) }
            }
            s.note("Payroll approved. It goes out on payday.", tone: "good")
        } else if action == "pay29", let i = s.companyIndex(companyID), data["k"].string == "late", option == 0 {
            let cfg = config(s.companies[i], today: t)
            if cfg.lateSince != nil {
                let r = runPayroll(&s, i, how: .manual, today: t, data: gd, context: context)
                let cur = context.currency(s.companies[i].countryCode, s)
                s.note("Payroll run at \(s.companies[i].name): \(cur.display(r.paid)) paid" + (r.short > 0 ? ", short by \(cur.display(r.short))" : "") + ".", tone: r.short > 0 ? "bad" : "good", companyID: companyID)
            }
        }
    }
}

// MARK: Reading the pay day for a screen

public struct PaydayChoice: Equatable, Sendable, Identifiable {
    public var id: Int { day }
    public var day: Int                 // 0 = last day of the month
    public var label: String            // "1st", "25th", "Last day"
    public var isCurrent: Bool
    public var isQueued: Bool
    /// The first payday that follows the choice (a weekend moves it to the Friday before).
    public var firstPayDay: Int
    public var firstPayText: String
    /// Days between that payday and the month-end bills of the same month; 0 = wages and rent fall on the same day.
    public var daysBeforeBills: Int
}

public struct PaydayInfo: Equatable, Sendable {
    public var hasPayroll: Bool
    public var day: Int
    public var dayLabel: String
    public var pendingDay: Int?
    public var pendingLabel: String?
    public var paidThisMonth: Bool
    public var isLate: Bool
    /// A change made now applies at once (this month is paid and nothing is late); otherwise it waits for the payroll.
    public var changesImmediately: Bool
    public var nextPayDay: Int
    public var nextPayText: String
    public var billDay: Int
    public var billText: String
    public var choices: [PaydayChoice]
}

extension Payday {
    static func ordinal(_ n: Int) -> String {
        let r = n % 100
        let suffix = (r >= 11 && r <= 13) ? "th" : (n % 10 == 1 ? "st" : n % 10 == 2 ? "nd" : n % 10 == 3 ? "rd" : "th")
        return "\(n)\(suffix)"
    }
    static func dayLabel(_ d: Int) -> String { d == 0 ? "Last day" : ordinal(d) }
    static func dateText(_ n: Int) -> String { let d = civil(n); return "\(d.day) \(GameCalendar.monthNames[d.month - 1]) \(d.year)" }
}

public extension GameEngine {
    func paydayInfo(companyID: Int) -> PaydayInfo? {
        let s = state
        guard let co = s.company(companyID) else { return nil }
        let t = Payday.dayNumber(week: s.week, day: s.day)
        let cfg = Payday.config(co, today: t)
        let c = Payday.civil(t)
        let mi = Payday.monthNumber(t)
        let immediate = cfg.paidMonth >= mi && cfg.lateSince == nil
        let next = Payday.nextPay(co, config: cfg, today: t)
        let nm = Payday.civil(next)
        let bill = Payday.billDate(year: c.year, month: c.month - 1)
        var probe = cfg
        // Immediately: the new day applies from next month. Queued: the payroll that is due stays on its date, then the new day applies.
        let basis = immediate ? (c.year, c.month - 1) : (nm.year, nm.month - 1)
        let after = basis.1 == 11 ? (basis.0 + 1, 0) : (basis.0, basis.1 + 1)
        let choices = Payday.paydayChoices.map { d -> PaydayChoice in
            probe.day = d
            let pd = Payday.payDate(config: probe, year: after.0, month: after.1)
            return PaydayChoice(day: d, label: Payday.dayLabel(d), isCurrent: d == cfg.day, isQueued: d == cfg.nextDay,
                                firstPayDay: pd, firstPayText: Payday.dateText(pd), daysBeforeBills: Payday.billDate(year: after.0, month: after.1) - pd)
        }
        return PaydayInfo(hasPayroll: Payday.hasPayroll(co), day: cfg.day, dayLabel: Payday.dayLabel(cfg.day), pendingDay: cfg.nextDay,
                          pendingLabel: cfg.nextDay.map(Payday.dayLabel), paidThisMonth: cfg.paidMonth >= mi, isLate: cfg.lateSince != nil,
                          changesImmediately: immediate, nextPayDay: next, nextPayText: Payday.dateText(next), billDay: bill,
                          billText: Payday.dateText(bill), choices: choices)
    }
}
