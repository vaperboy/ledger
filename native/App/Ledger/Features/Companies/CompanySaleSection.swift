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
    @State private var talking: Int?

    var body: some View {
        if CompanySale.canSell(engine.state, companyID: company.id) {
            let cur = engine.currency(for: company)
            let value = CompanySale.estimatedValue(engine.state, companyID: company.id, data: engine.data)
            let listing = CompanySale.listing(engine.state, companyID: company.id)
            LedgerSection(title: "Sell the company", trailing: {
                Text("Worth about " + cur.tidyShort(value * company.ownership / 100)).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
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
            .sheet(item: Binding(get: { talking.map { TalkID(id: $0) } }, set: { talking = $0?.id })) { t in
                BuyerTalkSheet(companyID: company.id, offerID: t.id) { confirming = $0 }
            }
            .confirmationDialog("Sell \(company.name)?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { o in
                Button("Sell for " + cur.tidyShort(o.price * company.ownership / 100), role: .destructive) {
                    let got = store.act { $0.update { s, data, ctx in CompanySale.accept(&s, companyID: company.id, offerID: o.id, data: data, context: ctx) } }
                    if store.engine?.state.company(company.id)?.status == .sold { Haptics.success(); store.show("\(company.name) is sold to \(o.buyer).", tone: "good") }
                    else { _ = got; Haptics.warning(); store.show("The sale did not go through: the other owners may be blocking it.", tone: "warn") }
                }
                Button("Cancel", role: .cancel) {}
            } message: { o in
                Text("\(o.buyer) pays " + cur.tidyDisplay(o.price * company.ownership / 100) + (o.kind == "mbo" ? ", a third of it after two years" : "") + ". " + consequences(o, cur))
            }
        }
    }

    private struct TalkID: Identifiable { var id: Int }

    /// What the sale does: what you are paid, which loans are settled, who loses a job, what the buyer does with it.
    private func consequences(_ o: CompanySale.Offer, _ cur: Currency) -> String {
        let loans = engine.state.loans.filter { $0.companyID == company.id }.reduce(0) { $0 + $1.balance }
        var t = "The company's staff (\(company.staff.count.peopleText)) leave your payroll"
        if loans > 0 { t += " and its loans of \(cur.tidyShort(loans)) are settled" }
        t += ". Gains are taxed. \(o.note) This cannot be undone."
        return t
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
                        Text(cur.tidyShort(o.price * company.ownership / 100)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(Theme.gold)
                    }
                    Text(o.note + " Open until " + GameCalendar.dateString(week: o.expiresWeek) + ".").font(.caption).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Accept") { Haptics.tap(); confirming = o }.buttonStyle(SmallGoldButtonStyle())
                        Button("Talk to the buyer") { Haptics.tap(); talking = o.id }.buttonStyle(SmallOutlineButtonStyle())
                        Button("Decline") { store.settle(store.act { $0.declineSaleOffer(companyID: company.id, offerID: o.id) }, "Offer from \(o.buyer) declined.", same: "That offer had already gone.") }.buttonStyle(SmallOutlineButtonStyle())
                    }
                }.padding(.vertical, 6)
            }
            Button("Take it off the market") {
                store.act { $0.update { s, _, _ in CompanySale.withdraw(&s, companyID: company.id) } }
                if CompanySale.listing(store.engine?.state ?? engine.state, companyID: company.id) == nil { store.show("\(company.name) is off the market.", tone: "n") } else { Haptics.warning(); store.show("It could not be taken off the market now.", tone: "warn") }
            }.buttonStyle(SmallOutlineButtonStyle())
        }
    }
}


/// The talk with one buyer: ask about the staff and how they would pay, name a price (they agree, stretch, or lose patience), then sign.
struct BuyerTalkSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var offerID: Int
    var onSign: (CompanySale.Offer) -> Void
    @State private var ask = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let co = e.state.company(companyID), let o = CompanySale.listing(e.state, companyID: companyID)?.offers.first(where: { $0.id == offerID }) {
                    let cur = e.currency(for: co)
                    let mine = co.ownership / 100
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(o.buyer).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                            Text(o.note.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        }
                        KeyFigures(items: [
                            .init(label: "They offer", value: cur.tidyShort(o.price * mine), sub: "for your \(Int(co.ownership.rounded()))%"),
                            .init(label: "Patience", value: String(repeating: "●", count: max(0, o.patience)) + String(repeating: "○", count: max(0, 3 - o.patience)), tint: o.patience <= 1 ? Theme.caution : Theme.ivory),
                            .init(label: "Open until", value: GameCalendar.dateString(week: o.expiresWeek)),
                        ])
                        if !o.talk.isEmpty {
                            LedgerSection("The talk") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(o.talk.enumerated()), id: \.offset) { _, l in
                                        Text((l.mine ? "You: " : "\(o.buyer): ") + l.text).font(.system(size: 13)).foregroundStyle(l.mine ? Theme.ivoryMuted : Theme.ivory)
                                    }
                                }
                            }
                        }
                        LedgerSection("Ask") {
                            HStack {
                                Button("What happens to my staff?") { store.act { $0.askBuyer(companyID: companyID, offerID: offerID, question: "staff") } }.buttonStyle(SmallOutlineButtonStyle())
                                Button("How would you pay?") { store.act { $0.askBuyer(companyID: companyID, offerID: offerID, question: "pay") } }.buttonStyle(SmallOutlineButtonStyle())
                            }
                        }
                        LedgerSection("Name your price") {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                AmountField(title: "Your price for the whole company", currency: cur, amount: $ask)
                                HStack {
                                    ForEach([0.03, 0.08, 0.15], id: \.self) { f in
                                        Button("+\(Int(f * 100))%") { ask = (o.price * (1 + f) / 1000).rounded() * 1000 }.buttonStyle(SmallOutlineButtonStyle())
                                    }
                                }
                                Text("At or below the offer they ask you to sign. A little above, they may agree or stretch half way; far above, they lose patience and may walk away.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                Button(ask > 0 ? "Ask \(cur.tidyShort(ask * mine)) for your share" : "Enter a price above") {
                                    switch store.act({ $0.counterBuyer(companyID: companyID, offerID: offerID, price: ask) }) {
                                    case .agreed(let p)?: Haptics.success(); store.show("\(o.buyer) agrees to \(cur.tidyShort(p * mine)).", tone: "good")
                                    case .stretched(let p)?: store.show("They stretch to \(cur.tidyShort(p * mine)) and no further.", tone: "n")
                                    case .refused?: Haptics.warning(); store.show("Far above what it is worth to them.", tone: "warn")
                                    case .walkedAway?: Haptics.warning(); store.show("\(o.buyer) walked away.", tone: "bad"); dismiss()
                                    default: store.show("That is what they offered. Sign, or ask for more.", tone: "n")
                                    }
                                }.buttonStyle(QuietButtonStyle()).disabled(ask <= 0)
                            }
                        }
                        Button("Sign at \(cur.tidyShort(o.price * mine))") { dismiss(); onSign(o) }.buttonStyle(GoldButtonStyle())
                    }
                    .padding(Theme.Space.margin)
                } else {
                    Text("This buyer has left.").foregroundStyle(Theme.ivoryMuted).padding()
                }
            }
            .ledgerBackground()
            .navigationTitle("Buyer talk").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
