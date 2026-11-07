import SwiftUI
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// The labour rules of the company's country, read only: minimum wage, hours and overtime, notice, severance, leave, probation.
/// They come from the country data and are enforced when you hire, give raises, set hours and let people go.
struct CompanyLabourCard: View {
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company

    var body: some View {
        let cur = engine.currency(for: company)
        let rules = LabourRules(country: cur.country)
        LedgerSection(title: "Rules", trailing: { Text(cur.country.name).textStyle(.caption, tint: P.inkFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rules.summary(currency: cur).enumerated()), id: \.offset) { n, row in
                    if n > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(row.label.tidyText).textStyle(.body)
                        Spacer(minLength: Theme.Space.s)
                        Text(row.value.tidyText).textStyle(.body, tint: P.inkSoft, numeric: true).multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, Theme.Space.s)
                    .accessibilityElement(children: .combine)
                }
                Text("Offers below the minimum are raised to it. Hours over the standard week cost the overtime premium and tire people. Letting someone go pays notice and severance by years of service.")
                    .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.top, Theme.Space.s)
            }
        }
    }
}
