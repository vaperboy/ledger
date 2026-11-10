import SwiftUI
import GameCore
import Countries
import Simulation

enum BankTab: String, CaseIterable, Hashable {
    case account = "Account", loans = "Loans", deposits = "Deposits", bills = "Bills", statements = "Statements"
}

struct BankRequest: Equatable {
    var account: BankAccountID
    var tab: BankTab = .account
    var applyLoan: Double? = nil
}

@MainActor
struct BankFmt {
    var store: GameStore
    var company: Company?
    func short(_ v: Double) -> String { company.map { store.short(v, in: $0) } ?? store.short(v) }
    func full(_ v: Double) -> String { company.map { store.money(v, in: $0) } ?? store.money(v) }
    func currency(_ e: GameEngine) -> Currency { company.map { e.currency(for: $0) } ?? e.homeCurrency }
}

enum BankGlyph {
    static let transfer = "M4 8 H19 M15 4 L19 8 L15 12 M20 16 H5 M9 12 L5 16 L9 20"
    static let bill = "M6 3 H18 V21 L15 19 L12 21 L9 19 L6 21 Z M9 8 H15 M9 12 H15"
}

struct BankApp: View {
    private var P: OutsidePalette { .bank }
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    @State private var account: BankAccountID?
    @State private var tab: BankTab = .account

    var body: some View {
        Group {
            if let account {
                BankAccountScreen(id: account, tab: $tab)
            } else {
                BankAccountsScreen { id, to in tab = to; account = id }
            }
        }
        .navigationBarBackButtonHidden(true)
            .swipeBackEnabled(canStep: { account != nil }, step: { back() })
        .toolbar(.hidden, for: .navigationBar)
        .ledgerBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ReturnLine(tab: .company)
                header
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)
                    .environment(\.outsidePalette, P.isLight ? OutsidePalette.forest : P)
            }
            .background((P.isLight ? FinanceColor.forest : P.ground).ignoresSafeArea(edges: .top))
        }
        .onAppear { take() }
        .onChange(of: store.appRequest) { _, _ in take() }
        .environment(\.outsidePalette, P)
    }

    private var header: some View {
        let t: (String, String) = titles
        let label: String = account == nil ? "Back to Phone" : "Back to accounts"
        return AppHeader(title: t.0, subtitle: t.1, onBack: { back() }, backLabel: label)
    }

    private var titles: (String, String) {
        guard let e = store.engine else { return ("Bank", "") }
        guard let account else { return ("Bank", "Your money in one place") }
        let d = e.bankAccount(account)
        return (d?.name ?? "Account", d?.detail ?? "")
    }

    private func back() {
        if account != nil { Motion.animate(Motion.quickAnimation) { account = nil } } else { dismiss() }
    }

    private func take() {
        guard let r = store.takeBankRequest() else { return }
        if let amount = r.applyLoan { store.pendingLoanApply = amount }
        tab = r.tab
        account = r.account
    }
}

struct BankCard<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String = ""
    var trailing: String = ""
    @ViewBuilder var content: () -> Content
    var body: some View {
        if title.isEmpty {
            Card(padding: 14) { VStack(alignment: .leading, spacing: Theme.Space.s) { content() } }
        } else {
            CardSection(title: title, trailing: {
                if !trailing.isEmpty { Text(trailing.tidyText).textStyle(.caption, tint: P.inkFaint) }
            }) { content() }
        }
    }
}
