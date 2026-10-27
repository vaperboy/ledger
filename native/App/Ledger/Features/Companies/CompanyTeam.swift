import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The full pages a row of the Team table opens.
enum TeamPage: String, Hashable, Identifiable {
    case management = "Management", targets = "Goals", perks = "Perks", labour = "Labour rules", hiring = "Hire someone"
    var id: String { rawValue }
}

/// One company's Team tab on ONE page: key figures above, a table of settings (management, goals, perks, labour rules, hiring), and
/// the pay run, delegation note and rosters below.
struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var page: TeamPage?

    /// Who handles day-to-day staffing here (the engine's decision chain), so an owner change is a deliberate override.
    @ViewBuilder private var delegation: some View {
        let chain = engine.decisionChain(companyID: company.id)
        if let boss = chain.first {
            let title = GameEngine.bossTitle(boss.kind, trade: engine.tradeInfo(companyID: company.id)).lowercased()
            let lvl = ["asks you before deciding", "decides within your limits", "decides on their own"][min(2, max(0, boss.level))]
            note("\(boss.name), \(title), runs the team day to day and \(lvl). Anything you change here overrides them; problems they cannot solve reach you in Team.", tint: Theme.ivoryMuted, medium: false)
        } else if company.status == .open {
            let owner: Bool = company.ownerHours > 0
            note(owner ? "You run this team yourself. A manager takes the day-to-day off you once the company is big enough to need one." : "No one runs this team: you do not work here and there is no manager.",
                 tint: owner ? Theme.ivoryMuted : Theme.caution, medium: !owner)
        }
    }

    private func note(_ text: String, tint: Color, medium: Bool) -> some View {
        Card(padding: 12, radius: Theme.Radius.row) {
            HStack(alignment: .top, spacing: 10) {
                GlyphView(glyph: Glyph.person, size: 16, weight: 1.5, tint: tint)
                Text(text).font(.system(size: 12.5, weight: medium ? .medium : .regular)).foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            keyFigures
            settingsTable
            CompanyPayrollRun(engine: engine, company: company)
            delegation
            CompanyTeamRoster(engine: engine, company: company)
            CompanyStaffRoster(engine: engine, company: company)
        }
        .navigationDestination(item: $page) { p in TeamPageDestination(page: p, companyID: company.id) }
    }

    // MARK: Key figures above

    private var runBy: String {
        if let boss = engine.decisionChain(companyID: company.id).first { return boss.name }
        return company.ownerHours > 0 ? "You" : "No one"
    }

    private var keyFigures: some View {
        let heads: Int = PremisesExtras.heads(company)
        let cells: [StatStrip.Cell] = [
            .init(label: "People", value: "\(heads)"),
            .init(label: "Run by", value: runBy, tint: runBy == "No one" ? Theme.caution : Theme.ivory),
            .init(label: "Your time", value: "\(Int(company.ownerHours.rounded())) h"),
        ]
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The team").capsLabel()
                Text("\(heads) \(heads == 1 ? "person" : "people") work here").font(.hero(30)).foregroundStyle(Theme.ivory).minimumScaleFactor(0.7).lineLimit(1)
                StatStrip(cells: cells)
            }
        }
    }

    // MARK: Table of settings

    private var settingsTable: some View {
        let cur: Currency = engine.currency(for: company)
        let goals: String = engine.targetStatus(companyID: company.id) == nil ? "Not set" : "Set"
        return SettingsTable(heading: "Team matters") {
            SettingsTableRow(title: "Management", note: "Manager, assistant and posts above them", value: runBy) { page = .management }
            SettingsTableRow(title: "Goals", note: "Monthly targets and bonus", value: goals) { page = .targets }
            SettingsTableRow(title: "Perks", note: "Cars and staff benefits", value: "Choose") { page = .perks }
            SettingsTableRow(title: "Labour rules", note: "Minimum pay, hours and notice", value: cur.country.name) { page = .labour }
            SettingsTableRow(title: "Hire someone", note: "Job ad, network or agency", value: "Find workers") { page = .hiring }
        }
    }
}

/// The full-screen page for one bigger Team decision.
struct TeamPageDestination: View {
    @EnvironmentObject var store: GameStore
    var page: TeamPage
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            if page == .hiring {
                HiringView(companyID: companyID)
            } else {
                SettingsPage(title: page.rawValue, subtitle: co.name) { content(e, co) }
            }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        switch page {
        case .management: CompanyManagement(engine: e, company: co)
        case .targets: CompanyTargetsCard(engine: e, company: co)
        case .perks: CompanyPerksCard(engine: e, company: co)
        case .labour: CompanyLabourCard(engine: e, company: co)
        case .hiring: EmptyView()
        }
    }
}
