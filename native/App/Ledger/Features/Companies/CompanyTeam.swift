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
            Text("\(boss.name), \(title), runs the team day to day and \(lvl). Anything you change here overrides them; problems they cannot solve reach you in Team.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if company.status == .open {
            Text(company.ownerHours > 0 ? "You run this team yourself. A manager takes the day-to-day off you once the company is big enough to need one." : "No one runs this team: you do not work here and there is no manager.")
                .font(.system(size: 12.5, weight: company.ownerHours > 0 ? .regular : .medium)).foregroundStyle(company.ownerHours > 0 ? Theme.ivoryMuted : Theme.caution).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        let live = store.engine ?? engine
        VStack(spacing: Theme.Space.l) {
            delegation
            CompanyManagement(engine: engine, company: company)
            CompanyTeamRoster(engine: engine, company: company)
            CompanyStaffRoster(engine: engine, company: company)
            CompanyTargetsCard(engine: engine, company: company)
            CompanyPerksCard(engine: engine, company: company)
            CompanyLabourCard(engine: engine, company: company)
            LedgerSection("Find workers") {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    let roles = engine.hireableRoles(companyID: company.id)
                    if roles.isEmpty { Text("This trade has no staff roles to hire for.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                    else {
                        SectionTabs(items: roles, title: { roleName($0) }, selection: $role).padding(.horizontal, -Theme.Space.margin)
                        WrapRow {
                            Button("Job ad") { search(.ads) }.buttonStyle(QuietButtonStyle())
                            Button("Network") { search(.network) }.buttonStyle(QuietButtonStyle())
                            Button("Agency") { search(.agency) }.buttonStyle(QuietButtonStyle())
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
