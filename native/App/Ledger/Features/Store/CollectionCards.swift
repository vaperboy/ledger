import SwiftUI
import GameCore
import Simulation

/// One card per collection: pieces owned of total, the reward, and a claim button once it is complete.
struct CollectionCard: View {
    @Environment(\.outsidePalette) private var P
    @ObservedObject private var season = SeasonModel.shared
    var collection: ArtifactCollection
    var cabinet: Cabinet

    var body: some View {
        let p: (have: Int, total: Int) = cabinet.progress(collection)
        let done: Bool = cabinet.isComplete(collection)
        let reward: GoldCosmetic? = GoldCosmetics.cosmetic(collection.rewardID)
        let claimed: Bool = season.pass.owned.contains(collection.rewardID)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(collection.name.tidyText).textStyle(.headline)
                Spacer(minLength: Theme.Space.s)
                Text("\(p.have) of \(p.total)").textStyle(.caption, tint: done ? P.gain : P.inkSoft, numeric: true)
            }
            if !collection.blurb.isEmpty { Text(collection.blurb.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: Theme.Space.s) {
                ForEach(collection.members, id: \.self) { (id: String) in
                    if let def = ArtifactCatalog.def(id) { ItemArt(artifact: def, size: 40).opacity(cabinet.owns(id) ? 1 : 0.3) }
                }
            }
            ProgressView(value: Double(p.have), total: Double(max(1, p.total))).tint(done ? P.gain : P.accent)
            rewardLine(reward, done: done, claimed: claimed)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.inset))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func rewardLine(_ reward: GoldCosmetic?, done: Bool, claimed: Bool) -> some View {
        if let reward {
            HStack(spacing: Theme.Space.s) {
                ItemArt(reward: reward.item, rarity: reward.rarity, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Reward").textStyle(.caption, tint: P.inkFaint)
                    Text(reward.item.title.tidyText).textStyle(.body, weight: .medium).lineLimit(2)
                }
                Spacer(minLength: Theme.Space.s)
                if done && claimed {
                    Text("Claimed").textStyle(.caption, tint: P.gain, weight: .semibold)
                }
            }
            if done && !claimed {
                Button { Haptics.success(); season.grantOwned(collection.rewardID) } label: { Text("Claim reward") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("collection-claim-" + collection.id)
            }
        } else {
            Text("Progress only: this collection has no reward.").textStyle(.caption, tint: P.inkFaint)
        }
    }
}
