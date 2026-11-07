import SwiftUI
import GameCore
import Businesses
import Countries
import Simulation

/// IT security of one company: the protection level, offline backups, staff training and the cyber insurance state. It lives where the
/// company's insurance and advisers are chosen (Manage > Insurance and advisers), not under Customers.
struct CompanySecurityCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let c = engine.cyberInfo(company)
        let cur = engine.currency(for: company)
        return PageGroup(title: "IT security", trailing: {
            Text("1 in \(Int((1 / max(0.002, c.yearOdds)).rounded())) a year").font(.system(size: 11)).foregroundStyle(c.yearOdds > 0.1 ? Theme.loss : Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                FigureStrip(items: [
                    .init(label: "Protection", value: Cyber.levels[c.status.level].name, sub: cur.tidyShort(c.monthlyNow) + " a month"),
                    .init(label: "Stopped", value: "\(c.status.blocked)", sub: "attacks caught"),
                    .init(label: "Cyber insurance", value: c.insured ? "Yes" : "No", tint: c.insured ? Theme.gain : Theme.ivory),
                ])
                if company.managerID != nil {
                    CardLine()
                    HStack {
                        Text(c.status.managerPicks ? "Your manager picks the level, keeps the backups and books the training." : "Your choice stands.").textStyle(.caption)
                        Spacer()
                        if !c.status.managerPicks { Button("Leave it to the manager") { store.act { $0.leaveCyberToManager(companyID: company.id) }; store.saved("your manager now picks the IT protection") }.buttonStyle(TinyButtonStyle(tint: Theme.gold)) }
                    }
                }
                ForEach(Cyber.levels.indices, id: \.self) { (i: Int) in
                    CardLine()
                    levelRow(i, c: c, cur: cur)
                }
                CardLine()
                HStack {
                    Button(c.status.backups ? "Offline backups: on" : "Offline backups: off") { Haptics.tap(); store.settle(store.act { $0.toggleBackups(companyID: company.id) }, c.status.backups ? "Offline backups switched off." : "Offline backups switched on.") }
                        .buttonStyle(TinyButtonStyle(tint: c.status.backups ? Theme.gold : Theme.ivoryMuted))
                    Spacer()
                    Button((c.status.trainedUntil ?? 0) > engine.state.week ? "Staff trained" : "Train staff · " + cur.tidyShort(c.trainingCost)) {
                        let r = store.act { $0.trainStaff(companyID: company.id) }
                        if case .refused(let why)? = r { store.show(why, tone: "warn") } else if r != nil { Haptics.success(); store.show("Staff training booked.", tone: "good") }
                    }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
                }
                if let last = c.status.log.first {
                    Text("Last: \(last.text)").textStyle(.caption, tint: Theme.inkFaint)
                }
            }
        }
    }

    private func levelRow(_ i: Int, c: CyberInfo, cur: Currency) -> some View {
        let on: Bool = c.status.level == i
        let costText: String = i == 0 ? "Free" : cur.tidyShort(c.levelCosts[i]) + "/mo"
        let done: String = "Cyber protection: \(Cyber.levels[i].name)."
        return Button {
            Haptics.choose()
            store.settle(store.act { $0.setCyberLevel(companyID: company.id, level: i) }, done, same: "That protection level is already in place.")
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Cyber.levels[i].name).font(.system(size: 13.5, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.gold : Theme.ivory)
                    Text(Cyber.levels[i].text).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(costText).textStyle(.caption, numeric: true)
                GlyphView(glyph: on ? Glyph.check : Glyph.ring, size: 14, weight: 1.6, tint: on ? Theme.gold : Theme.ivoryFaint)
            }.contentShape(Rectangle())
        }.buttonStyle(PressableStyle())
    }
}
