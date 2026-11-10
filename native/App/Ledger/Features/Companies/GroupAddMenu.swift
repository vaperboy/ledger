import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

enum GroupAddDestination: String, Identifiable, Hashable {
    case newCompany, holding, franchise, club
    var id: String { rawValue }
}

struct GroupAddMenu: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var onPick: (GroupAddDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            row(.newCompany, title: "New company", line: "Any trade, any city", id: "group-add-company")
            row(.holding, title: "Holding company", line: "Owns your companies, collects their dividends", id: "group-add-holding")
            row(.franchise, title: "Join a franchise", line: "A known brand, for a fee", id: "group-add-franchise")
        }
        .centerSheetTitle("Add to group")
    }

    private func row(_ d: GroupAddDestination, title: String, line: String, id: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button { Haptics.tap(); onPick(d) } label: {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).popupText(.button)
                    Text(line).popupText(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier(id)
            if d == .holding { HoldingInfoButton() }
            else { GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim) }
        }
        .padding(.vertical, Theme.Space.xs)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

enum HoldingRules {
    static func text(_ engine: GameEngine?) -> String {
        var rate: String = "a dividend tax"
        if let e = engine {
            let r: Double = e.homeCountry.dividendTax
            rate = "\(Int(saturating: (r * 100).rounded())) percent dividend tax"
        }
        return "A holding company owns your other limited companies. When a company it owns pays a dividend, the money goes into the holding's cash and "
            + "no personal dividend tax is taken at that step. Dividend tax (\(rate) in your home country, above a tax-free allowance) is due only when "
            + "the holding pays you. Companies in one country that it owns 90 percent or more of form a tax group: one company's profit covers a sister's loss. "
            + "It is also one place for the group's dividends and its board."
    }
}

struct HoldingInfoButton: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        InfoSheetButton(title: "Holding company", text: HoldingRules.text(store.engine), label: "What is a holding company", identifier: "holding-info")
    }
}
