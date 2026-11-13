import SwiftUI
import GameCore
import Events
import Finance
import Businesses
import Simulation

extension PlayerCardData {
    /// Your own card. `trial` holds items being tried on (kind to item id, empty id for none) and `trialLook` an avatar look being tried.
    @MainActor static func mine(_ e: GameEngine, store: GameStore, trial: [String: String] = [:], trialLook: AvatarLook? = nil) -> PlayerCardData {
        let local: ProfileLocal = ProfileLocal.shared
        let cabinet: Cabinet = StoreSession.shared.state.cabinet
        var worn: [String: String] = SeasonModel.shared.pass.equipped
        if let card = worn[SeasonPass.profileCardKey], !cabinet.contains(card) { worn[SeasonPass.profileCardKey] = nil }
        for (kind, id) in trial { worn[kind] = id.isEmpty ? nil : id }
        let avatar: AvatarLook = trialLook ?? local.avatar
        let name: String = local.name.isEmpty ? e.state.player.name : local.name
        let live: Int = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }.count
        return PlayerCardData(name: name,
                              title: e.careerStatus.rank.title,
                              levelText: "Level \(e.playerLevel.level)",
                              avatar: avatar,
                              worn: worn,
                              figures: [PlayerCardFigure(title: "Net worth", value: store.short(e.netWorth.total)),
                                        PlayerCardFigure(title: "Companies", value: "\(live)"),
                                        PlayerCardFigure(title: "Weeks played", value: "\(e.state.week)")],
                              hallOfFame: e.inHallOfFame)
    }
}

/// Keeps the online profile in step with the look worn on the card.
@MainActor
enum LookSync {
    static var signature: String { ProfileLocal.shared.shareCode(worn: SeasonModel.shared.pass.equipped) }

    static func push(_ online: OnlineSession) {
        let code: String = signature
        Task { _ = await online.update(ProfileUpdate(avatarLook: code)) }
    }
}
