import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public enum Payday {
    public static let payDay = 15

    public static func dayNumber(week: Int, day: Int) -> Int { GameCalendar.startDay + week * 7 + day }
    static func civil(_ n: Int) -> (year: Int, month: Int, day: Int) { GameCalendar.civilFromDays(n) }
    static func weekday(_ n: Int) -> Int { ((n % 7) + 7 + 3) % 7 }
    static func lastDay(_ y: Int, _ m: Int) -> Int { GameCalendar.daysFromCivil(year: m == 11 ? y + 1 : y, month: m == 11 ? 1 : m + 2, day: 1) - GameCalendar.daysFromCivil(year: y, month: m + 1, day: 1) }
    static func monthNumber(_ n: Int) -> Int { let c = civil(n); return c.year * 12 + (c.month - 1) }

    static func payDate(year y: Int, month m: Int) -> Int {
        let dd = min(payDay, lastDay(y, m))
        let d = GameCalendar.daysFromCivil(year: y, month: m + 1, day: dd)
        let wd = weekday(d)
        if wd == 5 || wd == 6 {
            let back = d - (wd == 5 ? 1 : 2)
            return civil(back).month == m + 1 ? back : d + (wd == 5 ? 2 : 1)
        }
        return d
    }
    static func billDate(year y: Int, month m: Int) -> Int { GameCalendar.daysFromCivil(year: y, month: m + 1, day: lastDay(y, m)) }

    public struct PayrollConfig: Equatable, Sendable {
        public var paidMonth = -1
        public var billsMonth = -1
        public var lateSince: Int?
        public var lateWhy = ""
        public var lateMonth = -1
        public var lateOwed = 0.0
        public var lateDays = 0
        public var billShortMonths = 0
        public var arrears: [String: Double] = [:]

        init(json j: JSONValue = .null, defaultsFor monthIndex: Int? = nil, paidThisMonth: Bool = false) {
            if j.isNull {
                if let mi = monthIndex {
                    paidMonth = paidThisMonth ? mi : mi - 1
                    billsMonth = mi - 1
                }
                return
            }
            paidMonth = j["pm"].isNull ? -1 : j["pm"].int
            billsMonth = j["bm"].isNull ? -1 : j["bm"].int
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
            var o: [String: JSONValue] = ["pm": .number(Double(paidMonth)), "bm": .number(Double(billsMonth)),
                                          "bs": .number(Double(billShortMonths))]
            if !arrears.isEmpty { o["arr"] = .object(arrears.mapValues { .number($0) }) }
            if let d0 = lateSince {
                o["late"] = .object(["d0": .number(Double(d0)), "why": .string(lateWhy), "mi": .number(Double(lateMonth)), "owe": .number(lateOwed), "n": .number(Double(lateDays))])
            } else { o["late"] = .null }
            return .object(o)
        }
    }

    public static func config(_ co: Company, today: Int) -> PayrollConfig {
        let j = co.value("pr29")
        if !j.isNull { return PayrollConfig(json: j) }
        let c = civil(today)
        let pd = payDate(year: c.year, month: c.month - 1)
        return PayrollConfig(json: .null, defaultsFor: monthNumber(today), paidThisMonth: today >= pd)
    }

    static func peopleOnPayroll(_ co: Company) -> Int { co.staff.count + (co.managerID != nil ? 1 : 0) }
    static func hasPayroll(_ co: Company) -> Bool { peopleOnPayroll(co) > 0 || (co.payables["wages"] ?? 0) > 1 }

    public struct PayrollResult { public var paid: Double; public var short: Double }

    @discardableResult
    static func runPayroll(_ s: inout GameState, _ i: Int, today t: Int, data: GameData, context: FinanceContext) -> PayrollResult {
        var co = s.companies[i]
        var cfg = config(co, today: t)
        let mi = monthNumber(t)
        let payMonth = cfg.lateSince != nil ? cfg.lateMonth : mi
        co = s.companies[i]
        let due = co.payables["wages"] ?? 0
        let room = context.overdraftRoom(co, s)
        let spare = max(0, co.cash + room)
        let p = min(due, spare)
        if p > 0 {
            AccountingLedger.note(category: "wages", label: "Payroll", ref: "payroll:\(mi)")
            Ledger.moveRaw(&s, .company(co.id), -p)
            co = s.companies[i]
            co.payables["wages"] = due - p
            co.addTransaction(week: s.week, amount: -jsRound(p), label: "Payroll")
        }
        let short = max(0, due - p)
        cfg.paidMonth = max(cfg.paidMonth, payMonth)
        let c = civil(t)
        if t >= payDate(year: c.year, month: c.month - 1) { cfg.paidMonth = max(cfg.paidMonth, mi) }
        co.wageShortfall = short
        if short > 1 {
            let repeated = cfg.lateSince != nil && mi > payMonth
            cfg.lateSince = cfg.lateSince ?? t
            cfg.lateWhy = "cash"; cfg.lateMonth = payMonth; cfg.lateOwed = short
            s.companies[i] = co
            reportShort(&s, co, due: due, short: short, serious: repeated || p < due * 0.25, data: data, context: context)
        } else {
            cfg.lateSince = nil; cfg.lateWhy = ""
        }
        co.set("pr29", cfg.json)
        s.companies[i] = co
        return PayrollResult(paid: jsRound(p), short: jsRound(short))
    }

    static func reportShort(_ s: inout GameState, _ co: Company, due: Double, short: Double, serious: Bool, data: GameData, context: FinanceContext) {
        let cur = context.currency(co.countryCode, s)
        let desk = Delegation.desk("finance", in: co, state: s, data: data)
        let toOwner = serious || desk == nil
        let line = "\(co.name): \(cur.display(short)) of \(cur.display(due)) is still owed to staff."
        let who = toOwner ? "" : (desk?.label ?? "")
        let intro = "Not every wage could be paid. Money put in is paid to staff automatically."
        if let k = s.inbox.firstIndex(where: { $0.actionID == "pay29s" && $0.week == s.week && ($0.status == "open") == toOwner }) {
            var ids = s.inbox[k].value("data")["ids"].array, lines = s.inbox[k].value("data")["l"].array
            if let at = ids.firstIndex(where: { $0.int == co.id }) { lines[at] = .string(line) } else { ids.append(.number(Double(co.id))); lines.append(.string(line)) }
            var m = s.inbox[k]
            m.set("data", .object(["k": "short", "ids": .array(ids), "l": .array(lines)]))
            m.title = ids.count == 1 ? "Payroll short at \(co.name)" : "Payroll short at \(ids.count) companies"
            m.body = intro + "\n" + lines.map { $0.string }.joined(separator: "\n")
            if !toOwner && m.handledBy != who { m.handledBy = "the finance desks" }
            m.isRead = false
            s.inbox[k] = m
            return
        }
        s.addMessage(kind: toOwner ? "ask" : "info", from: co.name, title: "Payroll short at \(co.name)", body: intro + "\n" + line,
                     companyID: co.id, tone: "bad", status: toOwner ? "open" : "done", options: toOwner ? [.option("Understood")] : [], action: "pay29s",
                     data: .object(["k": "short", "ids": .array([.number(Double(co.id))]), "l": .array([.string(line)])]),
                     sev: toOwner ? 3 : 2, aud: toOwner ? "owner" : "finance", handledBy: who)
    }

    static func backPay(_ s: inout GameState, _ i: Int, today t: Int) {
        var co = s.companies[i]
        var cfg = config(co, today: t)
        guard cfg.lateSince != nil, cfg.lateWhy == "cash" else { return }
        let wagesOwed = co.payables["wages"] ?? 0
        let p = min(cfg.lateOwed, wagesOwed, max(0, co.cash))
        if p < 1 && wagesOwed >= 1 { return }
        if p >= 1 {
            AccountingLedger.note(category: "wages", label: "Back pay to staff")
            Ledger.moveRaw(&s, .company(co.id), -p)
            co = s.companies[i]
            co.payables["wages"] = (co.payables["wages"] ?? 0) - p
            co.addTransaction(week: s.week, amount: -jsRound(p), label: "Back pay to staff")
            cfg.lateOwed -= p
        }
        let stillOwed = co.payables["wages"] ?? 0
        if cfg.lateOwed < 1 || stillOwed < 1 {
            cfg.lateSince = nil; cfg.lateWhy = ""; cfg.lateOwed = 0; co.wageShortfall = 0
            co.set("pr29", cfg.json)
            s.companies[i] = co
            s.note("Back pay sent at \(co.name). Everyone is paid in full.", tone: "good", companyID: co.id)
            co = s.companies[i]
        }
        co.set("pr29", cfg.json)
        s.companies[i] = co
    }

    @discardableResult
    static func payBills(_ s: inout GameState, _ i: Int, today t: Int, context: FinanceContext, data: GameData? = nil) -> (paid: Double, short: Double) {
        var co = s.companies[i]
        var left = max(0, co.cash + context.overdraftRoom(co, s))
        var short = 0.0, paid = 0.0
        var cfg = config(co, today: t)
        let overdue = (cfg.arrears["rent"] ?? 0) + (cfg.arrears["other"] ?? 0)
        let carried = min(overdue, (co.payables["rent"] ?? 0) + (co.payables["other"] ?? 0))
        let lateFee = jsRound(carried * SupplyTerms.lateMonthlyRate(country: context.country(of: co, s), policyRate: s.economy.policyRate))
        if lateFee > 0 {
            co.addPayable("other", lateFee)
            var b = co.books; b.add("int", lateFee); co.books = b
            s.companies[i] = co
            s.addDeskNotice("finance", company: co, data: data, title: "Late fees at \(co.name)",
                            body: "Rent and supplier bills left unpaid last month now carry late interest of \(context.currency(co.countryCode, s).display(lateFee)).")
        }
        for k in ["rent", "other"] {
            let due = co.payables[k] ?? 0
            if due <= 0 { cfg.arrears[k] = nil; continue }
            let p = min(due, left)
            if p > 0 {
                s.companies[i] = co
                AccountingLedger.note(category: k == "rent" ? "rent" : "cogs", label: k == "rent" ? "Rent" : "Supplier and monthly bills")
                Ledger.moveRaw(&s, .company(co.id), -p)
                co = s.companies[i]
                let used = !co.value("f30").object.isEmpty
                co.addTransaction(week: s.week, amount: -jsRound(p), label: k == "rent" ? "Rent" : (used ? "Monthly bills: suppliers, insurance, leasing, fees" : "Suppliers and costs"))
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
            if let d = data { SupplyTerms.billsMissed(&s, companyIndex: i, data: d) }
            cfg.billShortMonths += 1
            if cfg.billShortMonths == 1 {
                let cur = context.currency(co.countryCode, s)
                s.addDeskNotice("finance", company: co, data: data, title: "Could not pay all bills at \(co.name)",
                                body: "Missing \(cur.display(short)) for rent and suppliers this month. Put money in or cut costs, or suppliers will stop delivering.")
            }
            if cfg.billShortMonths >= 2 { s.companies[i].reputation = clamp(s.companies[i].reputation - 1, 0, 100) }
        } else { cfg.billShortMonths = 0 }
        let cutoffOn = FirstYear.effective(s, base: data?.balance.firstYear ?? FirstYear.bundled).supplierCutoffActive(week: s.week)
        let level = !cutoffOn ? 0 : cfg.billShortMonths >= 3 ? 2 : cfg.billShortMonths >= 2 ? 1 : 0
        if level > 0 || s.companies[i].raw["supCutB"] != nil { s.companies[i].set("supCutB", level); if level == 0 { s.companies[i].raw.removeValue(forKey: "supCutB") } }
        let level2 = max(level, SupplyTerms.invoiceCutLevel(s.companies[i], week: s.week))
        s.companies[i].set("supCut", level2)
        if level2 > wasCut {
            let body = level2 == 1 ? "After repeated missed bills suppliers only deliver stock against cash in the account. Pay what is overdue to get credit terms back."
                                   : "Suppliers refuse new stock until the overdue bills are paid. Sales will suffer."
            if level2 == 1 { s.addDeskNotice("finance", company: co, data: data, title: "Suppliers want cash at \(co.name)", body: body) }
            else { s.addMessage(from: co.name, title: "Suppliers stop delivering to \(co.name)", body: body, companyID: co.id, tone: "bad", sev: 3) }
        } else if level2 == 0 && wasCut > 0 {
            s.addDeskNotice("finance", company: co, data: data, title: "Suppliers deliver normally again", body: "The overdue bills at \(co.name) are paid. Suppliers are back on normal terms.", tone: "good", sev: 1)
        }
        s.companies[i].set("pr29", cfg.json)
        return (jsRound(paid), jsRound(short))
    }

    static func payBillsEarly(_ s: inout GameState, _ i: Int, today t: Int, context: FinanceContext) -> Double? {
        var co = s.companies[i]
        let owed = (co.payables["rent"] ?? 0) + (co.payables["other"] ?? 0)
        guard owed > 0, co.cash + context.overdraftRoom(co, s) >= owed else { return nil }
        var cfg = config(co, today: t)
        var paid = 0.0
        for k in ["rent", "other"] {
            let due = co.payables[k] ?? 0
            if due <= 0 { continue }
            s.companies[i] = co
            AccountingLedger.note(category: k == "rent" ? "rent" : "cogs", label: k == "rent" ? "Rent" : "Supplier and monthly bills")
            Ledger.moveRaw(&s, .company(co.id), -due)
            co = s.companies[i]
            let used = !co.value("f30").object.isEmpty
            co.addTransaction(week: s.week, amount: -jsRound(due), label: k == "rent" ? "Rent" : (used ? "Monthly bills: suppliers, insurance, leasing, fees" : "Suppliers and costs"))
            if k == "rent" { s.companies[i] = co; PremisesExtras.payLandlord(&s, tenantIndex: i, paid: due); co = s.companies[i] }
            cfg.arrears[k] = nil
            co.payables[k] = 0
            paid += due
        }
        co.set("f30", .object([:]))
        co.set("pr29", cfg.json)
        s.companies[i] = co
        return jsRound(paid)
    }

    static func unpaidForMonths(_ co: Company, today t: Int) -> Bool {
        config(co, today: t).billShortMonths >= 4 || co.unpaidMonths >= 6
    }

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
            for m in co.staff where !co.value("flags")["noquit"].bool && s.random.chance(0.04) {
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
                         body: "Staff took the unpaid wages to a lawyer. Legal costs and late interest: \(cur.display(f)). The wages are still owed.", companyID: co.id, tone: "bad", sev: 3)
        }
    }

    static func waitsForCash(_ s: inout GameState, _ i: Int, due: Double, today t: Int, data: GameData) -> Bool {
        guard due > 0, FirstYear.effective(s, balance: data.balance).noOverdraftActive(s), due > s.companies[i].cash else { return false }
        s.rest["tight"] = .number(Double(t))
        return true
    }

    static func payrollDue(_ s: GameState, _ i: Int) -> Double { s.companies[i].payables["wages"] ?? 0 }

    public static func onDay(_ s: inout GameState, data: GameData, context: FinanceContext) {
        if !s.dayMode || s.isGameOver { return }
        let t = dayNumber(week: s.week, day: s.day)
        let c = civil(t)
        let mi = monthNumber(t)
        var paidToday: [(String, Double)] = []
        s.rest.removeValue(forKey: "tight")
        for i in s.companies.indices where s.companies[i].status.isLive { LegalDebts.settle(&s, companyIndex: i) }
        for i in s.companies.indices where s.companies[i].status.isLive {
            var cfg = config(s.companies[i], today: t)
            let pd = payDate(year: c.year, month: c.month - 1)
            if cfg.paidMonth < mi && t >= pd && cfg.lateSince == nil,
               !waitsForCash(&s, i, due: payrollDue(s, i), today: t, data: data) {
                if !hasPayroll(s.companies[i]) {
                    cfg.paidMonth = mi
                    s.companies[i].set("pr29", cfg.json)
                } else {
                    let r = runPayroll(&s, i, today: t, data: data, context: context)
                    paidToday.append((s.companies[i].name, r.paid))
                }
            }
            cfg = config(s.companies[i], today: t)
            if cfg.lateSince != nil { lateDay(&s, i, today: t, data: data, context: context) }
            let bd2 = billDate(year: c.year, month: c.month - 1)
            cfg = config(s.companies[i], today: t)
            let billsOwed: Double = (s.companies[i].payables["rent"] ?? 0) + (s.companies[i].payables["other"] ?? 0)
            let billsWait: Bool = (cfg.billsMonth < mi - 1 || (cfg.billsMonth < mi && t >= bd2)) && waitsForCash(&s, i, due: billsOwed, today: t, data: data)
            if !billsWait && cfg.billsMonth < mi - 1 {
                cfg.billsMonth = mi - 1
                s.companies[i].set("pr29", cfg.json)
                payBills(&s, i, today: t, context: context, data: data)
            }
            cfg = config(s.companies[i], today: t)
            if !billsWait && cfg.billsMonth < mi && t >= bd2 {
                cfg.billsMonth = mi
                s.companies[i].set("pr29", cfg.json)
                payBills(&s, i, today: t, context: context, data: data)
            }
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

    static func nextPay(_ co: Company, config cfg: PayrollConfig, today t: Int) -> Int {
        let c = civil(t)
        let mi = monthNumber(t)
        if cfg.lateSince != nil, cfg.lateMonth >= 0 { return payDate(year: cfg.lateMonth / 12, month: cfg.lateMonth % 12) }
        if cfg.paidMonth < mi { return payDate(year: c.year, month: c.month - 1) }
        let nextMonth = c.month == 12 ? (c.year + 1, 0) : (c.year, c.month)
        return payDate(year: nextMonth.0, month: nextMonth.1)
    }

    static func dateText(_ n: Int) -> String { let d = civil(n); return "\(d.day) \(GameCalendar.monthNames[d.month - 1]) \(d.year)" }
}
