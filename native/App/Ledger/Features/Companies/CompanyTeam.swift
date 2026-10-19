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
    @State private var confirmFire: StaffMember?

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Team · \(company.staff.count)")
                    if company.staff.isEmpty { Text("No one works here but you.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                    ForEach(company.staff) { m in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(roleName(m.role)).font(.bodyText.weight(.semibold))
                                Spacer()
                                Text(cur.display(m.monthlyWage) + " / mo").font(.system(.subheadline, design: .default).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                            }
                            if m.tiredness > 60 { Chip(text: "Tired", tint: Theme.caution) }
                            let missing = StaffExtras.missing(m)
                            if !missing.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Chip(text: "\(missing.count) paperwork item\(missing.count == 1 ? "" : "s") missing", tint: Theme.loss)
                                    Text(missing.map { $0.text }.joined(separator: " · ")).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                    Button("Mark all done") { store.act { $0.completePaperwork(companyID: company.id, personID: m.id) }; Haptics.success() }.buttonStyle(QuietButtonStyle(tint: Theme.caution))
                                    Text("Missing papers can be fined in an inspection.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                }
                            }
                            if m.sickUntilWeek != nil { Chip(text: "Off sick", tint: Theme.loss) }
                            HStack {
                                Button("Raise 5%") { store.act { $0.raise(personID: m.id, companyID: company.id, percent: 0.05) }; Haptics.tap() }.buttonStyle(QuietButtonStyle())
                                Button("Let go") { confirmFire = m }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                            }
                        }
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Find workers")
                    let roles = engine.hireableRoles(companyID: company.id)
                    if roles.isEmpty { Text("This trade has no staff roles.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                    else {
                        Picker("Role", selection: $role) { ForEach(roles, id: \.self) { Text(roleName($0)).tag($0) } }.pickerStyle(.menu)
                        HStack {
                            Button("Job ad") { search(.ads) }.buttonStyle(QuietButtonStyle())
                            Button("Network") { search(.network) }.buttonStyle(QuietButtonStyle())
                            Button("Agency") { search(.agency) }.buttonStyle(QuietButtonStyle())
                        }
                        Text("Ads are cheap and slow, the agency is quick and expensive; better people take better searches.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                    ForEach(candidates) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.bodyText.weight(.semibold))
                                Text("Says \(Int(p.claimedSkill.rounded())) skill · \(p.age)").font(.caption).foregroundStyle(Theme.ivoryMuted)
                            }
                            Spacer()
                            Button(cur.short(p.askingMonthlyWage) + " / mo") { hire(p) }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
        }
        .onAppear { if role.isEmpty { role = engine.hireableRoles(companyID: company.id).first ?? "" } }
        .confirmationDialog("Let this person go?", isPresented: Binding(get: { confirmFire != nil }, set: { if !$0 { confirmFire = nil } }), presenting: confirmFire) { m in
            Button("Let go", role: .destructive) {
                let severance = store.act { $0.fire(personID: m.id, companyID: company.id) } ?? 0
                store.show(severance > 0 ? "Severance paid: \(cur.display(severance))" : "Done.", tone: "n")
                Haptics.warning()
            }
        } message: { _ in Text("Notice periods and severance may apply.") }
    }

    private func search(_ mode: Hiring.SearchMode) {
        guard !role.isEmpty else { return }
        candidates = store.act { $0.searchWorkers(companyID: company.id, role: role, mode: mode) } ?? []
        Haptics.tap()
        if candidates.isEmpty { store.show("No one suitable answered.", tone: "n") }
    }

    private func hire(_ p: Person) {
        let r = store.act { $0.hire(personID: p.id, companyID: company.id, monthlyWage: p.askingMonthlyWage) }
        switch r {
        case .ok?: Haptics.success(); candidates.removeAll { $0.id == p.id }; store.show("\(p.name) has joined.", tone: "good")
        case .taken?: store.show("They took another job.", tone: "warn")
        default: store.show("Could not hire.", tone: "warn")
        }
    }

    private func roleName(_ id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }
}
