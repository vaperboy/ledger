import Foundation
import GameCore

public enum TradeRules {
    public static func isAccountBound(_ defID: String) -> Bool {
        LevelRewards.isLevelIcon(defID) || SeasonRewards.item(defID)?.accountBound == true || GoldCosmetics.cosmetic(defID)?.item.accountBound == true
    }

    public static func isSellable(_ item: ArtifactItem) -> Bool { item.origin != .bought && !isAccountBound(item.defID) }

    public static func isSellable(reward r: SeasonReward) -> Bool {
        if r.accountBound { return false }
        return r.kind != .box && r.kind != .gold && r.kind != .xp
    }

    public static func isFounderEdition(_ defID: String) -> Bool {
        if let c = CardCatalog.def(defID) { return c.founderEdition }
        return SeasonRewards.item(defID)?.founderEdition == true
    }

    public static func isFounderEdition(_ item: ArtifactItem) -> Bool { isFounderEdition(item.defID) }
}
