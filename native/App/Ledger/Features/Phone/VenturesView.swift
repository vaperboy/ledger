import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// Startups, private equity, the big meeting and stakes in groups, as flat rows under Money > Invest. Logic: `Startups`, `PrivateEquity`, `BigMeeting`, `GroupDeals`.
struct VenturesContent: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if store.engine != nil { content }
    }

    private var content: some View {
        let e = store.engine!
        let cur = e.homeCurrency
        return VStack(spacing: Theme.Space.l) {
            LedgerSection(title: "My startups", trailing: { Text("\(e.founderRecord.exits) exits · \(e.founderRecord.fails) failures").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(StartupProducts.sectors) { sec in
                                Button("Found: " + sec.name) {
                                    store.act { $0.foundStartup(name: nil, sector: sec.id, product: sec.products[0].id, model: sec.models[0].id, who: sec.canBuildYourself ? "c2" : "c2", seedMultiple: 1) }
                                }.buttonStyle(SmallOutlineButtonStyle())
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
                                    Button("Raise a round") { store.act { $0.pitchStartupRound(startupID: f.id) } }.buttonStyle(SmallOutlineButtonStyle())
                                    Button("Put in " + cur.short(cur.scaledPrice(100000))) { store.act { $0.putMoneyIntoStartup(startupID: f.id, amount: cur.scaledPrice(100000)) } }.buttonStyle(SmallOutlineButtonStyle())
                                    Button("+ builder") { store.act { $0.changeBuilders(startupID: f.id, by: 1) } }.buttonStyle(SmallOutlineButtonStyle())
                                    Button("Shut down") { store.act { $0.shutDownStartup(startupID: f.id) } }.buttonStyle(SmallOutlineButtonStyle())
                                }
                                ForEach(f.offers) { o in
                                    HStack {
                                        Text("\(o.name): \(cur.short(o.amount)) for \(Int(o.pct.rounded()))%").font(.caption).foregroundStyle(Theme.ivory)
                                        Button("Accept") { store.act { $0.acceptStartupRound(startupID: f.id, index: o.id) } }.buttonStyle(SmallGoldButtonStyle())
                                        Button("Decline") { store.act { $0.declineStartupRound(startupID: f.id, index: o.id) } }.buttonStyle(SmallOutlineButtonStyle())
                                    }
                                }
                                if let p = f.product, p.ready {
                                    ForEach(e.companiesThatCanUseProduct(startupID: f.id), id: \.company.id) { c in
                                        Button((p.usedBy.contains(c.company.id) ? "Stop in " : "Use in ") + c.company.name + " (" + c.effect.summary + ")") {
                                            store.act { $0.toggleProductUse(startupID: f.id, companyID: c.company.id) }
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
                            Button("Invest " + cur.short(p.raise / 4)) { store.act { $0.investInStartup(pitchID: p.id, amount: p.raise / 4) } }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                    ForEach(e.startupStakes.filter { $0.live }) { st in
                        Hairline()
                        HStack {
                            Text("\(st.name) · \(st.stageName) · \(String(format: "%.1f", st.ownership))% · \(cur.short(st.value))").font(.caption).foregroundStyle(Theme.ivory)
                            Spacer()
                            if st.boardSeat { Button("Help") { store.act { $0.helpStartupOnBoard(stakeID: st.id) } }.buttonStyle(SmallOutlineButtonStyle()) }
                            Button("Sell half") { store.act { $0.sellStartupStake(stakeID: st.id, fraction: 0.5) } }.buttonStyle(SmallOutlineButtonStyle())
                            Button("Sell all") { store.act { $0.sellStartupStake(stakeID: st.id, fraction: 1) } }.buttonStyle(SmallOutlineButtonStyle())
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
                            Button("Sell " + cur.short(e.secondaryPrice(fundID: f.id))) { store.act { $0.sellFundStake(fundID: f.id) } }.buttonStyle(SmallOutlineButtonStyle())
                        }
                        Hairline()
                    }
                    ForEach(peOffers) { o in
                        HStack {
                            Text("\(o.name) · \(PrivateEquity.styles[o.style]?.name ?? "") · \(o.trackRecord)").font(.caption).foregroundStyle(Theme.ivory)
                            Spacer()
                            Button("Commit " + cur.short(o.minimum)) { store.act { $0.commitToFund(offerID: o.id, amount: o.minimum) } }.buttonStyle(SmallOutlineButtonStyle())
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
                            Button("Accept and borrow") { store.act { $0.acceptBigMeetingOffer() } }.buttonStyle(SmallGoldButtonStyle())
                            if !o.countered { Button("Counter -10%") { store.act { $0.counterBigMeetingOffer() } }.buttonStyle(SmallOutlineButtonStyle()) }
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
    }

    private var startupPitches: [Startups.Pitch] { store.engine?.startupPitchesOnOffer ?? [] }
    private var peOffers: [PrivateEquity.Offer] { store.engine?.privateEquityOffersOnTable ?? [] }
}
