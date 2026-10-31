import SwiftUI
import GameCore
import Countries
import Simulation

// Accounting > Documents: Company, Tax and Contracts. Every row is a real record the game keeps (registration and legal form, ownership, licences,
// tax settlements and open balances, employment, supplier, customer and financing contracts, chain and franchise membership), from `companyDocuments`.

struct AcctDocuments: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            let fmt = BankFmt(store: store, company: co)
            let docs: [AccountingDocument]? = e.companyDocuments(companyID: co.id, group: m.docTab.group, user: m.user)
            VStack(spacing: 0) {
                SectionTabs(items: AcctDocTab.allCases, title: { $0.rawValue }, selection: $m.docTab)
                    .padding(.top, 4)
                    .accessibilityIdentifier("acct-document-tabs")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let docs {
                            list(docs, co, fmt)
                        } else {
                            AcctLocked(section: "Documents")
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 40)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    @ViewBuilder private func list(_ docs: [AccountingDocument], _ co: Company, _ fmt: BankFmt) -> some View {
        if docs.isEmpty {
            AcctNotice(glyph: Glyph.list, title: "No \(m.docTab.rawValue.lowercased()) documents yet", message: emptyReason)
        } else {
            AcctPanel {
                ForEach(Array(docs.enumerated()), id: \.element.id) { n, d in
                    VStack(spacing: 0) {
                        if n > 0 { AcctDivider() }
                        row(d, co, fmt)
                    }
                }
            }
        }
    }

    private var emptyReason: String {
        switch m.docTab {
        case .company: return "Registration, legal form, ownership and licences appear as the company holds them."
        case .tax: return "Tax and VAT records appear once the company has settled or accrued any."
        case .contracts: return "Employment, supplier, customer and financing contracts appear as they are signed."
        }
    }

    private func tone(_ status: String) -> AcctPill.Tone {
        switch status {
        case "Held", "In force", "Paid", "Paid in", "Done", "Active", "Current": return .good
        case "Open", "Pending", "Balance outstanding": return .warn
        case "Not held": return .bad
        default: return .neutral
        }
    }

    private func glyph(_ d: AccountingDocument) -> String {
        switch d.kind {
        case "registration", "legalForm": return Glyph.accounting
        case "ownership": return Glyph.group
        case "licence": return Glyph.check
        case "filing": return Glyph.reports
        case "employment": return Glyph.people
        case "supplier": return Glyph.projects
        case "customer": return Glyph.person
        case "financing": return BankGlyph.transfer
        case "chain": return Glyph.group
        default: return Glyph.list
        }
    }

    private func row(_ d: AccountingDocument, _ co: Company, _ fmt: BankFmt) -> some View {
        var sub: String = d.detail
        if let date = d.dateText { sub = sub.isEmpty ? date : sub + " \u{00B7} " + date }
        let value: String = d.amount.map { fmt.short($0) } ?? ""
        let identifier: String = "acct-document-row"
        if d.kind == "financing" {
            return AnyView(AcctRow(glyph: glyph(d), title: d.title, subtitle: sub, value: value, pill: d.status, pillTone: tone(d.status), identifier: identifier) {
                store.openBank(.company(co.id), tab: .loans)
            })
        }
        return AnyView(AcctRow(glyph: glyph(d), title: d.title, subtitle: sub, value: value, pill: d.status, pillTone: tone(d.status), identifier: identifier))
    }
}
