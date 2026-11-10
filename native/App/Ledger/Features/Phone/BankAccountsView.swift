import SwiftUI
import GameCore
import Countries
import Simulation

struct BankAccountsScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var onPick: (BankAccountID, BankTab) -> Void
    @State private var givingOpen = false

    var body: some View {
        if let e = store.engine {
            let all = e.bankAccounts()
            let you: [BankAccountRow] = all.rows.filter { $0.kind == .personal }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    totalCard(all)
                    BankWealthCard(engine: e)
                    billsLink(all, e)
                    givingLink(e)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR ACCOUNT").capsLabel()
                        ForEach(you) { r in row(r, e) }
                    }
                    Text("Every company pays and earns through this one account. Each company still has its own profit and loss.")
                        .textStyle(.caption, tint: P.inkFaint).padding(.horizontal, 4)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag().scrollBounceBehavior(.basedOnSize)
        }
    }

    private func givingLink(_ e: GameEngine) -> some View {
        let n: Int = e.givingMarks.count
        let sub: String = "\(n) \(n == 1 ? "mark" : "marks")" + (e.foundation != nil ? " \u{00B7} foundation running" : "")
        return Button { givingOpen = true } label: {
            CardRow(glyph: Glyph.richList, title: "Giving back", subtitle: "Gifts, sponsorships and your foundation \u{00B7} " + sub)
        }
        .buttonStyle(PressableStyle())
        .navigationDestination(isPresented: $givingOpen) { GivingView() }
        .accessibilityIdentifier("bank-giving")
    }

    private func billsLink(_ all: BankAccounts, _ e: GameEngine) -> some View {
        let count: Int = e.financeOverview().upcoming.count
        let sub: String = count == 0 ? "Nothing is due" : "\(count) coming · \(store.short(all.dueWithin30Days)) due in 30 days"
        return Button { Haptics.tap(); onPick(.personal, .bills) } label: {
            CardRow(glyph: BankGlyph.bill, title: "Bills", subtitle: sub)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("bank-all-bills")
    }

    private func totalCard(_ all: BankAccounts) -> some View {
        let invested: Double = all.rows.filter { (r: BankAccountRow) -> Bool in r.kind == .investments }.reduce(0) { (a: Double, r: BankAccountRow) -> Double in a + r.balance }
        let cash: Double = all.total - invested
        let totalText: String = store.short(cash)
        let dueText: String = store.short(all.dueWithin30Days)
        return IvoryPanel {
            BankTotalPanel(totalText: totalText, negative: cash < 0, dueText: dueText, covered: all.isCovered)
        }
    }

    private func row(_ r: BankAccountRow, _ e: GameEngine) -> some View {
        let fmt = BankFmt(store: store, company: nil)
        let note: String = r.loanCount > 0 ? "\(r.loanCount) loan\(r.loanCount == 1 ? "" : "s")" : ""
        let tint: Color = r.balance < 0 ? P.loss : P.ink
        return Button { Haptics.tap(); onPick(r.id, .account) } label: {
            CardRow(glyph: Glyph.person, title: r.name, subtitle: note, value: fmt.short(r.balance), valueTint: tint)
        }
        .newGroupMarker(.bank, store.messageItemIDs(.bank, companyID: nil), alignment: .topLeading)
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("bank-account-\(r.id.id)")
    }
}
