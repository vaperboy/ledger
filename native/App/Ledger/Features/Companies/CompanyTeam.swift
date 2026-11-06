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

/// One company's Team tab on ONE page, STAFF ONLY: the head count with the hire button, why hiring is blocked or the free places, the
/// workers, what they cost, and a flat list of team settings (applicants, goals, perks, the management link). Managers, the owner and
/// executive posts live in Group > the company > Management. Perks open as a popup; labour rules are in Stats; payroll in Accounting.
struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var page: TeamPage?
    @State private var showPerks = false
    @State private var profile: WorkerRef?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                header
                placesNote
            }
            if company.staff.isEmpty {
                EmptyState(glyph: Glyph.hire, title: "No staff yet", message: "Hire the people the business needs to open and serve customers.", centered: false)
            } else {
                CompanyStaffRoster(engine: engine, company: company, profile: $profile)
            }
            CompanyPeopleCost(engine: engine, company: company)
            settingsList
        }
        .navigationDestination(item: $page) { p in TeamPageDestination(page: p, companyID: company.id) }
        .navigationDestination(item: $profile) { (w: WorkerRef) -> StaffProfileView in StaffProfileView(companyID: company.id, staffID: w.id) }
        .centerSheet(isPresented: $showPerks) { CompanyPerksPopup(companyID: company.id, onClose: { showPerks = false }).environmentObject(store) }
    }

    // MARK: Header and places

    /// The head count and the one filled action of the tab: "Hire workers" while nobody is hired, "Hire" after.
    private var header: some View {
        let n: Int = company.staff.count
        return HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Staff").textStyle(.label)
                Text(n == 0 ? "Nobody yet" : (n == 1 ? "1 person" : "\(n) people")).textStyle(.figure)
            }
            Spacer(minLength: Theme.Space.s)
            Button { Haptics.tap(); page = .hire } label: { Text(n == 0 ? "Hire workers" : "Hire") }
                .buttonStyle(PrimaryButtonStyle(size: .compact))
                .accessibilityIdentifier("team-hire-workers")
        }
    }

    /// Why hiring is blocked (the engine's reason), else how many places are free where the premises have a limit. Nothing for unlimited premises.
    @ViewBuilder private var placesNote: some View {
        if let why = engine.hireBlock(companyID: company.id) {
            Text(why.tidyText).textStyle(.caption, tint: P.warn, weight: .medium).fixedSize(horizontal: false, vertical: true)
        } else if let w = engine.workplaces(companyID: company.id), let cap = w.capacity, let free = w.free {
            Text(free == 1 ? "1 of \(cap) places is free" : "\(free) of \(cap) places are free").textStyle(.caption)
        }
    }

    // MARK: Team settings

    /// Applicants, goals, perks and the way to the managers, as one flat list of rows.
    private var settingsList: some View {
        let cur: Currency = engine.currency(for: company)
        let goals: String = engine.targetStatus(companyID: company.id) == nil ? "Not set" : "Set"
        let perksOn: Int = engine.staffPerkOptions.filter { engine.staffPerkIsOn(companyID: company.id, perk: $0.id) }.count
        let perksCost: Double = engine.staffPerksMonthlyTotal(companyID: company.id)
        let perksValue: String = perksOn == 0 ? "None on" : "\(perksOn) on"
        let perksNote: String = perksOn == 0 ? "" : cur.tidyShort(perksCost) + " a month"
        return LedgerSection("Team") {
            VStack(spacing: 0) {
                ApplicantsLinkRow(engine: engine, companyID: company.id)
                Hairline()
                LedgerRow(leading: .glyph(Glyph.goals), title: "Goals", subtitle: "Monthly targets and bonus", value: goals) { page = .targets }
                Hairline()
                LedgerRow(leading: .glyph(Glyph.person), title: "Perks", subtitle: "Cars and benefits for every worker", value: perksValue, valueNote: perksNote) { showPerks = true }
                Hairline()
                LedgerRow(leading: .glyph(Glyph.group), title: "Managers and executives", subtitle: "Hired in Group, under this company's Management",
                          identifier: "team-open-management") { store.openGroupEntity(companyID: company.id, section: "management") }
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
