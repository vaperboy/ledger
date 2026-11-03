import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Where "Add to group" leads. Every destination is an existing flow.
enum GroupAddDestination: String, Identifiable, Hashable {
    case newCompany, holding, franchise, club
    var id: String { rawValue }
}

/// The centred popup of the Group landing: the four ways to grow the group, each with one line of explanation. A tap closes the popup and
/// opens the flow (the Group tab pushes it).
struct GroupAddMenu: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var onPick: (GroupAddDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick how the group grows.").font(.system(size: 12.5)).foregroundStyle(P.inkSoft)
            row(.newCompany, title: "New company", line: "Start a business from scratch in a trade and city of your choice.", id: "group-add-company")
            row(.holding, title: "Holding company", line: "Owns your other companies and collects their dividends.", id: "group-add-holding")
            row(.franchise, title: "Join a franchise", line: "Run a known brand under its rules, for a fee.", id: "group-add-franchise")
            row(.club, title: "Buy or found a football club", line: "Buy a club in a top league, or found a new one.", id: "group-add-club")
        }
        .centerSheetTitle("Add to group")
    }

    private func row(_ d: GroupAddDestination, title: String, line: String, id: String) -> some View {
        HStack(spacing: 6) {
            Button { Haptics.tap(); onPick(d) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(P.ink)
                    Text(line).font(.system(size: 12)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 4)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

/// What a holding company is for, in plain words, with the engine's real tax rules (dividend rate of the home country, the 90 percent tax group).
enum HoldingRules {
    static func text(_ engine: GameEngine?) -> String {
        var rate: String = "a dividend tax"
        if let e = engine {
            let r: Double = e.homeCountry.dividendTax
            rate = "\(Int((r * 100).rounded())) percent dividend tax"
        }
        return "A holding company owns your other limited companies. When a company it owns pays a dividend, the money goes into the holding's cash and "
            + "no personal dividend tax is taken at that step. Dividend tax (\(rate) in your home country, above a tax-free allowance) is due only when "
            + "the holding pays you. Companies in one country that it owns 90 percent or more of form a tax group: one company's profit covers a sister's loss. "
            + "It is also one place for the group's dividends and its board."
    }
}

/// The small (i) that explains the holding company in a popover.
struct HoldingInfoButton: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @State private var open = false

    var body: some View {
        Button { Haptics.tap(); open.toggle() } label: {
            Text("i").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ivoryMuted)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("What is a holding company")
        .accessibilityIdentifier("holding-info")
        .contextPopover(isPresented: $open) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Holding company").font(.system(size: 14, weight: .semibold)).foregroundStyle(P.ink)
                Text(HoldingRules.text(store.engine)).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
