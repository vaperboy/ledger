import SwiftUI
import Simulation

/// The Cabinet: every artifact the player owns, the collections and their rewards, and the wardrobe where owned cosmetics are put on.
struct CabinetView: View {
    private let session = StoreSession.shared
    @ObservedObject private var season = SeasonModel.shared
    @State private var selling: ArtifactItem?

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        PhonePageScroll(spacing: Theme.Space.l) {
            collections(cabinet)
            pieces(cabinet)
            WardrobeGroup()
        }
        .appScreen(title: "Cabinet", subtitle: "Artifacts, collections and what you wear")
        .task { await session.load() }
        .centerSheet(item: $selling, title: "Sell at auction") { (item: ArtifactItem) in ListingCard(item: item) }
    }

    private func collections(_ cabinet: Cabinet) -> some View {
        OnlineGroup(title: "Collections", footer: "Own at least one piece of every artifact in a collection to receive its cosmetic, once.") {
            ForEach(Array(ArtifactCatalog.collections.enumerated()), id: \.element.id) { (i: Int, col: ArtifactCollection) in
                if i > 0 { Hairline() }
                let p = cabinet.progress(col)
                let done: Bool = cabinet.isComplete(col)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack {
                        Text(col.name).textStyle(.headline)
                        Spacer()
                        Text(done ? "Complete" : "\(p.have) of \(p.total)").textStyle(.caption, tint: done ? Theme.gain : Theme.inkSoft, numeric: true)
                    }
                    HStack(spacing: Theme.Space.s) {
                        ForEach(col.members, id: \.self) { (id: String) in
                            if let def = ArtifactCatalog.def(id) { ItemArt(artifact: def, size: 40).opacity(cabinet.owns(id) ? 1 : 0.3) }
                        }
                    }
                    ProgressView(value: Double(p.have), total: Double(p.total)).tint(done ? Theme.gain : Theme.accent)
                    Text(col.blurb + " Reward: " + (GoldCosmetics.cosmetic(col.rewardID)?.item.title ?? "a cosmetic") + ".").textStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(col.members.map { (id: String) -> String in
                        (cabinet.owns(id) ? "Have " : "Missing ") + (ArtifactCatalog.def(id)?.name ?? id)
                    }.joined(separator: ", ")).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Space.s)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func pieces(_ cabinet: Cabinet) -> some View {
        let canSell: Bool = StoreGate.access(countryCode: nil) != .hidden
        OnlineGroup(title: "Your artifacts", footer: cabinet.items.isEmpty ? "Artifacts come from boxes and auctions." : (canSell ? "Tap a piece to sell it at auction. Cash from a sale goes to your personal account, less a \(AuctionRules.feePercent)% fee." : "")) {
            if cabinet.items.isEmpty {
                Text("Nothing here yet.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 52, alignment: .leading)
            } else {
                ForEach(Array(cabinet.sorted.enumerated()), id: \.element.id) { (i: Int, item: ArtifactItem) in
                    if i > 0 { Hairline() }
                    if canSell {
                        Button { selling = item } label: { ArtifactRow(item: item, trailing: "Sell") }.buttonStyle(PressableStyle())
                    } else {
                        ArtifactRow(item: item)
                    }
                }
            }
        }
    }
}

/// Owned cosmetics grouped by kind with a Use button; the choice is kept with the Season Pass wardrobe.
struct WardrobeGroup: View {
    @ObservedObject private var season = SeasonModel.shared

    var body: some View {
        let owned: [SeasonReward] = season.pass.owned.compactMap { SeasonRewards.item($0) }.filter { $0.kind.isEquippable }
            .sorted { ($0.kind.label, $0.title) < ($1.kind.label, $1.title) }
        OnlineGroup(title: "Wardrobe", footer: owned.isEmpty ? "Cosmetics from the Season Pass, boxes and the store appear here." : "Name plates show on your profile.") {
            if owned.isEmpty {
                Text("Nothing to wear yet.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 52, alignment: .leading)
            } else {
                ForEach(Array(owned.enumerated()), id: \.element.id) { (i: Int, r: SeasonReward) in
                    if i > 0 { Hairline() }
                    let on: Bool = season.pass.equipped[r.kind.rawValue] == r.id
                    HStack(spacing: Theme.Space.m) {
                        ItemArt(reward: r, rarity: GoldCosmetics.cosmetic(r.id)?.rarity, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).textStyle(.headline)
                            Text(r.kind.label).textStyle(.caption)
                        }
                        Spacer()
                        Button(on ? "In use" : "Use") { Haptics.tap(); season.equip(r.id) }
                            .buttonStyle(SecondaryButtonStyle(size: .compact, passive: on))
                            .disabled(on)
                    }
                    .padding(.vertical, Theme.Space.s).frame(minHeight: 52)
                }
            }
        }
    }
}

/// The Cabinet section of a profile: how much is collected and the rarest pieces, with a way into the Cabinet.
struct CabinetSummary: View {
    private let session = StoreSession.shared

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        let done: Int = ArtifactCatalog.collections.filter { cabinet.isComplete($0) }.count
        let total: Int = ArtifactCatalog.collections.count
        VStack(alignment: .leading, spacing: 0) {
            OnlineLine(glyph: Glyph.luxury, title: cabinet.items.count == 1 ? "1 artifact" : "\(cabinet.items.count) artifacts",
                       note: "\(done) of \(total) collections complete")
            ForEach(Array(cabinet.sorted.prefix(3).enumerated()), id: \.element.id) { (_: Int, item: ArtifactItem) in
                Hairline()
                ArtifactRow(item: item)
            }
            Hairline()
            NavigationLink { CabinetView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Open the Cabinet", note: "Collections, selling and what you wear", chevron: true) }
                .buttonStyle(PressableStyle())
        }
        .task { await session.load() }
    }
}

/// The player's name on the plate they chose in the wardrobe (plain text when none is chosen).
struct NamePlateText: View {
    var name: String
    @ObservedObject private var season = SeasonModel.shared

    var body: some View {
        if let id = season.pass.equipped[SeasonReward.Kind.namePlate.rawValue], let r = SeasonRewards.item(id), r.colors.count >= 2 {
            Text(name).textStyle(.title, tint: Color(hex: r.colors[0]))
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.xs)
                .background(Capsule().fill(Color(hex: r.colors[1])))
                .overlay(Capsule().strokeBorder(Color(hex: r.colors[0]).opacity(0.5), lineWidth: 1))
        } else {
            Text(name).textStyle(.title)
        }
    }
}
