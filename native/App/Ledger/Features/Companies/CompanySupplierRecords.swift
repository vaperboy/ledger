import SwiftUI
import GameCore
import Countries
import Simulation

struct CompanySupplierRecords: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var search: String = ""
    @State private var showAll: Bool = false

    private static let collapsed: Int = 5

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let records: [SupplierRecord] = e.supplierRecords(companyID: co.id, search: search) ?? []
            let all: [SupplierRecord] = search.isEmpty ? (e.supplierRecords(companyID: co.id) ?? []) : records
            if !all.isEmpty || !search.isEmpty {
                let shown: [SupplierRecord] = showAll || !search.isEmpty ? records : Array(records.prefix(Self.collapsed))
                CardSection("Supplier records") {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        if all.count > Self.collapsed || !search.isEmpty {
                            AcctSearchField(text: $search, prompt: "Search suppliers", identifier: "supplier-record-search")
                        }
                        if shown.isEmpty {
                            Text("No supplier matches.").textStyle(.caption, tint: Theme.inkFaint)
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { n, s in
                            if n > 0 { Hairline() }
                            NavigationLink {
                                CompanySupplierRecordPage(companyID: co.id, supplierID: s.id)
                            } label: {
                                row(s, BankFmt(store: store, company: co))
                            }
                            .buttonStyle(AcctPressStyle())
                        }
                        if search.isEmpty && records.count > Self.collapsed {
                            Button(showAll ? "Show fewer" : "Show all \(records.count)") { showAll.toggle(); Haptics.tap() }
                                .buttonStyle(QuietButtonStyle())
                        }
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
        let note: String = s.openInvoices > 0.5 ? "open bills" : (s.purchasesTotal > 0.5 ? fmt.short(s.purchasesTotal) + " bought" : "")
        return SupplierRow(name: s.name, detail: sub, value: value, valueTint: Theme.caution, valueNote: note,
                           current: s.isCurrentGoodsSupplier || s.isCurrentRepairSupplier, identifier: "supplier-record-row", action: nil)
    }
}

struct CompanySupplierRecordPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var supplierID: String

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let fmt = BankFmt(store: store, company: co)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let s = (e.supplierRecords(companyID: co.id) ?? []).first(where: { $0.id == supplierID }) {
                        header(s)
                        terms(s, fmt)
                        purchases(s, co, fmt)
                    } else {
                        AcctNotice(glyph: Glyph.info, title: "This supplier is no longer on record", message: "Go back to the list.")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .appScreen(title: "Supplier", subtitle: co.name)
        }
    }

    private func header(_ s: SupplierRecord) -> some View {
        AcctPanel(padding: 16) {
            HStack(spacing: 12) {
                Text(AcctRow.initials(s.name)).textStyle(.body, tint: P.onAccent, weight: .semibold)
                    .frame(width: 44, height: 44).background(Circle().fill(P.accent))
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).textStyle(.headline).lineLimit(2)
                    Text(s.owner.isEmpty ? s.relationship : s.owner + " \u{00B7} " + s.relationship).textStyle(.caption, tint: P.inkFaint).lineLimit(2)
                }
                Spacer(minLength: 8)
            }
        }
    }

    private func terms(_ s: SupplierRecord, _ fmt: BankFmt) -> some View {
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
                FlatRow(label: "Rating", value: String(format: "%.1f", s.rating))
                FlatRow(label: "Bought in total", value: fmt.full(s.purchasesTotal))
                FlatRow(label: "Open bills", value: fmt.full(s.openInvoices), tint: s.openInvoices > 0.5 ? P.caution : nil)
            }
        }
    }

    @ViewBuilder private func purchases(_ s: SupplierRecord, _ co: Company, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Purchases and deliveries")
            if s.recentPurchases.isEmpty {
                AcctNotice(glyph: Glyph.list, title: "No purchases booked yet", message: "Each delivery you pay for is booked in the ledger and listed here.")
            } else {
                AcctPanel {
                    ForEach(Array(s.recentPurchases.enumerated()), id: \.element.id) { n, t in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            NavigationLink {
                                BankTransactionDetailScreen(companyID: co.id, transactionID: t.id).environment(\.outsidePalette, P)
                            } label: {
                                AcctRow(glyph: BankGlyph.bill, title: t.label, subtitle: t.category, value: fmt.signed(t.amount), valueNote: t.dateText, identifier: "supplier-record-purchase")
                            }
                            .buttonStyle(AcctPressStyle())
                        }
                    }
                }
            }
        }
    }
}

struct SupplierRow: View {
    var name: String
    var detail: String
    var value: String = ""
    var valueTint: Color? = nil
    var valueNote: String = ""
    var badge: String? = nil
    var badgeTone: AcctPill.Tone = .neutral
    var current: Bool = false
    var warning: Bool = false
    var identifier: String = ""
    var action: (() -> Void)? = nil
    @Environment(\.outsidePalette) private var P

    var body: some View {
        LedgerRow(leading: .glyph(current ? Glyph.check : Glyph.suppliers), leadingTint: current ? P.accent : P.inkFaint,
                  title: name, subtitle: detail, value: value, valueTint: valueTint, valueNote: valueNote, pill: current ? "In use" : badge, pillTone: current ? .good : badgeTone,
                  lineLimit: 3, identifier: identifier, action: action)
            .overlay(alignment: .bottomLeading) { if warning { Rectangle().fill(P.warn).frame(width: 2).padding(.vertical, Theme.Space.s) } }
    }
}
