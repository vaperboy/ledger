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
        NavigationStack(path: Binding<[PhoneHome.Page]>(get: { store.customPath }, set: { store.setCustomPath($0) })) {
            root
                .environment(\.hidesRootBack, true)
                .id(rootIdentity)
                .navigationDestination(for: PhoneHome.Page.self) { (page: PhoneHome.Page) in destination(page) }
                .companyRouteDestinations()
        }
        .accessibilityIdentifier("custom-tab")
    }

    private var rootIdentity: String { "\(String(describing: store.customTarget))-\(store.rootToken(.custom))" }

    @ViewBuilder private var root: some View {
        if let target = store.customTarget {
            switch target {
            case .app(let app): PhoneAppScreen(app: app)
            case .company(let id): CompanyRouteDestination(route: .company(id))
            }
        } else {
            CustomTabEmpty()
        }
    }

    @ViewBuilder private func destination(_ page: PhoneHome.Page) -> some View {
        switch page {
        case .app(let app): PhoneAppScreen(app: app)
        case .company(let route): CompanyRouteDestination(route: route)
        }
    }
}

/// The Custom tab before a destination is picked: a short invitation, then the same picker as the long-press one, as a page.
struct CustomTabEmpty: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P

    var body: some View {
        ScrollScreen(spacing: Theme.Space.xl, top: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Make this tab yours").textStyle(.display).fixedSize(horizontal: false, vertical: true)
                Text("Pin the app or company you open most. Long-press the tab to change it.").textStyle(.body, tint: P.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            CustomTabPicker(pickingFirst: true)
        }
        .ledgerBackground()
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("custom-empty")
    }
}

/// The picker that changes the Custom tab (a popup from a long press, or the empty tab's page): the apps as a grid of icons, and
/// "A company's page" for a second step that lists the player's companies.
struct CustomTabPicker: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @State private var choosingCompany = false
    /// True on the empty Custom tab, where the picker is the whole page under its own invitation.
    var pickingFirst = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if !pickingFirst || choosingCompany {
                Text(choosingCompany ? "The tab shows this company's page." : "Choose what this tab opens.").popupText(.subtitle)
            }
            if choosingCompany { companyList } else { appGrid }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(choosingCompany ? "Which company?" : (pickingFirst ? "Pick tab" : "Custom tab"))
        .accessibilityIdentifier("custom-picker")
    }

    private var appGrid: some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.xs, alignment: .top), count: 4)
        let apps: [PhoneApp] = CustomTabTarget.apps
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            if pickingFirst { Text("Apps").textStyle(.label, tint: P.inkFaint) }
            LazyVGrid(columns: columns, spacing: Theme.Space.l) {
                ForEach(apps) { (app: PhoneApp) in
                    appCell(app)
                }
            }
            if hasCompanies {
                if pickingFirst { Text("Or a company").textStyle(.label, tint: P.inkFaint).padding(.top, Theme.Space.s) }
                companyEntry
            }
        }
    }

    /// One app: its Phone icon and name; the current choice carries a champagne ring.
    private func appCell(_ app: PhoneApp) -> some View {
        let on: Bool = store.customTarget == CustomTabTarget.app(app)
        let tile: CGFloat = pickingFirst ? 58 : 50
        return Button {
            Haptics.tap()
            store.chooseCustom(.app(app))
        } label: {
            VStack(spacing: Theme.Space.xs) {
                AppIconTile(glyph: app.glyph, size: tile, tint: app.tint)
                    .overlay {
                        if on {
                            RoundedRectangle(cornerRadius: Theme.Radius.appIcon * tile / 62 + 3, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 1.5).padding(-3)
                        }
                    }
                Text(app.title).textStyle(.caption, tint: on ? Theme.accent : P.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(app.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("custom-pick-\(app.title)")
    }

    private var companyEntry: some View {
        LedgerRow(leading: .glyph(Glyph.home), title: "A company's page", subtitle: "Any company you own, at its overview",
                  identifier: "custom-pick-company", action: { choosingCompany = true })
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
                let on: Bool = store.customTarget == CustomTabTarget.company(c.id)
                LedgerRow(leading: .glyph(Glyph.home), title: c.name, value: on ? "Pinned" : "", valueTint: Theme.accent,
                          chevron: !on, action: { store.chooseCustom(.company(c.id)) })
                Hairline()
            }
            Button("Back to the apps") { Haptics.tap(); choosingCompany = false }
                .buttonStyle(TertiaryButtonStyle()).padding(.top, Theme.Space.s)
        }
    }
}
