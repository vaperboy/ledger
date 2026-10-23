import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

/// Startups, private equity, the big meeting and stakes in groups, as flat rows under Money > Invest. Logic: `Startups`, `PrivateEquity`, `BigMeeting`, `GroupDeals`.
struct VenturesContent: View {
    @EnvironmentObject var store: GameStore
    @State private var founding: StartupProducts.Sector?
    @State private var closing: Startups.Founded?

    var body: some View {
        if store.engine != nil { content }
    }

    private func startupRecordText(_ e: GameEngine) -> String {
        let r = e.founderRecord
        return "\(r.exits) exits · \(r.fails) failures"
    }

    private var content: some View {
        let e = store.engine!
        let cur = e.homeCurrency
        return VStack(spacing: Theme.Space.l) {
            LedgerSection(title: "My startups", trailing: { Text(startupRecordText(e)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(StartupProducts.sectors) { sec in
                                Button("Found: " + sec.name) { founding = sec }.buttonStyle(SmallOutlineButtonStyle())
                            }
                        }
                    }
                    ForEach(e.foundedStartups) { f in
                        Hairline()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(f.name) · \(f.productName) · \(f.stageName)").font(.system(size: 14)).foregroundStyle(Theme.ivory)
                            if f.live {
                                Text("You own \(Int(f.ownership.rounded()))% · value \(cur.short(f.valuation)) · cash \(cur.short(f.cash)) · \(f.runwayWeeks) weeks left" + (f.product.map { " · \($0.phase) \(Int($0.progress * 100))%" } ?? ""))
                                    .font(.caption).foregroundStyle(Theme.ivoryFaint)
                                HStack {
                                    Button("Raise a round") {
                                        switch store.act({ $0.pitchStartupRound(startupID: f.id) }) {
                                        case .offers(let n)?: store.show("\(n) investor\(n == 1 ? "" : "s") made an offer.", tone: "good")
                                        case .none?: store.show("No investor bit this time.", tone: "warn")
                                        case .tooSoon(let w)?: store.show("Too soon to pitch again: \(w) week\(w == 1 ? "" : "s") to go.", tone: "n")
                                        default: store.show("This startup is no longer running.", tone: "warn")
                                        }
                                    }.buttonStyle(SmallOutlineButtonStyle())
                                    Button("Put in " + cur.short(cur.scaledPrice(100000))) {
                                        let ok = store.act { $0.putMoneyIntoStartup(startupID: f.id, amount: cur.scaledPrice(100000)) } ?? false
                                        store.show(ok ? "Money put in." : "Not enough cash.", tone: ok ? "good" : "warn")
                                    }.buttonStyle(SmallOutlineButtonStyle())
                                    Button("+ builder") { store.act { $0.changeBuilders(startupID: f.id, by: 1) }; store.show("One more builder: faster work, higher monthly cost.", tone: "n") }.buttonStyle(SmallOutlineButtonStyle())
                                    Button("Shut down") { closing = f }.buttonStyle(SmallOutlineButtonStyle())
                                }
                                ForEach(f.offers) { o in
                                    HStack {
                                        Text("\(o.name): \(cur.short(o.amount)) for \(Int(o.pct.rounded()))%").font(.caption).foregroundStyle(Theme.ivory)
                                        Button("Accept") {
                                            let ok = store.act { $0.acceptStartupRound(startupID: f.id, index: o.id) } ?? false
                                            store.show(ok ? "Round closed: \(cur.short(o.amount)) in for \(Int(o.pct.rounded()))%." : "That offer is no longer on the table.", tone: ok ? "good" : "warn")
                                        }.buttonStyle(SmallGoldButtonStyle())
                                        Button("Decline") { store.act { $0.declineStartupRound(startupID: f.id, index: o.id) } }.buttonStyle(SmallOutlineButtonStyle())
                                    }
                                }
                                if let p = f.product, p.ready {
                                    ForEach(e.companiesThatCanUseProduct(startupID: f.id), id: \.company.id) { c in
                                        Button((p.usedBy.contains(c.company.id) ? "Stop in " : "Use in ") + c.company.name + " (" + c.effect.summary + ")") {
                                            let using = p.usedBy.contains(c.company.id)
                                            let ok = store.act { $0.toggleProductUse(startupID: f.id, companyID: c.company.id) } ?? false
                                            store.show(ok ? (using ? "\(c.company.name) stopped using it." : "\(c.company.name) now uses it.") : "Not possible right now.", tone: ok ? "good" : "warn")
                                        }.buttonStyle(SmallOutlineButtonStyle())
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            LedgerSection("Startups to invest in") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(Array(startupPitches.enumerated()), id: \.element.id) { n, p in
                        if n > 0 { Hairline() }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(p.name) · \(p.sector) · raising \(cur.short(p.raise)) at \(cur.short(p.preMoney))").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text("\(p.blurb) Team \(p.team), market \(p.market), traction \(p.traction).").font(.caption).foregroundStyle(Theme.ivoryFaint)
                            Button("Invest " + cur.short(p.raise / 4)) {
                                switch store.act({ $0.investInStartup(pitchID: p.id, amount: p.raise / 4) }) {
                                case .ok?: store.show("You invested in \(p.name).", tone: "good")
                                case .tooSmall?: store.show("They want a bigger cheque.", tone: "warn")
                                case .notEnoughMoney?: store.show("Not enough cash.", tone: "warn")
                                default: store.show("The round has closed.", tone: "warn")
                                }
                            }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                    ForEach(e.startupStakes.filter { $0.live }) { st in
                        Hairline()
                        HStack {
                            Text("\(st.name) · \(st.stageName) · \(String(format: "%.1f", st.ownership))% · \(cur.short(st.value))").font(.caption).foregroundStyle(Theme.ivory)
                            Spacer()
                            if st.boardSeat { Button("Help") { let ok = store.act { $0.helpStartupOnBoard(stakeID: st.id) } ?? false; store.show(ok ? "You spent time with the team." : "You helped recently.", tone: ok ? "good" : "n") }.buttonStyle(SmallOutlineButtonStyle()) }
                            Button("Sell half") { let v = store.act { $0.sellStartupStake(stakeID: st.id, fraction: 0.5) } ?? 0; store.show(v > 0 ? "Sold for \(cur.short(v))." : "No buyer.", tone: v > 0 ? "good" : "warn") }.buttonStyle(SmallOutlineButtonStyle())
                            Button("Sell all") { let v = store.act { $0.sellStartupStake(stakeID: st.id, fraction: 1) } ?? 0; store.show(v > 0 ? "Sold for \(cur.short(v))." : "No buyer.", tone: v > 0 ? "good" : "warn") }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                }
            }
            LedgerSection("Private equity") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(e.privateEquityFunds.filter { $0.live }) { f in
                        HStack {
                            Text("\(f.name) · year \((e.state.week - f.startWeek) / 52 + 1) · value \(cur.short(f.nav)) · back \(cur.short(f.distributed))").font(.caption).foregroundStyle(Theme.ivory)
                            Spacer()
                            Button("Sell " + cur.short(e.secondaryPrice(fundID: f.id))) { let v = store.act { $0.sellFundStake(fundID: f.id) } ?? nil; store.show(v.map { "Stake sold for \(cur.short($0))." } ?? "No buyer for the stake.", tone: v == nil ? "warn" : "good") }.buttonStyle(SmallOutlineButtonStyle())
                        }
                        Hairline()
                    }
                    ForEach(peOffers) { o in
                        HStack {
                            Text("\(o.name) · \(PrivateEquity.styles[o.style]?.name ?? "") · \(o.trackRecord)").font(.caption).foregroundStyle(Theme.ivory)
                            Spacer()
                            Button("Commit " + cur.short(o.minimum)) {
                                switch store.act({ $0.commitToFund(offerID: o.id, amount: o.minimum) }) {
                                case .ok?: store.show("Committed \(cur.short(o.minimum)). The fund calls the money over the coming years.", tone: "good")
                                case .tooSmall?: store.show("Below the fund's minimum.", tone: "warn")
                                case .notRichEnough?: store.show("Funds only take investors worth at least 1.5 times the commitment.", tone: "warn")
                                default: store.show("The fund has closed.", tone: "warn")
                                }
                            }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                }
            }
            if let o = e.bigMeetingOffer {
                LedgerSection("Big meeting") {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("\(o.seller) offers \(o.pct)% of \(o.target) for \(cur.short(o.price)) · profit share \(cur.short(o.yearlyProfitShare)) a year" + (e.bigMeetingRatesWarning() ? " · interest could exceed the profit share" : ""))
                            .font(.caption).foregroundStyle(Theme.ivory)
                        HStack {
                            Button("Accept and borrow") {
                                switch store.act({ $0.acceptBigMeetingOffer() }) {
                                case .ok?: store.show("You bought \(o.pct)% of \(o.target).", tone: "good")
                                case .needsOwnMoney(let v)?: store.show("The bank wants \(cur.short(v)) of your own money first.", tone: "warn")
                                default: store.show("The offer has gone.", tone: "warn")
                                }
                            }.buttonStyle(SmallGoldButtonStyle())
                            if !o.countered { Button("Counter -10%") {
                                let r = store.act { $0.counterBigMeetingOffer() } ?? nil
                                store.show(r == true ? "They accepted the lower price." : r == false ? "They refused and the offer is withdrawn." : "The offer has gone.", tone: r == true ? "good" : "warn")
                            }.buttonStyle(SmallOutlineButtonStyle()) }
                            Button("Walk away") { store.act { $0.walkAwayFromBigMeeting() } }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                }
            }
            if !e.bigMeetingStakes.isEmpty || !e.groupStakes.isEmpty {
                LedgerSection("Stakes in groups") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(e.bigMeetingStakes) { s in Text("\(s.name) · \(Int(s.pct))% · \(cur.short(s.value)) · \(cur.short(s.yearlyProfitShare)) a year").font(.caption).foregroundStyle(Theme.ivory) }
                        ForEach(e.groupStakes) { s in Text("\(s.name) · \(Int((s.ownership * 100).rounded()))% · \(cur.short(s.value))").font(.caption).foregroundStyle(Theme.ivory) }
                    }
                }
            }
        }
        .confirmationDialog("Found a \(founding?.name ?? "") startup?", isPresented: Binding(get: { founding != nil }, set: { if !$0 { founding = nil } }), titleVisibility: .visible) {
            Button("Found it") {
                if let sec = founding {
                    switch store.act({ $0.foundStartup(name: nil, sector: sec.id, product: sec.products[0].id, model: sec.models[0].id, who: "c2", seedMultiple: 1) }) {
                    case .ok?: Haptics.success(); store.show("Founded. Build the product, then raise a round.", tone: "good")
                    case .notEnoughMoney(let need)?: store.show("You need \(store.short(need)) in cash.", tone: "warn")
                    default: store.show("That sector is not available.", tone: "warn")
                    }
                }
                founding = nil
            }
        } message: { Text(founding.map { foundMessage($0) } ?? "") }
        .confirmationDialog("Shut down \(closing?.name ?? "")?", isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }), titleVisibility: .visible) {
            Button("Shut down", role: .destructive) {
                if let f = closing {
                    let back = store.act { $0.shutDownStartup(startupID: f.id) } ?? nil
                    store.show(back.map { "Shut down. \(store.short($0)) comes back to you." } ?? "It was already closed.", tone: "n")
                }
                closing = nil
            }
        } message: { Text("The team goes and the product stops. What cash is left comes back after costs; your stake is lost.") }
    }

    private func foundMessage(_ sec: StartupProducts.Sector) -> String {
        guard let e = store.engine, let p = e.startupPlan(sector: sec.id, who: "c2", seedMultiple: 1) else { return "" }
        let cur = e.homeCurrency
        return "Seed money \(cur.short(p.seed)) from your own cash, \(p.builders) builders at \(cur.short(p.buildersMonthly)) a month. About \(p.runwayWeeks) weeks of runway" + (p.weeksToSell.map { ", a product to sell in about \($0) weeks" } ?? "") + ". Most startups fail; rounds dilute you."
    }

    private var startupPitches: [Startups.Pitch] { store.engine?.startupPitchesOnOffer ?? [] }
    private var peOffers: [PrivateEquity.Offer] { store.engine?.privateEquityOffersOnTable ?? [] }
}
