import SwiftUI
import GameCore
import Countries
import Simulation

enum BankTxKind: String, CaseIterable, Hashable {
    case all = "All", income = "Income", expenses = "Expenses"
    var engineKind: TransactionFilterKind {
        switch self {
        case .all: return .all
        case .income: return .income
        case .expenses: return .expenses
        }
    }
}

enum BankTxRange: String, CaseIterable, Hashable {
    case month = "This month", quarter = "Last 3 months", year = "Last 12 months", all = "All time"

    func fromWeek(_ engine: GameEngine) -> Int? {
        let week: Int = engine.state.week
        switch self {
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

enum BankTxGlyphs {
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

struct BankTransactionsCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    @State private var kind: BankTxKind = .all
    @State private var range: BankTxRange = .month
    @State private var search: String = ""
    @State private var limit: Int = 40

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let fmt = BankFmt(store: store, company: co)
            let engineKind: TransactionFilterKind = kind.engineKind
            let from: Int? = range.fromWeek(e)
            let query: String = search
            let key: String = "tx|\(co.id)|\(engineKind)|\(from ?? -1)|\(query)"
            let page: TransactionPage? = (store.memo(key) { (g: GameEngine) -> [TransactionPage] in
                g.companyTransactions(companyID: co.id, kind: engineKind, fromWeek: from, search: query).map { [$0] } ?? []
            } ?? []).first
            VStack(alignment: .leading, spacing: 12) {
                Text("Transactions").capsLabel().padding(.horizontal, 2)
                SegmentedPill(items: BankTxKind.allCases, title: { $0.rawValue }, selection: $kind, identifier: { "bank-tx-" + $0.rawValue.lowercased() })
                HStack(spacing: 8) {
                    AcctSearchField(text: $search, prompt: "Search transactions", identifier: "bank-tx-search")
                    rangeMenu
                }
                if let page {
                    totals(page, fmt)
                    list(page, fmt)
                }
            }
            .onChange(of: kind) { _, _ in limit = 40 }
            .onChange(of: search) { _, _ in limit = 40 }
        }
    }

    private var rangeMenu: some View {
        Menu {
            ForEach(BankTxRange.allCases, id: \.self) { (r: BankTxRange) in
                Button {
                    range = r
                    limit = 40
                    Haptics.choose()
                } label: {
                    if r == range { Label(r.rawValue, systemImage: "checkmark") } else { Text(r.rawValue) }
                }
            }
        } label: {
            GlyphView(glyph: Glyph.calendar, size: 20, weight: 1.6, tint: P.accent)
                .frame(width: 46, height: 44)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(P.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Date range: " + range.rawValue)
        .accessibilityIdentifier("bank-tx-range")
    }

    private func totals(_ page: TransactionPage, _ fmt: BankFmt) -> some View {
        let net: Double = page.income - page.expenses
        return HStack(alignment: .firstTextBaseline) {
            Text(range.rawValue).textStyle(.caption, tint: P.inkFaint)
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
        let shown: [LedgerTransaction] = Array(page.entries.prefix(limit))
        if page.entries.isEmpty {
            AcctNotice(glyph: Glyph.list, title: "No transactions here",
                       message: search.isEmpty ? "Nothing was booked in this period. Try a longer date range." : "Nothing matches \u{201C}\(search)\u{201D}.")
        } else {
            AcctPanel {
                ForEach(Array(shown.enumerated()), id: \.element.id) { n, t in
                    VStack(spacing: 0) {
                        if n > 0 { AcctDivider() }
                        row(t, fmt)
                    }
                }
                if page.entries.count > shown.count {
                    AcctDivider()
                    Button {
                        limit += 40
                        Haptics.tap()
                    } label: {
                        Text("Show more (\(page.entries.count - shown.count) left)").textStyle(.body, tint: P.accent, weight: .medium)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(AcctPressStyle())
                    .accessibilityIdentifier("bank-tx-more")
                }
            }
        }
    }

    private func row(_ t: LedgerTransaction, _ fmt: BankFmt) -> some View {
        var sub: String = t.category
        if !t.counterparty.isEmpty { sub += " \u{00B7} " + t.counterparty }
        if t.count > 1 { sub += " \u{00B7} \(t.count) items" }
        return NavigationLink {
            BankTransactionDetailScreen(companyID: companyID, transactionID: t.id).environment(\.outsidePalette, P)
        } label: {
            AcctRow(glyph: BankTxGlyphs.category(t.categoryID), title: t.label, subtitle: sub, valueNote: t.dateText,
                    gain: t.amount, gainFormat: { (v: Double) -> String in fmt.short(v) }, identifier: "bank-tx-row")
        }
        .buttonStyle(AcctPressStyle())
    }
}

struct BankTransactionDetailScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var transactionID: String
    @State private var note: String = ""
    @State private var noted: Bool = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let fmt = BankFmt(store: store, company: co)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let d = e.transactionDetail(companyID: co.id, id: transactionID) {
                        header(d, fmt)
                        fields(d)
                        noteBlock(d)
                        linkBlock(d)
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
            .appScreen(title: "Transaction", subtitle: co.name)
        }
    }

    private func header(_ d: TransactionDetail, _ fmt: BankFmt) -> some View {
        let t: LedgerTransaction = d.transaction
        return AcctPanel(padding: 16) {
            HStack(spacing: 12) {
                IconCircle(glyph: BankTxGlyphs.category(t.categoryID), size: 44, tint: P.accent2)
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

    private func noteBlock(_ d: TransactionDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Note")
            TextField("Add a note for the books", text: $note, axis: .vertical)
                .lineLimit(1...4)
                .textStyle(.body)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(P.line, lineWidth: 1))
                .accessibilityIdentifier("bank-tx-note")
            AcctSecondaryButton(title: "Save note", identifier: "bank-tx-save-note") { save() }
        }
        .onAppear {
            if !noted { note = d.transaction.note ?? ""; noted = true }
        }
    }

    private func save() {
        let text: String = note
        let id: String = transactionID
        let company: Int = companyID
        let ok: Bool = store.act({ (e: inout GameEngine) -> Bool in e.setTransactionNote(companyID: company, id: id, note: text) }) ?? false
        if ok {
            Haptics.success()
            store.show(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Note removed." : "Note saved.", tone: "good")
        } else {
            Haptics.warning()
            store.show("The note could not be saved.", tone: "warn")
        }
    }

    @ViewBuilder private func linkBlock(_ d: TransactionDetail) -> some View {
        if let l = d.transaction.link {
            let subtitle: String = l.kind == "loan" ? "Loan" : (l.kind == "supplier" ? "Supplier record, under the company's Stats" : (l.kind == "payroll" ? "Payroll" : "Linked record"))
            VStack(alignment: .leading, spacing: 8) {
                AcctLabel(text: "Linked record")
                AcctPanel {
                    AcctRow(glyph: l.kind == "loan" ? BankGlyph.transfer : (l.kind == "supplier" ? Glyph.projects : (l.kind == "payroll" ? Glyph.people : Glyph.list)),
                            title: l.title, subtitle: subtitle, identifier: "bank-tx-link")
                }
            }
        }
    }
}
