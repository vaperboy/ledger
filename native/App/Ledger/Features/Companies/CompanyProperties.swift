import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The properties section of a rental company: what it owns, what is for sale, tenants and buyers.
/// Residential rentals, commercial property and parking/self-storage share it. Flat rows between hairlines, no boxes.
struct CompanyProperties: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var loanToValue = 0.4
    @State private var openTenants: Int? = nil
    @State private var pendingBuy: PropertyListing? = nil
    @State private var pendingSell: PropertyRow? = nil

    var body: some View {
        let cur = engine.currency(for: company)
        if let pf = engine.propertyPortfolio(companyID: company.id) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                figures(pf, cur)
                owned(pf, cur)
                forSale(pf, cur)
                Text("Housing prices rise and fall with the economy and with interest rates, and a mortgage magnifies both. Rent and vacancy follow the rent you set under Operations, the condition of the buildings, and whether you have caretakers and property managers.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Figures

    private func figures(_ pf: PropertyPortfolio, _ cur: Currency) -> some View {
        KeyFigures(items: [
            .init(label: "Property value", value: cur.short(pf.totalValue), sub: "\(pf.rows.count) \(pf.rows.count == 1 ? "property" : "properties")"),
            .init(label: "Rent a week", value: cur.short(pf.weeklyRent), sub: pf.totalValue > 0 ? "gross yield " + Currency.percent(pf.grossYield, decimals: 1) : ""),
            .init(label: "Let", value: Currency.percent(pf.occupancy, decimals: 0), tint: pf.occupancy < 0.8 ? Theme.caution : Theme.ivory, sub: "\(Int(pf.totalUnits.rounded())) \(pf.unitWord)"),
            .init(label: "Mortgages", value: cur.short(pf.mortgages), tint: pf.mortgages > 0 ? Theme.loss : Theme.ivory),
            .init(label: "Gain on cost", value: cur.short(pf.gainOnCost), tint: Theme.change(pf.gainOnCost), sub: "not profit until sold"),
            .init(label: "Staff cover", value: Currency.percent(min(1, pf.staffCover), decimals: 0), tint: pf.staffCover < 0.8 ? Theme.caution : Theme.ivory, sub: "caretakers, managers"),
        ])
    }

    // MARK: Owned

    private func owned(_ pf: PropertyPortfolio, _ cur: Currency) -> some View {
        LedgerSection("Properties") {
            if pf.rows.isEmpty {
                Text("No property yet. Buy one below to start earning rent.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
            }
            VStack(spacing: 0) {
                ForEach(Array(pf.rows.enumerated()), id: \.element.id) { n, p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory).lineLimit(2)
                                Text("\(Int(p.units.rounded())) \(pf.unitWord) · vacancy \(Currency.percent(p.vacancy, decimals: 0)) · \(conditionWord(p.condition))")
                                    .font(.caption).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(cur.short(p.value)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                                Text("bought " + cur.short(p.cost)).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            }
                        }
                        HStack(spacing: 14) {
                            Text("Rent " + cur.short(p.weeklyRent) + " a week").font(.caption).foregroundStyle(Theme.ivoryMuted)
                            if p.mortgage > 0 { Text("Mortgage " + cur.short(p.mortgage)).font(.caption).foregroundStyle(Theme.loss) }
                        }
                        HStack(spacing: 18) {
                            Button("Renovate") { renovate(p) }.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                            if p.kind == "com" {
                                Button(openTenants == p.id ? "Hide tenants" : "Tenants and buyers") { withAnimation(.snappy(duration: 0.2)) { openTenants = openTenants == p.id ? nil : p.id } }
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                            }
                            Button("Sell") { pendingSell = p }.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.loss)
                            Spacer()
                        }.buttonStyle(.plain)
                        if openTenants == p.id { tenants(p, cur) }
                    }
                    .padding(.vertical, 10)
                    if n < pf.rows.count - 1 { Hairline() }
                }
            }
        }
        .confirmationDialog("Sell this property?", isPresented: Binding(get: { pendingSell != nil }, set: { if !$0 { pendingSell = nil } }), presenting: pendingSell) { p in
            Button("Sell for about " + cur.short(p.value * 0.975) + (p.mortgage > 0 ? ", repay the mortgage" : ""), role: .destructive) { sell(p) }
            Button("Keep it", role: .cancel) {}
        } message: { p in
            Text("Selling on the market costs 2.5% of the value. \(p.name)")
        }
    }

    private func tenants(_ p: PropertyRow, _ cur: Currency) -> some View {
        let offers = engine.tenantOffers(companyID: company.id, propertyID: p.id)
        return VStack(alignment: .leading, spacing: 6) {
            if !p.leases.isEmpty {
                Text("Current tenants").capsLabel(Theme.ivoryFaint)
                ForEach(Array(p.leases.enumerated()), id: \.offset) { _, l in
                    HStack {
                        Text("\(l.tenant) · \(Int(l.squareMetres)) m2").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        Spacer()
                        Text(cur.short(l.weeklyRent) + " a week · \(l.weeksLeft / 52) y left").font(.caption.monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            if offers.isEmpty {
                Text("No space free to let, or nobody interested right now. Offers change every month.").font(.caption).foregroundStyle(Theme.ivoryFaint)
            } else {
                Text("Wants to lease").capsLabel(Theme.ivoryFaint)
                ForEach(offers) { o in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text("\(Int(o.squareMetres)) m2 · \(cur.short(o.squareMetres * o.weeklyRentPerM2)) a week · \(o.years) year lease").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer()
                        Button("Lease") { lease(p, o) }.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
                    }
                }
                Text("Wants to buy the building").capsLabel(Theme.ivoryFaint).padding(.top, 4)
                ForEach(offers.prefix(2)) { o in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text("Offers " + cur.short(p.value * o.buyMultiple) + " (\(Currency.percent(o.buyMultiple - 1, decimals: 0)) over value)").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer()
                        Button("Sell to them") { sellBuilding(p, o) }.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.loss).buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.leading, 12).padding(.top, 4)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 0.5) }
    }

    // MARK: For sale

    private func forSale(_ pf: PropertyPortfolio, _ cur: Currency) -> some View {
        let listings = engine.propertyListings(companyID: company.id)
        return LedgerSection(title: "For sale in \(engine.cityName(company))", trailing: { Text("new list every month").font(.caption2).foregroundStyle(Theme.ivoryFaint) }) {
            Text("Mortgage").font(.caption).foregroundStyle(Theme.ivoryMuted)
            SectionTabs(items: [0.0, 0.4, 0.6], title: { $0 == 0 ? "No loan" : Currency.percent($0, decimals: 0) + " loan" }, selection: $loanToValue)
                .padding(.horizontal, -Theme.Space.margin)
            Text("Rate \(Currency.percent(engine.state.economy.policyRate, decimals: 1)) plus a margin. Rents that return less than the loan costs make a mortgage lose money until prices rise.")
                .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            VStack(spacing: 0) {
                ForEach(Array(listings.enumerated()), id: \.element.id) { n, L in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory).lineLimit(2)
                            Text("Rent \(cur.short(L.rentPerUnit)) a week each · gross yield \(Currency.percent(L.grossYield, decimals: 1)) · \(conditionWord(L.condition))")
                                .font(.caption).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(cur.short(L.price)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                            Button("Buy") { pendingBuy = L }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold).buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 9)
                    if n < listings.count - 1 { Hairline() }
                }
            }
        }
        .confirmationDialog("Buy this property?", isPresented: Binding(get: { pendingBuy != nil }, set: { if !$0 { pendingBuy = nil } }), presenting: pendingBuy) { L in
            Button("Buy for " + cur.short(L.price) + " plus 2.5% costs, \(Currency.percent(loanToValue, decimals: 0)) loan") { buy(L) }
            Button("Cancel", role: .cancel) {}
        } message: { L in
            Text(L.name)
        }
    }

    // MARK: Actions

    private func buy(_ L: PropertyListing) {
        switch store.act({ $0.buyProperty(companyID: company.id, listingIndex: L.index, loanToValue: loanToValue) }) {
        case .ok?: Haptics.success(); store.show("Property bought.", tone: "good")
        case .notEnoughCash?: Haptics.warning(); store.show("The company needs more cash for the deposit and costs. Put money in under Finances.", tone: "warn")
        case .loanDeclined?: Haptics.warning(); store.show("The bank will not lend that much.", tone: "warn")
        default: break
        }
    }

    private func sell(_ p: PropertyRow) {
        if let net = store.act({ $0.sellProperty(companyID: company.id, propertyID: p.id) }), net > 0 { Haptics.success(); store.show("Sold.", tone: "good") }
    }

    private func renovate(_ p: PropertyRow) {
        switch store.act({ $0.renovateProperty(companyID: company.id, propertyID: p.id) }) {
        case .ok?: Haptics.success(); store.show("Renovated: better condition, higher value.", tone: "good")
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company.", tone: "warn")
        default: break
        }
    }

    private func lease(_ p: PropertyRow, _ o: TenantOffer) {
        if store.act({ $0.leaseSpace(companyID: company.id, propertyID: p.id, offerIndex: o.index) }) == true { Haptics.success(); store.show("Leased.", tone: "good") }
    }

    private func sellBuilding(_ p: PropertyRow, _ o: TenantOffer) {
        if let net = store.act({ $0.sellBuilding(companyID: company.id, propertyID: p.id, offerIndex: o.index) }), net > 0 {
            openTenants = nil; Haptics.success(); store.show("Sold.", tone: "good")
        } else { store.show("A company of yours rents space there. End that first.", tone: "warn") }
    }

    private func conditionWord(_ c: Double) -> String {
        c >= 0.9 ? "like new" : c >= 0.7 ? "good condition" : c >= 0.5 ? "worn" : c >= 0.3 ? "poor condition" : "barely usable"
    }
}
