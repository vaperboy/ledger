import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Buying a rival, step two: after the owner agrees a price, what the business should become. For each choice the cash needed, what you
/// take on and what changes in control, before anything is paid. Figures come from `acquisitionPlan`, which repeats the checks of the purchase.
struct AcquisitionSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var rivalID: Int
    var price: Double
    var choose: (AcquisitionPlan.Kind) -> Void
    @State private var selected: AcquisitionPlan.Kind = .own
    @State private var pending: PendingAction?

    private func title(_ k: AcquisitionPlan.Kind) -> String {
        switch k {
        case .own: return "Its own company"
        case .branch: return "Your branch"
        case .merge: return "Merge into your company"
        case .shut: return "Close it down"
        case .franchiseOldOwner: return "Franchise office, owner stays"
        case .franchiseNewOwner: return "Franchise office, new franchisee"
        case .ownBank: return "Its own company, 70% from your bank"
        }
    }

    private func effects(_ k: AcquisitionPlan.Kind, _ co: Company, _ r: Rivals.Rival) -> (gets: String, control: String, risk: String) {
        switch k {
        case .own: return ("A separate limited company with \(r.name)'s customers and goodwill, set up and open from day one.", "You own it fully and run it yourself or through a manager. It has its own books, staff and loans.", "Its own running costs start at once; it is not yet profitable by itself.")
        case .branch: return ("Carries your name \(co.name) from day one, with the rival's customers.", "Run as a site of \(co.name) with its own books; your brand covers it.", "A weak site hurts the name of the whole brand.")
        case .merge: return ("Their customers come over and some of their staff join \(co.name).", "The rival ceases to exist; \(co.name) simply grows. No separate company to manage.", "Hired staff add wages to \(co.name); the extra 8% is paid now.")
        case .shut: return ("One competitor less in the market.", "The rival closes and its staff go. You get nothing but the empty field.", "A large market share (over a third) can draw a fine from the competition authority; the extra 12% is paid now.")
        case .franchiseOldOwner: return ("Becomes a \(co.name) franchise office led by its old owner.", "You earn franchise fees and royalties; the owner runs it day to day under your rules.", "You control it less than a branch; a poor franchisee can hurt the brand.")
        case .franchiseNewOwner: return ("Becomes a \(co.name) franchise office led by a new franchisee, who pays you about half of the price back.", "You earn fees and royalties; the new franchisee runs it.", "The franchisee's skill is unknown; the pay-back is somewhere around 45 to 60% of the price.")
        case .ownBank: return ("The same as an own company, but most of the price is lent to you by your bank.", "You are the borrower; the loan is a personal debt of 8 years at the bank rate plus your credit margin and a point.", "The instalments come out of your own pocket whatever the business earns.")
        }
    }

    private func ownsCompany(_ k: AcquisitionPlan.Kind) -> Bool { k == .own || k == .branch || k == .ownBank }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let co = e.state.company(companyID), let r = Rivals.rivals(e.state, for: co).first(where: { $0.id == rivalID }), let plan = e.acquisitionPlan(companyID: companyID, rivalID: rivalID, price: price) {
                    let cur = e.currency(for: co)
                    let ch = plan.choices.first { $0.kind == selected } ?? plan.choices[0]
                    let fx = effects(ch.kind, co, r)
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Buy \(r.name)").font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                            Text("Agreed price \(cur.tidyDisplay(price)). Choose what it becomes.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                        }
                        LedgerSection("What it becomes") {
                            VStack(spacing: 0) {
                                ForEach(Array(plan.choices.enumerated()), id: \.element.id) { n, c in
                                    if n > 0 { Hairline() }
                                    Button { selected = c.kind } label: {
                                        HStack(spacing: Theme.Space.m) {
                                            Image(systemName: selected == c.kind ? "checkmark.circle.fill" : "circle").foregroundStyle(selected == c.kind ? Theme.gold : Theme.ivoryFaint)
                                            Text(title(c.kind)).font(.system(size: 13.5)).foregroundStyle(c.affordable ? Theme.ivory : Theme.ivoryFaint)
                                            Spacer()
                                            Text(c.affordable ? cur.tidyShort(c.cashNeeded) : "Short of cash").font(.system(size: 12).monospacedDigit()).foregroundStyle(c.affordable ? Theme.ivoryMuted : Theme.loss)
                                        }.padding(.vertical, 9).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        costs(plan, ch, price: price, cur: cur)
                        LedgerSection("What changes") {
                            VStack(alignment: .leading, spacing: 8) {
                                labelled("You get", fx.gets)
                                labelled("Control", fx.control)
                                labelled("Risk", fx.risk)
                                if plan.hiddenBillRisk { labelled("In trouble", "\(r.name) is in money trouble. Unpaid supplier bills or a tax claim from before may surface after you buy, and they become yours.") }
                            }
                        }
                        Button("Buy for \(cur.tidyShort(price))") {
                            pending = PendingAction(title: "\(title(ch.kind)): buy \(r.name)?", message: "\(cur.tidyDisplay(ch.cashNeeded)) needed in cash\(ch.loan > 0 ? ", of which \(cur.tidyDisplay(ch.loan)) borrowed from your bank" : ""). This cannot be undone.", button: "Buy it") {
                                let k = ch.kind; dismiss(); choose(k)
                            }
                        }.buttonStyle(QuietButtonStyle()).disabled(!ch.affordable)
                        if !ch.affordable { Text("You do not have enough cash for this choice. Pick another, or come back with more.").font(.caption).foregroundStyle(Theme.caution) }
                    }
                    .padding(Theme.Space.margin)
                } else {
                    Text("This rival is gone.").foregroundStyle(Theme.ivoryMuted).padding()
                }
            }
            .ledgerBackground()
            .navigationTitle("Acquisition").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
            .confirmAction($pending)
        }
    }

    @ViewBuilder private func costs(_ plan: AcquisitionPlan, _ ch: AcquisitionPlan.Choice, price: Double, cur: Currency) -> some View {
        let owns: Bool = ownsCompany(ch.kind)
        let extraLabel: String = owns ? "Set-up money for the new company" : "Extra cost of this choice"
        let loanSub: String = "\(cur.tidyShort(ch.loanMonthly)) a month for 8 years at \(Currency.percent(ch.loanRate, decimals: 2))"
        let needSub: String = owns ? "includes a \(cur.tidyShort(plan.reserve)) reserve the purchase insists on" : ""
        let have: Double = owns ? plan.liquid : plan.cash
        let haveSub: String = owns ? "cash and savings" : "current account"
        LedgerSection("Cash and costs") {
            VStack(spacing: 0) {
                FlatRow(label: "Price to the owner", value: cur.tidyShort(price), rule: false)
                if ch.extraCost > 0 { FlatRow(label: extraLabel, value: cur.tidyShort(ch.extraCost)) }
                if ch.loan > 0 { FlatRow(label: "Loan from your bank", value: "−" + cur.tidyShort(ch.loan), sub: loanSub, tint: Theme.caution) }
                FlatRow(label: "Cash you need", value: cur.tidyShort(ch.cashNeeded), sub: needSub, tint: ch.affordable ? Theme.ivory : Theme.loss)
                FlatRow(label: "You have", value: cur.tidyShort(have), sub: haveSub)
            }
        }
    }

    private func labelled(_ head: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(head).capsLabel(Theme.ivoryFaint)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
        }
    }
}
