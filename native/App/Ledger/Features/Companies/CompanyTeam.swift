import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyTeam: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company
    @State private var showHire = false
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
        .navigationDestination(isPresented: $showHire) { HireWorkersView(companyID: company.id) }
        .navigationDestination(item: $profile) { (w: WorkerRef) -> StaffProfileView in StaffProfileView(companyID: company.id, staffID: w.id) }
        .centerSheet(isPresented: $showPerks, category: .medium, tone: .info) { CompanyPerksPopup(companyID: company.id, onClose: { showPerks = false }).environmentObject(store) }
    }

    private var metrics: TeamMetrics? { engine.teamMetrics(companyID: company.id) }

    private var hero: some View {
        let n: Int = company.staff.count
        let cur: Currency = engine.currency(for: company)
        let t: TeamMetrics? = metrics.flatMap { $0.workers > 0 ? $0 : nil }
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            if n == 0 {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Your team").textStyle(.display)
                    Text("No staff yet. Hire the people the business needs to open and serve customers.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
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
                        Text("Wages \(cur.tidyShort(t.grossMonthlyWages)) plus taxes and cover \u{00B7} \(cur.tidyShort(t.totalAnnualCost)) a year \u{00B7} \(Int(saturating: t.totalHoursPerWeek.rounded())) h a week")
                            .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("people-cost-card")
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Button { Haptics.tap(); showHire = true } label: { Text(n == 0 ? "Hire workers" : "Hire") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("team-hire-workers")
                placesNote
            }
        }
    }

    private func heroFigure(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).textStyle(.display).lineLimit(2).minimumScaleFactor(0.8)
            Text(unit).textStyle(.caption, tint: P.inkFaint)
        }
    }

    @ViewBuilder private var placesNote: some View {
        if let why = engine.hireBlock(companyID: company.id) {
            Text(why.tidyText).textStyle(.caption, tint: P.caution).fixedSize(horizontal: false, vertical: true)
        } else if let w = engine.workplaces(companyID: company.id), let cap = w.capacity, let free = w.free {
            Text(free == 1 ? "1 of \(cap) places is free" : "\(free) of \(cap) places are free").textStyle(.caption).frame(maxWidth: .infinity)
        }
    }

    private var perksOpen: Bool {
        engine.staffTermsUnlocked(companyID: company.id) || engine.staffPerksMonthlyTotal(companyID: company.id) > 0
    }

    private var settingsList: some View {
        let cur: Currency = engine.currency(for: company)
        let perksOn: Int = engine.staffPerkOptions.filter { engine.staffPerkIsOn(companyID: company.id, perk: $0.id) }.count
        let perksCost: Double = engine.staffPerksMonthlyTotal(companyID: company.id)
        let perksValue: String = perksOn == 0 ? "None" : "\(perksOn) on"
        let perksNote: String = perksOn == 0 ? "" : cur.tidyShort(perksCost) + " a month"
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Running the team").textStyle(.label, tint: P.inkFaint)
            VStack(spacing: 0) {
                ApplicantsLinkRow(engine: engine, companyID: company.id)
                if perksOpen {
                    Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m)
                    LedgerRow(leading: .glyph(Glyph.person), title: "Perks", subtitle: "Cars and benefits for every worker", value: perksValue, valueNote: perksNote, identifier: "team-perks") { showPerks = true }
                }
            }
        }
    }
}
