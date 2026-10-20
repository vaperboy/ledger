import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// Owners, raising money and selling shares, as flat rows in the Money tab of a company. Logic: `Funding`, `Shareholders`, `CompanySale`.
struct CompanyOwnershipSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var message = ""

    var body: some View {
        let cur = engine.currency(for: company)
        let id = company.id
        LedgerSection(title: "Owners and shares", trailing: { Text("You own \(Int(company.ownership.rounded()))%").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(Theme.ivoryMuted) }
                ForEach(engine.owners(companyID: id)) { h in
                    HStack {
                        Text("\(h.name) · \(Shareholders.profileNames[h.profile] ?? "")").font(.system(size: 13)).foregroundStyle(Theme.ivory)
                        Spacer()
                        Text(String(format: "%.1f%% · %@", h.pct, h.moodWord)).font(.caption).foregroundStyle(Theme.ivoryFaint)
                        if let p = engine.buyBackPrice(companyID: id, holder: h.name) {
                            Button("Buy back " + cur.short(p)) { store.act { $0.buyBackStake(companyID: id, holder: h.name) }; Haptics.tap() }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                    Hairline()
                }
                if company.form == .limited && company.type != "hold" {
                    HStack {
                        Text("Dividend policy").font(.system(size: 13)).foregroundStyle(Theme.ivory)
                        Spacer()
                        ForEach(Shareholders.policies, id: \.self) { p in
                            Button(Shareholders.policyNames[p] ?? p) { store.act { $0.setDividendPolicy(companyID: id, policy: p) } }
                                .buttonStyle(SmallOutlineButtonStyle()).opacity(engine.dividendPolicy(companyID: id) == p ? 1 : 0.5)
                        }
                    }
                    Hairline()
                    Text("Investors: " + engine.investorInterest(companyID: id).word).font(.caption).foregroundStyle(Theme.ivoryMuted)
                    HStack {
                        Button("Pitch for " + cur.short(engine.suggestedFundingAmount(companyID: id))) {
                            let amount = engine.suggestedFundingAmount(companyID: id)
                            if let r = store.act({ $0.pitchToInvestors(companyID: id, amount: amount) }) {
                                switch r {
                                case .none: message = "No investor bit."
                                case .tooSoon(let w): message = "Try again in \(w) week(s)."
                                default: message = ""
                                }
                            }
                        }.buttonStyle(SmallOutlineButtonStyle())
                        ForEach(engine.shareOffers(companyID: id).prefix(3), id: \.pct) { o in
                            Button("Sell \(o.pct)% of yours " + cur.short(o.secondary)) { store.act { $0.sellPrivateShares(companyID: id, percent: Double(o.pct), mode: "secondary") } }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                    ForEach(engine.fundingOffers(companyID: id)) { o in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(o.name): \(cur.short(o.amount)) for \(Int(o.pct.rounded()))% · \(o.says)").font(.caption).foregroundStyle(Theme.ivory)
                            HStack {
                                Button("Accept") { store.act { $0.acceptFundingOffer(companyID: id, index: o.id) } }.buttonStyle(SmallGoldButtonStyle())
                                if !o.countered { Button("Counter") { store.act { $0.counterFundingOffer(companyID: id, index: o.id) } }.buttonStyle(SmallOutlineButtonStyle()) }
                                Button("Decline") { store.act { $0.declineFundingOffer(companyID: id, index: o.id) } }.buttonStyle(SmallOutlineButtonStyle())
                            }
                        }
                    }
                    HStack {
                        Text("Sell part of your shares").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        ForEach([10, 25, 34, 49], id: \.self) { p in
                            Button("\(p)%") { store.act { $0.listSharesForSale(companyID: id, percent: p, broker: false) } }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                }
                if company.type == "hold" {
                    if engine.isListed(companyID: id) { Text("Listed on the exchange").font(.caption).foregroundStyle(Theme.gain) }
                    else {
                        Button("Go public · fee " + cur.short(engine.listingFee)) {
                            let r = store.act { $0.listHoldingOnExchange(companyID: id) }
                            if case .tooSmall(let n)? = r { message = "Needs a value of at least " + cur.short(n) + "." }
                        }.buttonStyle(SmallOutlineButtonStyle())
                    }
                    HStack {
                        let g = engine.holdingValue(companyID: id) * 0.1
                        Button("Raise " + cur.short(g) + " privately") { store.act { $0.raiseMoneyForHolding(holdingID: id, goal: g, publicOffering: false) } }.buttonStyle(SmallOutlineButtonStyle())
                        if engine.isListed(companyID: id) { Button("Raise on the exchange") { store.act { $0.raiseMoneyForHolding(holdingID: id, goal: g, publicOffering: true) } }.buttonStyle(SmallOutlineButtonStyle()) }
                    }
                }
            }
        }
    }
}
