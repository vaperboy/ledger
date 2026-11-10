import SwiftUI
import GameCore
import Countries
import Simulation

enum BankTab: String, CaseIterable, Hashable {
    case loans = "Loans", statements = "Statements"
}

struct BankRequest: Equatable {
    var account: BankAccountID
    var tab: BankTab = .loans
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
    @State private var tab: BankTab = .loans

    var body: some View {
        Group {
            BankAccountScreen(id: .personal, tab: $tab)
        }
        .navigationBarBackButtonHidden(true)
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
        AppHeader(title: "Bank", subtitle: "", onBack: { dismiss() }, backLabel: "Back to Phone")
    }

    private func take() {
        guard let r = store.takeBankRequest() else { return }
        if let amount = r.applyLoan { store.pendingLoanApply = amount }
        tab = r.tab
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
