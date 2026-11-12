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
            LedgerGlyph(glyph: Glyph.luxury, size: Theme.Icon.medium, tint: Theme.gold)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1.2))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Customise")
        .accessibilityHint("Logo and banner")
        .accessibilityIdentifier("company-customise")
        .navigationDestination(isPresented: $open) { CompanyCustomiseView(companyID: companyID) }
    }
}

/// A company looks like a logo and one banner. The banner styles the company's header wherever it is shown.
struct CompanyCustomiseView: View {
    enum Part: String, CaseIterable, Identifiable {
        case banner, logo
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
        .task { await session.load() }
    }

    private func previewView(_ e: GameEngine, _ co: Company) -> some View {
        CompanyCardView(name: co.name, def: nil, logoID: e.companyLogoID(companyID: co.id), backdrop: LookKit.companyBackdrop(e, co.id))
    }

    private func signature(_ e: GameEngine, _ co: Company) -> String {
        [co.name, e.companyLogoID(companyID: co.id), e.companyBackdrop(companyID: co.id)].joined(separator: "|")
    }

    private func preview(_ e: GameEngine, _ co: Company) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("As other players see it").textStyle(.label, tint: Theme.inkFaint)
            previewView(e, co)
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
        case .banner: bannerGrid(e, co)
        case .logo: logoGrid(e, co)
        }
    }

    private func replace(_ item: String, on other: String, then run: @escaping () -> Void) {
        pending = PendingAction(title: "Replace?", message: item + " is on " + other + ". Move it here?", button: "Move", alwaysAsk: true, run: run)
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
            Text("Styles the header of this company everywhere it is shown.").textStyle(.caption, tint: Theme.inkSoft)
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
