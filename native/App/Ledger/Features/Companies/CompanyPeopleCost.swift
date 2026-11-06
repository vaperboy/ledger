import SwiftUI
import GameCore
import Countries
import Simulation

/// What the whole team costs the company: the monthly and yearly employer cost, gross wages and hours. Shown in Team and in Accounting > Payroll,
/// both read from the one employer-cost rule that payroll books.
struct CompanyPeopleCost: View {
    var engine: GameEngine
    var company: Company

    var body: some View {
        if let t = engine.teamMetrics(companyID: company.id), t.workers > 0 {
            card(t)
        }
    }

    private func card(_ t: TeamMetrics) -> some View {
        let cur: Currency = engine.currency(for: company)
        let hours: String = String(format: "%.0f", t.totalHoursPerWeek) + " h a week"
        let rate: String = "average " + cur.tidyShort(t.averageHourlyRate) + " an hour"
        let bonus: Double = engine.companyEmployerCost(companyID: company.id)?.managerBonus ?? 0
        let perks: Double = engine.companyEmployerCost(companyID: company.id)?.perksAndExpenses ?? 0
        return Card(padding: 14, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What your people cost").capsLabel().padding(.bottom, 6)
                FlatRow(label: "A month", value: cur.tidyShort(t.totalMonthlyCost), sub: "wages, employer taxes, insurance and leave cover", rule: false)
                FlatRow(label: "A year", value: cur.tidyShort(t.totalAnnualCost))
                FlatRow(label: "Gross wages a month", value: cur.tidyShort(t.grossMonthlyWages), sub: t.workers.peopleText)
                FlatRow(label: "Hours", value: hours, sub: rate)
                if bonus > 0.5 {
                    FlatRow(label: "Manager's profit share", value: cur.tidyShort(bonus), sub: "a month, at the expected size")
                }
                if perks > 0.5 {
                    FlatRow(label: "Perks and expenses", value: cur.tidyShort(perks), sub: "a month, for the whole team")
                }
            }
        }
        .accessibilityIdentifier("people-cost-card")
    }
}
