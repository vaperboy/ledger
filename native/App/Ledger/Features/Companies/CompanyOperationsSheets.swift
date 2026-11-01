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
        case .develop: SettingsPage(title: CompanyDevelopment.title(co, e), subtitle: co.name) { CompanyDevelopment(engine: e, company: co) }
        case .marketing: SettingsPage(title: "Marketing", subtitle: co.name) { CompanyMarketing(engine: e, company: co) }
        case .premises: premisesPage(e, co)
        case .suppliers: CompanySuppliersScreen(companyID: co.id)
        case .equipment: CompanyEquipmentScreen(companyID: co.id)
        case .insurance: CompanyCoverageScreen(companyID: co.id)
        }
    }

    @ViewBuilder private func premisesPage(_ e: GameEngine, _ co: Company) -> some View {
        if e.tradeInfo(companyID: co.id)?.family == "rent" {
            SettingsPage(title: "Properties", subtitle: co.name) { CompanyProperties(engine: e, company: co) }
        } else {
            // Premises are rented and bought in AirStay (Phone).
            VStack(spacing: Theme.Space.m) {
                Text("Places to rent and buy are in AirStay.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                Button("Open AirStay") { store.openAirStay(companyID: co.id) }.buttonStyle(QuietButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }
}

/// The small sheet for one simple Operations setting (hours, upkeep). It reads the company live, so the
/// controls always show what the engine holds; every change goes through the same engine call the old cards used.
struct OpsSettingSheet: View {
    @EnvironmentObject var store: GameStore
    var kind: OpsSheet
    var companyID: Int

    var body: some View {
        PeopleSheet(title: title) {
            if let e = store.engine, let co = e.state.company(companyID) {
                content(co)
            } else {
                Text("This company no longer exists.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        switch kind {
        case .hours: return "Your time"
        case .upkeep: return "Upkeep"
        }
    }

    @ViewBuilder private func content(_ co: Company) -> some View {
        switch kind {
        case .hours: hoursBody(co)
        case .upkeep: upkeepBody(co)
        }
    }

    /// Maintenance and stock in one sheet: both are how the company keeps its operation running between weeks.
    private func upkeepBody(_ co: Company) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("MAINTENANCE").capsLabel()
            levelBody(co, names: OpsWords.maintenance, current: co.maintenance, note: "Thorough upkeep costs more but equipment breaks less.") { level in
                store.act { $0.setMaintenance(companyID: co.id, level: level) }
                store.saved("Maintenance: \(OpsWords.name(OpsWords.maintenance, level).lowercased())")
            }
            Text("STOCK").capsLabel()
            levelBody(co, names: OpsWords.stock, current: co.int("stockPol", 1), note: "Generous stock avoids running out but ties up cash.") { level in
                store.act { $0.setStockPolicy(companyID: co.id, level: level) }
                store.saved("Stock: \(OpsWords.name(OpsWords.stock, level).lowercased())")
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
}
