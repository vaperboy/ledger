import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var role = ""
    @State private var candidates: [Person] = []

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
        let live = store.engine ?? engine
        VStack(spacing: Theme.Space.l) {
            CompanyPayrollRun(engine: engine, company: company)
            delegation
            CompanyManagement(engine: engine, company: company)
            CompanyTeamRoster(engine: engine, company: company)
            CompanyStaffRoster(engine: engine, company: company)
            CompanyTargetsCard(engine: engine, company: company)
            CompanyPerksCard(engine: engine, company: company)
            CompanyLabourCard(engine: engine, company: company)
            TeamGroup("Find workers") {
                Card(padding: 14, radius: Theme.Radius.card) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        let roles = engine.hireableRoles(companyID: company.id)
                        if roles.isEmpty { Text("This trade has no staff roles to hire for.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                        else {
                            SectionTabs(items: roles, title: { roleName($0) }, selection: $role).padding(.horizontal, -Theme.Space.margin)
                            WrapRow {
                                TeamAction(title: "Job ad") { search(.ads) }
                                TeamAction(title: "Network") { search(.network) }
                                TeamAction(title: "Agency") { search(.agency) }
                            }
                            Text("Ads are cheap and slow, the agency is quick and expensive; better people take better searches.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                            if role == "mktan" {
                                let v = engine.marketAnalystVerdict(companyID: company.id)
                                Text(v.title + ". " + v.text).font(.caption).foregroundStyle(v.ok ? Theme.ivoryMuted : Theme.caution)
                            }
                        }
                        CandidateHireList(people: candidates.compactMap { live.state.people[$0.id] }.filter { $0.employerID == 0 },
                                          emptyText: candidates.isEmpty ? "Run a search to see candidates." : "Everyone on the shortlist has taken another job. Search again.") { p in
                            WorkerHireRow(engine: live, company: company, person: p)
                        }
                    }
                }
            }
        }
        .onAppear { if role.isEmpty { role = engine.hireableRoles(companyID: company.id).first ?? "" } }
    }

    private func search(_ mode: Hiring.SearchMode) {
        guard !role.isEmpty else { return }
        candidates = store.act { $0.searchWorkers(companyID: company.id, role: role, mode: mode) } ?? []
        let how = mode == .ads ? "The job ad" : mode == .network ? "Your network" : "The agency"
        if candidates.isEmpty { Haptics.warning(); store.show("\(how) found no one suitable for \(roleName(role).lowercased()).", tone: "warn") }
        else { Haptics.tap(); store.show("\(how) found \(candidates.count) \(candidates.count == 1 ? "candidate" : "candidates") for \(roleName(role).lowercased()).", tone: "n") }
    }

    private func roleName(_ id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }
}
