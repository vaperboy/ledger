import SwiftUI
import GameCore
import Businesses
import Countries
import Simulation

struct CompanyCustomiseButton: View {
    var companyID: Int
    @State private var open = false

    var body: some View {
        Button { Haptics.tap(); open = true } label: {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.gold)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1.2))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Customise")
        .accessibilityHint("Name, logo and banner")
        .accessibilityIdentifier("company-customise")
        .navigationDestination(isPresented: $open) { CompanyCustomiseView(companyID: companyID) }
    }
}

/// The one place to change how a company looks: its name, logo and banner. Opened by the wrench on the company header.
/// The banner styles the company's header wherever it is shown. Tap the logo, name or banner in the preview to open that tab.
struct CompanyCustomiseView: View {
    enum Part: String, CaseIterable, Identifiable {
        case name, logo, banner
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    static let barClearance: CGFloat = 130

    var companyID: Int
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var season = SeasonModel.shared
    private let session = StoreSession.shared
    @State private var part: Part = .banner
    @State private var renaming = false
    @State private var pending: PendingAction?
    @State private var note = ""
    @State private var shareURL: URL?

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)]

    private var planPerks: Set<String> { PlanPerks.perks(owned: ent.effective.owned) }

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        preview(e, co)
                        SegmentedPill(items: Part.allCases, title: { (p: Part) -> String in p.title }, selection: $part, identifier: { (p: Part) -> String in "company-look-" + p.rawValue })
                        if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.accent).frame(maxWidth: .infinity, alignment: .leading).lineLimit(3) }
                        content(e, co)
                    }
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Self.barClearance)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .onAppear { refreshShare(e, co) }
                .onChange(of: signature(e, co)) { _, _ in refreshShare(e, co) }
            } else {
                Text("This company no longer exists.").textStyle(.body, tint: Theme.inkSoft).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .appScreen(title: "Customise", subtitle: store.engine?.state.company(companyID)?.name ?? "", backdrop: store.engine.flatMap { (e: GameEngine) -> SeasonReward? in LookKit.companyBackdrop(e, companyID) })
        .confirmAction($pending)
        .companyRename(companyID: companyID, isPresented: $renaming)
        .task { await session.load() }
    }

    private func previewView(_ e: GameEngine, _ co: Company) -> some View {
        CompanyCardView(name: co.name, def: nil, logoID: e.companyLogoID(companyID: co.id), backdrop: LookKit.companyBackdrop(e, co.id))
    }

    /// The preview you tap: the logo, the name and the banner each open their own tab.
    private func livePreview(_ e: GameEngine, _ co: Company) -> some View {
        CompanyCardView(name: co.name, def: nil, logoID: e.companyLogoID(companyID: co.id), backdrop: LookKit.companyBackdrop(e, co.id),
                        onLogo: { part = .logo; note = "" },
                        onName: { part = .name; note = ""; renaming = true },
                        onBanner: { part = .banner; note = "" })
    }

    private func signature(_ e: GameEngine, _ co: Company) -> String {
        [co.name, e.companyLogoID(companyID: co.id), e.companyBackdrop(companyID: co.id)].joined(separator: "|")
    }

    private func preview(_ e: GameEngine, _ co: Company) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("As other players see it. Tap a part to change it.").textStyle(.label, tint: Theme.inkFaint)
            livePreview(e, co)
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

    private func refreshShare(_ e: GameEngine, _ co: Company) {
        let page = previewView(e, co)
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

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        switch part {
        case .name: nameSection(e, co)
        case .banner: bannerGrid(e, co)
        case .logo: logoGrid(e, co)
        }
    }

    private func replace(_ item: String, on other: String, then run: @escaping () -> Void) {
        pending = PendingAction(title: "Replace?", message: item + " is on " + other + ". Move it here?", button: "Move", alwaysAsk: true, run: run)
    }

    private func nameSection(_ e: GameEngine, _ co: Company) -> some View {
        let left: Int = e.renameCooldownLeft(companyID: co.id)
        let cur: Currency = e.currency(for: co)
        let cost: Double = e.renameCost(companyID: co.id)
        let inChain: Bool = e.chainOf(companyID: co.id) != nil
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(co.name).textStyle(.title)
            if inChain {
                Text("This store carries its chain's name. Rebranding the whole chain is done from the chain.").textStyle(.caption, tint: Theme.inkSoft)
            } else {
                Text(left > 0 ? "The name can change again in \(left) \(left == 1 ? "week" : "weeks"). Costs \(cur.tidyDisplay(cost))."
                              : "Costs \(cur.tidyDisplay(cost)); about a third of customers lose track of you. Then you wait \(GameEngine.renameCooldownWeeks) weeks.")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                Button("Rename") { Haptics.tap(); renaming = true }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("company-rename")
            }
        }
    }

    private func bannerGrid(_ e: GameEngine, _ co: Company) -> some View {
        var seen = Set<String>()
        let all: [SeasonReward] = (SeasonRewards.all + GoldCosmetics.all.map { (g: GoldCosmetic) -> SeasonReward in g.item })
            .filter { (r: SeasonReward) -> Bool in r.kind == .backdrop && seen.insert(r.id).inserted }
        let owned: [SeasonReward] = all.filter { (r: SeasonReward) -> Bool in season.pass.owned.contains(r.id) }.sorted { $0.title < $1.title }
        let shut: [SeasonReward] = all.filter { (r: SeasonReward) -> Bool in !season.pass.owned.contains(r.id) }
        let current: String = e.companyBackdrop(companyID: co.id)
        let id: Int = co.id
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Fills the top of this company everywhere it is shown.").textStyle(.caption, tint: Theme.inkSoft)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(owned + shut) { (r: SeasonReward) in
                    let isOpen: Bool = season.pass.owned.contains(r.id)
                    let how: String = CustomiseView.how(r)
                    LookTile(title: r.title, note: isOpen ? "" : how, worn: current == r.id, wornText: "On this company", locked: !isOpen, id: "company-banner-" + r.id,
                             art: ItemArt(reward: r, rarity: GoldCosmetics.cosmetic(r.id)?.rarity, size: 48, wide: true)) {
                        if !isOpen { Haptics.warning(); note = r.title + ": " + how; return }
                        Haptics.success()
                        note = ""
                        let next: String = current == r.id ? "" : r.id
                        _ = store.act { (g: inout GameEngine) -> Void in _ = g.setCompanyBackdrop(companyID: id, id: next) }
                    }
                }
            }
        }
    }

    private func logoGrid(_ e: GameEngine, _ co: Company) -> some View {
        let current: String = e.companyLogoID(companyID: co.id)
        return LazyVGrid(columns: columns, spacing: Theme.Space.s) {
            ForEach(e.logoChoices(perks: planPerks)) { (c: LogoChoice) in
                let elsewhere: String? = e.companyUsingLogo(c.id, besides: co.id)?.name
                LookTile(title: c.logo.name, note: c.unlocked ? (elsewhere.map { (n: String) -> String in "On " + n } ?? "") : c.how, worn: c.id == current, wornText: "In use", locked: !c.unlocked,
                         id: "company-logo-" + c.id, art: LogoBadge(logoID: c.id, size: 48), action: { pickLogo(c, current: current, elsewhere: elsewhere) })
            }
        }
    }

    private func pickLogo(_ c: LogoChoice, current: String, elsewhere: String?) {
        let id: Int = companyID
        let logoID: String = c.id
        let perks: Set<String> = planPerks
        guard c.unlocked else { Haptics.warning(); note = c.logo.name + ": " + c.how; return }
        let apply: () -> Void = {
            Haptics.success()
            _ = store.act { (e: inout GameEngine) -> Void in _ = e.setCompanyLogo(companyID: id, logoID: logoID, perks: perks) }
            note = ""
        }
        if c.id == current {
            Haptics.choose()
            _ = store.act { (e: inout GameEngine) -> Void in e.clearCompanyLogo(companyID: id) }
        } else if let other = elsewhere {
            replace(c.logo.name, on: other, then: apply)
        } else {
            apply()
        }
    }
}
