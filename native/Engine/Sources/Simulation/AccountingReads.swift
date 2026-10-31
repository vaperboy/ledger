import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

// Accounting read models and records (Stage 2). Accounting records and manages; the Bank holds the money and executes payments. Everything here reads
// the existing engine (Payments/Ledger rows, receivables and invoices, payroll, staff contracts, suppliers, documents); nothing is invented.
// Every read takes `user` (nil = the owner) and answers nil when that user has no access to the section (see AccountingAccess).

// MARK: Transactions

public enum TransactionFilterKind: Sendable { case all, income, expenses }

public struct LedgerLink: Equatable, Sendable {
    /// loan, supplier, invoice, payroll
    public var kind: String
    public var id: String
    public var title: String
}

public struct LedgerTransaction: Equatable, Sendable, Identifiable {
    public var id: String
    public var week: Int
    public var day: Int
    public var dateText: String
    /// Signed: income positive, expense negative. A merged row is the sum of `count` movements of the week.
    public var amount: Double
    public var count: Int
    public var categoryID: String
    public var category: String
    public var isIncome: Bool
    public var label: String
    public var counterparty: String
    public var link: LedgerLink?
    public var note: String?
    /// From the old capped list, before the full ledger began for this company.
    public var isLegacy: Bool
}

public struct TransactionCategoryTotal: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var income: Double
    public var expenses: Double
}

public struct TransactionPage: Equatable, Sendable {
    public var entries: [LedgerTransaction]
    public var income: Double
    public var expenses: Double
    public var categories: [TransactionCategoryTotal]
    /// The week the full ledger began for this company (earlier rows are legacy).
    public var ledgerFromWeek: Int?
}

public struct TransactionDetail: Equatable, Sendable {
    public var transaction: LedgerTransaction
    public var account: String
    public var fields: [(String, String)]
    public static func == (a: Self, b: Self) -> Bool { a.transaction == b.transaction && a.account == b.account && a.fields.elementsEqual(b.fields, by: { $0 == $1 }) }
}

// MARK: Invoices

public enum InvoiceKind: String, Sendable { case customer, supplier }
/// `draft` exists for completeness of the model; the simulation raises invoices already sent, so none is ever draft.
public enum InvoiceStatus: String, Sendable { case draft, sent, paid, overdue, writtenOff }

public struct InvoiceLineItem: Equatable, Sendable { public var description: String; public var quantity: Double; public var net: Double }

public struct InvoiceItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var number: String
    public var kind: InvoiceKind
    public var counterparty: String
    public var issuedDateText: String
    public var dueDateText: String
    public var status: InvoiceStatus
    public var gross: Double
    public var tax: Double
    public var net: Double
    public var lines: [InvoiceLineItem]
    public var paidDateText: String?
    /// Supplier invoices can be paid now through the Bank payment engine.
    public var canPayNow: Bool
    public var obligationID: String?
}

// MARK: Payroll

public struct PayslipLine: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var role: String
    /// "staff", "manager" or "owner"
    public var kind: String
    public var grossMonthly: Double
    public var employerContributions: Double
    public var insurance: Double
    public var paidLeaveCover: Double
    public var hoursPerMonth: Double
    public var totalEmployerCost: Double
}

public struct PayrollRunRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var periodIndex: Int
    public var periodText: String
    public var dateText: String
    public var paid: Double
    public var short: Double
    public var linesTotal: Double
    public var runBy: String
    public var lines: [PayslipLine]
    public var grossTotal: Double { lines.reduce(0) { $0 + $1.grossMonthly } }
    public var employerCostsTotal: Double { lines.reduce(0) { $0 + $1.employerContributions + $1.insurance + $1.paidLeaveCover } }
}

/// The review before payroll goes out: who is included, gross, employer taxes and contributions, total employer cost, the account and its balance.
public struct PayrollRunReview: Equatable, Sendable {
    public var companyID: Int
    public var periodText: String
    public var payDateText: String
    public var lines: [PayslipLine]
    public var grossTotal: Double
    public var employerContributions: Double
    public var insurance: Double
    public var paidLeaveCover: Double
    public var totalEmployerCost: Double
    /// What payroll has accrued and will pay (wages owed now plus what builds up to the pay day).
    public var amountDue: Double
    public var account: String
    public var availableBalance: Double
    public var canCover: Bool
    public var alreadyPaidForPeriod: Bool
    public var responsibleName: String
    public var needsYourApproval: Bool
    /// Deductions from the employee's pay are not modelled in the payroll books.
    public var deductionsNote: String
}

public struct TimesheetRow: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var role: String
    public var contractedHoursPerWeek: Double
    public var workingPercentage: Double
    /// Hours the contract expects in the month (0 while laid off for the off-season).
    public var expectedHoursInMonth: Double
    public var offSeason: Bool
    public var sickUntilWeek: Int?
    /// The simulation does not record hours actually worked, so none are shown.
    public var actualHoursRecorded: Double?
}

// MARK: Suppliers

public struct SupplierRecord: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var owner: String
    public var rating: Double
    public var relationship: String
    public var discount: Double
    public var isCurrentGoodsSupplier: Bool
    public var isCurrentRepairSupplier: Bool
    public var agreement: String?
    public var purchasesTotal: Double
    public var openInvoices: Double
    public var recentPurchases: [LedgerTransaction]
}

// MARK: Documents

public enum DocumentGroup: String, Sendable { case company, tax, contracts }

public struct AccountingDocument: Equatable, Sendable, Identifiable {
    public var id: String
    public var group: DocumentGroup
    /// registration, legalForm, ownership, licence, filing, employment, supplier, customer, financing, chain
    public var kind: String
    public var title: String
    public var detail: String
    public var status: String
    public var dateText: String?
    public var amount: Double?
}

public extension GameEngine {
    // MARK: Transactions

    private static let categoryNames: [(id: String, name: String)] = [
        ("sales", "Sales"), ("purchases", "Supplier purchases"), ("payroll", "Payroll"), ("rent", "Rent"), ("marketing", "Marketing"), ("insurance", "Insurance"),
        ("running", "Running costs"), ("interest", "Interest"), ("loans", "Loans"), ("tax", "Tax and VAT"), ("accounting", "Accounting fees"), ("fines", "Fines"),
        ("equipment", "Equipment"), ("owner", "Owner"), ("other", "Other"),
    ]

    static func ledgerCategory(code: String, label: String) -> String {
        switch code {
        case "rev": return "sales"
        case "cogs": return "purchases"
        case "wages": return "payroll"
        case "rent": return "rent"
        case "mkt": return "marketing"
        case "ins": return "insurance"
        case "oth": return "running"
        case "int": return "interest"
        case "loan": return "loans"
        case "tax": return "tax"
        case "acc": return "accounting"
        case "fine": return "fines"
        case "owner": return "owner"
        default: break
        }
        let l = label.lowercased()
        if l.contains("loan") { return "loans" }
        if l.contains("vat") || l.contains("tax") { return "tax" }
        if l.contains("payroll") || l.contains("wages") || l.contains("salary") || l.contains("back pay") { return "payroll" }
        if l.contains("rent") { return "rent" }
        if l.contains("stock") || l.contains("supplier") || l.contains("goods") { return "purchases" }
        if l.contains("equipment") || l.contains("vehicle") || l.contains("machine") { return "equipment" }
        if l.contains("dividend") || l.contains("capital") || l.contains("drawing") || l.contains("investment") || l.contains("invested") { return "owner" }
        if l.contains("sale") || l.contains("customer") { return "sales" }
        return "other"
    }

    private func ledgerTransactions(_ co: Company) -> [LedgerTransaction] {
        let notes = co.value("lednotes")
        var out: [LedgerTransaction] = []
        let rows = AccountingLedger.rows(co)
        let from = co.raw["ledFrom"].map { $0.int } ?? Int.max
        for r in rows {
            let cat = Self.ledgerCategory(code: r.category, label: r.label)
            var link: LedgerLink?
            var party = ""
            let parts = r.ref.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                switch parts[0] {
                case "loan": link = LedgerLink(kind: "loan", id: parts[1], title: state.loans.first { String($0.id) == parts[1] }?.name ?? "Loan"); party = "Bank"
                case "supplier": let n = Suppliers.vendor(state, id: parts[1], data: data)?.name ?? "Supplier"; link = LedgerLink(kind: "supplier", id: parts[1], title: n); party = n
                case "payroll": link = LedgerLink(kind: "payroll", id: parts[1], title: "Payroll run"); party = "Employees"
                default: link = LedgerLink(kind: parts[0], id: parts[1], title: parts[0].capitalized)
                }
            }
            let id = r.id
            out.append(LedgerTransaction(id: id, week: r.week, day: r.day, dateText: GameCalendar.dateString(week: r.week, dayOffset: r.day), amount: r.amount, count: r.count,
                                         categoryID: cat, category: Self.categoryNames.first { $0.id == cat }?.name ?? "Other", isIncome: r.amount > 0, label: r.label,
                                         counterparty: party, link: link, note: notes[id].isNull ? nil : notes[id].string, isLegacy: false))
        }
        // The old capped list, only for the time before the full ledger began.
        for (k, t) in co.transactions.enumerated() where t["w"].int < from {
            let label = t["l"].string, amount = t["a"].double
            let cat = Self.ledgerCategory(code: "-", label: label)
            let id = "t\(t["w"].int).\(k)"
            out.append(LedgerTransaction(id: id, week: t["w"].int, day: 0, dateText: GameCalendar.dateString(week: t["w"].int), amount: amount, count: 1, categoryID: cat,
                                         category: Self.categoryNames.first { $0.id == cat }?.name ?? "Other", isIncome: amount > 0, label: label, counterparty: "", link: nil,
                                         note: notes[id].isNull ? nil : notes[id].string, isLegacy: true))
        }
        return out.sorted { $0.week != $1.week ? $0.week > $1.week : ($0.day != $1.day ? $0.day > $1.day : $0.id > $1.id) }
    }

    /// The transaction ledger of one company: all / income / expenses, a category, a date range (game weeks), a search over label, category,
    /// counterparty and note. Newest first. nil without access.
    func companyTransactions(companyID: Int, kind: TransactionFilterKind = .all, category: String? = nil, fromWeek: Int? = nil, toWeek: Int? = nil,
                             search: String = "", user: String? = nil) -> TransactionPage? {
        guard let co = state.company(companyID), canAccess(.transactions, companyID: companyID, user: user) else { return nil }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all = ledgerTransactions(co).filter { t in
            (fromWeek == nil || t.week >= fromWeek!) && (toWeek == nil || t.week <= toWeek!) && (category == nil || t.categoryID == category)
                && (q.isEmpty || t.label.lowercased().contains(q) || t.category.lowercased().contains(q) || t.counterparty.lowercased().contains(q) || (t.note ?? "").lowercased().contains(q))
        }
        let shown = all.filter { kind == .all || (kind == .income) == $0.isIncome }
        var totals: [String: (Double, Double)] = [:]
        for t in all { var v = totals[t.categoryID] ?? (0, 0); if t.isIncome { v.0 += t.amount } else { v.1 -= t.amount }; totals[t.categoryID] = v }
        let cats = Self.categoryNames.compactMap { c in totals[c.id].map { TransactionCategoryTotal(id: c.id, name: c.name, income: $0.0, expenses: $0.1) } }
        return TransactionPage(entries: shown, income: all.filter(\.isIncome).reduce(0) { $0 + $1.amount }, expenses: -all.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount },
                               categories: cats, ledgerFromWeek: co.raw["ledFrom"].map { $0.int })
    }

    func transactionDetail(companyID: Int, id: String, user: String? = nil) -> TransactionDetail? {
        guard let co = state.company(companyID), canAccess(.transactions, companyID: companyID, user: user),
              let t = ledgerTransactions(co).first(where: { $0.id == id }) else { return nil }
        var f: [(String, String)] = [("Date", t.dateText), ("Category", t.category), ("Description", t.label), ("Direction", t.isIncome ? "Income" : "Expense")]
        if t.count > 1 { f.append(("Movements in the week", "\(t.count)")) }
        if !t.counterparty.isEmpty { f.append(("Counterparty", t.counterparty)) }
        if let l = t.link { f.append(("Linked record", l.title)) }
        if t.isLegacy { f.append(("Source", "Old transaction list, before the full ledger")) }
        return TransactionDetail(transaction: t, account: co.name + " account", fields: f)
    }

    /// Add or clear a note on a transaction (full bookkeeping access).
    @discardableResult
    mutating func setTransactionNote(companyID: Int, id: String, note: String, user: String? = nil) -> Bool {
        guard canAccess(.notes, companyID: companyID, user: user), let co = state.company(companyID), ledgerTransactions(co).contains(where: { $0.id == id }) else { return false }
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            var n = s.companies[i].value("lednotes")
            if n.isNull { n = .object([:]) }
            let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            if text.isEmpty { var o = n.object; o.removeValue(forKey: id); n = .object(o) } else { n[id] = .string(text) }
            if n.object.isEmpty { s.companies[i].raw.removeValue(forKey: "lednotes") } else { s.companies[i].set("lednotes", n) }
        }
        return true
    }

    // MARK: Invoices

    func invoices(companyID: Int, kind: InvoiceKind? = nil, status: InvoiceStatus? = nil, user: String? = nil) -> [InvoiceItem]? {
        guard let co = state.company(companyID), canAccess(.invoices, companyID: companyID, user: user) else { return nil }
        var out: [InvoiceItem] = []
        if kind != .supplier {
            for r in InvoiceBook.records(co) {
                let st: InvoiceStatus = r.closed == "paid" ? .paid : r.closed == "bad" ? .writtenOff : (state.week > r.dueWeek ? .overdue : .sent)
                out.append(InvoiceItem(id: "c-" + r.number, number: r.number, kind: .customer, counterparty: r.customer, issuedDateText: GameCalendar.dateString(week: r.issuedWeek),
                                       dueDateText: GameCalendar.dateString(week: r.dueWeek), status: st, gross: r.gross, tax: r.tax, net: r.gross - r.tax,
                                       lines: r.lines.map { InvoiceLineItem(description: $0.description, quantity: $0.quantity, net: $0.net) },
                                       paidDateText: r.paidWeek.map { GameCalendar.dateString(week: $0) }, canPayNow: false, obligationID: nil))
            }
        }
        if kind != .customer {
            let open = financeOverview(companyID: companyID).upcoming.filter { $0.kind == .invoice }
            for inv in SupplyTerms.invoices(state, buyer: companyID) {
                let oid = open.first { $0.id.hasPrefix("inv\(companyID)|") && $0.id.contains("|\(inv.providerName)|") && $0.id.hasSuffix("|\(inv.dueWeek)") }?.id
                out.append(InvoiceItem(id: "s-\(inv.id)", number: "SI-" + String(format: "%04d", inv.id), kind: .supplier, counterparty: inv.providerName,
                                       issuedDateText: GameCalendar.dateString(week: inv.issuedWeek), dueDateText: GameCalendar.dateString(week: inv.dueWeek),
                                       status: state.week > inv.dueWeek ? .overdue : .sent, gross: inv.amount, tax: 0, net: inv.amount,
                                       lines: [InvoiceLineItem(description: inv.kind.isEmpty ? "Goods and services" : inv.kind.capitalized, quantity: 1, net: inv.face)],
                                       paidDateText: nil, canPayNow: oid != nil, obligationID: oid))
            }
        }
        return out.filter { status == nil || $0.status == status }.sorted { $0.id > $1.id }
    }

    /// Pay an open supplier invoice now through the Bank payment engine (the same path as the Bills list). Customer invoices are paid by the customer.
    @discardableResult
    mutating func paySupplierInvoice(companyID: Int, invoiceID: String, user: String? = nil) -> EarlyPaymentOutcome {
        guard canAccess(.payments, companyID: companyID, user: user) else { return .refused("You do not have access to pay invoices.") }
        guard let item = invoices(companyID: companyID, kind: .supplier)?.first(where: { $0.id == invoiceID }), let oid = item.obligationID,
              let o = financeOverview(companyID: companyID).upcoming.first(where: { $0.id == oid }) else { return .refused("That invoice is not open.") }
        return payObligationNow(o)
    }

    // MARK: Payroll

    private func payslipLine(_ id: Int, _ name: String, _ role: String, _ kind: String, _ b: EmployerCost.Breakdown) -> PayslipLine {
        PayslipLine(id: id, name: name, role: role, kind: kind, grossMonthly: b.grossMonthlyWage, employerContributions: b.employerTaxesAndContributions, insurance: b.insurance,
                    paidLeaveCover: b.paidLeaveCover, hoursPerMonth: b.expectedHoursPerMonth, totalEmployerCost: b.totalMonthly)
    }

    private func currentPayslipLines(_ co: Company) -> [PayslipLine] {
        let country = context.country(of: co, state)
        var lines = co.staff.map { payslipLine($0.id, state.people[$0.id]?.name ?? "Employee", $0.role, "staff", EmployerCost.monthly($0, country: country)) }
        if let mid = co.managerID { lines.append(payslipLine(mid, state.people[mid]?.name ?? "Manager", "manager", "manager", EmployerCost.monthly(wage: co.managerMonthlyWage, country: country))) }
        if Payday.ownerOnPayroll(co) { lines.append(payslipLine(0, "You (owner)", "owner", "owner", EmployerCost.monthly(wage: co.ownerMonthlySalary, country: country))) }
        return lines
    }

    private func periodText(_ mi: Int) -> String { "\(GameCalendar.monthNames[((mi % 12) + 12) % 12]) \(mi / 12)" }

    /// Payroll runs, newest first. Each is the record of a real run of the payment engine.
    func payrollRuns(companyID: Int, user: String? = nil) -> [PayrollRunRecord]? {
        guard let co = state.company(companyID), canAccess(.payroll, companyID: companyID, user: user) else { return nil }
        return co.value("prun").array.reversed().map { r in
            PayrollRunRecord(id: r["id"].int, periodIndex: r["mi"].int, periodText: periodText(r["mi"].int), dateText: GameCalendar.dateString(week: r["w"].int), paid: r["paid"].double,
                             short: r["short"].double, linesTotal: r["tot"].double, runBy: r["by"].string,
                             lines: r["ln"].array.map { PayslipLine(id: $0["id"].int, name: $0["n"].string, role: $0["r"].string, kind: $0["k"].string, grossMonthly: $0["gross"].double,
                                                                   employerContributions: $0["ec"].double, insurance: $0["ins"].double, paidLeaveCover: $0["lv"].double,
                                                                   hoursPerMonth: $0["hrs"].double, totalEmployerCost: $0["tot"].double) })
        }
    }

    /// The payslips of one run, one per person paid.
    func payslips(companyID: Int, runID: Int, user: String? = nil) -> [PayslipLine]? { payrollRuns(companyID: companyID, user: user)?.first { $0.id == runID }?.lines }

    /// Review before payroll goes out (who is included, gross, employer costs, the account and its balance, whether this period is already paid).
    func payrollRunReview(companyID: Int, user: String? = nil) -> PayrollRunReview? {
        guard let co = state.company(companyID), canAccess(.payroll, companyID: companyID, user: user), let o = payrollOverview(companyID: companyID) else { return nil }
        let lines = currentPayslipLines(co)
        let t = Payday.dayNumber(week: state.week, day: state.day)
        let cfg = Payday.config(co, today: t)
        let nextKey = Payday.monthNumber(o.nextPayDay)
        return PayrollRunReview(companyID: companyID, periodText: periodText(nextKey), payDateText: o.nextPayText, lines: lines, grossTotal: lines.reduce(0) { $0 + $1.grossMonthly },
                                employerContributions: lines.reduce(0) { $0 + $1.employerContributions }, insurance: lines.reduce(0) { $0 + $1.insurance },
                                paidLeaveCover: lines.reduce(0) { $0 + $1.paidLeaveCover }, totalEmployerCost: lines.reduce(0) { $0 + $1.totalEmployerCost },
                                amountDue: o.estimate, account: co.name + " account", availableBalance: co.cash, canCover: co.cash >= o.estimate,
                                alreadyPaidForPeriod: cfg.paidMonth >= nextKey, responsibleName: o.responsibility?.name ?? "You", needsYourApproval: o.needsApproval,
                                deductionsNote: "Deductions from employees' pay are not part of the company's payroll books; the figures are the company's cost.")
    }

    /// Run payroll from Accounting: approves the coming pay day, or pays late payroll now. It is the existing payroll action (never a second one),
    /// so a period cannot be paid twice.
    @discardableResult
    mutating func runPayrollFromAccounting(companyID: Int, user: String? = nil) -> PayrollAlertOutcome {
        guard canAccess(.payroll, companyID: companyID, user: user) else { return .notNeeded("You do not have access to payroll.") }
        return resolvePayrollAlert(companyID: companyID)
    }

    /// Hours from the contracts for a month (default the current one). Hours actually worked are not recorded by the simulation, so they are not made up.
    func timesheets(companyID: Int, monthIndex: Int? = nil, user: String? = nil) -> [TimesheetRow]? {
        guard let co = state.company(companyID), canAccess(.timesheets, companyID: companyID, user: user) else { return nil }
        let mi = monthIndex ?? GameCalendar.monthIndex(week: state.week)
        let current = mi == GameCalendar.monthIndex(week: state.week)
        return co.staff.map { m in
            let b = EmployerCost.monthly(m, country: context.country(of: co, state))
            let off = current && m.isOffSeason
            return TimesheetRow(id: m.id, name: state.people[m.id]?.name ?? "Employee", role: m.role, contractedHoursPerWeek: b.contractedHoursPerWeek, workingPercentage: b.workingPercentage,
                                expectedHoursInMonth: off ? 0 : b.expectedHoursPerMonth, offSeason: off, sickUntilWeek: m.sickUntilWeek, actualHoursRecorded: nil)
        }
    }

    // MARK: Suppliers

    func supplierRecords(companyID: Int, search: String = "", user: String? = nil) -> [SupplierRecord]? {
        guard let co = state.company(companyID), canAccess(.suppliers, companyID: companyID, user: user) else { return nil }
        let goods = Suppliers.goodsVendor(state, company: co, data: data)?.id
        let repair = Suppliers.repairVendor(state, company: co, data: data)?.id
        let tx = ledgerTransactions(co)
        let invoices = SupplyTerms.invoices(state, buyer: companyID)
        var vendors = Suppliers.known(state, data: data)
        for id in [goods, repair].compactMap({ $0 }) where !vendors.contains(where: { $0.id == id }) { if let v = Suppliers.vendor(state, id: id, data: data) { vendors.append(v) } }
        let q = search.lowercased()
        return vendors.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.owner.lowercased().contains(q) }.map { v in
            let mine = tx.filter { $0.link?.kind == "supplier" && $0.link?.id == v.id }
            return SupplierRecord(id: v.id, name: v.name, owner: v.owner, rating: v.rating, relationship: v.relationshipWord, discount: v.discount, isCurrentGoodsSupplier: v.id == goods,
                                  isCurrentRepairSupplier: v.id == repair, agreement: Suppliers.agreement(state, scope: "goods"), purchasesTotal: -mine.reduce(0) { $0 + $1.amount },
                                  openInvoices: invoices.filter { $0.vendorID == v.id }.reduce(0) { $0 + $1.amount }, recentPurchases: Array(mine.prefix(8)))
        }
    }

    // MARK: Documents

    func companyDocuments(companyID: Int, group: DocumentGroup? = nil, user: String? = nil) -> [AccountingDocument]? {
        guard let co = state.company(companyID), canAccess(.documents, companyID: companyID, user: user), let country = data.countries[co.countryCode] else { return nil }
        var out: [AccountingDocument] = []
        func add(_ g: DocumentGroup, _ kind: String, _ id: String, _ title: String, _ detail: String, _ status: String, week: Int? = nil, amount: Double? = nil) {
            out.append(AccountingDocument(id: id, group: g, kind: kind, title: title, detail: detail, status: status, dateText: week.map { GameCalendar.dateString(week: $0) }, amount: amount))
        }
        let forms = country.companyForms
        let legal = co.value("legal")
        add(.company, "legalForm", "legal", co.form == .limited ? (forms["limited"] ?? "Limited company") : (forms["soleTrader"] ?? "Sole trader"),
            co.name, "In force", week: legal["since"].isNull ? co.foundedWeek : legal["since"].int)
        for h in legal["hist"].array {
            add(.company, "legalForm", "conv\(h["w"].int)", "Conversion to a limited company", "Fee \(h["fee"].double.rounded()), share capital \(h["capital"].double.rounded()), paid by \(h["payer"].string)",
                "Done", week: h["w"].int, amount: h["capital"].double)
        }
        let holders = co.value("holders").array.filter { $0["pct"].double > 0 }
        add(.company, "ownership", "own", "Ownership", "You hold \(Int(co.ownership.rounded()))%" + (holders.isEmpty ? "" : "; others: " + holders.map { "\($0["name"].string) \(Int($0["pct"].double.rounded()))%" }.joined(separator: ", ")), "Current")
        if co.shareCapital > 0 { add(.company, "ownership", "capital", "Share capital", legal["shares"]["count"].isNull ? "" : "\(Int(legal["shares"]["count"].double)) shares", "Paid in", amount: co.shareCapital) }
        let acc = co.value("acc")
        if !acc["id"].isNull { add(.company, "registration", "accagr", "Accountant agreement", acc["name"].string, co.value("docs")["accountant_agreement"]["st"].string == "ok" ? "In force" : "Pending", week: acc["w0"].int) }
        let w = World(state: state, data: data)
        for (id, d) in co.value("docs").object.sorted(by: { $0.key < $1.key }) where id != "accountant_agreement" {
            guard let def = Documents.definition(id, country: country, tables: data.catalog.tables) else { continue }
            let st = d["st"].string
            let isTax = id.hasPrefix("vat") || id == "tax"
            add(isTax ? .tax : .company, id == "registration" ? "registration" : "licence", "doc-" + id, def.name, def.issuer, st == "ok" ? "Held" : st.isEmpty ? "Not held" : st.capitalized,
                week: d["ok"].isNull ? nil : d["ok"].int)
        }
        _ = w
        // Tax: filings and payments recorded in the ledger (real VAT and corporate tax settlements).
        for t in ledgerTransactions(co) where t.categoryID == "tax" && t.amount < 0 {
            add(.tax, "filing", "tax-" + t.id, t.label, t.counterparty, "Paid", week: t.week, amount: -t.amount)
        }
        if co.taxAccrued > 0 || (co.payables["tax"] ?? 0) > 0 { add(.tax, "filing", "taxopen", "Corporate tax this year", "Accrued, not yet due", "Open", amount: max(co.taxAccrued, co.payables["tax"] ?? 0)) }
        if co.vatBalance > 1 { add(.tax, "filing", "vatopen", "VAT balance", "To be settled with the next return", "Open", amount: co.vatBalance) }
        // Contracts: employment, supplier, customer, financing, chain/franchise.
        for m in co.staff {
            let name = state.people[m.id]?.name ?? "Employee"
            let ft = m.raw["ft"].map { $0.isNull ? nil : $0.int } ?? nil
            add(.contracts, "employment", "emp\(m.id)", "Employment contract: \(name)", "\(m.role), \(Int((m.weeklyHours ?? StaffModel.fullWeekHours).rounded())) h a week" + (ft.map { ", fixed term to \(GameCalendar.dateString(week: $0))" } ?? ""),
                "In force", week: m.hiredWeek, amount: m.monthlyWage)
        }
        if let mid = co.managerID { add(.contracts, "employment", "emp\(mid)", "Employment contract: \(state.people[mid]?.name ?? "Manager")", "Manager", "In force", amount: co.managerMonthlyWage) }
        if let v = Suppliers.goodsVendor(state, company: co, data: data) {
            add(.contracts, "supplier", "sup-" + v.id, "Supplier: \(v.name)", Suppliers.agreement(state, scope: "goods") ?? "Standing supplier, no written agreement", "Active")
        }
        for a in co.value("accts").array { add(.contracts, "customer", "cus\(a["id"].int)", "Business customer: \(a["name"].string)", "Supplied on trade terms", "Active") }
        for l in loanRecords(companyID: companyID) {
            add(.contracts, "financing", "loan\(l.id)", "\(l.name) \(l.number)", "\(l.lender), \(l.termMonths) months at \(String(format: "%.2f", l.yearlyRate * 100))%" + (l.personallyGuaranteed ? ", personally guaranteed" : ""),
                "Balance outstanding", week: l.startWeek, amount: l.balance)
        }
        if !co.value("chain").isNull { add(.contracts, "chain", "chain", "Chain membership", "Store of a chain", "Active") }
        if co.value("fr")["on"].bool { add(.contracts, "chain", "franchise", "Franchise", "Franchise agreements held by this company", "Active") }
        return out.filter { group == nil || $0.group == group }
    }
}
