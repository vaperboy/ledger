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
            CardSection(title: "Sell the company", trailing: {
                Text("Worth about " + cur.tidyShort(value * company.ownership / 100)).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }) {
                if let l = listing {
                    listed(l, cur)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("A quiet private sale draws fewer buyers and is slower; staff and rivals do not hear. A broker finds more buyers for a 4% fee, but word gets out.")
                            .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        WrapRow {
                            Button("Quiet private sale") { list(broker: false) }.buttonStyle(QuietButtonStyle())
                            Button("Use a broker (4% fee)") { list(broker: true) }.buttonStyle(QuietButtonStyle())
                        }
                        Text("Listing is not a sale: nothing is sold until you accept an offer, and you can take it off the market at any time.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            .sheet(item: Binding(get: { talking.map { TalkID(id: $0) } }, set: { talking = $0?.id })) { t in
                BuyerTalkSheet(companyID: company.id, offerID: t.id) { confirming = $0 }
            }
            .confirmationDialog("Sell \(company.name)?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { o in
                Button("Sell for " + cur.tidyShort(o.price * company.ownership / 100), role: .destructive) {
                    let alone = engine.boardVote(kind: "sell", companyID: company.id).pushedThroughAlone
                    let got = store.act { $0.update { s, data, ctx in CompanySale.accept(&s, companyID: company.id, offerID: o.id, data: data, context: ctx) } }
                    if store.engine?.state.company(company.id)?.status == .sold {
                        if alone { store.act { $0.recordPushedThrough(companyID: company.id) } }
                        Haptics.success(); store.show("\(company.name) is sold to \(o.buyer)." + (alone ? " The other owners did not want this." : ""), tone: "good")
                    }
                    else { _ = got; Haptics.warning(); store.show("The sale did not go through: the other owners may be blocking it.", tone: "warn") }
                }
                Button("Cancel", role: .cancel) {}
            } message: { o in
                Text("\(o.buyer) pays " + cur.tidyDisplay(o.price * company.ownership / 100) + (o.kind == "mbo" ? ", a third of it after two years" : "") + ". " + consequences(o, cur))
            }
        }
    }

    private struct TalkID: Identifiable { var id: Int }

    private func list(broker: Bool) {
        Haptics.tap()
        store.act { $0.update { s, _, _ in CompanySale.startListing(&s, companyID: company.id, broker: broker) } }
        if CompanySale.listing(store.engine?.state ?? engine.state, companyID: company.id) != nil {
            store.show(broker ? "\(company.name) is on the market through a broker. Offers arrive over the coming weeks." : "\(company.name) is quietly on the market. Offers arrive over the coming weeks.", tone: "n")
        } else { Haptics.warning(); store.show("It could not be put on the market now.", tone: "warn") }
    }

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
                Text("No offers yet. Buyers show up over the coming weeks.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
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
                    WrapRow {
                        Button("Accept…") { Haptics.tap(); confirming = o }.buttonStyle(QuietButtonStyle())
                        Button("Talk to the buyer") { Haptics.tap(); talking = o.id }.buttonStyle(QuietButtonStyle())
                        Button("Decline") { store.settle(store.act { $0.declineSaleOffer(companyID: company.id, offerID: o.id) }, "Offer from \(o.buyer) declined.", same: "That offer had already gone.") }.buttonStyle(QuietButtonStyle())
                    }
                }.padding(.vertical, 6)
            }
            Button("Take it off the market") {
                store.act { $0.update { s, _, _ in CompanySale.withdraw(&s, companyID: company.id) } }
                if CompanySale.listing(store.engine?.state ?? engine.state, companyID: company.id) == nil { store.show("\(company.name) is off the market.", tone: "n") } else { Haptics.warning(); store.show("It could not be taken off the market now.", tone: "warn") }
            }.buttonStyle(QuietButtonStyle())
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
                            .init(label: "Mood", value: PatienceWords.feeling(left: o.patience, of: 3).text, tint: PatienceWords.feeling(left: o.patience, of: 3).tint),
                            .init(label: "Open until", value: GameCalendar.dateString(week: o.expiresWeek)),
                        ])
                        if !o.talk.isEmpty {
                            CardSection("The talk") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(o.talk.enumerated()), id: \.offset) { _, l in
                                        Text((l.mine ? "You: " : "\(o.buyer): ") + l.text).font(.system(size: 13)).foregroundStyle(l.mine ? Theme.ivoryMuted : Theme.ivory)
                                    }
                                }
                            }
                        }
                        CardSection("Ask") {
                            WrapRow {
                                Button("What happens to my staff?") { store.act { $0.askBuyer(companyID: companyID, offerID: offerID, question: "staff") }; Haptics.tap() }.buttonStyle(QuietButtonStyle())
                                Button("How would you pay?") { store.act { $0.askBuyer(companyID: companyID, offerID: offerID, question: "pay") }; Haptics.tap() }.buttonStyle(QuietButtonStyle())
                            }
                        }
                        CardSection("Name your price") {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                AmountField(title: "Your price for the whole company", currency: cur, amount: $ask)
                                WrapRow {
                                    ForEach([0.03, 0.08, 0.15], id: \.self) { f in
                                        Button("+\(Int(f * 100))%") { ask = (o.price * (1 + f) / 1000).rounded() * 1000 }.buttonStyle(QuietButtonStyle())
                                    }
                                }
                                Text("At or below the offer they ask you to sign. A little above, they may agree or stretch half way; far above, they lose patience and may walk away.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                Button(ask > 0 ? "Ask \(cur.tidyShort(ask * mine)) for your share" : "Enter a price above") {
                                    switch store.act({ $0.counterBuyer(companyID: companyID, offerID: offerID, price: ask) }) {
                                    case .agreed(let p)?: Haptics.success(); store.show("\(o.buyer) agrees to \(cur.tidyShort(p * mine)).", tone: "good")
                                    case .stretched(let p)?: Haptics.tap(); store.show("They stretch to \(cur.tidyShort(p * mine)) and no further.", tone: "n")
                                    case .refused?: Haptics.warning(); store.show("Far above what it is worth to them.", tone: "warn")
                                    case .walkedAway?: Haptics.warning(); store.show("\(o.buyer) walked away.", tone: "bad"); dismiss()
                                    default: store.show("That is what they offered (\(cur.tidyShort(o.price * mine))). Sign, or ask for more.", tone: "n")
                                    }
                                }.buttonStyle(QuietButtonStyle()).disabled(ask <= 0)
                            }
                        }
                        Button("Sign at \(cur.tidyShort(o.price * mine))…") { dismiss(); onSign(o) }.buttonStyle(QuietButtonStyle())
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
