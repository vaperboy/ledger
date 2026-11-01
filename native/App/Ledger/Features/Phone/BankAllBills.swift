import SwiftUI
import GameCore
import Countries
import Simulation

/// Bills across the whole Bank app: every account's coming payments in one list, grouped by the company (or you) that pays them, each row
/// with Pay now (`BankBillsList`: payroll approval, loan instalment, or the engine's `payObligationNow`). A payroll run by a manager or an
/// accountant says so instead of offering a button. Pushed from the Bank home.
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
                        Text("Nothing is due anywhere.").font(.system(size: 13)).foregroundStyle(P.inkSoft)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .appScreen(title: "Bills", subtitle: "Everything coming, company by company")
        }
    }

    private func summary(_ all: BankAccounts) -> some View {
        let tint: Color = all.isCovered ? P.gain : P.loss
        return Card(padding: 16, radius: Theme.Radius.hero) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DUE IN 30 DAYS").capsLabel()
                    Text(store.short(all.dueWithin30Days)).font(.hero(30)).foregroundStyle(P.ink).minimumScaleFactor(0.6).lineLimit(1)
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
                Text("\(d.upcoming.count) · \(fmt.short(total))").font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
            }
            .padding(.horizontal, 2)
            Card(padding: 14, radius: Theme.Radius.hero) {
                BankBillsList(account: r.id, upcoming: d.upcoming, cash: d.balance)
            }
        }
    }
}
