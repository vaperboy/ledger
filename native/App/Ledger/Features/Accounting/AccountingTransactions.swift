import SwiftUI
import GameCore
import Countries
import Simulation

// Accounting > Transactions: the company's ledger (income and expenses) with a date range and search, a detail with a note where the access level
// allows it, and links to the record a movement belongs to (a loan, a supplier, a payroll run). All data from `companyTransactions` and
// `transactionDetail`; the ledger itself is the Bank's payment engine's record, nothing here moves money.

enum AcctGlyphs {
    /// The icon of a ledger category.
    static func category(_ id: String) -> String {
        switch id {
        case "sales": return Glyph.arrowIn
        case "purchases": return BankGlyph.bill
        case "payroll": return Glyph.people
        case "rent": return Glyph.home
        case "marketing": return Glyph.market
        case "insurance": return Glyph.lock
        case "running": return Glyph.settings
        case "interest", "loans": return BankGlyph.transfer
        case "tax": return Glyph.reports
        case "accounting": return Glyph.accounting
        case "fines": return Glyph.warning
        case "equipment": return Glyph.projects
        case "owner": return Glyph.person
        default: return Glyph.list
        }
    }
}

struct AcctTransactions: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            let fmt = BankFmt(store: store, company: co)
            let kind: TransactionFilterKind = m.txKind.engineKind
            let from: Int? = m.fromWeek(e)
            let search: String = m.txSearch
            let user: String? = m.user
            // The ledger walk runs once per engine change and filter, not on every render of the live Phone tab.
            let userKey: String = user.map { (u: String) -> String in "u" + u } ?? "-"
            let key: String = "tx|\(co.id)|\(kind)|\(from ?? -1)|\(search)|" + userKey
            let page: TransactionPage? = (store.memo(key) { (g: GameEngine) -> [TransactionPage] in
                g.companyTransactions(companyID: co.id, kind: kind, fromWeek: from, search: search, user: user).map { [$0] } ?? []
            } ?? []).first
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SegmentedPill(items: AcctTxKind.allCases, title: { $0.rawValue }, selection: $m.txKind, identifier: { "acct-tx-" + $0.rawValue.lowercased() })
                    HStack(spacing: 8) {
                        AcctSearchField(text: $m.txSearch, prompt: "Search transactions", identifier: "acct-tx-search")
                        rangeMenu
                    }
                    if let page {
                        totals(page, fmt)
                        list(page, fmt)
                    } else {
                        AcctLocked(section: "Transactions")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var rangeMenu: some View {
        Menu {
            ForEach(AcctRange.allCases, id: \.self) { (r: AcctRange) in
                Button {
                    m.txRange = r
                    m.txLimit = 40
                    Haptics.choose()
                } label: {
                    if r == m.txRange { Label(r.rawValue, systemImage: "checkmark") } else { Text(r.rawValue) }
                }
            }
        } label: {
            GlyphView(glyph: Glyph.calendar, size: 20, weight: 1.6, tint: P.accent)
                .frame(width: 46, height: 44)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(P.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Date range: " + m.txRange.rawValue)
        .accessibilityIdentifier("acct-tx-range")
    }

    private func totals(_ page: TransactionPage, _ fmt: BankFmt) -> some View {
        let net: Double = page.income - page.expenses
        return HStack(alignment: .firstTextBaseline) {
            Text(m.txRange.rawValue).textStyle(.caption, tint: P.inkFaint)
            Spacer(minLength: 8)
            Text("In " + fmt.short(page.income)).textStyle(.caption, tint: P.gain, numeric: true)
            Text("Out " + fmt.short(page.expenses)).textStyle(.caption, tint: P.loss, numeric: true)
            HStack(spacing: Theme.Space.xs) {
                Text("Net").textStyle(.caption, tint: P.inkFaint)
                ArrowAmount(gain: net, format: { (v: Double) -> String in fmt.short(v) }, step: .caption, weight: .medium)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func list(_ page: TransactionPage, _ fmt: BankFmt) -> some View {
        let shown: [LedgerTransaction] = Array(page.entries.prefix(m.txLimit))
        if page.entries.isEmpty {
            AcctNotice(glyph: Glyph.list, title: "No transactions here",
                       message: m.txSearch.isEmpty ? "Nothing was booked in this period. Try a longer date range." : "Nothing matches \u{201C}\(m.txSearch)\u{201D}.")
        } else {
            AcctPanel {
                ForEach(Array(shown.enumerated()), id: \.element.id) { n, t in
                    VStack(spacing: 0) {
                        if n > 0 { AcctDivider() }
                        row(t, fmt)
                    }
                    .transition(.opacity)
                }
                if page.entries.count > shown.count {
                    AcctDivider()
                    Button {
                        m.txLimit += 40
                        Haptics.tap()
                    } label: {
                        Text("Show more (\(page.entries.count - shown.count) left)").textStyle(.body, tint: P.accent, weight: .medium)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(AcctPressStyle())
                    .accessibilityIdentifier("acct-tx-more")
                }
            }
            .animation(Motion.quickAnimation, value: shown.map { $0.id })
        }
    }

    private func row(_ t: LedgerTransaction, _ fmt: BankFmt) -> some View {
        var sub: String = t.category
        if !t.counterparty.isEmpty { sub += " \u{00B7} " + t.counterparty }
        if t.count > 1 { sub += " \u{00B7} \(t.count) items" }
        return AcctRow(glyph: AcctGlyphs.category(t.categoryID), title: t.label, subtitle: sub, valueNote: t.dateText,
                       gain: t.amount, gainFormat: { (v: Double) -> String in fmt.short(v) },
                       identifier: "acct-tx-row") { m.push(.transaction(t.id)) }
    }
}

struct AcctTransactionDetail: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel
    var transactionID: String
    @State private var note: String = ""
    @State private var noted: Bool = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            let fmt = BankFmt(store: store, company: co)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !e.canAccess(.transactions, companyID: co.id, user: m.user) {
                        AcctLocked(section: "Transactions")
                    } else if let d = e.transactionDetail(companyID: co.id, id: transactionID, user: m.user) {
                        header(d, fmt)
                        fields(d)
                        noteBlock(e, co, d)
                        linkBlock(e, d)
                    } else {
                        AcctNotice(glyph: Glyph.info, title: "This transaction is no longer in the ledger",
                                   message: "Older rows are folded together as the ledger grows. Go back to the list.")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func header(_ d: TransactionDetail, _ fmt: BankFmt) -> some View {
        let t: LedgerTransaction = d.transaction
        return AcctPanel(padding: 16) {
            HStack(spacing: 12) {
                IconCircle(glyph: AcctGlyphs.category(t.categoryID), size: 44, tint: P.accent2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.label.tidyText).textStyle(.headline).lineLimit(2)
                    Text(t.category + " \u{00B7} " + t.dateText).textStyle(.caption, tint: P.inkFaint)
                }
                Spacer(minLength: 8)
                ArrowAmount(gain: t.amount, format: { (v: Double) -> String in fmt.short(v) }, step: .figure).minimumScaleFactor(0.6).lineLimit(1)
            }
        }
    }

    private func fields(_ d: TransactionDetail) -> some View {
        AcctPanel(padding: 14) {
            ForEach(Array(d.fields.enumerated()), id: \.offset) { n, f in
                FlatRow(label: f.0, value: f.1, rule: n > 0)
            }
            FlatRow(label: "Account", value: d.account)
        }
    }

    @ViewBuilder private func noteBlock(_ e: GameEngine, _ co: Company, _ d: TransactionDetail) -> some View {
        let canNote: Bool = e.canAccess(.notes, companyID: co.id, user: m.user)
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Note")
            if canNote {
                TextField("Add a note for the books", text: $note, axis: .vertical)
                    .lineLimit(1...4)
                    .textStyle(.body)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(P.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(P.line, lineWidth: 1))
                    .accessibilityIdentifier("acct-tx-note")
                AcctSecondaryButton(title: "Save note", identifier: "acct-tx-save-note") { save(co.id) }
            } else if let existing = d.transaction.note, !existing.isEmpty {
                AcctNotice(glyph: Glyph.list, title: existing, message: "Notes are added by people with full bookkeeping access.")
            } else {
                AcctNotice(glyph: Glyph.lock, title: "Notes need full bookkeeping access", message: "This access level can read the ledger but not annotate it.")
            }
        }
        .onAppear {
            if !noted { note = d.transaction.note ?? ""; noted = true }
        }
    }

    private func save(_ companyID: Int) {
        let text: String = note
        let id: String = transactionID
        let user: String? = m.user
        let ok: Bool = store.act({ (e: inout GameEngine) -> Bool in e.setTransactionNote(companyID: companyID, id: id, note: text, user: user) }) ?? false
        if ok {
            Haptics.success()
            store.show(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Note removed." : "Note saved.", tone: "good")
        } else {
            Haptics.warning()
            store.show("The note could not be saved. You need full bookkeeping access.", tone: "warn")
        }
    }

    @ViewBuilder private func linkBlock(_ e: GameEngine, _ d: TransactionDetail) -> some View {
        if let l = d.transaction.link {
            VStack(alignment: .leading, spacing: 8) {
                AcctLabel(text: "Linked record")
                AcctPanel {
                    switch l.kind {
                    case "loan":
                        AcctRow(glyph: BankGlyph.transfer, title: l.title, subtitle: "Loan", identifier: "acct-tx-link")
                    case "supplier":
                        AcctRow(glyph: Glyph.projects, title: l.title, subtitle: "Supplier record", identifier: "acct-tx-link") { m.push(.supplier(l.id)) }
                    case "payroll":
                        if let run = e.payrollRuns(companyID: m.companyID, user: m.user)?.first(where: { String($0.periodIndex) == l.id }) {
                            AcctRow(glyph: Glyph.people, title: "Payroll run: " + run.periodText, subtitle: "Payslips and breakdown", identifier: "acct-tx-link") { m.push(.payrollRun(run.id)) }
                        } else {
                            AcctRow(glyph: Glyph.people, title: l.title, subtitle: "Payroll", identifier: "acct-tx-link") { m.push(.payroll) }
                        }
                    default:
                        AcctRow(glyph: Glyph.list, title: l.title, subtitle: "Linked record", identifier: "acct-tx-link")
                    }
                }
            }
        }
    }
}
