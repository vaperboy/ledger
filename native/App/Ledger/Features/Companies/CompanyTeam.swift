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

/// One company's Team tab on ONE page: compact key figures above, a table of settings (management, goals, perks and labour rules, hiring),
/// and a plain line about who runs the team and the rosters below. Perks open as a popup; the labour rules are in Stats. Payroll is in Accounting and the Bank, not here.
struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var page: TeamPage?
    @State private var showPerks = false

    /// Who handles day-to-day staffing here (the engine's decision chain), so an owner change is a deliberate override.
    @ViewBuilder private var delegation: some View {
        let chain = engine.decisionChain(companyID: company.id)
        if let boss = chain.first {
            let title = GameEngine.bossTitle(boss.kind, trade: engine.tradeInfo(companyID: company.id)).lowercased()
            let lvl = ["asks you before deciding", "decides within your limits", "decides on their own"][min(2, max(0, boss.level))]
            line("\(boss.name), \(title), runs the team day to day and \(lvl).", tint: Theme.ivoryMuted, medium: false)
        } else if company.status == .open && !OwnerHours.works(company) {
            line("No one runs this team: you do not work here and there is no manager.", tint: Theme.caution, medium: true)
        }
    }

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
                CompanyManagement(engine: engine, company: company)
            }
            if !company.staff.isEmpty { CompanyStaffRoster(engine: engine, company: company) }
            settingsTable
        }
        .navigationDestination(item: $page) { p in TeamPageDestination(page: p, companyID: company.id) }
        .centerSheet(isPresented: $showPerks) { CompanyPerksPopup(companyID: company.id, onClose: { showPerks = false }).environmentObject(store) }
    }

    // MARK: Header and places

    /// "Team" with the hire button at the top right: "Hire workers" while nobody is hired, "Hire" after.
    private var header: some View {
        HStack(alignment: .center) {
            Text("Team").capsLabel()
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
    @Environment(\.dismiss) private var dismiss

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
