import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Group > Dividends: the dividend desk. Nothing is paid by itself; the owner picks a company or a holding and a share of what it may pay.
struct GroupDividendsPage: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var pending: PendingAction?

    var body: some View {
        let rows: [DividendRow] = engine.dividendRows()
        let holdings: [Company] = engine.holdingCompanies.filter { (h: Company) -> Bool in rows.contains { (r: DividendRow) -> Bool in r.holdingID == h.id } }
        VStack(alignment: .leading, spacing: 12) {
            if rows.isEmpty {
                Text("No company has retained profit to pay out yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            }
            ForEach(holdings) { (h: Company) in holdingCard(h, rows.filter { (r: DividendRow) -> Bool in r.holdingID == h.id }) }
            let direct: [DividendRow] = rows.filter { (r: DividendRow) -> Bool in r.holdingID == nil }
            ForEach(direct) { (r: DividendRow) in companyCard(r) }
        }
        .confirmAction($pending)
    }

    private func holdingCard(_ h: Company, _ under: [DividendRow]) -> some View {
        let total: Double = under.reduce(0) { $0 + $1.payable }
        return Card(padding: 12, radius: Theme.Radius.table) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ivory)
                        Text("Collects from \(under.count) \(under.count == 1 ? "company" : "companies") \u{00B7} up to \(store.short(total, in: h))").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer(minLength: 8)
                }
                shareButtons { (s: Double) in askCollect(h, total, s) }
                ForEach(under) { (r: DividendRow) in
                    HStack {
                        Text(r.name).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                        Spacer(minLength: 8)
                        Text(store.short(r.payable, in: h)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
                    }
                }
            }
        }
    }

    private func companyCard(_ r: DividendRow) -> some View {
        Card(padding: 12, radius: Theme.Radius.table) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ivory)
                        Text("Can pay \(money(r.payable, r.id)) \u{00B7} paid so far \(money(r.distributed, r.id))").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer(minLength: 8)
                }
                if r.payable > 0 { shareButtons { (s: Double) in askPay(r, s) } }
            }
        }
    }

    private func money(_ v: Double, _ id: Int) -> String {
        guard let c = engine.state.company(id) else { return "" }
        return store.short(v, in: c)
    }

    private func shareButtons(_ pick: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach([0.25, 0.5, 1.0], id: \.self) { (s: Double) in
                Button(s == 1 ? "All" : "\(Int(s * 100))%") { pick(s) }.buttonStyle(QuietButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private func askPay(_ r: DividendRow, _ share: Double) {
        guard let co = engine.state.company(r.id) else { return }
        let cur: Currency = engine.currency(for: co)
        let amount: Double = (r.payable * share).rounded(.down)
        let to: String = r.holdingName ?? "you"
        pending = PendingAction(title: "Pay \(cur.tidyShort(amount)) from \(r.name)?", message: "It goes to \(to) from retained profit. It is taxed as income and cannot be paid back in as a dividend.", button: "Pay", amount: amount, currency: cur) {
            let paid: Double = store.act { $0.payDividendShare(companyID: r.id, share: share) } ?? 0
            store.show(paid > 0 ? "Dividend of \(cur.tidyShort(paid)) paid." : "Nothing could be paid.", tone: paid > 0 ? "good" : "warn")
            if paid > 0 { store.flyChip("Dividend", amount: paid) }
        }
    }

    private func askCollect(_ h: Company, _ total: Double, _ share: Double) {
        let cur: Currency = engine.currency(for: h)
        let amount: Double = (total * share).rounded(.down)
        pending = PendingAction(title: "Collect about \(cur.tidyShort(amount)) for \(h.name)?", message: "Each company under it pays \(share == 1 ? "all it can" : "\(Int(share * 100))% of what it can") from retained profit.", button: "Collect", amount: amount, currency: cur) {
            let r: (total: Double, companies: Int) = store.act { $0.collectForHolding(holdingID: h.id, share: share) } ?? (total: 0, companies: 0)
            store.show(r.total > 0 ? "Collected \(cur.tidyShort(r.total)) from \(r.companies)." : "Nothing could be collected.", tone: r.total > 0 ? "good" : "warn")
        }
    }
}
