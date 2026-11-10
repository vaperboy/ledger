import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct OpsPageDestination: View {
    @EnvironmentObject var store: GameStore
    var part: OpsPart
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            page(e, co)
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func page(_ e: GameEngine, _ co: Company) -> some View {
        switch part {
        case .setup: EmptyView()
        case .premises: premisesPage(e, co)
        case .equipment: CompanyEquipmentScreen(companyID: co.id)
        case .insurance: CompanyCoverageScreen(companyID: co.id)
        case .accountant: CompanyAccountantScreen(companyID: co.id)
        case .licences: SettingsPage(title: "Licences", subtitle: co.name) { CompanyLicences(engine: e, company: co) }
        }
    }

    @ViewBuilder private func premisesPage(_ e: GameEngine, _ co: Company) -> some View {
        if e.tradeInfo(companyID: co.id)?.family == "rent" {
            SettingsPage(title: "Properties", subtitle: co.name) { CompanyProperties(engine: e, company: co) }
        } else {
            EmptyState(glyph: Glyph.airStay, title: "Premises are in AirStay", message: "Places to rent and buy are in AirStay.")
                .frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }
}

struct OpsSettingSheet: View {
    @EnvironmentObject var store: GameStore
    var kind: OpsSheet
    var companyID: Int

    var body: some View {
        PeopleSheet(title: title) {
            if let e = store.engine, let co = e.state.company(companyID) {
                content(co)
            } else {
                Text("This company no longer exists.").popupText(.body)
            }
        }
    }

    private var title: String {
        switch kind {
        case .upkeep: return "Upkeep"
        }
    }

    @ViewBuilder private func content(_ co: Company) -> some View {
        switch kind {
        case .upkeep: upkeepBody(co)
        }
    }

    private func upkeepBody(_ co: Company) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("MAINTENANCE").capsLabel()
            levelBody(co, names: OpsWords.maintenance, current: co.maintenance, note: "Thorough upkeep costs more but equipment breaks less.") { level in
                store.act { $0.setMaintenance(companyID: co.id, level: level) }
                store.saved("Maintenance: \(OpsWords.name(OpsWords.maintenance, level).lowercased())")
            }
            Text("STOCK").capsLabel()
            levelBody(co, names: OpsWords.stock, current: co.int("stockPol", 1), note: "Generous stock avoids running out but ties up cash.") { level in
                store.act { $0.setStockPolicy(companyID: co.id, level: level) }
                store.saved("Stock: \(OpsWords.name(OpsWords.stock, level).lowercased())")
            }
        }
    }

    private func levelBody(_ co: Company, names: [String], current: Int, note: String, set: @escaping (Int) -> Void) -> some View {
        let binding = Binding<Int>(get: { current }, set: { set($0) })
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SegmentedPill(items: [0, 1, 2], title: { names[$0] }, selection: binding)
                Text(note).popupText(.caption)
            }
        }
    }
}

struct CompanyLookRow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var company: Company
    @State private var open = false
    private let session = StoreSession.shared

    var body: some View {
        let card: CardDef? = store.engine?.companyCard(company.id, cabinet: session.state.cabinet)
        let logo: String = LogoCatalogue.logo(store.engine?.companyLogoID(companyID: company.id) ?? "")?.name ?? ""
        let parts: [String] = [card?.name ?? "", logo].filter { (s: String) -> Bool in !s.isEmpty }
        PageGroup("") {
            LedgerRow(leading: .glyph(Glyph.luxury), leadingTint: P.inkSoft, title: "Look", subtitle: parts.isEmpty ? "Card, colours and logo" : parts.joined(separator: " \u{00B7} "),
                      identifier: "manage-look") { open = true }
        }
        .navigationDestination(isPresented: $open) { CompanyLookView(companyID: company.id) }
    }
}

struct CompanyLookView: View {
    enum Part: String, CaseIterable, Identifiable {
        case card, colours, logo
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var companyID: Int
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @AppStorage(CosmeticKeys.badge) private var globalBadge: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var globalTheme: String = Cosmetics.defaultThemeID
    private let session = StoreSession.shared
    @State private var part: Part = .card
    @State private var pending: PendingAction?
    @State private var note = ""

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)]

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                let cabinet: Cabinet = session.state.cabinet
                VStack(spacing: Theme.Space.m) {
                    preview(e, co, cabinet)
                    SegmentedPill(items: Part.allCases, title: { (p: Part) -> String in p.title }, selection: $part, identifier: { (p: Part) -> String in "company-look-" + p.rawValue })
                    if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.accent).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2) }
                    ScrollView {
                        content(e, co, cabinet).padding(.bottom, Theme.Space.l)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            } else {
                Text("This company no longer exists.").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .appScreen(title: "Look", subtitle: store.engine?.state.company(companyID)?.name ?? "")
        .confirmAction($pending)
        .task { await session.load() }
    }

    private func style(_ e: GameEngine) -> (theme: String, badge: String) {
        let s: (theme: String, badge: String) = e.companyStyle(companyID: companyID)
        return (s.theme.isEmpty ? globalTheme : s.theme, s.badge.isEmpty ? globalBadge : s.badge)
    }

    private func preview(_ e: GameEngine, _ co: Company, _ cabinet: Cabinet) -> some View {
        let s: (theme: String, badge: String) = style(e)
        let badge: Cosmetics.Badge = Cosmetics.resolvedBadge(s.badge, earned: e.careerCosmetics, pro: ent.isPro)
        let accent: Color = Cosmetics.resolvedTheme(s.theme, pro: ent.isPro).accent
        let logo: String = e.companyLogoID(companyID: co.id)
        return VStack(spacing: Theme.Space.s) {
            CompanyCardView(name: co.name, def: e.companyCard(co.id, cabinet: cabinet))
            HStack(spacing: Theme.Space.m) {
                if logo.isEmpty { ThumbnailView(kind: .trade, key: co.type, size: 28) } else { LogoBadge(logoID: logo, size: 28) }
                CosmeticBadgeView(badge: badge, tint: accent, size: 24)
            }
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company, _ cabinet: Cabinet) -> some View {
        switch part {
        case .card: cardGrid(e, co, cabinet)
        case .colours: colours(e, co)
        case .logo: logoGrid(e, co)
        }
    }

    private func replace(_ item: String, on other: String, then run: @escaping () -> Void) {
        pending = PendingAction(title: "Replace?", message: item + " is on " + other + ". Move it here?", button: "Move", alwaysAsk: true, run: run)
    }

    private func cardGrid(_ e: GameEngine, _ co: Company, _ cabinet: Cabinet) -> some View {
        let owned: [ArtifactItem] = cabinet.sorted.filter { (i: ArtifactItem) -> Bool in CardCatalog.def(forItem: i.id)?.kind == .company }
        let used: [Int: String] = e.companyCardAssignments()
        return Group {
            if owned.isEmpty {
                Text("You do not own a company card yet. Open a card pack, climb the Season Pass or level up.").textStyle(.body, tint: Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                    ForEach(owned) { (item: ArtifactItem) in
                        if let d = CardCatalog.def(forItem: item.id) {
                            let holder: Int? = used.first(where: { (_: Int, v: String) -> Bool in v == item.id })?.key
                            let here: Bool = holder == co.id
                            let elsewhere: String? = holder.flatMap { (id: Int) -> String? in id == co.id ? nil : e.state.company(id)?.name }
                            LookTile(title: d.name, note: elsewhere.map { (n: String) -> String in "On " + n } ?? (d.isAnimated ? "Animated" : ""), worn: here, wornText: "On this company", locked: false,
                                     id: "company-card-" + item.id, art: CardThumb(def: d, width: 72), action: { pickCard(item, d, here: here, elsewhere: elsewhere) })
                        }
                    }
                }
            }
        }
    }

    private func pickCard(_ item: ArtifactItem, _ d: CardDef, here: Bool, elsewhere: String?) {
        let id: Int = companyID
        let cabinet: Cabinet = session.state.cabinet
        let apply: () -> Void = {
            Haptics.success()
            _ = store.act { (e: inout GameEngine) -> Void in _ = e.applyCompanyCard(itemID: item.id, companyID: id, cabinet: cabinet) }
            note = ""
        }
        if here {
            Haptics.choose()
            _ = store.act { (e: inout GameEngine) -> Void in e.clearCompanyCard(companyID: id) }
        } else if let other = elsewhere {
            replace(d.name, on: other, then: apply)
        } else {
            apply()
        }
    }

    private func colours(_ e: GameEngine, _ co: Company) -> some View {
        let id: Int = companyID
        let s: (theme: String, badge: String) = style(e)
        let theme = Binding<String>(get: { s.theme }, set: { (v: String) in _ = store.act { (g: inout GameEngine) -> Void in _ = g.setCompanyStyle(companyID: id, theme: v) } })
        let badge = Binding<String>(get: { s.badge }, set: { (v: String) in _ = store.act { (g: inout GameEngine) -> Void in _ = g.setCompanyStyle(companyID: id, badge: v) } })
        return ColourBadgePicker(earned: e.careerCosmetics, theme: theme, badge: badge)
    }

    private func logoGrid(_ e: GameEngine, _ co: Company) -> some View {
        let current: String = e.companyLogoID(companyID: co.id)
        return LazyVGrid(columns: columns, spacing: Theme.Space.s) {
            ForEach(e.logoChoices()) { (c: LogoChoice) in
                let elsewhere: String? = e.companyUsingLogo(c.id, besides: co.id)?.name
                LookTile(title: c.logo.name, note: c.unlocked ? (elsewhere.map { (n: String) -> String in "On " + n } ?? "") : c.how, worn: c.id == current, wornText: "In use", locked: !c.unlocked,
                         id: "company-logo-" + c.id, art: LogoBadge(logoID: c.id, size: 48), action: { pickLogo(c, current: current, elsewhere: elsewhere) })
            }
        }
    }

    private func pickLogo(_ c: LogoChoice, current: String, elsewhere: String?) {
        let id: Int = companyID
        let logoID: String = c.id
        guard c.unlocked else { Haptics.warning(); note = c.logo.name + ": " + c.how; return }
        let apply: () -> Void = {
            Haptics.success()
            _ = store.act { (e: inout GameEngine) -> Void in _ = e.setCompanyLogo(companyID: id, logoID: logoID) }
            note = ""
        }
        if c.id == current {
            Haptics.choose()
            _ = store.act { (e: inout GameEngine) -> Void in _ = e.clearCompanyLogo(companyID: id) }
        } else if let other = elsewhere {
            replace(c.logo.name, on: other, then: apply)
        } else {
            apply()
        }
    }
}
