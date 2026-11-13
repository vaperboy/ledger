import SwiftUI
import Simulation

struct FriendPlayGroups: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    var friends: [PlayerProfile]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            raceGroup
            goalGroup
        }
        .task(id: friends.map { (p: PlayerProfile) -> String in p.id }) { await reload() }
    }

    private func reload() async {
        await FriendPlayModel.shared.refresh(engine: store.engine, friends: friends, service: online.service)
    }

    private var model: FriendPlayModel { FriendPlayModel.shared }

    private func percent(_ g: Double) -> String { String(format: "%+.1f%%", g * 100) }

    private var raceGroup: some View {
        OnlineGroup(title: "Weekly race", footer: "Friends race on how much their net worth grows this week. The top three win gold.") {
            if model.race.count < 2 {
                Text("Add a friend to start a race.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 56, alignment: .leading)
            } else {
                ForEach(Array(model.race.prefix(8).enumerated()), id: \.element.id) { (i: Int, r: RaceEntry) in
                    if i > 0 { Hairline() }
                    HStack(spacing: Theme.Space.m) {
                        Text("\(i + 1)").textStyle(.headline, tint: i < 3 ? Theme.gold : Theme.inkFaint, numeric: true).frame(width: 24, alignment: .leading)
                        Text(r.isYou ? "You" : r.name).textStyle(.body, tint: r.isYou ? Theme.accent : Theme.ink).lineLimit(1)
                        Spacer(minLength: Theme.Space.s)
                        Text(percent(r.growth)).textStyle(.caption, tint: r.growth < 0 ? Theme.loss : Theme.inkSoft, numeric: true)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            if model.lastReward > 0, let place = model.lastPlace {
                Hairline()
                HStack {
                    Text("Last week you came \(place).").textStyle(.body)
                    Spacer(minLength: Theme.Space.s)
                    Button("Claim \(model.lastReward) gold") { claimRace() }
                        .buttonStyle(PrimaryButtonStyle(size: .compact))
                        .accessibilityIdentifier("friends-race-claim")
                }
                .frame(minHeight: 52)
            }
        }
        .accessibilityIdentifier("friends-race")
    }

    @ViewBuilder private var goalGroup: some View {
        if let g = model.goal {
            let fraction: Double = min(1, g.total / max(1, g.target))
            let prize: String = GoldCosmetics.cosmetic(g.reward)?.item.title ?? ""
            OnlineGroup(title: "Shared goal", footer: prize.isEmpty ? "You already own every reward on offer." : "Everyone who plays adds the units they sold. Reach the target together for \(prize).") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Sell \(Int(saturating: g.target)) units together this week").textStyle(.body)
                    ProgressLine(fraction: fraction, tint: Theme.gold, height: 5)
                    Text("\(Int(saturating: g.total)) of \(Int(saturating: g.target)) units").textStyle(.caption, numeric: true)
                    if model.goalClaimable {
                        Button("Claim \(prize)") { claimGoal() }
                            .buttonStyle(PrimaryButtonStyle(size: .compact))
                            .accessibilityIdentifier("friends-goal-claim")
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .accessibilityIdentifier("friends-goal")
        }
    }

    private func claimRace() {
        Task { @MainActor in
            let gold: Int = await FriendPlayModel.shared.claimRace()
            guard gold > 0 else { return }
            Haptics.success()
            store.tell("Race reward", "+\(gold) gold for last week's race.", tone: "good")
        }
    }

    private func claimGoal() {
        Task { @MainActor in
            guard let name = await FriendPlayModel.shared.claimGoal(service: online.service) else { return }
            Haptics.success()
            store.tell("Shared goal reached", "You and your friends earned \(name).", tone: "good")
        }
    }
}

struct GiftChoices: View {
    var friend: PlayerProfile
    var send: (ArtifactItem) -> Void
    private var session: StoreSession { StoreSession.shared }

    var body: some View {
        let items: [ArtifactItem] = session.state.cabinet.items
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if items.isEmpty {
                Text("Your cabinet is empty. Open a box in the Store to find something to give.").popupText(.body)
            } else {
                Text("Pick one piece to send to \(friend.displayName). It leaves your cabinet.").popupText(.caption)
                ForEach(items, id: \.id) { (item: ArtifactItem) in
                    ChoiceCard(title: ArtifactCatalog.def(item.defID)?.name ?? "Piece", subtitle: ArtifactCatalog.label(item), selected: false) { send(item) }
                }
            }
        }
        .task { await StoreSession.shared.load() }
    }
}

@MainActor enum GiftSender {
    static func send(_ item: ArtifactItem, to friend: PlayerProfile, online: OnlineSession, store: GameStore) async -> String? {
        guard FriendPlayModel.shared.canGift else { return "You have already sent a gift today." }
        guard await StoreSession.shared.giveAway(item) else { return StoreSession.shared.problem }
        do {
            try await online.service.sendGift(to: friend.id, item: item, fromName: online.profile?.displayName ?? "A friend")
            FriendPlayModel.shared.markGift()
            store.tell("Gift sent", "\(ArtifactCatalog.def(item.defID)?.name ?? "A piece") is on its way to \(friend.displayName).", tone: "good")
            return nil
        } catch {
            await StoreSession.shared.receiveGift(item)
            return (error as? LocalizedError)?.errorDescription ?? "The gift could not be sent. It is back in your cabinet."
        }
    }
}
