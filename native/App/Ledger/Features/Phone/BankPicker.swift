import SwiftUI
import GameCore
import Countries
import Simulation

/// The first page of the Bank app: whose account to open. Lists the accounts the bank already has (the player personally, the investments
/// account, each company); choosing one opens the Bank for it. "Log out" inside the Bank comes back here, the only way to swap account.
struct BankPickerScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var onPick: (BankAccountID) -> Void

    var body: some View {
        if let e = store.engine {
            let rows: [BankAccountRow] = e.bankAccounts().rows
            let you: [BankAccountRow] = rows.filter { $0.kind == .personal }
            let group: [BankAccountRow] = rows.filter { $0.kind == .investments }
            let companies: [BankAccountRow] = rows.filter { $0.kind == .company }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    section("YOU", you, e)
                    section("GROUP", group, e)
                    section("YOUR COMPANIES", companies, e)
                    Text("Choose whose account to open. Log out inside the bank to swap.")
                        .font(.system(size: 11.5)).foregroundStyle(P.inkFaint).padding(.horizontal, 4)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("bank-picker")
        }
    }

    @ViewBuilder private func section(_ title: String, _ rows: [BankAccountRow], _ e: GameEngine) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).capsLabel()
                ForEach(rows) { r in row(r, e) }
            }
        }
    }

    private func row(_ r: BankAccountRow, _ e: GameEngine) -> some View {
        let co: Company? = r.companyID.flatMap { e.state.company($0) }
        let glyph: String = r.kind == .personal ? Glyph.person : r.kind == .investments ? Glyph.invest : BankGlyph.company
        let sub: String = r.hasAlert ? (r.alertNote ?? r.detail) : r.kind == .investments ? "Shares · crypto · funds" : r.kind == .personal ? "Personal accounts" : r.detail
        return Button { Haptics.tap(); onPick(r.id) } label: {
            CardRow(glyph: glyph, title: r.name, subtitle: sub, badge: r.hasAlert ? 1 : 0,
                    thumb: co.map { ThumbSpec(kind: .trade, key: $0.type, glyph: glyph) })
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bank-pick-\(r.id.id)")
    }
}
