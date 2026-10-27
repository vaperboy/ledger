import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

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
            CompanyPayrollRun(engine: engine, company: company)
            delegation
            CompanyManagement(engine: engine, company: company)
            CompanyTeamRoster(engine: engine, company: company)
            CompanyStaffRoster(engine: engine, company: company)
            CompanyTargetsCard(engine: engine, company: company)
            CompanyPerksCard(engine: engine, company: company)
            CompanyLabourCard(engine: engine, company: company)
            TeamGroup("Find workers") { HiringEntry(company: company) }
        }
    }
}
