import Foundation
import GameCore

/// The week's company money is worked out at once and released over seven days (`GameEngine.stageWeek` / `releaseDay`).
/// While it is held back it is in neither the company's cash nor anything the player can see. When the player takes a
/// company out of the game in those days (sold, wound up), its unreleased share must be settled first so that the
/// liquidation or the sale sees the true cash, and nothing lands later in a dead company. Bankruptcy and forced sales
/// happen inside the weekly turn, before the week is staged, so they have nothing held.
public enum HeldMoney {
    /// The part of a company's staged week that has not landed yet (negative = bills still to leave). Zero outside a staged week.
    public static func remaining(_ s: GameState, companyID: Int) -> Double {
        guard let P = s.rest["pend"], !P.isNull else { return 0 }
        for x in P["co"].array where x[0].int == companyID {
            let total = x[1].double, one = x[2].double
            let oneOff = one + min(0, total - one)
            let spread = total - oneOff
            return spread - jsRound(spread * Double(s.day + 1) / 7)
        }
        return 0
    }

    /// Release what is still held for this company into its cash and forget the entry. Returns the amount released.
    @discardableResult
    public static func settle(_ s: inout GameState, companyID: Int) -> Double {
        guard let P = s.rest["pend"], !P.isNull, s.companyIndex(companyID) != nil else { return 0 }
        let rest = remaining(s, companyID: companyID)
        var pend = P
        pend["co"] = .array(P["co"].array.filter { $0[0].int != companyID })
        s.rest["pend"] = pend
        if rest != 0 { Ledger.moveRaw(&s, .company(companyID), rest) }
        return rest
    }
}
