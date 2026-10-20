import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// Selling the company: put it on the market privately or through a broker, then take, counter or decline the offers that come.
/// Original: V.sale in features/player/selling_startups_and_crisis.js. Shown in the company's Money tab.
struct CompanySaleSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var confirming: CompanySale.Offer?

    var body: some View {
        if CompanySale.canSell(engine.state, companyID: company.id) {
            let cur = engine.currency(for: company)
            let value = CompanySale.estimatedValue(engine.state, companyID: company.id, data: engine.data)
            let listing = CompanySale.listing(engine.state, companyID: company.id)
            LedgerSection(title: "Sell the company", trailing: {
                Text("Worth about " + cur.short(value * company.ownership / 100)).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }) {
                if let l = listing {
                    listed(l, cur)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("A quiet private sale draws fewer buyers and is slower; staff and rivals do not hear. A broker finds more buyers for a 4% fee, but word gets out.")
                            .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Quiet private sale") { Haptics.tap(); store.act { $0.update { s, _, _ in CompanySale.startListing(&s, companyID: company.id, broker: false) } } }
                                .buttonStyle(SmallOutlineButtonStyle())
                            Button("Use a broker") { Haptics.tap(); store.act { $0.update { s, _, _ in CompanySale.startListing(&s, companyID: company.id, broker: true) } } }
                                .buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                }
            }
            .confirmationDialog("Sell \(company.name)?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { o in
                Button("Sell for " + cur.short(o.price * company.ownership / 100), role: .destructive) {
                    store.act { $0.update { s, data, ctx in CompanySale.accept(&s, companyID: company.id, offerID: o.id, data: data, context: ctx) } }
                    Haptics.success()
                }
                Button("Cancel", role: .cancel) {}
            } message: { o in
                Text("\(o.buyer) pays " + cur.display(o.price * company.ownership / 100) + (o.kind == "mbo" ? ", a third of it after two years" : "") + ". This cannot be undone.")
            }
        }
    }

    @ViewBuilder private func listed(_ l: CompanySale.Listing, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("On the market since " + GameCalendar.dateString(week: l.since) + (l.broker ? " through a broker" : ", a quiet private sale") + " · \(l.offers.count) offer\(l.offers.count == 1 ? "" : "s")")
                .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            if l.offers.isEmpty {
                Text("No offers yet. Buyers show up over the coming weeks.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            }
            ForEach(Array(l.offers.enumerated()), id: \.element.id) { i, o in
                if i > 0 { Hairline() }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(o.buyer).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                        Spacer()
                        Text(cur.short(o.price * company.ownership / 100)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(Theme.gold)
                    }
                    Text(o.note + " Open until " + GameCalendar.dateString(week: o.expiresWeek) + ".").font(.caption).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Accept") { Haptics.tap(); confirming = o }.buttonStyle(SmallGoldButtonStyle())
                        if !o.countered {
                            Button("Counter +8%") { Haptics.tap(); store.act { $0.update { s, _, _ in CompanySale.counter(&s, companyID: company.id, offerID: o.id) } } }.buttonStyle(SmallOutlineButtonStyle())
                        }
                        Button("Decline") { store.act { $0.update { s, _, _ in CompanySale.decline(&s, companyID: company.id, offerID: o.id) } } }.buttonStyle(SmallOutlineButtonStyle())
                    }
                }.padding(.vertical, 6)
            }
            Button("Take it off the market") { store.act { $0.update { s, _, _ in CompanySale.withdraw(&s, companyID: company.id) } } }.buttonStyle(SmallOutlineButtonStyle())
        }
    }
}
