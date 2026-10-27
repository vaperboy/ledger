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
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let id = company.id
        CardSection(title: "Owners and shares", trailing: { Text("You own \(Int(company.ownership.rounded()))%").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                let owners = engine.owners(companyID: id)
                if owners.isEmpty { Text("You are the only owner.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                ForEach(owners) { h in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.name).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                                Text("\(Shareholders.profileNames[h.profile] ?? "") · mood: \(h.moodWord)").font(.caption).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Text(String(format: "%.1f%%", h.pct)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory)
                        }
                        if let p = engine.buyBackPrice(companyID: id, holder: h.name) {
                            Button("Buy back for " + cur.tidyShort(p) + "…") {
                                pending = PendingAction(title: "Buy back \(h.name)'s \(String(format: "%.1f", h.pct))%?", message: "\(cur.tidyDisplay(p)) from your own cash. Their votes and dividends come back to you.", button: "Buy back", destructive: true) {
                                    let ok = store.act { $0.buyBackStake(companyID: id, holder: h.name) } ?? false
                                    if !ok { Haptics.warning() }
                                    store.show(ok ? "You bought back \(h.name)'s stake for \(cur.tidyShort(p))." : "Not enough cash, or they will not sell now.", tone: ok ? "good" : "warn")
                                }
                            }.buttonStyle(QuietButtonStyle())
                        }
                    }.padding(.vertical, 6)
                    CardLine()
                }
                if company.form == .limited && company.type != "hold" {
                    Text("Dividend policy").font(.system(size: 13)).foregroundStyle(Theme.ivory)
                    WrapRow {
                        ForEach(Shareholders.policies, id: \.self) { p in
                            let on = engine.dividendPolicy(companyID: id) == p
                            Button((on ? "✓ " : "") + (Shareholders.policyNames[p] ?? p)) { store.settle(store.act { $0.setDividendPolicy(companyID: id, policy: p) }, "Dividend policy: \(Shareholders.policyNames[p] ?? p).", same: "That is already the dividend policy.") }
                                .buttonStyle(QuietButtonStyle(tint: on ? Theme.gold : Theme.ivoryMuted))
                        }
                    }
                    CardLine()
                    Text("Investors: " + engine.investorInterest(companyID: id).word).font(.caption).foregroundStyle(Theme.ivoryMuted)
                    WrapRow {
                        Button("Pitch for " + cur.tidyShort(engine.suggestedFundingAmount(companyID: id))) {
                            let amount = engine.suggestedFundingAmount(companyID: id)
                            if let r = store.act({ $0.pitchToInvestors(companyID: id, amount: amount) }) {
                                switch r {
                                case .none: Haptics.warning(); store.show("No investor bit.", tone: "warn")
                                case .tooSoon(let w): Haptics.warning(); store.show("Try again in \(w.weeksText).", tone: "warn")
                                case .notLimited: Haptics.warning(); store.show("Only a limited company can pitch to investors.", tone: "warn")
                                case .offers(let n): Haptics.success(); store.show("\(n) \(n == 1 ? "offer" : "offers") came in: see below. Nothing is taken until you accept.", tone: "good")
                                }
                            }
                        }.buttonStyle(QuietButtonStyle())
                        ForEach(engine.shareOffers(companyID: id).prefix(3), id: \.pct) { o in
                            Button("Sell \(o.pct)% for " + cur.tidyShort(o.secondary) + "…") {
                                pending = PendingAction(title: "Sell \(o.pct)% of your shares?", message: "About \(cur.tidyDisplay(o.secondary)) comes to you (gains are taxed). The buyer gets votes and a share of every dividend; your control falls. This cannot be undone.", button: "Sell", destructive: true) {
                                    switch store.act({ $0.sellPrivateShares(companyID: id, percent: Double(o.pct), mode: "secondary") }) {
                                    case .ok(let v)?: Haptics.success(); store.show("Sold for \(cur.tidyShort(v)).", tone: "good")
                                    case .notLimited?: Haptics.warning(); store.show("Only a limited company can sell shares.", tone: "warn")
                                    case .tooMuch?: Haptics.warning(); store.show("That would cost you control.", tone: "warn")
                                    case nil: break
                                    default: Haptics.warning(); store.show("The owners blocked the sale.", tone: "warn")
                                    }
                                }
                            }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    ForEach(engine.fundingOffers(companyID: id)) { o in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(o.name): \(cur.tidyShort(o.amount)) for \(Int(o.pct.rounded()))% · \(o.says)").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            WrapRow {
                                Button("Accept") {
                                    pending = PendingAction(title: "Take \(cur.tidyShort(o.amount)) for \(Int(o.pct.rounded()))%?", message: "The money goes into the company. \(o.name) becomes an owner with votes and a share of profits; your share falls. This cannot be undone.", button: "Accept", destructive: true) {
                                        let ok = store.act { $0.acceptFundingOffer(companyID: id, index: o.id) } ?? false
                                        if !ok { Haptics.warning() } else { Haptics.success() }
                                        store.show(ok ? "\(cur.tidyShort(o.amount)) is in the company; \(o.name) now owns \(Int(o.pct.rounded()))%." : "The offer has gone.", tone: ok ? "good" : "warn")
                                    }
                                }.buttonStyle(QuietButtonStyle())
                                if !o.countered { Button("Counter") { store.settle(store.act { $0.counterFundingOffer(companyID: id, index: o.id) }, "Counter sent. Their answer replaces the offer.", same: "That offer has gone or was already countered.") }.buttonStyle(QuietButtonStyle()) }
                                Button("Decline") { store.settle(store.act { $0.declineFundingOffer(companyID: id, index: o.id) }, "Declined.", same: "That offer had already gone.") }.buttonStyle(QuietButtonStyle())
                            }
                        }
                    }
                    Text("Sell part of your shares").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    WrapRow {
                        ForEach([10, 25, 34, 49], id: \.self) { p in
                            Button("\(p)%") {
                                pending = PendingAction(title: "Look for a buyer for \(p)%?", message: "Buyers make offers over the coming weeks; nothing is sold until you accept one.", button: "List \(p)%") {
                                    let ok = store.act { $0.listSharesForSale(companyID: id, percent: p, broker: false) } ?? false
                                    if !ok { Haptics.warning() }
                                    store.show(ok ? "\(p)% listed. Offers arrive in the Inbox." : "Not possible now: it may already be listed, or would cost you control.", tone: ok ? "good" : "warn")
                                }
                            }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }
                if company.type == "hold" {
                    if engine.isListed(companyID: id) { HStack(spacing: 6) { GlyphView(glyph: Glyph.check, size: 14, weight: 1.6, tint: Theme.gain); Text("Listed on the exchange").font(.caption).foregroundStyle(Theme.gain) } }
                    else {
                        Button("Go public · fee " + cur.tidyShort(engine.listingFee) + "…") {
                            pending = PendingAction(title: "List \(company.name) on the exchange?", message: "A bank takes the holding public for a fee of \(cur.tidyDisplay(engine.listingFee)). The shares can then be traded and raised on.", button: "Go public", destructive: true) {
                                switch store.act({ $0.listHoldingOnExchange(companyID: id) }) {
                                case .ok?: Haptics.success(); store.show("\(company.name) is listed on the exchange.", tone: "good")
                                case .alreadyListed?: store.show("It is already listed.", tone: "n")
                                case .tooSmall(let n)?: Haptics.warning(); store.show("Needs a value of at least " + cur.tidyShort(n) + ".", tone: "warn")
                                case .notEnoughMoney(let n)?: Haptics.warning(); store.show("The fee needs " + cur.tidyShort(n) + ".", tone: "warn")
                                case .notAHolding?: store.show("Only a holding company can go public.", tone: "warn")
                                case nil: break
                                }
                            }
                        }.buttonStyle(QuietButtonStyle())
                    }
                    WrapRow {
                        let g = engine.holdingValue(companyID: id) * 0.1
                        Button("Raise " + cur.tidyShort(g) + " privately") { confirmRaise(g, publicOffering: false, cur: cur) }.buttonStyle(QuietButtonStyle())
                        if engine.isListed(companyID: id) { Button("Raise on the exchange") { confirmRaise(g, publicOffering: true, cur: cur) }.buttonStyle(QuietButtonStyle()) }
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
                                button: "Raise", destructive: true) {
            if let raised = store.act({ $0.raiseMoneyForHolding(holdingID: id, goal: goal, publicOffering: publicOffering) }) ?? nil {
                Haptics.success(); store.show("Raised " + cur.tidyShort(raised) + ", before the fee.", tone: "good")
            } else { Haptics.warning(); store.show("Nothing was raised.", tone: "warn") }
        }
    }
}
