import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The full pages a row of the Team table opens.
enum TeamPage: String, Hashable, Identifiable {
    case management = "Management", targets = "Goals", promises = "Promises", hiring = "Hire someone"
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
        } else if company.status == .open && company.ownerHours <= 0 {
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
            keyFigures
            settingsTable
            delegation
            CompanyTeamRoster(engine: engine, company: company)
            CompanyStaffRoster(engine: engine, company: company)
        }
        .navigationDestination(item: $page) { p in TeamPageDestination(page: p, companyID: company.id) }
        .fullScreenCover(isPresented: $showPerks) {
            CompanyPerksPopup(companyID: company.id, onClose: { showPerks = false }).presentationBackground(.clear)
        }
    }

    // MARK: Key figures above

    private var runBy: String {
        if let boss = engine.decisionChain(companyID: company.id).first { return boss.name }
        return company.ownerHours > 0 ? "You" : "No one"
    }

    private var keyFigures: some View {
        let heads: Int = PremisesExtras.heads(company)
        let cur: Currency = engine.currency(for: company)
        let metrics: TeamMetrics? = engine.teamMetrics(companyID: company.id)
        let rate: String = (metrics?.averageHourlyRate ?? 0) > 0 ? cur.tidyDisplay(metrics?.averageHourlyRate ?? 0) : "none"
        let hours: String = String(Int((metrics?.totalHoursPerWeek ?? 0).rounded()))
        let payroll: String = cur.tidyShort(metrics?.totalMonthlyCost ?? 0)
        let metricCells: [StatStrip.Cell] = [
            .init(label: "Workers", value: String(metrics?.workers ?? 0)),
            .init(label: "Avg rate/h", value: rate),
            .init(label: "Hours/week", value: hours),
            .init(label: "Payroll/month", value: payroll),
        ]
        let cells: [StatStrip.Cell] = [
            .init(label: "Run by", value: runBy, tint: runBy == "No one" ? Theme.caution : Theme.ivory),
            .init(label: "Your time", value: "\(Int(company.ownerHours.rounded())) h"),
        ]
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The team").capsLabel()
                Text("\(heads) \(heads == 1 ? "person" : "people") work here").font(.hero(30)).foregroundStyle(Theme.ivory).minimumScaleFactor(0.7).lineLimit(1)
                StatStrip(cells: metricCells)
                StatStrip(cells: cells)
            }
        }
    }

    // MARK: Table of settings

    private var promisesValue: String {
        let open: Int = engine.promises(companyID: company.id).filter { $0.status == .pending || $0.status == .due }.count
        return open == 0 ? "None open" : "\(open) open"
    }

    private var settingsTable: some View {
        let cur: Currency = engine.currency(for: company)
        let goals: String = engine.targetStatus(companyID: company.id) == nil ? "Not set" : "Set"
        let perksOn: Int = engine.staffPerkOptions.filter { engine.staffPerkIsOn(companyID: company.id, perk: $0.id) }.count
        let perksCost: Double = engine.staffPerksMonthlyTotal(companyID: company.id)
        let perksValue: String = perksOn == 0 ? "None on" : "\(perksOn) on · " + cur.tidyShort(perksCost) + " a month"
        return SettingsTable(heading: "Team matters") {
            SettingsTableRow(title: "Management", note: "Manager, assistant and posts above them", value: runBy) { page = .management }
            SettingsTableRow(title: "Goals", note: "Monthly targets and bonus", value: goals) { page = .targets }
            SettingsTableRow(title: "Perks", note: "Cars and staff benefits for every worker", value: perksValue) { showPerks = true }
            SettingsTableRow(title: "Promises", note: "What you have promised your people, and when it falls due", value: promisesValue) { page = .promises }
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
        case .promises: CompanyPromises(engine: e, company: co)
        case .hiring: EmptyView()
        }
    }
}
