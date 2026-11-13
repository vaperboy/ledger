import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

struct BankAccountScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var id: BankAccountID
    @Binding var tab: BankTab
    @State private var givingOpen = false

    var body: some View {
        if let e = store.engine, let d = e.bankAccount(id) {
            let fmt = BankFmt(store: store, company: nil)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Figure(label: "Balance", value: fmt.full(d.balance), tint: d.balance < 0 ? P.loss : P.ink, size: .display, live: d.balance)
                    SegmentedPill(items: BankTab.allCases, title: { (t: BankTab) -> String in t.rawValue }, selection: $tab,
                                  identifier: { (t: BankTab) -> String in "bank-tab-\(t.rawValue)" })
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                SegmentPager(items: BankTab.allCases, selection: $tab) { (t: BankTab) in
                    ScrollScreen(spacing: Theme.Space.l, top: Theme.Space.m, maxWidth: 560) {
                        switch t {
                        case .loans: BankLoansTab(account: id, loans: d.loans)
                        case .statements:
                            BankStatementsTab(account: id, detail: d)
                            givingLink
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $givingOpen) { GivingView() }
            .onAppear { clearLoanDot() }
            .onChange(of: tab) { _, _ in clearLoanDot() }
        } else {
            EmptyState(title: "This account is closed.").padding(Theme.Space.xl)
        }
    }

    private func clearLoanDot() {
        guard tab == .loans else { return }
        for mid in store.loanMessageIDs() { store.markItemSeen(.bank, mid) }
    }

    private var givingLink: some View {
        Button { givingOpen = true } label: {
            CardRow(glyph: Glyph.richList, title: "Giving back", subtitle: "")
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("bank-giving")
    }
}

struct BankTransactionRow: View {
    @Environment(\.outsidePalette) private var P
    var transaction: BankTransaction
    var fmt: BankFmt
    var body: some View {
        let sign: String = transaction.amount >= 0 ? "+" : "−"
        LedgerRow(title: transaction.label, subtitle: transaction.dateText, value: sign + fmt.short(abs(transaction.amount)),
                  valueTint: P.change(transaction.amount), density: .compact)
    }
}
