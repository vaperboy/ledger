import Foundation
import GameCore

/// Money of a weekly step that is worked out at once and released over the seven days that follow (`GameEngine.endSlice` / `releaseDay`).
/// Each company's step runs on its own weekday, so several such batches are in flight at any time: `rest["pend"]` holds them all,
/// with absolute game-day numbers (week * 7 + day). While money is held back it is in neither the company's cash nor anything the
/// player can see. When the player takes a company out of the game in those days (sold, wound up), its unreleased share must be settled
/// first so that the liquidation or the sale sees the true cash, and nothing lands later in a dead company.
/// A save from before the stagger holds one batch with days 0...6 of its week and no "v" key; `normalise` converts it.
public enum HeldMoney {
    /// Absolute game-day number of today.
    public static func today(_ s: GameState) -> Int { s.week * 7 + s.day }

    static func isLegacy(_ pend: JSONValue) -> Bool { pend["v"].isNull }

    /// Turn a pre-stagger batch (days relative to the week it was staged in) into absolute days. Does nothing for the current format.
    public static func normalise(_ s: inout GameState) {
        guard let P = s.rest["pend"], !P.isNull, isLegacy(P) else { return }
        let base = s.week * 7
        func shifted(_ list: [JSONValue]) -> JSONValue {
            .array(list.map { x -> JSONValue in var r = x; r["d"] = .number(Double(base + x["d"].int)); return r })
        }
        let co: [JSONValue] = P["co"].array.map { .array([$0[0], $0[1], $0[2], .number(Double(base))]) }
        s.rest["pend"] = .object(["v": 2, "rows": shifted(P["rows"].array), "co": .array(co), "msgs": shifted(P["msgs"].array), "news": shifted(P["news"].array)])
        // The old turn already worked this week out: the daily slices take over from the next week.
        s.rest["sliceStart"] = .number(Double(s.week + 1))
    }

    /// The part of a company's held money that has not landed yet (negative = bills still to leave). Zero when nothing is held.
    public static func remaining(_ s: GameState, companyID: Int) -> Double {
        guard let P = s.rest["pend"], !P.isNull else { return 0 }
        let legacy = isLegacy(P), now = today(s)
        var left = 0.0
        for x in P["co"].array where x[0].int == companyID {
            let total = x[1].double, one = x[2].double
            let oneOff = one + min(0, total - one)
            let spread = total - oneOff
            let start = legacy ? s.week * 7 : x[3].int
            let landed = min(7, max(0, now - start + 1))
            left += spread - jsRound(spread * Double(landed) / 7)
        }
        return left
    }

    /// The player's own held money that has not landed yet (negative = payments still to leave).
    public static func playerRemaining(_ s: GameState) -> Double {
        guard let P = s.rest["pend"], !P.isNull else { return 0 }
        let legacy = isLegacy(P), now = today(s), base = s.week * 7
        return P["rows"].array.filter { (legacy ? base + $0["d"].int : $0["d"].int) > now }.reduce(0) { $0 + $1["a"].double }
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
