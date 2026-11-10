import SwiftUI
import GameCore
import Countries
import Simulation

struct BankAllBillsScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            let all = e.bankAccounts()
            let groups: [BankAccountRow] = all.rows.filter { $0.kind != .investments }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary(all)
                    ForEach(groups) { r in
                        if let d = e.bankAccount(r.id), !d.upcoming.isEmpty { group(r, d) }
                    }
                    if groups.allSatisfy({ e.bankAccount($0.id)?.upcoming.isEmpty ?? true }) {
                        Text("Nothing is due anywhere.").textStyle(.body, tint: P.inkSoft)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag().scrollBounceBehavior(.basedOnSize)
            .appScreen(title: "Bills", subtitle: "Everything coming, company by company")
        }
    }

    private func summary(_ all: BankAccounts) -> some View {
        let tint: Color = all.isCovered ? P.gain : P.loss
        return Card(padding: 16, radius: Theme.Radius.hero) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DUE IN 30 DAYS").capsLabel()
                    Text(store.short(all.dueWithin30Days)).textStyle(.display).minimumScaleFactor(0.8).lineLimit(2)
                }
                Spacer(minLength: 8)
                Chip(text: all.isCovered ? "Covered" : "Not covered", tint: tint)
            }
        }
    }

    private func group(_ r: BankAccountRow, _ d: BankAccountDetail) -> some View {
        let fmt = BankFmt(store: store, company: r.companyID.flatMap { store.engine?.state.company($0) })
        let total: Double = d.upcoming.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.name).capsLabel()
                Spacer(minLength: 8)
                Text("\(d.upcoming.count) · \(fmt.short(total))").textStyle(.caption, tint: P.inkFaint)
            }
            .padding(.horizontal, 2)
            Card(padding: 14, radius: Theme.Radius.hero) {
                BankBillsList(account: r.id, upcoming: d.upcoming, cash: d.balance)
            }
        }
    }
}
