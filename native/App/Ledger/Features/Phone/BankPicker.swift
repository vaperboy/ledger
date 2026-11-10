import SwiftUI
import GameCore
import Countries
import Simulation

struct BankPickerScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var onPick: (BankAccountID) -> Void

    var body: some View {
        if let e = store.engine {
            let rows: [BankAccountRow] = e.bankAccounts().rows
            let you: [BankAccountRow] = rows.filter { $0.kind == .personal }
            let companies: [BankAccountRow] = rows.filter { $0.kind == .company }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    section("YOU", you, e)
                    section("YOUR COMPANIES", companies, e)
                    Text("Choose an account. Back from it shows every account and the totals.")
                        .textStyle(.caption, tint: P.inkFaint).padding(.horizontal, 4)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag().scrollBounceBehavior(.basedOnSize)
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
        let glyph: String = r.kind == .personal ? Glyph.person : BankGlyph.company
        let sub: String = r.kind == .personal ? "Personal accounts" : r.detail
        return Button { Haptics.tap(); onPick(r.id) } label: {
            CardRow(glyph: glyph, title: r.name, subtitle: sub,
                    thumb: co.map { ThumbSpec(kind: .trade, key: $0.type, glyph: glyph) })
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("bank-pick-\(r.id.id)")
    }
}
