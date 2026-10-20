import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The ownership side of the game in one place: what runs every week (your startups, your stakes in other startups, private equity funds,
/// the big meeting and its stakes, the owners of your companies) and which inbox actions belong to it. The parts are `Startups`, `PrivateEquity`,
/// `BigMeeting`, `Shareholders`, `GroupDeals`, `Funding` and (for selling) `CompanySale`.
public enum Ventures {
    /// Called once a week from the weekly turn.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        Startups.weekly(&s, data: data, context: fc)
        PrivateEquity.weekly(&s)
        BigMeeting.weekly(&s, data: data, context: fc)
        Shareholders.weekly(&s, data: data, context: fc)
    }

    /// Inbox actions that belong here: pro-rata rounds and bridge money for startups you hold, bids from rival groups, demands of your co-owners.
    public static func handlesAnswer(_ action: String) -> Bool {
        action == "round" || action == "bridge" || action == GroupDeals.bidAction || action == Shareholders.action
    }

    /// Returns false when the answer could not be carried out (not enough money): the message stays open.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context fc: FinanceContext) -> Bool {
        switch m.actionID {
        case "round", "bridge": return Startups.answer(&s, message: m, option: idx)
        case GroupDeals.bidAction: GroupDeals.answerBid(&s, message: m, option: idx, data: data, context: fc); return true
        case Shareholders.action: Shareholders.answer(&s, message: m, option: idx, data: data, context: fc); return true
        default: return true
        }
    }

    /// The crisis centre: every open decision that is bad news or a decision, soonest deadline first. Original: `crisisList`.
    public static func crises(_ s: GameState) -> [Message] {
        s.inbox.filter { $0.status == "open" && !$0.options.isEmpty && ($0.tone == "bad" || $0.kind == "decision") && $0.actionID != "mprop" }
            .sorted { ($0.expiresWeek ?? 999) < ($1.expiresWeek ?? 999) }
    }
}
