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
    @State private var pending: PendingAction?

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
                            Button("Buy back " + cur.tidyShort(p)) {
                                pending = PendingAction(title: "Buy back \(h.name)'s \(String(format: "%.1f", h.pct))%?", message: "\(cur.tidyShort(p)) from your own cash. Their votes and dividends come back to you.", button: "Buy back") {
                                    let ok = store.act { $0.buyBackStake(companyID: id, holder: h.name) } ?? false
                                    store.show(ok ? "You bought back \(h.name)'s stake." : "Not enough cash, or they will not sell now.", tone: ok ? "good" : "warn")
                                }
                            }.buttonStyle(SmallOutlineButtonStyle())
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
                        Button("Pitch for " + cur.tidyShort(engine.suggestedFundingAmount(companyID: id))) {
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
                            Button("Sell \(o.pct)% of yours " + cur.tidyShort(o.secondary)) {
                                pending = PendingAction(title: "Sell \(o.pct)% of your shares?", message: "About \(cur.tidyShort(o.secondary)) comes to you (gains are taxed). The buyer gets votes and a share of every dividend; your control falls.", button: "Sell") {
                                    switch store.act({ $0.sellPrivateShares(companyID: id, percent: Double(o.pct), mode: "secondary") }) {
                                    case .ok(let v)?: store.show("Sold for \(cur.tidyShort(v)).", tone: "good")
                                    case .notLimited?: store.show("Only a limited company can sell shares.", tone: "warn")
                                    case .tooMuch?: store.show("That would cost you control.", tone: "warn")
                                    default: store.show("The owners blocked the sale.", tone: "warn")
                                    }
                                }
                            }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                    ForEach(engine.fundingOffers(companyID: id)) { o in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(o.name): \(cur.tidyShort(o.amount)) for \(Int(o.pct.rounded()))% · \(o.says)").font(.caption).foregroundStyle(Theme.ivory)
                            HStack {
                                Button("Accept") {
                                    pending = PendingAction(title: "Take \(cur.tidyShort(o.amount)) for \(Int(o.pct.rounded()))%?", message: "The money goes into the company. \(o.name) becomes an owner with votes and a share of profits.", button: "Accept") {
                                        let ok = store.act { $0.acceptFundingOffer(companyID: id, index: o.id) } ?? false
                                        store.show(ok ? "\(cur.tidyShort(o.amount)) is in the company." : "The offer has gone.", tone: ok ? "good" : "warn")
                                    }
                                }.buttonStyle(SmallGoldButtonStyle())
                                if !o.countered { Button("Counter") { store.act { $0.counterFundingOffer(companyID: id, index: o.id) }; store.show("Counter sent. Their answer replaces the offer.", tone: "n") }.buttonStyle(SmallOutlineButtonStyle()) }
                                Button("Decline") { store.act { $0.declineFundingOffer(companyID: id, index: o.id) }; store.show("Declined.", tone: "n") }.buttonStyle(SmallOutlineButtonStyle())
                            }
                        }
                    }
                    HStack {
                        Text("Sell part of your shares").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        ForEach([10, 25, 34, 49], id: \.self) { p in
                            Button("\(p)%") {
                                pending = PendingAction(title: "Look for a buyer for \(p)%?", message: "Buyers make offers over the coming weeks; nothing is sold until you accept one.", button: "List \(p)%") {
                                    let ok = store.act { $0.listSharesForSale(companyID: id, percent: p, broker: false) } ?? false
                                    store.show(ok ? "Listed. Offers arrive in the Inbox." : "Not possible now.", tone: ok ? "good" : "warn")
                                }
                            }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                }
                if company.type == "hold" {
                    if engine.isListed(companyID: id) { Text("Listed on the exchange").font(.caption).foregroundStyle(Theme.gain) }
                    else {
                        Button("Go public · fee " + cur.tidyShort(engine.listingFee)) {
                            let r = store.act { $0.listHoldingOnExchange(companyID: id) }
                            if case .tooSmall(let n)? = r { message = "Needs a value of at least " + cur.tidyShort(n) + "." }
                        }.buttonStyle(SmallOutlineButtonStyle())
                    }
                    HStack {
                        let g = engine.holdingValue(companyID: id) * 0.1
                        Button("Raise " + cur.tidyShort(g) + " privately") { confirmRaise(g, publicOffering: false, cur: cur) }.buttonStyle(SmallOutlineButtonStyle())
                        if engine.isListed(companyID: id) { Button("Raise on the exchange") { confirmRaise(g, publicOffering: true, cur: cur) }.buttonStyle(SmallOutlineButtonStyle()) }
                    }
                }
            }
        }
        .confirmAction($pending)
    }

    /// New shares are issued for money: say what it costs before doing it, and report what the engine raised.
    private func confirmRaise(_ goal: Double, publicOffering: Bool, cur: Currency) {
        let id = company.id
        pending = PendingAction(title: "Raise about \(cur.tidyShort(goal))?",
                                message: "Benefit: the money goes into the holding. Cost: new shares are issued, so your share of it shrinks, and a fee is taken. Risk: it cannot be undone; the engine decides how much it raises and at what price.",
                                button: "Raise") {
            if let raised = store.act({ $0.raiseMoneyForHolding(holdingID: id, goal: goal, publicOffering: publicOffering) }) ?? nil {
                Haptics.success(); message = "Raised " + cur.tidyShort(raised) + ", before the fee."
            } else { Haptics.warning(); message = "Nothing was raised." }
        }
    }
}
