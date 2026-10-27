import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The full-screen page a row of the Operations table opens. Each reuses the screen that already holds the decision.
struct OpsPageDestination: View {
    @EnvironmentObject var store: GameStore
    var part: OpsPart
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            page(e, co)
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func page(_ e: GameEngine, _ co: Company) -> some View {
        switch part {
        case .setup: EmptyView()
        case .sell: sellPage(e, co)
        case .marketing: SettingsPage(title: "Marketing", subtitle: co.name) { CompanyMarketing(engine: e, company: co) }
        case .premises: premisesPage(e, co)
        case .suppliers: CompanySuppliersScreen(companyID: co.id)
        case .equipment: CompanyEquipmentScreen(companyID: co.id)
        case .insurance: CompanyCoverageScreen(companyID: co.id)
        case .workplace: SettingsPage(title: "Where you work", subtitle: co.name) { CompanyWorkplaceSection(engine: e, company: co) }
        }
    }

    @ViewBuilder private func sellPage(_ e: GameEngine, _ co: Company) -> some View {
        if let trade = e.tradeInfo(companyID: co.id), !trade.knobs.isEmpty {
            SettingsPage(title: "How you sell", subtitle: co.name) { CompanyHowYouSell(engine: e, company: co, trade: trade) }
        } else {
            SettingsPage(title: "How you sell", subtitle: co.name) {
                Text("This business has no choices of how to sell.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
            }
        }
    }

    @ViewBuilder private func premisesPage(_ e: GameEngine, _ co: Company) -> some View {
        if e.tradeInfo(companyID: co.id)?.family == "rent" {
            SettingsPage(title: "Properties", subtitle: co.name) { CompanyProperties(engine: e, company: co) }
        } else {
            CompanyEquipmentScreen(companyID: co.id, opensOnPremises: true)
        }
    }
}

/// The small sheet for one simple Operations setting (price, hours, maintenance, stock, hold prices). It reads the company live, so the
/// controls always show what the engine holds; every change goes through the same engine call the old cards used.
struct OpsSettingSheet: View {
    @EnvironmentObject var store: GameStore
    var kind: OpsSheet
    var companyID: Int
    @State private var lastPrice: SettingResult?
    @State private var pending: PendingAction?

    var body: some View {
        PeopleSheet(title: title) {
            if let e = store.engine, let co = e.state.company(companyID) {
                content(co)
            } else {
                Text("This company no longer exists.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .confirmAction($pending)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        switch kind {
        case .price: return "Price"
        case .hours: return "Your time"
        case .maintenance: return "Maintenance"
        case .stock: return "Stock"
        case .hold: return "Hold my prices"
        }
    }

    @ViewBuilder private func content(_ co: Company) -> some View {
        switch kind {
        case .price: priceBody(co)
        case .hours: hoursBody(co)
        case .maintenance: levelBody(co, names: OpsWords.maintenance, current: co.maintenance, note: "Thorough upkeep costs more but equipment breaks less.") { level in
            store.act { $0.setMaintenance(companyID: co.id, level: level) }
            store.saved("Maintenance: \(OpsWords.name(OpsWords.maintenance, level).lowercased())")
        }
        case .stock: levelBody(co, names: OpsWords.stock, current: co.int("stockPol", 1), note: "Generous stock avoids running out but ties up cash.") { level in
            store.act { $0.setStockPolicy(companyID: co.id, level: level) }
            store.saved("Stock: \(OpsWords.name(OpsWords.stock, level).lowercased())")
        }
        case .hold: holdBody(co)
        }
    }

    // MARK: Price

    private func priceBody(_ co: Company) -> some View {
        let level: Double = co.priceLevel
        let priceBinding = Binding<Double>(get: { co.priceLevel }, set: { v in
            lastPrice = store.act { $0.setPriceLevel(companyID: co.id, level: (v * 2).rounded() / 2) }
        })
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(OpsWords.price(level)).font(.hero(34)).foregroundStyle(Theme.ivory)
                    Spacer()
                    Text(String(format: "%+.1f", level)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                }
                Slider(value: priceBinding, in: -3...3, step: 0.5) { editing in
                    if !editing {
                        Haptics.tap()
                        store.settle(lastPrice, "Price: \(OpsWords.price(co.priceLevel)).", same: "Price is already \(OpsWords.price(co.priceLevel)).", tone: "good")
                    }
                }
                .tint(Theme.gold)
                HStack {
                    Text("Bargain").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    Spacer()
                    Text("Luxury").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
                Text("Cheaper brings more customers, dearer more profit per sale. The right spot depends on your trade and area. The change applies from next week.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Hours

    private func hoursBody(_ co: Company) -> some View {
        let hours: Int = Int(co.ownerHours.rounded())
        let line: String = co.ownerHours == 0 ? "The team runs it without you" : "You work here yourself"
        let hoursBinding = Binding<Double>(get: { co.ownerHours }, set: { v in
            store.settle(store.act { $0.setOwnerHours(companyID: co.id, hours: v) }, "Hours saved.", same: "Hours are already that.")
        })
        return VStack(alignment: .leading, spacing: 6) {
            Card {
                HStack(spacing: Theme.Space.m) {
                    IconCircle(glyph: Glyph.person)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hours) hours a week").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text(line).font(.caption).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer()
                    StepperPill(value: hoursBinding, range: 0...80, step: 5)
                }
            }
            Text("Max 80 h across all companies").font(.caption2).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Maintenance and stock

    private func levelBody(_ co: Company, names: [String], current: Int, note: String, set: @escaping (Int) -> Void) -> some View {
        let binding = Binding<Int>(get: { current }, set: { set($0) })
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SegmentedPill(items: [0, 1, 2], title: { names[$0] }, selection: binding)
                Text(note).font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Hold prices

    /// "Hold my prices": prices stay where they were set while the market inflates, so customers see the company as cheaper over time.
    /// Switching it off lets prices follow the market again and drops the edge built up so far (the engine resets it).
    private func holdBody(_ co: Company) -> some View {
        let held: Bool = co.flag("inflHold")
        let edge: Double = max(0, (co.num("ig", 1) - 1) * 100)
        let heldText: String = edge >= 0.5 ? "Customers now see you about \(Int(edge.rounded()))% cheaper than if prices had followed inflation. Costs still rise." : "Prices stay where you set them while the market inflates. Costs still rise."
        let freeText: String = "Prices follow inflation by themselves. Switch on to keep them where you set them: customers see you as cheaper over time, but your margin shrinks as costs rise."
        return Card {
            Toggle(isOn: Binding(get: { held }, set: { v in setHold(co, v, edge: edge) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hold my prices").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text(held ? heldText : freeText).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            }.tint(Theme.gold)
        }
    }

    private func setHold(_ co: Company, _ on: Bool, edge: Double) {
        let id = co.id, name = co.name
        let apply = {
            guard store.act({ $0.setInflationHold(companyID: id, hold: on) }) != nil else { store.show("Could not change the price setting.", tone: "warn"); return }
            store.show(on ? "\(name) now holds its prices." : "\(name)'s prices follow inflation again.", tone: "n")
        }
        if !on && edge >= 0.5 {
            pending = PendingAction(title: "Let prices follow inflation?", message: "The edge built up while holding (about \(Int(edge.rounded()))% cheaper in customers' eyes) is dropped at once.", button: "Let go", run: apply)
        } else { apply() }
    }
}
