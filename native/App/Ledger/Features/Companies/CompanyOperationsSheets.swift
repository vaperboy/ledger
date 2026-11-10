import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct OpsPageDestination: View {
    @EnvironmentObject var store: GameStore
    var part: OpsPart
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            page(e, co)
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func page(_ e: GameEngine, _ co: Company) -> some View {
        switch part {
        case .setup: EmptyView()
        case .premises: premisesPage(e, co)
        case .equipment: CompanyEquipmentScreen(companyID: co.id)
        case .insurance: CompanyCoverageScreen(companyID: co.id)
        case .accountant: CompanyAccountantScreen(companyID: co.id)
        case .licences: SettingsPage(title: "Licences", subtitle: co.name) { CompanyLicences(engine: e, company: co) }
        }
    }

    @ViewBuilder private func premisesPage(_ e: GameEngine, _ co: Company) -> some View {
        if e.tradeInfo(companyID: co.id)?.family == "rent" {
            SettingsPage(title: "Properties", subtitle: co.name) { CompanyProperties(engine: e, company: co) }
        } else {
            EmptyState(glyph: Glyph.airStay, title: "Premises are in AirStay", message: "Places to rent and buy are in AirStay.")
                .frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }
}

struct OpsSettingSheet: View {
    @EnvironmentObject var store: GameStore
    var kind: OpsSheet
    var companyID: Int

    var body: some View {
        PeopleSheet(title: title) {
            if let e = store.engine, let co = e.state.company(companyID) {
                content(co)
            } else {
                Text("This company no longer exists.").popupText(.body)
            }
        }
    }

    private var title: String {
        switch kind {
        case .upkeep: return "Upkeep"
        case .logo: return "Company logo"
        }
    }

    @ViewBuilder private func content(_ co: Company) -> some View {
        switch kind {
        case .upkeep: upkeepBody(co)
        case .logo: logoBody(co)
        }
    }

    private func logoBody(_ co: Company) -> some View {
        let choices: [LogoChoice] = store.engine?.logoChoices() ?? []
        let current: String = store.engine?.companyLogoID(companyID: co.id) ?? ""
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Shown on the company card and to suppliers and buyers.").popupText(.subtitle)
            ForEach(Array(choices.enumerated()), id: \.element.id) { (n: Int, c: LogoChoice) in
                if n > 0 { Hairline() }
                Button {
                    guard c.unlocked else { Haptics.warning(); return }
                    Haptics.tap()
                    _ = store.act { $0.setCompanyLogo(companyID: co.id, logoID: c.id) }
                    store.saved("logo: " + c.logo.name.lowercased())
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        LogoBadge(logoID: c.id, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.logo.name).popupText(.body)
                            Text(c.unlocked ? c.how : "Locked: " + c.how.lowercased()).popupText(.caption)
                        }
                        Spacer(minLength: Theme.Space.s)
                        if c.id == current { Chip(text: "In use", tint: Theme.accent) }
                    }
                    .opacity(c.unlocked ? 1 : 0.5)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("logo-pick-\(c.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private func levelBody(_ co: Company, names: [String], current: Int, note: String, set: @escaping (Int) -> Void) -> some View {
        let binding = Binding<Int>(get: { current }, set: { set($0) })
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SegmentedPill(items: [0, 1, 2], title: { names[$0] }, selection: binding)
                Text(note).popupText(.caption)
            }
        }
    }
}
