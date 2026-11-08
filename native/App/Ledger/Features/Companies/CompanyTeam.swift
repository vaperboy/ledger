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

/// One company's Team tab on ONE page, STAFF ONLY. A hero (head count and what the team costs a month, then Hire, the one action), the people
/// as clean rows with role and mood (a tap pushes the profile), then a short list of team settings (applicants, goals, perks). Managers, the owner and executive posts live in Group > the company > Management. Labour rules are in Stats; payroll in Accounting.
struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var page: TeamPage?
    @State private var showPerks = false
    @State private var profile: WorkerRef?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            hero
            if !company.staff.isEmpty {
                CompanyStaffRoster(engine: engine, company: company, profile: $profile)
            }
            settingsList
        }
        .navigationDestination(item: $page) { p in TeamPageDestination(page: p, companyID: company.id) }
        .navigationDestination(item: $profile) { (w: WorkerRef) -> StaffProfileView in StaffProfileView(companyID: company.id, staffID: w.id) }
        .centerSheet(isPresented: $showPerks, category: .medium, tone: .info) { CompanyPerksPopup(companyID: company.id, onClose: { showPerks = false }).environmentObject(store) }
    }

    // MARK: Hero

    /// What the whole team costs (this company's contracts only).
    private var metrics: TeamMetrics? { engine.teamMetrics(companyID: company.id) }

    /// The head count and the monthly cost side by side, one context line, then Hire full width with why it is blocked or the free places.
    private var hero: some View {
        let n: Int = company.staff.count
        let cur: Currency = engine.currency(for: company)
        let t: TeamMetrics? = metrics.flatMap { $0.workers > 0 ? $0 : nil }
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            if n == 0 {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("No staff yet").textStyle(.display)
                    Text("Hire the people the business needs to open and serve customers.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                        heroFigure("\(n)", n == 1 ? "person" : "people")
                        Rectangle().fill(P.hairline).frame(width: 0.5, height: 44)
                        heroFigure(t.map { cur.tidyShort($0.totalMonthlyCost) } ?? "\u{2014}", "a month")
                        Spacer(minLength: 0)
                    }
                    if let t {
                        Text("Wages \(cur.tidyShort(t.grossMonthlyWages)) plus taxes and cover \u{00B7} \(cur.tidyShort(t.totalAnnualCost)) a year \u{00B7} \(Int(t.totalHoursPerWeek.rounded())) h a week")
                            .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("people-cost-card")
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Button { Haptics.tap(); page = .hire } label: { Text(n == 0 ? "Hire workers" : "Hire") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("team-hire-workers")
                placesNote
            }
        }
    }

    private func heroFigure(_ value: String, _ unit: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(value).textStyle(.display).lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).textStyle(.caption, tint: P.inkFaint)
        }
    }

    /// Why hiring is blocked (the engine's reason), else how many places are free where the premises have a limit. Nothing for unlimited premises.
    @ViewBuilder private var placesNote: some View {
        if let why = engine.hireBlock(companyID: company.id) {
            Text(why.tidyText).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true)
        } else if let w = engine.workplaces(companyID: company.id), let cap = w.capacity, let free = w.free {
            Text(free == 1 ? "1 of \(cap) places is free" : "\(free) of \(cap) places are free").textStyle(.caption).frame(maxWidth: .infinity)
        }
    }

    // MARK: Team settings

    /// Applicants, goals and perks, as one flat list of rows.
    private var settingsList: some View {
        let cur: Currency = engine.currency(for: company)
        let status: ManagerTargets.Status? = engine.targetStatus(companyID: company.id)
        let goals: String = status == nil ? "None" : (status?.budget.map { !$0.approved } ?? false) ? "To approve" : "Set"
        let perksOn: Int = engine.staffPerkOptions.filter { engine.staffPerkIsOn(companyID: company.id, perk: $0.id) }.count
        let perksCost: Double = engine.staffPerksMonthlyTotal(companyID: company.id)
        let perksValue: String = perksOn == 0 ? "None" : "\(perksOn) on"
        let perksNote: String = perksOn == 0 ? "" : cur.tidyShort(perksCost) + " a month"
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Running the team").textStyle(.label, tint: P.inkFaint)
            VStack(spacing: 0) {
                ApplicantsLinkRow(engine: engine, companyID: company.id)
                Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m)
                LedgerRow(leading: .glyph(Glyph.goals), title: "Goals", subtitle: "Monthly targets and the yearly budget", value: goals, identifier: "team-goals") { page = .targets }
                Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m)
                LedgerRow(leading: .glyph(Glyph.person), title: "Perks", subtitle: "Cars and benefits for every worker", value: perksValue, valueNote: perksNote, identifier: "team-perks") { showPerks = true }
            }
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
            EmptyState(title: "This company no longer exists.").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        switch page {
        case .targets: CompanyTargetsCard(engine: e, company: co)
        case .hire: EmptyView()
        }
    }
}
