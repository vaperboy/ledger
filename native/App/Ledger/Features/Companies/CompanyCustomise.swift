import SwiftUI
import GameCore
import Businesses
import Simulation

struct CompanyCardPreview: View {
    var name: String
    var def: CardDef?
    var logoID: String
    var tradeKey: String
    var badge: Cosmetics.Badge
    var accent: Color

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            CompanyCardView(name: name, def: def, logoID: logoID)
            HStack(spacing: Theme.Space.m) {
                if logoID.isEmpty { ThumbnailView(kind: .trade, key: tradeKey, size: 28) } else { LogoBadge(logoID: logoID, size: 28) }
                CosmeticBadgeView(badge: badge, tint: accent, size: 24)
            }
        }
    }
}

struct CompanyCustomiseButton: View {
    var companyID: Int
    @State private var open = false

    var body: some View {
        HomeRoundButton(glyph: Glyph.luxury, label: "Customise", identifier: "company-customise") { open = true }
            .navigationDestination(isPresented: $open) { CompanyCustomiseView(companyID: companyID) }
    }
}

struct CompanyCustomiseView: View {
    enum Part: String, CaseIterable, Identifiable {
        case card, colours, logo, plate
        var id: String { rawValue }
        var title: String { self == .plate ? "Profile plate" : rawValue.capitalized }
    }

    static let skipPrice = 40

    var companyID: Int
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @AppStorage(CosmeticKeys.badge) private var globalBadge: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var globalTheme: String = Cosmetics.defaultThemeID
    @ObservedObject private var season = SeasonModel.shared
    private let session = StoreSession.shared
    @State private var part: Part = .card
    @State private var pending: PendingAction?
    @State private var note = ""
    @State private var newName = ""
    @State private var shortOfGold = false
    @State private var shortNeed = 0
    @State private var showPacks = false
    @State private var shareURL: URL?

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)]

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                let cabinet: Cabinet = session.state.cabinet
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        preview(e, co, cabinet)
                        nameSection(e, co)
                        SegmentedPill(items: Part.allCases, title: { (p: Part) -> String in p.title }, selection: $part, identifier: { (p: Part) -> String in "company-look-" + p.rawValue })
                        if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.accent).frame(maxWidth: .infinity, alignment: .leading).lineLimit(3) }
                        content(e, co, cabinet)
                    }
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onAppear { refreshShare(e, co, cabinet) }
                .onChange(of: signature(e, co, cabinet)) { _, _ in refreshShare(e, co, cabinet) }
            } else {
                Text("This company no longer exists.").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .appScreen(title: "Customise", subtitle: store.engine?.state.company(companyID)?.name ?? "")
        .confirmAction($pending)
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") { ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true }) }
        .navigationDestination(isPresented: $showPacks) { StoreApp() }
        .task { await session.load() }
    }

    private func style(_ e: GameEngine) -> (theme: String, badge: String) {
        let s: (theme: String, badge: String) = e.companyStyle(companyID: companyID)
        return (s.theme.isEmpty ? globalTheme : s.theme, s.badge.isEmpty ? globalBadge : s.badge)
    }

    private func previewView(_ e: GameEngine, _ co: Company, _ cabinet: Cabinet) -> CompanyCardPreview {
        let s: (theme: String, badge: String) = style(e)
        let badge: Cosmetics.Badge = Cosmetics.resolvedBadge(s.badge, earned: e.careerCosmetics, pro: ent.isPro)
        let accent: Color = Cosmetics.resolvedTheme(s.theme, pro: ent.isPro).accent
        return CompanyCardPreview(name: co.name, def: e.companyCard(co.id, cabinet: cabinet), logoID: e.companyLogoID(companyID: co.id), tradeKey: co.type, badge: badge, accent: accent)
    }

    private func signature(_ e: GameEngine, _ co: Company, _ cabinet: Cabinet) -> String {
        let s: (theme: String, badge: String) = style(e)
        return [co.name, e.companyCard(co.id, cabinet: cabinet)?.id ?? "", e.companyLogoID(companyID: co.id), s.theme, s.badge].joined(separator: "|")
    }

    private func preview(_ e: GameEngine, _ co: Company, _ cabinet: Cabinet) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("As other players see it").textStyle(.label, tint: Theme.inkFaint)
            previewView(e, co, cabinet)
            if let url = shareURL {
                ShareLink(item: url) {
                    HStack(spacing: Theme.Space.xs) {
                        LedgerGlyph(glyph: Glyph.share, size: Theme.Icon.small, tint: Theme.accent)
                        Text("Share").textStyle(.body, tint: Theme.accent, weight: .medium)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("company-card-share")
            }
        }
    }

    private func refreshShare(_ e: GameEngine, _ co: Company, _ cabinet: Cabinet) {
        let page = previewView(e, co, cabinet)
            .frame(width: 360)
            .padding(Theme.Space.l)
            .background(Theme.page)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: page)
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { shareURL = nil; return }
        let url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Company card \(companyID).png")
        do { try data.write(to: url, options: .atomic); shareURL = url } catch { shareURL = nil }
    }

    @ViewBuilder private func nameSection(_ e: GameEngine, _ co: Company) -> some View {
        let inChain: Bool = e.chainOf(companyID: co.id) != nil
        let left: Int = e.renameCooldownLeft(companyID: co.id)
        let cur = e.currency(for: co)
        let cost: Double = e.renameCost(companyID: co.id)
        let clean: String = newName.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Company name").textStyle(.label, tint: Theme.inkFaint)
            if inChain {
                Text("This store carries its chain's name. Rebranding the whole chain is done from the chain.").textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            } else {
                TextField(co.name, text: $newName).textStyle(.body).autocorrectionDisabled()
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset))
                    .accessibilityIdentifier("company-new-name")
                if left > 0 {
                    Text("The name can change again in \(left) \(left == 1 ? "week" : "weeks"). Costs \(cur.tidyDisplay(cost)).").textStyle(.caption, tint: Theme.inkSoft)
                    Button { skipAndRename(clean) } label: { Text("Change now \u{00B7} \(StoreText.gold(Self.skipPrice))") }
                        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: Theme.accent))
                        .disabled(clean.count < 2)
                        .accessibilityIdentifier("company-name-skip")
                } else {
                    Text("Costs \(cur.tidyDisplay(cost)); about a third of customers lose track of you. Then you wait \(GameEngine.renameCooldownWeeks) weeks.").textStyle(.caption, tint: Theme.inkSoft)
                    Button { confirmRename(clean, cost, cur) } label: { Text("Change name") }
                        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: Theme.accent))
                        .disabled(clean.count < 2)
                        .accessibilityIdentifier("company-name-change")
                }
            }
        }
    }

    private func confirmRename(_ name: String, _ cost: Double, _ cur: Currency) {
        pending = PendingAction(title: "Rename to \u{201C}\(name)\u{201D}?", message: "Costs \(cur.tidyDisplay(cost)) and some awareness: customers have to learn the new name.", button: "Rename", amount: cost, currency: cur, tone: .info, icon: "pencil") {
            rename(name, skip: false)
        }
    }

    private func skipAndRename(_ name: String) {
        StorePurchase.ask(.service("Skip the name wait", Self.skipPrice), pending: $pending, onShort: { (price: Int) in shortNeed = price; shortOfGold = true }, then: { (done: Bool) in
            if done { rename(name, skip: true) }
        })
    }

    private func rename(_ name: String, skip: Bool) {
        let id: Int = companyID
        switch store.act({ $0.renameCompany(companyID: id, to: name, skipCooldown: skip) }) {
        case .ok?: Haptics.success(); newName = ""; store.show("Now called \(name).", tone: "good")
        case .tooShort?: Haptics.warning(); store.show("Choose a different name of at least two letters.", tone: "warn")
        case .nameTaken?: Haptics.warning(); store.show("Another company already has that name.", tone: "warn")
        case .notEnoughCash?: Haptics.warning(); store.show("The company does not have the cash for new signs.", tone: "warn")
        case .partOfChain?: Haptics.warning(); store.show("A chain store carries the chain's name.", tone: "warn")
        case .cooldown?: Haptics.warning(); store.show("The name cannot change yet.", tone: "warn")
        case nil: break
        default: Haptics.warning(); store.show("It cannot be renamed now.", tone: "warn")
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company, _ cabinet: Cabinet) -> some View {
        switch part {
        case .card: cardGrid(e, co, cabinet)
        case .colours: colours(e, co)
        case .logo: logoGrid(e, co)
        case .plate: plateGrid()
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

    private func plateGrid() -> some View {
        var seen = Set<String>()
        let all: [SeasonReward] = (SeasonRewards.all + GoldCosmetics.all.map { (g: GoldCosmetic) -> SeasonReward in g.item })
            .filter { (r: SeasonReward) -> Bool in r.kind == .tradePlate && seen.insert(r.id).inserted }
        let owned: [SeasonReward] = all.filter { (r: SeasonReward) -> Bool in season.pass.owned.contains(r.id) }.sorted { $0.title < $1.title }
        let shut: [SeasonReward] = all.filter { (r: SeasonReward) -> Bool in !season.pass.owned.contains(r.id) }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Frames your company name on your profile.").textStyle(.caption, tint: Theme.inkSoft)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(owned + shut) { (r: SeasonReward) in
                    let isOpen: Bool = season.pass.owned.contains(r.id)
                    let worn: Bool = season.pass.equipped[r.kind.rawValue] == r.id
                    let how: String = CustomiseView.how(r)
                    LookTile(title: r.title, note: isOpen ? "" : how, worn: worn, locked: !isOpen, id: "company-plate-" + r.id,
                             art: ItemArt(reward: r, rarity: GoldCosmetics.cosmetic(r.id)?.rarity, size: 48, wide: true)) {
                        if !isOpen { Haptics.warning(); note = r.title + ": " + how; return }
                        Haptics.success()
                        if worn { season.unequip(r.kind) } else { season.equipAsking(r.id, pending: $pending) }
                    }
                }
            }
        }
    }
}
