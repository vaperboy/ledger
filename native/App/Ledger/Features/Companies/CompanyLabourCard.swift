import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// The labour rules of the company's country, read only: minimum wage, hours and overtime, notice, severance, leave, probation.
/// They come from the country data and are enforced when you hire, give raises, set hours and let people go.
struct CompanyLabourCard: View {
    var engine: GameEngine
    var company: Company

    var body: some View {
        let cur = engine.currency(for: company)
        let rules = LabourRules(country: cur.country)
        LedgerSection(title: "Labour rules", trailing: { Text(cur.country.name).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rules.summary(currency: cur).enumerated()), id: \.offset) { n, row in
                    if n > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Spacer(minLength: 8)
                        Text(row.value).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.trailing)
                    }.padding(.vertical, 7)
                }
                Text("Offers below the minimum are raised to it. Hours over the standard week cost the overtime premium and tire people. Letting someone go pays notice and severance by years of service.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
        }
    }
}
