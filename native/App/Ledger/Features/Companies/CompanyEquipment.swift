import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A link from Setup and Operations to the equipment, fleet, software and premises of a company. Flat row, no box.
struct EquipmentEntryRow: View {
    var company: Company
    var body: some View {
        NavigationLink {
            CompanyEquipmentScreen(companyID: company.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Equipment, fleet and premises").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text("Pick brands, buy new or used, lease, subscribe, choose where to work").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }
            .padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Hairline() }
    }
}

private enum EquipmentTab: String, CaseIterable, Hashable { case needed = "Needed", owned = "Owned", fleet = "Fleet", software = "Software", premises = "Premises" }

/// Equipment item by item: what is needed, what is owned unit by unit, the fleet, software and the choice of premises.
/// Original: `eqUI` and its tabs (features/company/realistic_buying.js).
struct CompanyEquipmentScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    /// Opened from the setup checklist's premises row: start on the choice of premises.
    var opensOnPremises = false
    @State private var tab: EquipmentTab = .needed
    @State private var pending: Pending? = nil
    @State private var pendingListing: CompanySetup.Listing? = nil

    private enum Pending: Identifiable {
        case unit(equipmentID: String, unitID: Int, name: String)
        case all(equipmentID: String, name: String)
        case vehicle(id: Int, name: String)
        case cancelPlan(equipmentID: String, name: String)
        var id: String {
            switch self {
            case .unit(let e, let u, _): return "u\(e)\(u)"
            case .all(let e, _): return "a\(e)"
            case .vehicle(let v, _): return "v\(v)"
            case .cancelPlan(let e, _): return "c\(e)"
            }
        }
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let needs = e.equipmentNeeds(companyID: companyID)
            let tabs = EquipmentTab.allCases.filter { t in
                t == .fleet ? needs.contains { $0.isVehicle } : t == .software ? needs.contains { $0.isSoftware } : t == .premises ? (e.tradeInfo(companyID: companyID)?.premisesKind.map { $0 != "none" && $0 != "home" } ?? false) : true
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(co.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory).lineLimit(2)
                        Text("Cash \(store.short(co.cash, in: co))" + (e.equipmentHealth(companyID: companyID).map { " · equipment health \(Int(($0 * 100).rounded()))%" } ?? ""))
                            .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    SectionTabs(items: tabs, title: { $0.rawValue }, selection: $tab).padding(.horizontal, -Theme.Space.margin)
                    switch tab {
                    case .needed: needed(e, co, needs)
                    case .owned: owned(e, co)
                    case .fleet: fleet(e, co, needs)
                    case .software: software(e, co, needs)
                    case .premises: premises(e, co)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .navigationTitle("Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if opensOnPremises && tabs.contains(.premises) { tab = .premises } }
            .confirmationDialog(pendingTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let p = pending { Button(pendingButton(p), role: .destructive) { confirm(p) } }
            } message: { Text(pendingMessage) }
            .confirmationDialog("Where to work", isPresented: Binding(get: { pendingListing != nil }, set: { if !$0 { pendingListing = nil } }), titleVisibility: .visible) {
                if let l = pendingListing, let t = e.premisesTerms(companyID: companyID, listing: l) {
                    Button("Rent: \(store.short(t.monthlyRent, in: co)) a month, deposit \(store.short(t.deposit, in: co))") { takePremises(l, buy: false) }
                    if !(e.tradeInfo(companyID: companyID)?.premisesKind == "slope") {
                        Button("Buy: \(store.short(t.purchasePrice, in: co)), \(store.short(t.downPayment, in: co)) down") { takePremises(l, buy: true) }
                    }
                }
            } message: { Text(pendingListing.map { "\($0.name), \(Int($0.squareMetres)) m². Fit-out is paid on top. Moving gives the old deposit back." } ?? "") }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    // MARK: Confirmations

    private var pendingTitle: String {
        switch pending {
        case .unit(_, _, let n)?: return "Sell this \(n)?"
        case .all(_, let n)?: return "Sell all \(n)?"
        case .vehicle(_, let n)?: return "Sell \(n)?"
        case .cancelPlan(_, let n)?: return "Cancel \(n)?"
        case nil: return ""
        }
    }
    private var pendingMessage: String {
        switch pending {
        case .unit?: return "Used equipment sells for well under what you paid, less if it looks worn."
        case .all?: return "You get about 70% of book value. Capacity may collapse."
        case .vehicle?: return "You get roughly 78% of its book value. A loan on it is settled; a lease just ends."
        case .cancelPlan?: return "It stops working right away."
        case nil: return ""
        }
    }
    private func pendingButton(_ p: Pending) -> String {
        if case .cancelPlan = p { return "Cancel plan" }
        return "Sell"
    }
    private func confirm(_ p: Pending) {
        switch p {
        case .unit(let eq, let u, _):
            let v = store.act { $0.sellEquipmentUnit(companyID: companyID, equipmentID: eq, unitID: u) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "Not sold.", tone: v > 0 ? "good" : "warn")
        case .all(let eq, _):
            let v = store.act { $0.sellAllEquipment(companyID: companyID, equipmentID: eq) } ?? 0
            store.show("Sold for \(store.short(v)).", tone: "good")
        case .vehicle(let id, _):
            let v = store.act { $0.sellVehicle(companyID: companyID, vehicleID: id) } ?? 0
            store.show(v > 0 ? "Sold for \(store.short(v))." : "Vehicle returned.", tone: "good")
        case .cancelPlan(let eq, _):
            store.act { $0.cancelSubscription(companyID: companyID, equipmentID: eq) }
            store.show("Plan cancelled.", tone: "n")
        }
        pending = nil
    }

    private func takePremises(_ l: CompanySetup.Listing, buy: Bool) {
        switch store.act({ $0.takePremises(companyID: companyID, listing: l, buy: buy) }) {
        case .ok?: Haptics.success(); store.show(buy ? "Bought: \(l.name)." : "Rented: \(l.name).", tone: "good")
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash for the deposit and fit-out.", tone: "warn")
        default: Haptics.warning(); store.show("Not possible.", tone: "warn")
        }
        pendingListing = nil
    }

    // MARK: Needed

    @ViewBuilder private func needed(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let cur = e.currency(for: co)
        let missing = needs.filter { $0.required && $0.have + $0.leased < 1 }
        let short = needs.filter { $0.need > 0 && $0.have + $0.leased < $0.need && !($0.required && $0.have + $0.leased < 1) }
        let upgrades = needs.filter { $0.need == 0 && $0.have + $0.leased == 0 && !$0.required }
        let inPlace = needs.filter { $0.have + $0.leased > 0 && $0.have + $0.leased >= $0.need }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if !missing.isEmpty {
                Text((co.status == .setup ? "You cannot open without " : "Work stops without ") + (missing.count > 1 ? "these \(missing.count) items." : missing[0].name.lowercased() + "."))
                    .font(.system(size: 13)).foregroundStyle(Theme.caution)
                needRows("Missing", missing, cur)
            }
            if !short.isEmpty { needRows("Short for your team", short, cur) }
            if !upgrades.isEmpty { needRows("Upgrades", upgrades, cur) }
            if !inPlace.isEmpty { needRows("In place", inPlace, cur) }
        }
    }

    private func needRows(_ title: String, _ list: [EquipmentMarket.Need], _ cur: Currency) -> some View {
        LedgerSection(title) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, x in
                    NavigationLink { EquipmentShopView(companyID: companyID, equipmentID: x.equipmentID) } label: {
                        VStack(spacing: 0) {
                            if n > 0 { Hairline() }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(x.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                                    Text(needLine(x)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                Text(x.have + x.leased > 0 && x.have + x.leased >= x.need ? "Owned" : x.subscription ? "from " + cur.tidyShort(x.fromPrice / max(1, x.lifeYears) / 12) + "/mo" : "from " + cur.tidyShort(x.fromPrice))
                                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(x.have + x.leased >= max(1, x.need) ? Theme.gain : Theme.ivoryMuted)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint)
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func needLine(_ x: EquipmentMarket.Need) -> String {
        var parts = [EquipmentMarket.kindName(x.kind)]
        let have = Int((x.have + x.leased).rounded())
        if x.need > 0 { parts.insert("\(have) of \(Int(x.need))", at: 0) } else if have > 0 { parts.insert("\(have) owned", at: 0) }
        if x.required { parts.append("required") }
        return parts.joined(separator: " · ")
    }

    // MARK: Owned

    @ViewBuilder private func owned(_ e: GameEngine, _ co: Company) -> some View {
        let list = e.ownedEquipment(companyID: companyID).filter { $0.kind != "veh" }
        let cur = e.currency(for: co)
        if list.isEmpty {
            Text("Nothing bought yet. Start under Needed.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
        }
        ForEach(list) { o in
            LedgerSection(o.name) {
                VStack(alignment: .leading, spacing: 0) {
                    if let s = o.subscription {
                        FlatRow(label: s, value: cur.tidyShort(o.subscriptionMonthly) + "/mo", sub: "Subscription", rule: false)
                    } else if let l = o.licence {
                        FlatRow(label: l, value: o.outdated ? "Outdated" : "Current", sub: "", tint: o.outdated ? Theme.caution : Theme.ivory, rule: false)
                    }
                    ForEach(Array(o.units.enumerated()), id: \.element.id) { n, u in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.name + (u.year > 0 ? " · \(u.year)" : "")).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text((u.boughtUsed ? "Bought used · " : "") + u.warranty + (u.daysInRepair > 0 ? " · in repair \(u.daysInRepair) days" : ""))
                                    .font(.system(size: 11)).foregroundStyle(u.daysInRepair > 0 ? Theme.loss : Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Text(u.wear).font(.system(size: 12.5)).foregroundStyle(u.seenCondition >= 0.8 ? Theme.gain : u.seenCondition >= 0.48 ? Theme.ivoryMuted : Theme.loss)
                            Button("Sell") { pending = .unit(equipmentID: o.equipmentID, unitID: u.id, name: o.name.lowercased()) }.buttonStyle(QuietButtonStyle())
                        }.padding(.vertical, 8).overlay(alignment: .top) { if n > 0 || o.subscription != nil || o.licence != nil { Hairline() } }
                    }
                    if o.leasedCount > 0 {
                        FlatRow(label: "\(Int(o.leasedCount)) on lease", value: cur.tidyShort(o.leaseMonthly) + "/mo", sub: "Service included", rule: !o.units.isEmpty)
                        Button("End the lease") { store.act { $0.endEquipmentLease(companyID: companyID, equipmentID: o.equipmentID) }; store.show("Lease ended.") }.buttonStyle(QuietButtonStyle())
                    }
                    HStack(spacing: Theme.Space.m) {
                        NavigationLink { EquipmentShopView(companyID: companyID, equipmentID: o.equipmentID) } label: { Text(o.subscription != nil ? "Plans" : "Buy more").font(.subheadline.weight(.medium)).foregroundStyle(Theme.gold) }
                        if o.subscription != nil {
                            Button("Cancel plan") { pending = .cancelPlan(equipmentID: o.equipmentID, name: o.name.lowercased()) }.buttonStyle(.plain).font(.subheadline).foregroundStyle(Theme.loss)
                        } else if o.licence == nil {
                            if o.count > 0 {
                                Button("Service all · \(cur.tidyShort(o.serviceCost))") {
                                    switch store.act({ $0.serviceEquipment(companyID: companyID, equipmentID: o.equipmentID) }) {
                                    case .ok?: store.show("Serviced.", tone: "good")
                                    default: store.show("Not enough cash.", tone: "warn")
                                    }
                                }.buttonStyle(.plain).font(.subheadline).foregroundStyle(Theme.ivoryMuted)
                                Button("Sell all") { pending = .all(equipmentID: o.equipmentID, name: o.name.lowercased()) }.buttonStyle(.plain).font(.subheadline).foregroundStyle(Theme.loss)
                            }
                        }
                        Spacer()
                    }.padding(.top, 8)
                }
            }
        }
        if let h = e.equipmentHealth(companyID: companyID) {
            LedgerSection("Condition") {
                VStack(alignment: .leading, spacing: 4) {
                    Meter(label: "Equipment health, as far as you can tell", value: h * 100)
                    Text("Old equipment breaks more often. Under warranty the maker repairs it for free, but it is away for days. Servicing costs little; replacing costs a lot.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    // MARK: Fleet

    @ViewBuilder private func fleet(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let cur = e.currency(for: co)
        let owned = e.ownedEquipment(companyID: companyID)
        ForEach(needs.filter { $0.isVehicle }) { n in
            let mine = owned.first { $0.equipmentID == n.equipmentID }?.vehicles ?? []
            LedgerSection(title: n.name, trailing: { Text(n.need > 0 ? "\(mine.count) of \(Int(n.need))" : "\(mine.count)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }) {
                VStack(alignment: .leading, spacing: 0) {
                    if mine.isEmpty { Text("No vehicles yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6) }
                    ForEach(Array(mine.enumerated()), id: \.element.id) { i, v in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(vehicleLine(v, cur))
                                    .font(.system(size: 11)).foregroundStyle(v.daysInRepair > 0 ? Theme.loss : Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Text(v.wear).font(.system(size: 12.5)).foregroundStyle(v.seenCondition >= 0.8 ? Theme.gain : v.seenCondition >= 0.48 ? Theme.ivoryMuted : Theme.loss)
                            Button(v.mode == "lease" ? "Return" : "Sell") { pending = .vehicle(id: v.id, name: v.name) }.buttonStyle(QuietButtonStyle())
                        }.padding(.vertical, 8).overlay(alignment: .top) { if i > 0 { Hairline() } }
                    }
                    NavigationLink { EquipmentShopView(companyID: companyID, equipmentID: n.equipmentID) } label: { Text("Buy, buy used or lease").font(.subheadline.weight(.medium)).foregroundStyle(Theme.gold) }.padding(.top, 8)
                }
            }
        }
        perkCars(owned, cur)
        runningCosts(e, cur)
        Text("Cash keeps you debt-free but drains the account. Finance builds ownership over four to five years. Leasing is a low monthly cost with service included, but you own nothing at the end.")
            .font(.caption2).foregroundStyle(Theme.ivoryFaint)
    }

    @ViewBuilder private func perkCars(_ owned: [EquipmentMarket.Owned], _ cur: Currency) -> some View {
        if let perk = owned.first(where: { $0.equipmentID == "perkcar" }) {
            LedgerSection(title: perk.name, trailing: { Text("\(perk.vehicles.count)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(perk.vehicles.enumerated()), id: \.element.id) { i, v in
                        FlatRow(label: v.driver, value: cur.tidyShort(v.monthlyLease) + "/mo", sub: v.name + " · fuel " + cur.tidyShort(v.fuelPerWeek) + "/wk", rule: i > 0)
                    }
                    Text("Leased for the Company car perk (Team > Perks). They go back when the perk is switched off or the person leaves.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                }
            }
        }
    }

    @ViewBuilder private func runningCosts(_ e: GameEngine, _ cur: Currency) -> some View {
        let run = e.fleetRunningCosts(companyID: companyID)
        if run.total > 0 {
            LedgerSection(title: "Running costs", trailing: { Text("\(cur.tidyShort(run.total)) a week").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }) {
                VStack(alignment: .leading, spacing: 0) {
                    if run.fuel > 0 { FlatRow(label: "Fuel", value: cur.tidyShort(run.fuel), sub: "At full use; taxis, couriers and hauliers carry fuel in their cost of sales", rule: false) }
                    if run.leases > 0 { FlatRow(label: "Leases", value: cur.tidyShort(run.leases), sub: "Service included", rule: run.fuel > 0) }
                    if run.charges.insurance > 0 { FlatRow(label: "Motor insurance", value: cur.tidyShort(run.charges.insurance), sub: "", rule: true) }
                    if run.charges.vehicleTax > 0 { FlatRow(label: "Vehicle tax", value: cur.tidyShort(run.charges.vehicleTax), sub: "", rule: true) }
                    if run.charges.benefitCharge > 0 { FlatRow(label: "Charges on company cars", value: cur.tidyShort(run.charges.benefitCharge), sub: "Employer's share on the taxable benefit", rule: true) }
                }
            }
        }
    }

    private func vehicleLine(_ v: EquipmentMarket.VehicleRow, _ cur: Currency) -> String {
        var line = v.driver.isEmpty ? "" : "\(v.driver) · "
        line += modeWord(v, cur) + " · \(v.kilometres / 1000) 000 km"
        if v.fuelPerWeek > 0 { line += " · fuel \(cur.tidyShort(v.fuelPerWeek))/wk" }
        line += " · " + v.warranty
        if v.daysInRepair > 0 { line += " · in repair \(v.daysInRepair) days" }
        return line
    }

    private func modeWord(_ v: EquipmentMarket.VehicleRow, _ cur: Currency) -> String {
        v.mode == "fin" ? "Financed" : v.mode == "lease" ? "Leased " + cur.tidyShort(v.monthlyLease) + "/mo" : "Owned"
    }

    // MARK: Software

    @ViewBuilder private func software(_ e: GameEngine, _ co: Company, _ needs: [EquipmentMarket.Need]) -> some View {
        let cur = e.currency(for: co)
        let owned = e.ownedEquipment(companyID: companyID)
        Text("Small programs are bought once. Bigger systems cost more up front plus yearly updates. Some are only sold as a subscription, priced by how many people use them. You have \(EquipmentMarket.users(co)) \(EquipmentMarket.users(co) == 1 ? "user" : "users").")
            .font(.caption).foregroundStyle(Theme.ivoryMuted)
        LedgerSection("Software") {
            VStack(spacing: 0) {
                ForEach(Array(needs.filter { $0.isSoftware }.enumerated()), id: \.element.id) { n, x in
                    let o = owned.first { $0.equipmentID == x.equipmentID }
                    let mode = e.softwareMode(companyID: companyID, equipmentID: x.equipmentID)
                    NavigationLink { EquipmentShopView(companyID: companyID, equipmentID: x.equipmentID) } label: {
                        VStack(spacing: 0) {
                            if n > 0 { Hairline() }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(x.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                                    Text((mode == .subscription ? "Subscription only" : mode == .once ? "One-time licence" : "Licence up front + yearly updates") + (x.required ? " · required" : ""))
                                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                Text(o?.subscription != nil ? cur.tidyShort(o?.subscriptionMonthly ?? 0) + "/mo" : o?.licence != nil ? (o?.outdated == true ? "Outdated" : "Owned") : "from " + cur.tidyShort(mode == .subscription ? x.fromPrice / max(1, x.lifeYears) / 12 : x.fromPrice))
                                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(o != nil ? Theme.gain : Theme.ivoryMuted)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint)
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Premises

    @ViewBuilder private func premises(_ e: GameEngine, _ co: Company) -> some View {
        let cur = e.currency(for: co)
        let prem = co.value("prem")
        let lists = e.premisesListings(companyID: companyID)
        LedgerSection("Your premises") {
            VStack(alignment: .leading, spacing: 0) {
                if prem.isNull || prem["m2"].double <= 0 {
                    Text("No premises yet. Choose one below.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
                } else {
                    FlatRow(label: prem["lname"].string.isEmpty ? "Premises" : prem["lname"].string, value: "\(Int(prem["m2"].double)) m²", sub: prem["landlord"].string, rule: false)
                    if prem["owned"].bool {
                        FlatRow(label: "Value", value: cur.tidyShort(prem["val"].double))
                        if prem["loan"].double != 0 { FlatRow(label: "Mortgage", value: cur.tidyShort(e.state.loans.first { $0.id == prem["loan"].int }?.balance ?? 0), tint: Theme.loss) }
                    } else {
                        FlatRow(label: "Rent a month", value: cur.tidyShort(prem["rent"].double * prem["m2"].double / 12))
                        if prem["dep"].double > 0 { FlatRow(label: "Deposit held", value: cur.tidyShort(prem["dep"].double)) }
                    }
                    if prem["loc"].double != 0 {
                        let l = prem["loc"].double
                        FlatRow(label: "Location", value: l > 1.03 ? "More passing trade" : l < 0.97 ? "Less passing trade" : "Normal", tint: l > 1.03 ? Theme.gain : l < 0.97 ? Theme.caution : Theme.ivory)
                    }
                    if let bd = e.tradeInfo(companyID: companyID) {
                        FlatRow(label: "Space needed", value: "about \(Int(jsRound(bd.premisesM2 * co.size))) m²")
                    }
                }
            }
        }
        LedgerSection(prem.isNull || prem["m2"].double <= 0 ? "Places to rent" : "Move or buy") {
            VStack(spacing: 0) {
                ForEach(Array(lists.enumerated()), id: \.element.id) { n, l in
                    let t = e.premisesTerms(companyID: companyID, listing: l)
                    Button { pendingListing = l } label: {
                        VStack(spacing: 0) {
                            if n > 0 { Hairline() }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(l.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                    Text("\(Int(l.squareMetres)) m² · \(l.landlord) · " + (l.location > 1.03 ? "more passing trade" : l.location < 0.97 ? "less passing trade" : "normal location"))
                                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text((t.map { cur.tidyShort($0.monthlyRent) } ?? "") + "/mo").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
                                    Text("deposit " + (t.map { cur.tidyShort($0.deposit) } ?? "")).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                                }
                            }.padding(.vertical, 9).contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
        Text("The list changes twice a year. A place in the centre costs more and draws more passing trade; one out of town is cheap but quiet. Space is checked against what your size needs.")
            .font(.caption2).foregroundStyle(Theme.ivoryFaint)
    }
}

// MARK: The shop

private enum ShopMode: Hashable { case new, used, lease }

/// One item at a time: brands and classes, used listings, lease, subscription plans. Original: `V.shop` (realistic_buying.js).
struct EquipmentShopView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var companyID: Int
    var equipmentID: String
    @State private var mode: ShopMode = .new
    @State private var cls: Int? = nil
    @State private var selected: String? = nil
    @State private var quantity = 0
    @State private var finance = false

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let need = e.equipmentNeeds(companyID: companyID).first(where: { $0.equipmentID == equipmentID }) {
            let cur = e.currency(for: co)
            let one = need.kind == "soft" || need.kind == "svc"
            let modes: [ShopMode] = [.new] + (need.canUsed ? [.used] : []) + (need.canLease ? [.lease] : [])
            let current = modes.contains(mode) ? mode : .new
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(need.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        Text(EquipmentMarket.kindName(need.kind) + " · lasts about \(Int(need.lifeYears)) years" + (need.warrantyYears > 0 ? " · warranty \(Int(need.warrantyYears)) yr new" : ""))
                            .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    if modes.count > 1 {
                        SectionTabs(items: modes, title: { $0 == .new ? (one ? (need.subscription ? "Plans" : "Licences") : "New") : $0 == .used ? "Used" : "Lease" },
                                    selection: Binding(get: { current }, set: { mode = $0; selected = nil; finance = false })).padding(.horizontal, -Theme.Space.margin)
                    }
                    KeyFigures(items: [
                        .init(label: "You have", value: "\(Int((need.have + need.leased).rounded()))"),
                        .init(label: "Needed", value: need.need > 0 ? "\(Int(need.need))" : "–"),
                        .init(label: "Cash", value: store.short(co.cash, in: co), tint: co.cash < 0 ? Theme.loss : Theme.ivory),
                    ])
                    if need.isVehicle { vehicles(e, co, need, current, cur) }
                    else if current == .used { used(e, co, need, cur) }
                    else if need.subscription && current == .new { plans(e, co, need, cur) }
                    else { brands(e, co, need, current, cur, one: one) }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("Not sold here.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    // MARK: Rows

    private func stars(_ r: Double, _ n: Int) -> String { String(format: "%.1f", r) + " ★ (\(n))" }

    private func row(_ title: String, _ sub: String, _ right: String, _ id: String, rule: Bool, tint: Color = Theme.ivory) -> some View {
        Button { selected = selected == id ? nil : id } label: {
            VStack(spacing: 0) {
                if rule { Hairline() }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: selected == id ? "checkmark.circle.fill" : "circle").font(.system(size: 14)).foregroundStyle(selected == id ? Theme.gold : Theme.ivoryFaint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                        Text(sub).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(right).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(tint)
                }.padding(.vertical, 9).contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    private func reliabilityWord(_ r: Double) -> String { r < 0.85 ? "excellent" : r < 1.05 ? "good" : r < 1.25 ? "fair" : "poor" }

    // MARK: New equipment, by brand

    @ViewBuilder private func brands(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ mode: ShopMode, _ cur: Currency, one: Bool) -> some View {
        let all = e.equipmentOffers(companyID: companyID, equipmentID: equipmentID)
        let list = all.filter { cls == nil || $0.cls == cls }
        let lease = mode == .lease
        HStack(spacing: 18) {
            ForEach([-1, 0, 1, 2], id: \.self) { c in
                let on = (c < 0 && cls == nil) || cls == c
                Button { cls = c < 0 ? nil : c; selected = nil } label: {
                    Text(c < 0 ? "All" : EquipmentMarket.classNames[c]).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.gold : Theme.ivoryFaint)
                }.buttonStyle(.plain)
            }
        }
        LedgerSection(one ? "Suppliers" : "Brands") {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, o in
                    let p = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: o.priceFactor)
                    row(o.name, "\(o.className) · \(o.seller) · \(stars(o.rating, o.reviews)) · output \(o.performance >= 1 ? "+" : "")\(Int(((o.performance - 1) * 100).rounded()))% · reliability \(reliabilityWord(o.reliability)) · \(o.comment)",
                        lease ? cur.tidyShort(EquipmentMarket.leaseMonthly(price: p)) + "/mo" : cur.tidyShort(p), String(o.index), rule: n > 0)
                }
            }
        }
        if let sel = all.first(where: { String($0.index) == selected }) {
            let unit = e.equipmentPrice(companyID: companyID, equipmentID: equipmentID, factor: sel.priceFactor)
            let q = one ? 1 : (quantity > 0 ? quantity : max(1, Int(need.need - need.have - need.leased)))
            let total = unit * Double(q)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if !one { stepper(q) }
                if !lease && e.canFinance(companyID: companyID, equipmentID: equipmentID, total: total) { payChoice() }
                let useFinance = finance && !lease && e.canFinance(companyID: companyID, equipmentID: equipmentID, total: total)
                FlatRow(label: lease ? "Lease, 3 years, service included" : useFinance ? "Down payment now, loan for the rest" : "Total", value: lease ? cur.tidyShort(EquipmentMarket.leaseMonthly(price: total)) + "/mo" : useFinance ? cur.tidyShort(total * 0.2) : cur.tidyShort(total))
                Button(lease ? "Lease \(q)" : one ? "Buy licence" : "Buy \(q)") {
                    report(store.act { $0.buyEquipmentItem(companyID: companyID, equipmentID: equipmentID, offer: sel, quantity: q, payment: lease ? .lease : useFinance ? .finance : .cash) }, lease ? "Lease signed." : "Bought.")
                }.buttonStyle(GoldButtonStyle())
            }
        }
    }

    // MARK: Subscriptions

    @ViewBuilder private func plans(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ cur: Currency) -> some View {
        let all = e.equipmentOffers(companyID: companyID, equipmentID: equipmentID).filter { $0.cls == 1 }
        let owned = e.ownedEquipment(companyID: companyID).first { $0.equipmentID == equipmentID }
        Text("Sold only as a subscription. Pick a provider and a plan. Plans are priced by users: you have \(EquipmentMarket.users(co)).").font(.caption).foregroundStyle(Theme.ivoryMuted)
        ForEach(all) { o in
            LedgerSection(title: o.name, trailing: { Text(stars(o.rating, o.reviews)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted) }) {
                VStack(spacing: 0) {
                    ForEach(Array(e.subscriptionPlans(companyID: companyID, equipmentID: equipmentID, offer: o).enumerated()), id: \.element.index) { n, p in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name + (p.recommended ? " · fits your team" : "")).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(p.maxUsers > 1_000_000 ? "any number of users" : "up to \(p.maxUsers) users").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Text(cur.tidyShort(p.monthlyFee) + "/mo").font(.system(size: 13.5).monospacedDigit())
                            Button(owned?.subscription != nil ? "Switch" : "Subscribe") {
                                report(store.act { $0.subscribeSoftware(companyID: companyID, equipmentID: equipmentID, plan: p.index, offer: o) }, "Subscribed.")
                            }.buttonStyle(QuietButtonStyle())
                        }.padding(.vertical, 8).overlay(alignment: .top) { if n > 0 { Hairline() } }
                    }
                }
            }
        }
    }

    // MARK: Used

    @ViewBuilder private func used(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ cur: Currency) -> some View {
        let list = e.usedListings(companyID: companyID, equipmentID: equipmentID)
        Text("Second-hand, sold as seen: no warranty and no guarantees. The seller describes the wear. It is not always the whole truth.").font(.caption).foregroundStyle(Theme.ivoryMuted)
        if list.isEmpty {
            Text("Nothing for sale this month. New listings appear next month.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
        }
        LedgerSection("For sale this month") {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { n, x in
                    row("\(x.name) · \(x.year)",
                        "\(x.seller) · \(x.age) \(x.age == 1 ? "year" : "years") old · \(EquipmentMarket.wearWord(x.visibleCondition)) · \u{201C}\(x.says)\u{201D}"
                            + (x.kilometres > 0 ? " · \(x.kilometres / 1000) 000 km · breakdown risk, your guess: \(x.risk.lowercased()) · fuel and service: \(x.fuel.lowercased())" : "")
                            + (x.knownToLast ? " · known to last" : "") + " · no warranty",
                        cur.tidyShort(x.price), x.id, rule: n > 0, tint: Theme.gain)
                }
            }
        }
        if let sel = list.first(where: { $0.id == selected }) {
            let canFin = e.canFinance(companyID: companyID, equipmentID: equipmentID, total: sel.price)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if canFin { payChoice() }
                let useFinance = finance && canFin
                FlatRow(label: useFinance ? "Down payment now, loan for the rest" : "Total", value: cur.tidyShort(useFinance ? sel.price * 0.2 : sel.price))
                Button("Buy used · \(cur.tidyShort(sel.price))") {
                    report(store.act { $0.buyUsedItem(companyID: companyID, equipmentID: equipmentID, listing: sel, payment: useFinance ? .finance : .cash) }, "Bought.")
                }.buttonStyle(GoldButtonStyle())
            }
        }
    }

    // MARK: Vehicles

    @ViewBuilder private func vehicles(_ e: GameEngine, _ co: Company, _ need: EquipmentMarket.Need, _ mode: ShopMode, _ cur: Currency) -> some View {
        if mode == .used {
            used(e, co, need, cur)
        } else {
            let offers = e.vehicleOffers(companyID: companyID, equipmentID: equipmentID)
            let lease = mode == .lease
            Text("Cash, finance (20% down, five years) or lease (three years, service and repairs included).").font(.caption).foregroundStyle(Theme.ivoryMuted)
            LedgerSection("Makes and models") {
                VStack(spacing: 0) {
                    ForEach(Array(offers.enumerated()), id: \.element.id) { n, o in
                        let price = e.vehiclePrice(modelID: o.modelID, factor: o.priceFactor)
                        row(o.name + ", new", "\(o.modelName) · \(stars(o.rating, o.reviews)) · reliability \(reliabilityWord(o.reliability))",
                            lease ? cur.tidyShort(EquipmentMarket.vehicleLeaseMonthly(price: price)) + "/mo" : cur.tidyShort(price), o.id, rule: n > 0)
                    }
                }
            }
            if let sel = offers.first(where: { $0.id == selected }) {
                let price = e.vehiclePrice(modelID: sel.modelID, factor: sel.priceFactor)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if !lease { payChoice() }
                    FlatRow(label: lease ? "Lease, 3 years" : finance ? "Down payment now, loan for the rest" : "Total",
                            value: lease ? cur.tidyShort(EquipmentMarket.vehicleLeaseMonthly(price: price)) + "/mo" : cur.tidyShort(finance ? price * 0.2 : price))
                    Button(lease ? "Lease" : "Buy new") {
                        report(store.act { $0.buyVehicleItem(companyID: companyID, equipmentID: equipmentID, offer: sel, payment: lease ? .lease : finance ? .finance : .cash) }, lease ? "Lease signed." : "Bought.")
                    }.buttonStyle(GoldButtonStyle())
                }
            }
        }
    }

    // MARK: Shared

    private func payChoice() -> some View {
        HStack {
            Text("How to pay").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            SectionTabs(items: [false, true], title: { $0 ? "Finance" : "Cash" }, selection: $finance)
        }
    }

    private func stepper(_ q: Int) -> some View {
        HStack {
            Text("Quantity").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            StepperPill(value: Binding(get: { Double(q) }, set: { quantity = max(1, min(50, Int($0))) }), range: 1...50, step: 1)
        }
    }

    private func report(_ r: EquipmentMarket.Result?, _ ok: String) {
        switch r {
        case .ok?: Haptics.success(); store.show(ok, tone: "good"); selected = nil; quantity = 0
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash.", tone: "warn")
        default: Haptics.warning(); store.show("Not possible.", tone: "warn")
        }
    }
}
