import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A holding company's own section: what it is worth, the companies under it, the index fund, and moving money.
struct CompanyHolding: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var amount = 0.0

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
                        KeyFigures(items: [
                            .init(label: "Holding value", value: cur.tidyShort(o.holdingValue)),
                            .init(label: "Companies", value: cur.tidyShort(o.companiesValue), sub: "your share"),
                            .init(label: "Index fund", value: cur.tidyShort(o.indexFund)),
                            .init(label: "Revenue 12 mo", value: cur.tidyShort(o.revenueTTM), sub: "your share"),
                            .init(label: "Profit 12 mo", value: cur.tidyShort(o.profitTTM), tint: o.profitTTM < 0 ? Theme.loss : Theme.ivory, sub: "your share"),
                            .init(label: "Cash in group", value: cur.tidyShort(o.cashInGroup)),
                        ])
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
                                    Button("Release") {
                                        let ok = store.act { $0.releaseFromHolding(companyID: k.id) } ?? false
                                        Haptics.choose(); store.show(ok ? "Released: it is owned by you directly again." : "It could not be released now.", tone: ok ? "good" : "warn")
                                    }.font(.system(size: 11.5)).foregroundStyle(Theme.gold).buttonStyle(.plain)
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
                                    Button("Add") {
                                        if store.act({ $0.moveToHolding(companyID: c.id, holdingID: company.id) }) == true { Haptics.success() }
                                    }.buttonStyle(QuietButtonStyle())
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
                                else { Haptics.warning(); store.show("You don't have that much available.", tone: "warn") }
                            }.buttonStyle(QuietButtonStyle())
                            Button("Invest in index") {
                                if amount > 0, store.act({ $0.holdingInvest(holdingID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Invested.", tone: "good") }
                                else { store.show("Not enough cash in the holding.", tone: "warn") }
                            }.buttonStyle(QuietButtonStyle())
                            Button("Sell index") {
                                if amount > 0, store.act({ $0.holdingDivest(holdingID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Sold.", tone: "good") }
                                else { store.show("Nothing to sell.", tone: "warn") }
                            }.buttonStyle(QuietButtonStyle())
                        }
                        Button("Pay a dividend to me") {
                            switch store.act({ $0.payDividend(companyID: company.id, amount: amount) }) {
                            case .ok?: Haptics.success(); store.show("Dividend paid.", tone: "good")
                            case .noRetainedProfit?: store.show("There are no retained profits to pay out.", tone: "warn")
                            default: store.show("Not enough cash in the holding.", tone: "warn")
                            }
                        }.buttonStyle(QuietButtonStyle())
                        Text("Dividends flow up from the companies into the holding, and down to you. A holding that runs short of cash takes a dividend from a company by itself. The index fund costs 0.66% to sell.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
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
                    }.buttonStyle(GoldButtonStyle())
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("New holding company")
        }
    }
}
