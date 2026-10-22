import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The management roles above the manager (managing director, department heads, regional manager) as rows of one list, each with a
/// role and a scope badge. Hiring, pay-offer, authority and release happen in this list. Chain and group level posts are the same
/// rows seen from the chain (see CompanyChain); there is no separate screen for them.
struct CompanyTeamRoster: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var searchKey: String?
    @State private var candidates: [Int] = []
    @State private var releasing: ManagerModel.TeamSlot?

    private func scope(_ slot: ManagerModel.TeamSlot) -> String {
        switch slot.key { case "ceo": return company.type == "hold" ? "group" : "company"; case "reg": return "region"; default: return "company" }
    }

    var body: some View {
        let slots = engine.teamSlots(companyID: company.id)
        if !slots.isEmpty {
            let cur = engine.currency(for: company)
            LedgerSection(title: "Management", trailing: { Text("above the manager").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { n, slot in
                        if n > 0 { Hairline() }
                        row(slot, cur)
                    }
                }
            }
            .confirmationDialog("Let \(releasing?.title.lowercased() ?? "them") go?", isPresented: Binding(get: { releasing != nil }, set: { if !$0 { releasing = nil } }), titleVisibility: .visible) {
                Button("Let go", role: .destructive) {
                    if let r = releasing { _ = store.act { $0.releaseTeam(companyID: company.id, key: r.key, regionalID: r.regionalID) }; Haptics.warning() }
                    releasing = nil
                }
            } message: { Text("One month of pay plus employer costs is paid now, and their work goes back to the manager.") }
        }
    }

    @ViewBuilder private func row(_ slot: ManagerModel.TeamSlot, _ cur: Currency) -> some View {
        let person = slot.personID.flatMap { engine.state.people[$0] }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(person?.name ?? slot.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        Chip(text: "\(slot.title) · \(scope(slot))", tint: Theme.gold)
                    }
                    Text(person == nil ? slot.detail : "Since week \(slot.since)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if person != nil { Text(cur.short(slot.monthlyWage)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory) }
            }
            if person != nil {
                HStack(spacing: 16) {
                    if slot.key == "ceo" {
                        Menu(["Asks you", "Within limit", "Full control"][min(2, max(0, slot.level))]) {
                            ForEach(0..<3, id: \.self) { l in Button(["Asks you", "Within limit", "Full control"][l]) { store.act { $0.setTeamAuthority(companyID: company.id, level: l) } } }
                        }
                        if slot.level == 1 {
                            Menu("Spend up to \(cur.short(slot.buy))") {
                                ForEach([25000.0, 50000, 100000, 250000, 500000], id: \.self) { v in Button(cur.short(cur.scaledPrice(v))) { store.act { $0.setTeamAuthority(companyID: company.id, buy: cur.scaledPrice(v)) } } }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Let go") { releasing = slot }.foregroundStyle(Theme.loss)
                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
            } else {
                Button("Executive search · \(cur.short(cur.scaledPrice(15000)))") {
                    if let list = store.act({ $0.searchTeam(companyID: company.id, key: slot.key) }) ?? nil { searchKey = slot.id; candidates = list.map { $0.id }; Haptics.tap() }
                    else { store.show("Not enough cash for the search.", tone: "warn") }
                }.buttonStyle(QuietButtonStyle())
                if searchKey == slot.id {
                    ForEach(candidates, id: \.self) { id in
                        if let p = engine.state.people[id] {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory)
                                    Text("Age \(p.age) · \(String(format: "%g", p.num("exp"))) yr · \(p.str("resume"))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                Menu("\(cur.short(p.askingMonthlyWage)) / mo") {
                                    ForEach([1.0, 1.1], id: \.self) { f in
                                        Button("Offer \(cur.short(cur.roundedStep(p.askingMonthlyWage * f, about: 500)))") { hire(slot, p, cur.roundedStep(p.askingMonthlyWage * f, about: 500)) }
                                    }
                                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                            }
                        }
                    }
                }
            }
        }.padding(.vertical, 8)
    }

    private func hire(_ slot: ManagerModel.TeamSlot, _ p: Person, _ wage: Double) {
        switch store.act({ $0.hireTeam(companyID: company.id, key: slot.key, personID: p.id, monthlyWage: wage) }) {
        case .ok?: Haptics.success(); candidates = []; searchKey = nil; store.show("\(p.name) starts as \(slot.title.lowercased()).", tone: "good")
        case .refused?: store.show("\(p.name) found that a bit low.", tone: "warn")
        default: store.show("They took another job.", tone: "warn")
        }
    }
}
