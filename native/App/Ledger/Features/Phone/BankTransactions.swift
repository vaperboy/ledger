import SwiftUI
import GameCore
import Countries
import Simulation

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
