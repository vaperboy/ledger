import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The full pages a row of the Team table opens.
enum TeamPage: String, Hashable, Identifiable {
    case targets = "Goals"
    /// The hire flow page (pushed). Perks is a popup on the Team page, not a page.
    case hire = "Hire workers"
    var id: String { rawValue }
}

/// One company's Team tab on ONE page, STAFF ONLY: the hire button, free places, the workers and a table of settings (goals, perks).
/// Managers, the owner and executive posts live in Group > the company > Management. Perks open as a popup; the labour rules are in Stats. Payroll is in Accounting and the Bank, not here.
struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var page: TeamPage?
    @State private var showPerks = false

    /// One plain line of text (not a card).
    private func line(_ text: String, tint: Color, medium: Bool) -> some View {
        Text(text).font(.system(size: 12, weight: medium ? .medium : .regular)).foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 8) {
                header
                placesNote
                managementNote
                ApplicantsLinkRow(engine: engine, companyID: company.id)
            }
            if !company.staff.isEmpty { CompanyStaffRoster(engine: engine, company: company) }
            settingsTable
        }
        .navigationDestination(item: $page) { p in TeamPageDestination(page: p, companyID: company.id) }
        .centerSheet(isPresented: $showPerks) { CompanyPerksPopup(companyID: company.id, onClose: { showPerks = false }).environmentObject(store) }
    }

    // MARK: Header and places

    /// Managers and executives are not here any more: they are hired per company in Group > the company > Management.
    private var managementNote: some View {
        Button { Haptics.tap(); store.openGroupEntity(companyID: company.id, section: "management") } label: {
            HStack(spacing: 6) {
                Text("Managers and executive posts are in Group").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                Spacer(minLength: 6)
                Text("Management \u{203A}").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold)
            }
            .frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("team-open-management")
    }

    /// "Staff" with the hire button at the top right: "Hire workers" while nobody is hired, "Hire" after.
    private var header: some View {
        HStack(alignment: .center) {
            Text("Staff").capsLabel()
            Spacer(minLength: 8)
            TeamAction(title: company.staff.isEmpty ? "Hire workers" : "Hire") { page = .hire }
                .accessibilityIdentifier("team-hire-workers")
        }
    }

    /// Why hiring is blocked (the engine's reason), else how many places are free where the premises have a limit. Nothing for unlimited premises.
    @ViewBuilder private var placesNote: some View {
        if let why = engine.hireBlock(companyID: company.id) {
            line(why, tint: Theme.caution, medium: true)
        } else if let w = engine.workplaces(companyID: company.id), let cap = w.capacity, let free = w.free {
            line(free == 1 ? "1 of \(cap) places is free" : "\(free) of \(cap) places are free", tint: Theme.ivoryFaint, medium: false)
        }
    }

    // MARK: Table of settings

    private var settingsTable: some View {
        let cur: Currency = engine.currency(for: company)
        let goals: String = engine.targetStatus(companyID: company.id) == nil ? "Not set" : "Set"
        let perksOn: Int = engine.staffPerkOptions.filter { engine.staffPerkIsOn(companyID: company.id, perk: $0.id) }.count
        let perksCost: Double = engine.staffPerksMonthlyTotal(companyID: company.id)
        let perksValue: String = perksOn == 0 ? "None on" : "\(perksOn) on · " + cur.tidyShort(perksCost) + " a month"
        return SettingsTable(heading: "Team matters") {
            SettingsTableRow(title: "Goals", note: "Monthly targets and bonus", value: goals) { page = .targets }
            SettingsTableRow(title: "Perks", note: "Cars and staff benefits for every worker", value: perksValue) { showPerks = true }
        }
    }
}

/// The full-screen page for one bigger Team decision.
struct TeamPageDestination: View {
    @EnvironmentObject var store: GameStore
    var page: TeamPage
    var companyID: Int
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            if page == .hire {
                HireWorkersView(companyID: companyID)
            } else {
                SettingsPage(title: page.rawValue, subtitle: co.name) { content(e, co) }
            }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        switch page {
        case .targets: CompanyTargetsCard(engine: e, company: co)
        case .hire: EmptyView()
        }
    }
}
