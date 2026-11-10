import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

enum GroupAddDestination: String, Identifiable, Hashable {
    case newCompany, outlet, holding, franchise, club
    var id: String { rawValue }
}

struct GroupOutletPicker: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            let companies: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.status == .open && CompanyChain.isRelevant(c, e) }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if companies.isEmpty {
                        EmptyState(glyph: Glyph.group, title: "No company can open another outlet yet", message: "Open a company and let it trade first.")
                    } else {
                        ForEach(companies, id: \.id) { (c: Company) in row(e, c) }
                    }
                }
                .environment(\.insideCard, true)
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.page)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag()
            .ledgerBackground()
            .appScreen(title: "Open another outlet", subtitle: "Pick the company to copy", tab: .group)
        }
    }

    private func row(_ e: GameEngine, _ c: Company) -> some View {
        let ready: Expansion.Readiness? = Expansion.readiness(e.state, data: e.data, companyID: c.id, cityID: c.cityID)
        let cost: String = ready.map { (r: Expansion.Readiness) -> String in store.short(r.startCost, in: c) } ?? ""
        let note: String = ready.map { (r: Expansion.Readiness) -> String in r.enoughCash ? "Ready" : "Needs cash" } ?? ""
        return Button { Haptics.tap(); store.openGroupEntity(companyID: c.id, section: "expansion") } label: {
            CardRow(glyph: Glyph.group, title: c.name, subtitle: note, value: cost)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("group-outlet-\(c.id)")
    }
}

struct GroupAddMenu: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var onPick: (GroupAddDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            row(.newCompany, title: "New company", line: "Any trade, any city", id: "group-add-company")
            row(.outlet, title: "Open another outlet", line: "A second place for a trade you run", id: "group-add-outlet")
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
