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
            MoreHeader(glyph: Glyph.group, title: "Holding", blurb: "")
            // The holding's own management (its managing director): the holding has no staff list, so its roster lives here.
            CompanyTeamRoster(engine: engine, company: company)
            if let o {
                MoreBlock("Consolidated") {
                    VStack(alignment: .leading, spacing: 0) {
                        FigureStrip(items: figureItems(o, cur))
                        if o.groupCovered > 0 {
                            Text("Tax group: profits cover \(cur.tidyShort(o.groupCovered)) of sister companies' losses this year.").font(.caption2).foregroundStyle(Theme.gain).padding(.top, Theme.Space.s)
                        }
                    }
                }
                MoreBlock(title: "Companies held", card: false, trailing: { Text("\(o.subsidiaries.count)").textStyle(.caption, tint: Theme.inkFaint) }) {
                    VStack(spacing: Theme.Space.m) {
                        if o.subsidiaries.isEmpty {
                            Card(padding: Theme.Space.m, radius: Theme.Radius.row) {
                                Text("No companies under this holding yet. Dividends from companies under it are taxed far lower.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                            }
                        }
                        ForEach(o.subsidiaries, id: \.id) { k in heldCard(k, cur) }
                    }
                }
                if !free.isEmpty {
                    MoreBlock("Put a company under it", card: false) {
                        VStack(spacing: Theme.Space.m) {
                            ForEach(free, id: \.id) { c in
                                EntityCard {
                                    HStack(spacing: Theme.Space.m) {
                                        ThumbnailView(kind: .trade, key: c.type, size: 34, glyph: Glyph.home)
                                        Text(c.name).textStyle(.body, tint: Theme.ink, weight: .medium)
                                        Spacer()
                                        Button("Add…") { askAdd(c.id, c.name) }.buttonStyle(TinyButtonStyle())
                                    }
                                }
                            }
                            Text("Only limited companies can be held. Owning 90% or more in the same country puts them in one tax group.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
                HoldingFinanceManagerCard(engine: engine, company: company)
                MoreBlock("Move money") {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        AmountField(title: "Amount", currency: cur, amount: $amount)
                        HStack {
                            Button("Put money in") {
                                if amount > 0, store.act({ $0.putMoneyInto(companyID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Moved in.", tone: "good") }
                                else { Haptics.warning(); store.show(amount > 0 ? "You don't have that much available." : "Enter an amount first.", tone: "warn") }
                            }.buttonStyle(TinyButtonStyle())
                            Button("Treasury and dividends") { store.openGroupEntity(companyID: company.id, section: "money") }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
                        }
                        Text("Dividends flow up from the companies into the holding, and down to you. A holding that runs short of cash takes a dividend from a company by itself. The index fund and paying yourself are in the Group tab under Money.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            } else {
                Text("This holding company has no figures yet.").font(.caption).foregroundStyle(Theme.ivoryFaint)
            }
        }
        .confirmAction($pending)
    }

    private func heldCard(_ k: HoldingModel.Subsidiary, _ cur: Currency) -> some View {
        let tax: String = k.inTaxGroup ? " · tax group" : ""
        let line: String = "\(Int(k.ownership.rounded()))% · profit \(cur.tidyShort(k.profitTTM)) · cash \(cur.tidyShort(k.cash))\(tax)"
        return EntityCard {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ThumbnailView(kind: .trade, key: k.trade, size: 34, glyph: Glyph.home)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k.name).textStyle(.body, tint: Theme.ink, weight: .medium)
                        Text(line).textStyle(.caption, tint: Theme.inkFaint)
                    }
                    Spacer(minLength: 8)
                    Text(cur.tidyShort(k.share)).textStyle(.body, tint: Theme.ink, numeric: true, weight: .medium)
                }
                HStack {
                    Button("Release…") { askRelease(k.id, k.name) }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
                    Spacer()
                }
            }
        }
    }

    private func askRelease(_ id: Int, _ name: String) {
        pending = PendingAction(title: "Release \(name)?", message: "It leaves the holding and is owned by you directly again. It drops out of the tax group, and dividends to you are taxed at the normal rate.", button: "Release", destructive: true) {
            let ok: Bool = store.act { $0.releaseFromHolding(companyID: id) } ?? false
            Haptics.choose()
            store.show(ok ? "\(name) is owned by you directly again." : "It could not be released now.", tone: ok ? "good" : "warn")
        }
    }

    private func askAdd(_ id: Int, _ name: String) {
        pending = PendingAction(title: "Put \(name) under this holding?", message: "The holding takes over your shares in it. Dividends then flow into the holding at the lower rate, and at 90% or more in one country it joins the tax group.", button: "Put under holding", alwaysAsk: true) {
            if store.act({ $0.moveToHolding(companyID: id, holdingID: company.id) }) == true { Haptics.success(); store.show("\(name) is now held by \(company.name).", tone: "good") }
            else { Haptics.warning(); store.show("\(name) could not be moved under the holding.", tone: "warn") }
        }
    }
}

/// Register a new holding company and choose which companies it holds.
struct NewHoldingView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    @State private var name = ""
    @State private var picked: Set<Int> = []
    @State private var accountantID: Int?

    var body: some View {
        if let e = store.engine {
            let country = e.homeCountry
            let cur = e.homeCurrency
            let free = e.companiesForHolding
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    ZStack(alignment: .topTrailing) {
                        MoreHeader(glyph: Glyph.group, title: "A holding company", blurb: "Owns the shares of your other limited companies and collects their dividends in one place. Tap (i) for how it is taxed.")
                        HoldingInfoButton()
                    }
                    MoreBlock("Name") {
                        TextField("Holding company name", text: $name).textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(Theme.ivory)
                    }
                    MoreBlock("Which companies it holds") {
                        VStack(spacing: 0) {
                            if free.isEmpty { Text("No limited companies to hold yet. You can add them later.").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                            ForEach(Array(free.enumerated()), id: \.element.id) { n, c in
                                if n > 0 { Hairline() }
                                Button {
                                    if picked.contains(c.id) { picked.remove(c.id) } else { picked.insert(c.id) }
                                    Haptics.choose()
                                } label: {
                                    HStack {
                                        Text(c.name).textStyle(.body, tint: Theme.ink)
                                        Spacer()
                                        Image(systemName: picked.contains(c.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(picked.contains(c.id) ? Theme.gold : Theme.ivoryFaint)
                                    }.padding(.vertical, Theme.Space.m).contentShape(Rectangle())
                                }.buttonStyle(PressableStyle()).accessibilityValue(picked.contains(c.id) ? "Selected" : "Not selected")
                            }
                        }
                    }
                    AccountantStep(countryCode: e.state.homeCountryCode, currency: cur, accountantID: $accountantID)
                    MoreBlock("What it costs") {
                        VStack(spacing: 0) {
                            FlatRow(label: "Share capital", value: cur.tidyShort(country.shareCapitalMinimum), sub: "stays in the holding", rule: false)
                            FlatRow(label: "Registration", value: cur.tidyShort(country.registrationFee))
                        }
                    }
                    HStack { Button("Create the holding company") {
                        let r = store.act { $0.createHolding(name: name, companies: Array(picked), accountantID: accountantID) }
                        switch r {
                        case .success(let id)?: Haptics.success(); store.show("Registered.", tone: "good"); store.openCompany(id)
                        case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You need \(cur.tidyShort(country.shareCapitalMinimum + country.registrationFee)) in your account.", tone: "warn")
                        default: store.show("Not possible.", tone: "warn")
                        }
                    }.buttonStyle(TinyButtonStyle()); Spacer() }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.page)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .appScreen(title: "New holding company", subtitle: "Register it and choose what it holds.")
        }
    }
}
