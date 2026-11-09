import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

// Accounting read models and records. Accounting records and manages; the Bank holds the money and executes payments. Everything here reads
// the existing engine (Payments/Ledger rows, receivables and invoices, payroll, staff contracts, suppliers, documents); nothing is invented.
// Records are the owner's: there are no named users.

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

/// `insurance` and `applications` are records of their own: the policies the company holds, and the chain, franchise and brand applications with their status.
public enum AccountingDocumentGroup: String, Sendable { case company, tax, contracts, insurance, applications }

public struct AccountingDocument: Equatable, Sendable, Identifiable {
    public var id: String
    public var group: AccountingDocumentGroup
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
        case "fin": return "interest"
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
    /// counterparty and note. Newest first.
    func companyTransactions(companyID: Int, kind: TransactionFilterKind = .all, category: String? = nil, fromWeek: Int? = nil, toWeek: Int? = nil,
                             search: String = "") -> TransactionPage? {
        guard let co = state.company(companyID) else { return nil }
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

    func transactionDetail(companyID: Int, id: String) -> TransactionDetail? {
        guard let co = state.company(companyID),
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
    mutating func setTransactionNote(companyID: Int, id: String, note: String) -> Bool {
        guard let co = state.company(companyID), ledgerTransactions(co).contains(where: { $0.id == id }) else { return false }
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

    /// Send a draft customer invoice now instead of at the next weekly run.
    @discardableResult
    mutating func sendDraftInvoice(companyID: Int, number: String) -> Bool {
        var ok = false
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            var c = s.companies[i]
            ok = InvoiceBook.send(&c, number: number, week: s.week)
            if ok { s.companies[i] = c }
        }
        return ok
    }

    // MARK: Suppliers

    func supplierRecords(companyID: Int, search: String = "") -> [SupplierRecord]? {
        guard let co = state.company(companyID) else { return nil }
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

    func companyDocuments(companyID: Int, group: AccountingDocumentGroup? = nil) -> [AccountingDocument]? {
        guard let co = state.company(companyID), let country = data.countries[co.countryCode] else { return nil }
        var out: [AccountingDocument] = []
        func add(_ g: AccountingDocumentGroup, _ kind: String, _ id: String, _ title: String, _ detail: String, _ status: String, week: Int? = nil, amount: Double? = nil) {
            out.append(AccountingDocument(id: id, group: g, kind: kind, title: title, detail: detail, status: status, dateText: week.map { GameCalendar.dateString(week: $0) }, amount: amount))
        }
        let legal = co.value("legal")
        add(.company, "legalForm", "legal", country.companyForms["limited"] ?? "Limited company",
            co.name, "In force", week: legal["since"].isNull ? co.foundedWeek : legal["since"].int)
        let holders = co.value("holders").array.filter { $0["pct"].double > 0 }
        add(.company, "ownership", "own", "Ownership", "You hold \(Int(saturating: co.ownership.rounded()))%" + (holders.isEmpty ? "" : "; others: " + holders.map { "\($0["name"].string) \(Int(saturating: $0["pct"].double.rounded()))%" }.joined(separator: ", ")), "Current")
        if co.shareCapital > 0 { add(.company, "ownership", "capital", "Share capital", legal["shares"]["count"].isNull ? "" : "\(Int(legal["shares"]["count"].double)) shares", "Paid in", amount: co.shareCapital) }
        let acc = co.value("acc")
        if !acc["id"].isNull { add(.company, "registration", "accagr", "Accountant agreement", acc["name"].string, co.value("docs")["accountant_agreement"]["st"].string == "ok" ? "In force" : "Pending", week: acc["w0"].int) }
        let w = World(state: state, data: data)
        for (id, d) in co.value("docs").object.sorted(by: { $0.key < $1.key }) where id != "accountant_agreement" && !["chain", "fran", "trademark", "ops_manual"].contains(id) {
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
        // Corporate tax is paid each month, so only what the account could not cover is still open.
        if (co.payables["tax"] ?? 0) > 1 { add(.tax, "filing", "taxopen", "Corporate tax owed", "Unpaid: the account could not cover it", "Open", amount: co.payables["tax"] ?? 0) }
        if co.vatBalance > 1 { add(.tax, "filing", "vatopen", "VAT balance", "To be settled with the next return", "Open", amount: co.vatBalance) }
        // Contracts: employment, supplier, customer, financing, chain/franchise.
        for m in co.staff {
            let name = state.people[m.id]?.name ?? "Employee"
            let ft = m.raw["ft"].map { $0.isNull ? nil : $0.int } ?? nil
            add(.contracts, "employment", "emp\(m.id)", "Employment contract: \(name)", "\(m.role), \(Int(saturating: (m.weeklyHours ?? StaffModel.fullWeekHours).rounded())) h a week" + (ft.map { ", fixed term to \(GameCalendar.dateString(week: $0))" } ?? ""),
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
        // Receipts filed with this company: store orders, leases and insurance policies bought through the Phone apps.
        for r in Receipts.rows(co) {
            add(.contracts, "receipt", "rcpt-" + r.number, r.title, r.detail + " \u{00B7} " + r.number, "Paid", week: r.week, amount: r.amount)
        }
        if !co.value("chain").isNull { add(.contracts, "chain", "chain", "Chain membership", "Store of a chain", "Active") }
        if co.value("fr")["on"].bool { add(.contracts, "chain", "franchise", "Franchise", "Franchise agreements held by this company", "Active") }
        // Insurance: the policies the company holds now, from the coverage read model (the same data as Manage > Insurance and advisers).
        if let cover = coverageOverview(companyID: companyID) {
            let cur = currency(for: co)
            for p in cover.policies where p.isOn {
                let who: String = cover.insurer.map { $0.name + " \u{00B7} " } ?? ""
                let number: String = Advisers.policyRecord(co, product: p.id).map { " \u{00B7} " + $0.number } ?? ""
                add(.insurance, "insurance", "ins-" + p.id, p.name, who + cur.short(p.weeklyPremium) + " a week" + number, "In force", amount: p.weeklyPremium)
            }
        }
        // Applications: the company's own chain and franchise paperwork (waiting, approved), and your applications to join a franchise brand.
        for id in ["trademark", "ops_manual", "chain", "fran"] {
            let d = co.value("docs")[id]
            guard !d.isNull, let def = Documents.definition(id, country: country, tables: data.catalog.tables) else { continue }
            let st = d["st"].string
            let status: String = st == "ok" ? "Approved" : (st == "applied" ? "Under review" : (st.isEmpty ? "Not applied" : st.capitalized))
            var detail: String = def.issuer
            if st == "applied" { detail += " \u{00B7} decision due " + GameCalendar.dateString(week: d["done"].int) }
            add(.applications, "chain", "app-" + id, ["trademark": "Trademark registration", "ops_manual": "Operations manual", "chain": "Chain registration"][id] ?? "Franchise disclosure document", detail, status, week: d["w0"].isNull ? nil : d["w0"].int)
        }
        if let apps = state.rest["fbApps"]?.object, !apps.isEmpty {
            let world = World(state: state, data: data)
            for key in apps.keys.sorted() {
                guard let a = apps[key] else { continue }
                let name: String = FranchiseBrands.brand(key, world)?.name ?? "Franchise brand"
                let st = a["st"].string
                let status: String
                switch st {
                case "pending": status = "Under review"
                case "invited": status = "Invited to talk"
                case "agreed": status = "Terms signed"
                case "refused": status = "Declined"
                default: status = st.capitalized
                }
                let city: String = data.countries.city(a["city"].string, preferring: a["country"].string)?.city.name ?? a["city"].string
                var detail: String = "Your application to join as a franchisee" + (city.isEmpty ? "" : " \u{00B7} " + city)
                if st == "pending" { detail += " \u{00B7} answer due " + GameCalendar.dateString(week: a["due"].int) }
                if st == "invited" || st == "agreed" { detail += " \u{00B7} stands until " + GameCalendar.dateString(week: a["exp"].int) }
                add(.applications, "franchise", "fb-" + key, "Franchise: " + name, detail, status, week: a["w0"].isNull ? nil : a["w0"].int)
            }
        }
        return out.filter { group == nil || $0.group == group }
    }
}
