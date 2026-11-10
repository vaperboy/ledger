import SwiftUI
import GameCore
import Businesses
import Simulation

/// Set on the root screen of the Custom tab: the tab root has nothing to go back to, so the round back button of an app header is hidden.
private struct HidesRootBackKey: EnvironmentKey { static let defaultValue: Bool = false }
extension EnvironmentValues {
    var hidesRootBack: Bool {
        get { self[HidesRootBackKey.self] }
        set { self[HidesRootBackKey.self] = newValue }
    }
}

/// The Custom tab: the chosen destination as the root of its own navigation stack. Phone apps are the very same `PhoneAppScreen` the
/// Phone tab opens; what they link to (a company, another app) is pushed on this stack, so Back works. Tapping the tab again returns to the root.
struct CustomTabView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        NavigationStack(path: Binding<[NavRoute]>(get: { store.customPath }, set: { store.setCustomPath($0) })) {
            root
                .environment(\.hidesRootBack, true)
                .id(rootIdentity)
                .companyRouteDestinations()
        }
        .accessibilityIdentifier("custom-tab")
    }

    private var rootIdentity: String { "\(String(describing: store.customTarget))-\(store.rootToken(.custom))" }

    @ViewBuilder private var root: some View {
        switch store.customTarget {
        case .app(let app):
            PhoneAppScreen(app: app)
        case .company(let id):
            if store.engine?.state.company(id) != nil { CompanyRouteDestination(route: .company(id)) } else { PhoneAppScreen(app: .inbox) }
        }
    }
}

/// The compact popup that changes the Custom tab: a grid of destinations with their icons, and "A company" for a second step that lists
/// the player's companies.
struct CustomTabPicker: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @State private var choosingCompany = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(choosingCompany ? "The tab shows this company's page." : "Choose what this tab opens.").popupText(.subtitle)
            if choosingCompany { companyList } else { appGrid }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(choosingCompany ? "Which company?" : "Custom tab")
        .accessibilityIdentifier("custom-picker")
    }

    /// Every Phone app (Store and Market included), then "A company's page".
    private var appGrid: some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CustomTabTarget.apps) { (app: PhoneApp) in appCell(app) }
            }
            if hasCompanies { companyEntry }
        }
    }

    private func appCell(_ app: PhoneApp) -> some View {
        let on: Bool = store.customTarget == CustomTabTarget.app(app)
        return Button {
            Haptics.tap()
            store.chooseCustom(.app(app))
        } label: {
            VStack(spacing: 5) {
                IconCircle(glyph: app.glyph, size: 40, tint: on ? Theme.gold : nil)
                Text(app.title).textStyle(.caption, tint: on ? Theme.accent : P.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(app.title)
        .accessibilityIdentifier("custom-pick-\(app.title)")
    }

    private var companyEntry: some View {
        Button {
            Haptics.tap()
            choosingCompany = true
        } label: {
            HStack(spacing: 10) {
                IconCircle(glyph: Glyph.home, size: 32)
                Text("A company's page").popupText(.button)
                Spacer(minLength: 8)
                GlyphView(glyph: Glyph.chevron, size: 12, weight: 1.8, tint: P.inkFaint)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("custom-pick-company")
    }

    private var hasCompanies: Bool { !companyChoices.isEmpty }

    private struct Choice: Identifiable {
        var id: Int
        var name: String
    }

    private var companyChoices: [Choice] {
        guard let e = store.engine else { return [] }
        let list = e.state.companies.filter { $0.type != "hold" && $0.status != .sold }
        return list.map { Choice(id: $0.id, name: $0.name) }
    }

    private var companyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(companyChoices) { (c: Choice) in
                Button {
                    Haptics.tap()
                    store.chooseCustom(.company(c.id))
                } label: {
                    HStack(spacing: 10) {
                        IconCircle(glyph: Glyph.home, size: 32)
                        Text(c.name).popupText(.body).lineLimit(1)
                        Spacer(minLength: 8)
                        if store.customTarget == CustomTabTarget.company(c.id) { GlyphView(glyph: Glyph.chevron, size: 12, weight: 1.8, tint: Theme.gold) }
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            Button("Back to the apps") { choosingCompany = false }
                .buttonStyle(QuietButtonStyle()).padding(.top, 8)
        }
    }
}
