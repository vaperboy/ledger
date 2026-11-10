import Foundation
import GameCore

public enum HeldMoney {
    public static func today(_ s: GameState) -> Int { s.week * 7 + s.day }

    static func isLegacy(_ pend: JSONValue) -> Bool { pend["v"].isNull }

    public static func normalise(_ s: inout GameState) {
        guard let P = s.rest["pend"], !P.isNull, isLegacy(P) else { return }
        let base = s.week * 7
        func shifted(_ list: [JSONValue]) -> JSONValue {
            .array(list.map { x -> JSONValue in var r = x; r["d"] = .number(Double(base + x["d"].int)); return r })
        }
        let co: [JSONValue] = P["co"].array.map { .array([$0[0], $0[1], $0[2], .number(Double(base))]) }
        s.rest["pend"] = .object(["v": 2, "rows": shifted(P["rows"].array), "co": .array(co), "msgs": shifted(P["msgs"].array), "news": shifted(P["news"].array)])
        s.rest["sliceStart"] = .number(Double(s.week + 1))
    }

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

    public static func playerRemaining(_ s: GameState) -> Double {
        guard let P = s.rest["pend"], !P.isNull else { return 0 }
        let legacy = isLegacy(P), now = today(s), base = s.week * 7
        return P["rows"].array.filter { (legacy ? base + $0["d"].int : $0["d"].int) > now }.reduce(0) { $0 + $1["a"].double }
    }

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
