import SwiftUI
import GameCore
import Countries
import Simulation

/// The Accounting & Compliance app (Master spec Stage 2B, mockup accounting_app.png). Accounting records and manages; the Bank holds the money and
/// executes payments. Every screen reads the engine's Accounting reads (`companyTransactions`, `invoices`, `payrollRunReview`, `supplierRecords`,
/// `companyDocuments`, `accountingRoster` ...), which answer nil when the viewer has no access to the section: that is the locked state.

/// Where the app is. `.home` is the root; every other page is pushed on `AcctModel.stack`.
enum AcctRoute: Equatable {
    case home, transactions, payroll, invoices, suppliers, documents, settings
    case transaction(String)
    case invoice(String)
    case supplier(String)
    case payrollRun(Int)
    case access(String)
    case addUser
}

enum AcctTxKind: String, CaseIterable, Hashable {
    case all = "All", income = "Income", expenses = "Expenses"
    var engineKind: TransactionFilterKind {
        switch self {
        case .all: return .all
        case .income: return .income
        case .expenses: return .expenses
        }
    }
}

enum AcctRange: String, CaseIterable, Hashable {
    case month = "This month", quarter = "Last 3 months", year = "Last 12 months", all = "All time"
}

enum AcctPayrollTab: String, CaseIterable, Hashable { case overview = "Overview", employees = "Employees", timesheets = "Timesheets", run = "Run payroll" }
enum AcctInvoiceTab: String, CaseIterable, Hashable { case invoices = "Invoices", payments = "Payments" }
enum AcctInvoiceFilter: String, CaseIterable, Hashable { case all = "All", draft = "Draft", sent = "Sent", paid = "Paid", overdue = "Overdue" }
enum AcctDocTab: String, CaseIterable, Hashable {
    case company = "Company", tax = "Tax", contracts = "Contracts", insurance = "Insurance", applications = "Applications"
    var group: AccountingDocumentGroup {
        switch self {
        case .company: return .company
        case .tax: return .tax
        case .contracts: return .contracts
        case .insurance: return .insurance
        case .applications: return .applications
        }
    }
}

/// What the Accounting app remembers while it is open: the business chosen, the page stack, and the filters of each page (so coming back from a
/// detail keeps the list as it was). `user` is who is looking: nil is the owner; the owner can preview another named user to see exactly what they see.
@MainActor
final class AcctModel: ObservableObject {
    @Published var companyID: Int = 0
    @Published var stack: [AcctRoute] = []
    @Published var user: String? = nil
    @Published var userName: String = ""

    @Published var txKind: AcctTxKind = .all
    @Published var txRange: AcctRange = .month
    @Published var txSearch: String = ""
    @Published var txLimit: Int = 40

    @Published var payTab: AcctPayrollTab = .overview
    @Published var invTab: AcctInvoiceTab = .invoices
    @Published var invFilter: AcctInvoiceFilter = .all
    @Published var docTab: AcctDocTab = .company
    @Published var supplierSearch: String = ""

    var route: AcctRoute { stack.last ?? .home }
    func push(_ r: AcctRoute) { stack.append(r) }
    func pop() { if !stack.isEmpty { stack.removeLast() } }
    func goHome() { stack = [] }

    /// The first game week of a date range (nil = no limit).
    func fromWeek(_ engine: GameEngine) -> Int? {
        let week: Int = engine.state.week
        switch txRange {
        case .month:
            var w: Int = week
            let current: Int = GameCalendar.monthIndex(week: week)
            while w > 0 && GameCalendar.monthIndex(week: w - 1) == current { w -= 1 }
            return w
        case .quarter: return max(0, week - 13)
        case .year: return max(0, week - 52)
        case .all: return nil
        }
    }
}

struct AccountingApp: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarClearance) private var clearance
    @StateObject private var m = AcctModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ReturnLine(tab: .phone)
                AcctHeader(title: titles.0, subtitle: titles.1, backLabel: m.stack.isEmpty ? "Back to Phone" : "Back", onBack: { back() })
            }
            .background(FinanceColor.forest.ignoresSafeArea(edges: .top))
            if m.user != nil { previewBanner }
            screen.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.outsidePalette, OutsidePalette.accounting)
        .environment(\.colorScheme, .light)
        .environment(\.tabBarClearance, 0)
        .foregroundStyle(OutsidePalette.accounting.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: clearance) }
        .background(OutsidePalette.accounting.ground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
            .swipeBackEnabled(canStep: { !m.stack.isEmpty }, step: { back() })
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { setUp() }
        .onChange(of: store.appRequest) { _, _ in take() }
    }

    // MARK: Pages

    @ViewBuilder private var screen: some View {
        switch m.route {
        case .home: AcctHome(m: m)
        case .transactions: AcctTransactions(m: m)
        case .transaction(let id): AcctTransactionDetail(m: m, transactionID: id)
        case .payroll: AcctPayroll(m: m)
        case .payrollRun(let id): AcctPayrollRunDetail(m: m, runID: id)
        case .invoices: AcctInvoices(m: m)
        case .invoice(let id): AcctInvoiceDetail(m: m, invoiceID: id)
        case .suppliers: AcctSuppliers(m: m)
        case .supplier(let id): AcctSupplierProfile(m: m, supplierID: id)
        case .documents: AcctDocuments(m: m)
        case .settings: AcctSettings(m: m)
        case .access(let id): AcctAccessDetail(m: m, userID: id)
        case .addUser: AcctAddUser(m: m)
        }
    }

    private var companyName: String {
        store.engine?.state.company(m.companyID)?.name ?? "Accounting"
    }

    private var titles: (String, String) {
        switch m.route {
        case .home: return ("Accounting", "All your financial and administrative tools")
        case .transactions: return ("Transactions", companyName)
        case .transaction: return ("Transaction", companyName)
        case .payroll: return ("Payroll", companyName)
        case .payrollRun: return ("Payroll run", companyName)
        case .invoices: return ("Invoices & Payments", companyName)
        case .invoice: return ("Invoice", companyName)
        case .suppliers: return ("Suppliers", companyName)
        case .supplier: return ("Supplier", companyName)
        case .documents: return ("Documents", companyName)
        case .settings: return ("Settings", "Access and company records")
        case .access: return ("Access", companyName)
        case .addUser: return ("Add user", companyName)
        }
    }

    private func back() {
        if m.stack.isEmpty { dismiss() } else { Motion.animate(Motion.quickAnimation) { m.pop() } }
    }

    private var previewBanner: some View {
        let who: String = m.userName.isEmpty ? "another user" : m.userName
        return HStack(spacing: 10) {
            GlyphView(glyph: Glyph.lock, size: 16, weight: 1.6, tint: OutsidePalette.accounting.caution)
            Text("Viewing as \(who). You see what they can see.").font(.system(size: 12.5)).foregroundStyle(OutsidePalette.accounting.ink)
            Spacer(minLength: 4)
            Button {
                Haptics.tap()
                m.user = nil
                m.userName = ""
            } label: {
                Text("Stop").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(OutsidePalette.accounting.accent).padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("acct-stop-preview")
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(OutsidePalette.accounting.caution.opacity(0.14))
    }

    // MARK: Start-up and links

    private func setUp() {
        guard let e = store.engine else { return }
        let live: [Company] = e.state.liveCompanies
        if m.companyID == 0 || e.state.company(m.companyID) == nil { m.companyID = live.first?.id ?? 0 }
        take()
    }

    /// A link from elsewhere (Team's payroll line, the Bank's payroll note, the Phone banner) names the company and page.
    private func take() {
        guard let r = store.takeAccountingRequest() else { return }
        if store.engine?.state.company(r.companyID) != nil { m.companyID = r.companyID }
        m.user = nil
        m.userName = ""
        m.stack = r.payroll ? [.payroll] : []
        if r.payroll { m.payTab = .overview }
    }
}

// MARK: Home

/// Home: the business selector and the six sections (Transactions, Payroll, Invoices & Payments, Suppliers, Documents, Settings).
struct AcctHome: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine {
            let companies: [Company] = e.state.liveCompanies
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if companies.isEmpty {
                        AcctNotice(glyph: Glyph.accounting, title: "No company yet",
                                   message: "Accounting keeps the books of your companies. Start a company and its transactions, payroll, invoices and records appear here.")
                    } else {
                        selector(companies)
                        sections(e)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }
    }

    private func selector(_ companies: [Company]) -> some View {
        let current: String = companies.first { $0.id == m.companyID }?.name ?? "Choose a business"
        return VStack(alignment: .leading, spacing: 6) {
            AcctLabel(text: "Select business")
            Menu {
                ForEach(companies) { (co: Company) in
                    Button {
                        m.companyID = co.id
                        Haptics.choose()
                    } label: {
                        if co.id == m.companyID { Label(co.name, systemImage: "checkmark") } else { Text(co.name) }
                    }
                }
            } label: {
                HStack {
                    Text(current).font(.system(size: 15, weight: .medium)).foregroundStyle(P.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(P.inkFaint)
                }
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("acct-company-picker")
        }
    }

    private func sections(_ e: GameEngine) -> some View {
        let id: Int = m.companyID
        let u: String? = m.user
        let tag: (String, AcctPill.Tone)? = payrollTag(e, id)
        let overdue: Int = e.invoices(companyID: id, kind: nil, status: .overdue, user: u)?.count ?? 0
        let drafts: Int = e.invoices(companyID: id, kind: .customer, status: .draft, user: u)?.count ?? 0
        var invoiceNote: String = "Send, receive and track invoices"
        if overdue > 0 { invoiceNote = "\(overdue) overdue" } else if drafts > 0 { invoiceNote = "\(drafts) draft\(drafts == 1 ? "" : "s") to send" }
        let payrollNeedsYou: Bool = PhoneAlerts.payroll(engine: e).contains { (p: PayrollAlertInfo) -> Bool in p.companyID == id }
        let items: [HomeItem] = [
            HomeItem(key: "transactions", glyph: BankGlyph.bill, title: "Transactions", note: "View and match all transactions", route: .transactions),
            HomeItem(key: "payroll", glyph: Glyph.people, title: "Payroll", note: "Manage salaries and timesheets", route: .payroll, pill: tag?.0, tone: tag?.1 ?? .neutral, flag: payrollNeedsYou),
            HomeItem(key: "invoices", glyph: Glyph.reports, title: "Invoices & Payments", note: invoiceNote, route: .invoices, flag: overdue > 0),
            HomeItem(key: "suppliers", glyph: Glyph.projects, title: "Suppliers", note: "Supplier agreements and purchases", route: .suppliers),
            HomeItem(key: "documents", glyph: Glyph.list, title: "Documents", note: "Records, tax, contracts, insurance, applications", route: .documents),
            HomeItem(key: "settings", glyph: Glyph.settings, title: "Settings", note: "Access and user management", route: .settings),
        ]
        return AcctPanel {
            ForEach(Array(items.enumerated()), id: \.element.key) { n, item in
                VStack(spacing: 0) {
                    if n > 0 { AcctDivider() }
                    AcctRow(glyph: item.glyph, title: item.title, subtitle: item.note, pill: item.pill, pillTone: item.tone, identifier: "acct-row-" + item.key) { m.push(item.route) }
                        .flagMarker(item.flag, important: true, alignment: .topLeading)
                }
            }
        }
    }

    private struct HomeItem {
        var key: String
        var glyph: String
        var title: String
        var note: String
        var route: AcctRoute
        var pill: String? = nil
        var tone: AcctPill.Tone = .neutral
        var flag: Bool = false
    }

    private func payrollTag(_ e: GameEngine, _ id: Int) -> (String, AcctPill.Tone)? {
        guard e.canAccess(.payroll, companyID: id, user: m.user), let o = e.payrollOverview(companyID: id), o.hasPayroll else { return nil }
        if o.isLate { return ("Late", .bad) }
        if o.needsApproval { return ("Needs you", .warn) }
        if o.isApproved { return ("Approved", .good) }
        return ("On schedule", .neutral)
    }
}
