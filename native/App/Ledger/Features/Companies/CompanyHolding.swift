import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A holding company's own section: what it is worth, the companies under it, the index fund, and moving money.
struct CompanyHolding: View {
    private func figureItems(_ o: HoldingModel.Consolidated, _ cur: Currency) -> [KeyFigures.Item] {
        let profitTint: Color = o.profitTTM < 0 ? Theme.loss : Theme.ivory
        return [
            .init(label: "Holding value", value: cur.tidyShort(o.holdingValue)),
            .init(label: "Companies", value: cur.tidyShort(o.companiesValue), sub: "your share"),
            .init(label: "Index fund", value: cur.tidyShort(o.indexFund)),
            .init(label: "Revenue 12 mo", value: cur.tidyShort(o.revenueTTM), sub: "your share"),
            .init(label: "Profit 12 mo", value: cur.tidyShort(o.profitTTM), tint: profitTint, sub: "your share"),
            .init(label: "Cash in group", value: cur.tidyShort(o.cashInGroup)),
        ]
    }

    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        let o = engine.holdingOverview(companyID: company.id)
        let free = engine.companiesForHolding
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            // The holding's own management (its managing director): the holding has no staff list, so its roster lives here.
            CompanyTeamRoster(engine: engine, company: company)
            if let o {
                LedgerSection("Consolidated") {
                    VStack(alignment: .leading, spacing: 0) {
                        KeyFigures(items: figureItems(o, cur))
                        if o.groupCovered > 0 {
                            Text("Tax group: profits cover \(cur.tidyShort(o.groupCovered)) of sister companies' losses this year.").font(.caption2).foregroundStyle(Theme.gain).padding(.top, 8)
                        }
                    }
                }
                LedgerSection(title: "Companies held", trailing: { Text("\(o.subsidiaries.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                    VStack(spacing: 0) {
                        if o.subsidiaries.isEmpty { Text("No companies under this holding yet. Dividends from companies under it are taxed far lower.").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                        ForEach(Array(o.subsidiaries.enumerated()), id: \.element.id) { n, k in
                            if n > 0 { Hairline() }
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(k.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                    Text("\(Int(k.ownership.rounded()))% · profit \(cur.tidyShort(k.profitTTM)) · cash \(cur.tidyShort(k.cash))\(k.inTaxGroup ? " · tax group" : "")")
                                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(cur.tidyShort(k.share)).font(.system(size: 13.5).monospacedDigit())
                                    Button("Release…") { askRelease(k.id, k.name) }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                                }
                            }.padding(.vertical, 9)
                        }
                    }
                }
                if !free.isEmpty {
                    LedgerSection("Put a company under it") {
                        VStack(spacing: 0) {
                            ForEach(Array(free.enumerated()), id: \.element.id) { n, c in
                                if n > 0 { Hairline() }
                                HStack {
                                    Text(c.name).font(.system(size: 13.5))
                                    Spacer()
                                    Button("Add…") { askAdd(c.id, c.name) }.buttonStyle(QuietButtonStyle())
                                }.padding(.vertical, 6)
                            }
                            Text("Only limited companies can be held. Owning 90% or more in the same country puts them in one tax group.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                        }
                    }
                }
                HoldingFinanceManagerCard(engine: engine, company: company)
                LedgerSection("Move money") {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        AmountField(title: "Amount", currency: cur, amount: $amount)
                        HStack {
                            Button("Put money in") {
                                if amount > 0, store.act({ $0.putMoneyInto(companyID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Moved in.", tone: "good") }
                                else { Haptics.warning(); store.show(amount > 0 ? "You don't have that much available." : "Enter an amount first.", tone: "warn") }
                            }.buttonStyle(QuietButtonStyle())
                            Button("Invest in index") {
                                if amount > 0, store.act({ $0.holdingInvest(holdingID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Invested.", tone: "good") }
                                else { Haptics.warning(); store.show(amount > 0 ? "Not enough cash in the holding." : "Enter an amount first.", tone: "warn") }
                            }.buttonStyle(QuietButtonStyle())
                            Button("Sell index") {
                                if amount > 0, store.act({ $0.holdingDivest(holdingID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Sold.", tone: "good") }
                                else { Haptics.warning(); store.show(amount > 0 ? "Nothing to sell." : "Enter an amount first.", tone: "warn") }
                            }.buttonStyle(QuietButtonStyle())
                        }
                        Button("Pay a dividend to me…") { askDividend(cur) }.buttonStyle(QuietButtonStyle())
                        Text("Dividends flow up from the companies into the holding, and down to you. A holding that runs short of cash takes a dividend from a company by itself. The index fund costs 0.66% to sell.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            } else {
                Text("This holding company has no figures yet.").font(.caption).foregroundStyle(Theme.ivoryFaint)
            }
        }
        .confirmAction($pending)
    }

    private func askRelease(_ id: Int, _ name: String) {
        pending = PendingAction(title: "Release \(name)?", message: "It leaves the holding and is owned by you directly again. It drops out of the tax group, and dividends to you are taxed at the normal rate.", button: "Release", destructive: true) {
            let ok: Bool = store.act { $0.releaseFromHolding(companyID: id) } ?? false
            Haptics.choose()
            store.show(ok ? "\(name) is owned by you directly again." : "It could not be released now.", tone: ok ? "good" : "warn")
        }
    }

    private func askAdd(_ id: Int, _ name: String) {
        pending = PendingAction(title: "Put \(name) under this holding?", message: "The holding takes over your shares in it. Dividends then flow into the holding at the lower rate, and at 90% or more in one country it joins the tax group.", button: "Put under holding") {
            if store.act({ $0.moveToHolding(companyID: id, holdingID: company.id) }) == true { Haptics.success(); store.show("\(name) is now held by \(company.name).", tone: "good") }
            else { Haptics.warning(); store.show("\(name) could not be moved under the holding.", tone: "warn") }
        }
    }

    private func askDividend(_ cur: Currency) {
        let amt: Double = amount
        guard amt > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        pending = PendingAction(title: "Pay \(cur.tidyShort(amt)) to yourself?", message: "It comes out of the holding's retained profits and is taxed as your income. It cannot be paid back in as a dividend.", button: "Pay dividend", amount: amt, currency: cur) {
            switch store.act({ $0.payDividend(companyID: company.id, amount: amt) }) {
            case .ok?: Haptics.success(); store.show("Dividend of \(cur.tidyShort(amt)) paid.", tone: "good")
            case .noRetainedProfit?: Haptics.warning(); store.show("There are no retained profits to pay out.", tone: "warn")
            default: Haptics.warning(); store.show("Not enough cash in the holding.", tone: "warn")
            }
        }
    }
}

/// Register a new holding company and choose which companies it holds.
struct NewHoldingView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var picked: Set<Int> = []

    var body: some View {
        if let e = store.engine {
            let country = e.homeCountry
            let cur = e.homeCurrency
            let free = e.companiesForHolding
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("A holding company owns the shares of your other limited companies. Dividends into it are taxed far lower, it can invest spare cash, and companies in one country that it owns 90% or more of share profits and losses for tax.")
                        .font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                    LedgerSection("Name") {
                        TextField("Holding company name", text: $name).textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(Theme.ivory)
                    }
                    LedgerSection("Which companies it holds") {
                        VStack(spacing: 0) {
                            if free.isEmpty { Text("No limited companies to hold yet. You can add them later.").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                            ForEach(Array(free.enumerated()), id: \.element.id) { n, c in
                                if n > 0 { Hairline() }
                                Button {
                                    if picked.contains(c.id) { picked.remove(c.id) } else { picked.insert(c.id) }
                                    Haptics.choose()
                                } label: {
                                    HStack {
                                        Text(c.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                        Spacer()
                                        Image(systemName: picked.contains(c.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(picked.contains(c.id) ? Theme.gold : Theme.ivoryFaint)
                                    }.padding(.vertical, 10).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    LedgerSection("What it costs") {
                        VStack(spacing: 0) {
                            FlatRow(label: "Share capital", value: cur.tidyShort(country.shareCapitalMinimum), sub: "stays in the holding", rule: false)
                            FlatRow(label: "Registration", value: cur.tidyShort(country.registrationFee))
                        }
                    }
                    Button("Create the holding company") {
                        let r = store.act { $0.createHolding(name: name, companies: Array(picked)) }
                        switch r {
                        case .success(let id)?: Haptics.success(); store.show("Registered.", tone: "good"); store.openCompany(id)
                        case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You need \(cur.tidyShort(country.shareCapitalMinimum + country.registrationFee)) in your account.", tone: "warn")
                        default: store.show("Not possible.", tone: "warn")
                        }
                    }.buttonStyle(QuietButtonStyle())
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("New holding company")
        }
    }
}
