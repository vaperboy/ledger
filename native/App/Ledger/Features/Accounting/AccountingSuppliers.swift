import SwiftUI
import GameCore
import Countries
import Simulation

// Accounting > Suppliers: the canonical supplier records (who you have dealt with, the agreement and the terms, what you bought, what is open).
// This screen only reads and records. Choosing or switching a supplier decides what the company buys and from whom, so it stays in the company's
// purchasing (Manage), and nothing here ever buys anything.

struct AcctSuppliers: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            let fmt = BankFmt(store: store, company: co)
            let records: [SupplierRecord]? = e.supplierRecords(companyID: co.id, search: m.supplierSearch, user: m.user)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AcctSearchField(text: $m.supplierSearch, prompt: "Search suppliers", identifier: "acct-supplier-search")
                    if let records {
                        list(records, fmt)
                        addBlock(co)
                    } else {
                        AcctLocked(section: "Suppliers")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder private func list(_ records: [SupplierRecord], _ fmt: BankFmt) -> some View {
        if records.isEmpty {
            AcctNotice(glyph: Glyph.projects, title: m.supplierSearch.isEmpty ? "No supplier records yet" : "No supplier matches",
                       message: m.supplierSearch.isEmpty ? "A supplier appears here once you have bought from them or chosen them to supply goods or repairs." : "Try another name.")
        } else {
            AcctPanel {
                ForEach(Array(records.enumerated()), id: \.element.id) { n, s in
                    VStack(spacing: 0) {
                        if n > 0 { AcctDivider() }
                        row(s, fmt)
                    }
                }
            }
        }
    }

    private func row(_ s: SupplierRecord, _ fmt: BankFmt) -> some View {
        var sub: String = s.relationship
        if s.discount > 0.0001 { sub += " \u{00B7} " + Currency.percent(s.discount, decimals: 0) + " discount" }
        if s.isCurrentGoodsSupplier { sub += " \u{00B7} goods" }
        if s.isCurrentRepairSupplier { sub += " \u{00B7} repairs" }
        let value: String = s.openInvoices > 0.5 ? fmt.short(s.openInvoices) : ""
        let note: String = s.openInvoices > 0.5 ? "open invoices" : (s.purchasesTotal > 0.5 ? fmt.short(s.purchasesTotal) + " bought" : "")
        return AcctRow(initials: AcctRow.initials(s.name), title: s.name, subtitle: sub, value: value, valueTint: P.caution, valueNote: note, identifier: "acct-supplier-row") { m.push(.supplier(s.id)) }
    }

    private func addBlock(_ co: Company) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AcctNotice(glyph: Glyph.info, title: "Suppliers are added by buying or choosing them",
                       message: "Adding a supplier here would not be a record, it would change what \(co.name) buys. That decision stays in the company's purchasing, where its cost is shown first. Nothing on this screen buys anything.")
            AcctSecondaryButton(title: "Open purchasing", identifier: "acct-supplier-purchasing") { store.openCompany(co.id, section: .operations) }
        }
    }
}

struct AcctSupplierProfile: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel
    var supplierID: String

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            let fmt = BankFmt(store: store, company: co)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let all = e.supplierRecords(companyID: co.id, user: m.user) {
                        if let s = all.first(where: { $0.id == supplierID }) {
                            header(s)
                            terms(s, fmt)
                            invoices(e, co, s, fmt)
                            purchases(s, fmt)
                        } else {
                            AcctNotice(glyph: Glyph.info, title: "This supplier is no longer on record", message: "Go back to the list.")
                        }
                    } else {
                        AcctLocked(section: "Suppliers")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }
    }

    private func header(_ s: SupplierRecord) -> some View {
        AcctPanel(padding: 16) {
            HStack(spacing: 12) {
                Text(AcctRow.initials(s.name)).font(.system(size: 14, weight: .semibold)).foregroundStyle(P.onAccent)
                    .frame(width: 44, height: 44).background(Circle().fill(P.accent))
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).font(.system(size: 16, weight: .medium)).foregroundStyle(P.ink).lineLimit(2)
                    Text(s.owner.isEmpty ? s.relationship : s.owner + " \u{00B7} " + s.relationship).font(.system(size: 12.5)).foregroundStyle(P.inkFaint).lineLimit(2)
                }
                Spacer(minLength: 8)
            }
        }
    }

    private func terms(_ s: SupplierRecord, _ fmt: BankFmt) -> some View {
        let rating: String = String(format: "%.1f", s.rating)
        var roles: [String] = []
        if s.isCurrentGoodsSupplier { roles.append("Supplies your goods") }
        if s.isCurrentRepairSupplier { roles.append("Services your equipment") }
        let role: String = roles.isEmpty ? "No standing arrangement" : roles.joined(separator: ", ")
        let discount: String = s.discount > 0.0001 ? Currency.percent(s.discount, decimals: 1) : "None"
        return VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Agreement and terms")
            AcctPanel(padding: 14) {
                FlatRow(label: "Arrangement", value: role, rule: false)
                FlatRow(label: "Agreement", value: s.agreement ?? "No written agreement")
                FlatRow(label: "Discount", value: discount)
                FlatRow(label: "Rating", value: rating)
                FlatRow(label: "Bought in total", value: fmt.full(s.purchasesTotal))
                FlatRow(label: "Open invoices", value: fmt.full(s.openInvoices), tint: s.openInvoices > 0.5 ? P.caution : nil)
            }
        }
    }

    @ViewBuilder private func invoices(_ e: GameEngine, _ co: Company, _ s: SupplierRecord, _ fmt: BankFmt) -> some View {
        let mine: [InvoiceItem] = (e.invoices(companyID: co.id, kind: .supplier, user: m.user) ?? []).filter { $0.counterparty == s.name }
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AcctLabel(text: "Invoices")
                AcctPanel {
                    ForEach(Array(mine.prefix(6).enumerated()), id: \.element.id) { n, inv in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            AcctRow(title: "#" + inv.number, subtitle: "due " + inv.dueDateText, value: fmt.short(inv.gross), pill: inv.status.label, pillTone: inv.status.tone,
                                    identifier: "acct-supplier-invoice") { m.push(.invoice(inv.id)) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func purchases(_ s: SupplierRecord, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Purchases and deliveries")
            if s.recentPurchases.isEmpty {
                AcctNotice(glyph: Glyph.list, title: "No purchases booked yet", message: "Each delivery you pay for is booked in the ledger and listed here.")
            } else {
                AcctPanel {
                    ForEach(Array(s.recentPurchases.enumerated()), id: \.element.id) { n, t in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            AcctRow(glyph: BankGlyph.bill, title: t.label, subtitle: t.category, value: fmt.signed(t.amount), valueNote: t.dateText, identifier: "acct-supplier-purchase") { m.push(.transaction(t.id)) }
                        }
                    }
                }
            }
        }
    }
}
