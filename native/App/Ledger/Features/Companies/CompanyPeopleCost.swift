import SwiftUI
import GameCore
import Countries
import Simulation

/// What the whole team costs the company, from the one employer-cost rule payroll books: the monthly total once (gross wages are its
/// note), the year and the hours, then the manager's share and perks when there are any. Shown in Team.
struct CompanyPeopleCost: View {
    var engine: GameEngine
    var company: Company

    var body: some View {
        if let t = engine.teamMetrics(companyID: company.id), t.workers > 0 {
            section(t)
        }
    }

    private func section(_ t: TeamMetrics) -> some View {
        let cur: Currency = engine.currency(for: company)
        let cost = engine.companyEmployerCost(companyID: company.id)
        let bonus: Double = cost?.managerBonus ?? 0
        let perks: Double = cost?.perksAndExpenses ?? 0
        let items: [KeyFigures.Item] = [
            .init(label: "A month", value: cur.tidyShort(t.totalMonthlyCost), sub: "wages " + cur.tidyShort(t.grossMonthlyWages) + " plus taxes and cover"),
            .init(label: "A year", value: cur.tidyShort(t.totalAnnualCost), sub: t.workers.peopleText),
            .init(label: "Hours a week", value: String(format: "%.0f", t.totalHoursPerWeek), sub: "average " + cur.tidyShort(t.averageHourlyRate) + " an hour"),
        ]
        return LedgerSection("What your people cost") {
            VStack(alignment: .leading, spacing: 0) {
                FigureRow(items: items, columns: 3, combineCells: true)
                if bonus > 0.5 {
                    Hairline().padding(.top, Theme.Space.m)
                    LedgerRow(title: "Manager's profit share", subtitle: "A month, at the expected size", value: cur.tidyShort(bonus), density: .compact)
                }
                if perks > 0.5 {
                    Hairline().padding(.top, bonus > 0.5 ? 0 : Theme.Space.m)
                    LedgerRow(title: "Perks and expenses", subtitle: "A month, for the whole team", value: cur.tidyShort(perks), density: .compact)
                }
            }
        }
        .accessibilityIdentifier("people-cost-card")
    }
}
