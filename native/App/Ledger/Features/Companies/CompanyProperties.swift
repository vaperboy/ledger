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
    @State private var pending: PendingAction? = nil
    @State private var detailID: Int? = nil

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
        let count: String = "\(pf.rows.count) \(pf.rows.count == 1 ? "property" : "properties")"
        let yield: String = pf.totalValue > 0 ? "gross yield " + Currency.percent(pf.grossYield, decimals: 1) : ""
        let units: String = "\(Int(pf.totalUnits.rounded())) \(pf.unitWord)"
        let footer: String = [count, yield, units, "gain on cost is not profit until sold"].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        let letTint: Color = pf.occupancy < 0.8 ? Theme.caution : Theme.ivory
        let coverTint: Color = pf.staffCover < 0.8 ? Theme.caution : Theme.ivory
        let mortgageTint: Color = pf.mortgages > 0 ? Theme.loss : Theme.ivory
        let first: [StatStrip.Cell] = [
            StatStrip.Cell(label: "Property value", value: cur.tidyShort(pf.totalValue)),
            StatStrip.Cell(label: "Rent a week", value: cur.tidyShort(pf.weeklyRent)),
            StatStrip.Cell(label: "Let", value: Currency.percent(pf.occupancy, decimals: 0), tint: letTint),
        ]
        let second: [StatStrip.Cell] = [
            StatStrip.Cell(label: "Mortgages", value: cur.tidyShort(pf.mortgages), tint: mortgageTint),
            StatStrip.Cell(label: "Gain on cost", value: cur.tidyShort(pf.gainOnCost), tint: Theme.change(pf.gainOnCost)),
            StatStrip.Cell(label: "Staff cover", value: Currency.percent(min(1, pf.staffCover), decimals: 0), tint: coverTint),
        ]
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                StatStrip(cells: first, ruled: false)
                StatStrip(cells: second)
                Text(footer).font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Owned

    private func owned(_ pf: PropertyPortfolio, _ cur: Currency) -> some View {
        LedgerSection("Properties") {
            if pf.rows.isEmpty {
                Text("No property yet. Buy one below to start earning rent.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
            }
            if !pf.rows.isEmpty {
                SettingsTable(heading: "Property") {
                    ForEach(pf.rows, id: \.id) { (p: PropertyRow) in
                        SettingsTableRow(title: p.name, note: "\(Int(p.units.rounded())) \(pf.unitWord) · vacancy \(Currency.percent(p.vacancy, decimals: 0))",
                                         value: cur.tidyShort(p.value), opens: .sheet) { detailID = p.id }
                    }
                }
            }
        }
        .confirmAction($pending)
        .sheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } })) {
            propertySheet(cur)
        }
        .confirmationDialog("Sell this property?", isPresented: Binding(get: { pendingSell != nil }, set: { if !$0 { pendingSell = nil } }), presenting: pendingSell) { p in
            Button("Sell for about " + cur.tidyShort(p.value * 0.975) + (p.mortgage > 0 ? ", repay the mortgage" : ""), role: .destructive) { sell(p) }
            Button("Keep it", role: .cancel) {}
        } message: { p in
            Text("Selling on the market costs 2.5% of the value. \(p.name)")
        }
    }

    /// One property in a sheet: its figures and its actions. Renovate and Sell close the sheet and ask on the page.
    @ViewBuilder private func propertySheet(_ cur: Currency) -> some View {
        let pf: PropertyPortfolio? = engine.propertyPortfolio(companyID: company.id)
        if let pf, let p = pf.rows.first(where: { $0.id == detailID }) {
            PeopleSheet(title: "Property") { propertyCard(p, pf, cur) }
                .presentationDetents([.medium, .large])
        } else {
            PeopleSheet(title: "Property") { Text("This property is gone.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
        }
    }

    private func propertyCard(_ p: PropertyRow, _ pf: PropertyPortfolio, _ cur: Currency) -> some View {
        VStack(spacing: Theme.Space.s) {
            VStack(spacing: Theme.Space.s) {
                ForEach([p], id: \.id) { (p: PropertyRow) in
                    Card { VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory).lineLimit(2)
                                Text("\(Int(p.units.rounded())) \(pf.unitWord) · vacancy \(Currency.percent(p.vacancy, decimals: 0)) · \(conditionWord(p.condition))")
                                    .font(.caption).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(cur.tidyShort(p.value)).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                                Text("bought " + cur.tidyShort(p.cost)).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            }
                        }
                        HStack(spacing: 14) {
                            Text("Rent " + cur.tidyShort(p.weeklyRent) + " a week").font(.caption).foregroundStyle(Theme.ivoryMuted)
                            if p.mortgage > 0 { Text("Mortgage " + cur.tidyShort(p.mortgage)).font(.caption).foregroundStyle(Theme.loss) }
                        }
                        HStack(spacing: 18) {
                            Button("Renovate") { detailID = nil; pending = PendingAction(title: "Renovate this property?", message: "The work is paid from company cash. Better condition raises its value and rent.", button: "Renovate") { renovate(p) } }.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                            if p.kind == "com" {
                                Button(openTenants == p.id ? "Hide tenants" : "Tenants and buyers") { withAnimation(.snappy(duration: 0.2)) { openTenants = openTenants == p.id ? nil : p.id } }
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                            }
                            Button("Sell") { detailID = nil; pendingSell = p }.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.loss)
                            Spacer()
                        }.buttonStyle(.plain)
                        if openTenants == p.id { tenants(p, cur) }
                    } }
                }
            }
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
                        Text(cur.tidyShort(l.weeklyRent) + " a week · \(l.weeksLeft / 52) y left").font(.caption.monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
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
                            Text("\(Int(o.squareMetres)) m2 · \(cur.tidyShort(o.squareMetres * o.weeklyRentPerM2)) a week · \(o.years) year lease").font(.caption2).foregroundStyle(Theme.ivoryFaint)
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
                            Text("Offers " + cur.tidyShort(p.value * o.buyMultiple) + " (\(Currency.percent(o.buyMultiple - 1, decimals: 0)) over value)").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer()
                        Button("Sell to them") { detailID = nil; pending = PendingAction(title: "Sell the building to this tenant?", message: "The sale is final. The tenant takes over the building and your rental income from it ends.", button: "Sell to them", destructive: true) { sellBuilding(p, o) } }.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.loss).buttonStyle(.plain)
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
            SegmentedPill(items: [0.0, 0.4, 0.6], title: { $0 == 0 ? "No loan" : Currency.percent($0, decimals: 0) + " loan" }, selection: $loanToValue)
            Text("Rate \(Currency.percent(engine.state.economy.policyRate, decimals: 1)) plus a margin. Rents that return less than the loan costs make a mortgage lose money until prices rise.")
                .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            SettingsTable(heading: "Listing") {
                ForEach(listings, id: \.id) { (L: PropertyListing) in
                    SettingsTableRow(title: L.name, note: "Rent \(cur.tidyShort(L.rentPerUnit)) a week each · yield \(Currency.percent(L.grossYield, decimals: 1)) · \(conditionWord(L.condition))",
                                     value: cur.tidyShort(L.price), opens: .sheet) { pendingBuy = L }
                }
            }
        }
        .confirmationDialog("Buy this property?", isPresented: Binding(get: { pendingBuy != nil }, set: { if !$0 { pendingBuy = nil } }), presenting: pendingBuy) { L in
            Button("Buy for " + cur.tidyShort(L.price) + " plus 2.5% costs, \(Currency.percent(loanToValue, decimals: 0)) loan") { buy(L) }
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
        default: Haptics.warning(); store.show("The property could not be bought now.", tone: "warn")
        }
    }

    private func sell(_ p: PropertyRow) {
        if let net = store.act({ $0.sellProperty(companyID: company.id, propertyID: p.id) }), net > 0 { Haptics.success(); store.show("Sold for \(engine.currency(for: company).tidyShort(net)) after costs.", tone: "good") }
        else { Haptics.warning(); store.show("The property could not be sold.", tone: "warn") }
    }

    private func renovate(_ p: PropertyRow) {
        switch store.act({ $0.renovateProperty(companyID: company.id, propertyID: p.id) }) {
        case .ok?: Haptics.success(); store.show("Renovated: better condition, higher value.", tone: "good")
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company.", tone: "warn")
        default: store.show("It cannot be renovated now.", tone: "warn")
        }
    }

    private func lease(_ p: PropertyRow, _ o: TenantOffer) {
        if store.act({ $0.leaseSpace(companyID: company.id, propertyID: p.id, offerIndex: o.index) }) == true { Haptics.success(); store.show("Leased.", tone: "good") }
        else { Haptics.warning(); store.show("That tenant is no longer interested.", tone: "warn") }
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
