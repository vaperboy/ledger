import SwiftUI
import GameCore
import Countries
import Simulation

/// The tabs of one Bank account (BankAccount.dc.html).
enum BankTab: String, CaseIterable, Hashable {
    case account = "Account", loans = "Loans", deposits = "Deposits", bills = "Bills", statements = "Statements"
}

/// Where a link into the Bank app lands: an account, and optionally one of its tabs.
struct BankRequest: Equatable {
    var account: BankAccountID
    var tab: BankTab = .account
}

/// Money in an account's own currency, through the store formatter (a company's in its own currency, the others in the home currency).
@MainActor
struct BankFmt {
    var store: GameStore
    var company: Company?
    func short(_ v: Double) -> String { company.map { store.short(v, in: $0) } ?? store.short(v) }
    func full(_ v: Double) -> String { company.map { store.money(v, in: $0) } ?? store.money(v) }
    func currency(_ e: GameEngine) -> Currency { company.map { e.currency(for: $0) } ?? e.homeCurrency }
    static func make(_ store: GameStore, _ id: BankAccountID) -> BankFmt {
        BankFmt(store: store, company: id.companyID.flatMap { store.engine?.state.company($0) })
    }
}

/// Icons of the Bank app that the shared set does not have.
enum BankGlyph {
    static let transfer = "M4 8 H19 M15 4 L19 8 L15 12 M20 16 H5 M9 12 L5 16 L9 20"
    static let deposit = "M12 4 V16 M7 11 L12 16 L17 11 M5 20 H19"
    static let withdraw = "M12 16 V4 M7 9 L12 4 L17 9 M5 20 H19"
    static let bill = "M6 3 H18 V21 L15 19 L12 21 L9 19 L6 21 Z M9 8 H15 M9 12 H15"
    static let company = "M4 20 V8 L12 4 L20 8 V20 M9 20 V13 H15 V20"
}

/// The Bank app: pick an account, then manage it. It shows both screens itself so the header's round back button can go from an account
/// to the list before it leaves the app; links from elsewhere (a company's "Open in Bank", an Inbox warning) arrive as `store.bankRequest`.
struct BankApp: View {
    private var P: OutsidePalette { store.engine?.playerMainBankIsOwn == true ? .game : .bank }
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    /// The account the player logged in as; nil shows the picker (the first page). `account` is nil on the all-accounts overview.
    @State private var session: BankAccountID?
    @State private var account: BankAccountID?
    @State private var tab: BankTab = .account

    var body: some View {
        Group {
            if session == nil {
                BankPickerScreen { id in tab = .account; account = id; session = id }
            } else if let account {
                BankAccountScreen(id: account, tab: $tab)
            } else {
                BankAccountsScreen(lockedTo: session) { id in tab = .account; account = id }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .ledgerBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ReturnLine(tab: .phone)
                header
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)
            }
            .background(P.ground)
        }
        .onAppear { take() }
        .onChange(of: store.bankRequest) { _, _ in take() }
        // Someone else's bank app, in its own navy and teal, unless the player's own bank is the main bank: then the game's colours.
        .environment(\.outsidePalette, P)
    }

    private var header: some View {
        let t: (String, String) = titles
        let label: String = account == nil ? "Back to Phone" : "Back to accounts"
        return AppHeader(title: t.0, subtitle: t.1, onBack: { back() }, backLabel: label) {
            if session != nil {
                SmallOutlineButton(title: "Log out") { logOut() }
                    .accessibilityIdentifier("bank-log-out")
            }
        }
    }

    private var titles: (String, String) {
        guard let e = store.engine else { return ("Bank", "") }
        guard session != nil else { return ("Bank", "Choose an account") }
        guard let account else {
            let n: Int = e.bankAccounts().alertCount
            let who: String = n == 1 ? "a company" : "\(n) companies"
            return ("Bank", n > 0 ? "Choose an account · payroll waits on \(who)" : "Choose an account")
        }
        let d = e.bankAccount(account)
        return (d?.name ?? "Account", d?.detail ?? "")
    }

    private func back() {
        if account != nil { withAnimation(.snappy(duration: 0.2)) { account = nil } } else { dismiss() }
    }

    private func logOut() {
        withAnimation(.snappy(duration: 0.2)) { account = nil; session = nil; tab = .account }
    }

    private func take() {
        guard let r = store.bankRequest else { return }
        store.bankRequest = nil
        tab = r.tab
        account = r.account
        session = r.account
    }
}

/// A caps label over a card, the section style of the Bank app.
struct BankCard<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String = ""
    var trailing: String = ""
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).capsLabel()
                    Spacer(minLength: 8)
                    if !trailing.isEmpty { Text(trailing.tidyText).font(.system(size: 11.5)).foregroundStyle(P.inkFaint) }
                }
            }
            Card(padding: 14, radius: Theme.Radius.hero) { content() }
        }
    }
}
