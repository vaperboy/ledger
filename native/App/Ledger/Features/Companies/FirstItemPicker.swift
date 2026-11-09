import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The first choice of a new company: the starter products or services the trade can begin with, one selectable row each (market price
/// and kind), a primary button to confirm, and the path to add your own. Shown by `ItemsList` while `needsFirstItemChoice` is true.
struct FirstItemPicker: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var noun: String
    var onAddOwn: () -> Void
    /// Called with the id of the item that was picked, so the caller can ask who supplies it.
    var onChosen: (String) -> Void = { _ in }
    @State private var picked: String?
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let choices: [SalesItem] = engine.firstItemChoices(companyID: company.id)
        let selected: String? = picked ?? choices.first?.id
        return VStack(spacing: 0) {
            Text("Pick the \(noun) you start with. You can add more later.").textStyle(.caption, tint: P.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, Theme.Space.s)
            LazyVStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { (i: Int, it: SalesItem) in
                    if i > 0 { RowRule(inset: 52) }
                    let on: Bool = it.id == selected
                    let id: String = it.id
                    LedgerRow(leading: .symbol(on ? "checkmark.circle.fill" : "circle"), leadingTint: on ? P.accent : P.inkFaint,
                              title: it.name, subtitle: it.isService ? "Service" : "Product", value: itemAmount(it.marketPrice, cur),
                              valueNote: "market price", lineLimit: 1, identifier: "first-item-\(id)") { Haptics.tap(); picked = id }
                }
            }
            AcctPrimaryButton(title: "Start with this \(noun)", enabled: selected != nil, identifier: "first-item-confirm") { confirm(selected) }
                .padding(.top, Theme.Space.m)
            Button { Haptics.tap(); onAddOwn() } label: {
                Text("Or add your own \(noun)").textStyle(.headline, tint: P.accent).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(AcctPressStyle())
            .accessibilityIdentifier("sales-add-item")
        }
        .coachAnchor(.firstPick)
    }

    private func confirm(_ itemID: String?) {
        guard let itemID else { return }
        let id: Int = company.id
        let r = store.act { $0.chooseFirstItem(companyID: id, itemID: itemID) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else { Haptics.success(); onChosen(itemID) }
    }
}
