import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum StartupHolding {
    public struct Stake: Identifiable, Equatable {
        public var id: Int
        public var name: String, sector: String
        public var stage: Int, stageName: String
        public var live: Bool, failed: Bool
        public var percent: Double, paid: Double
        public var valuation: Double
        public var value: Double
        public var boardSeat: Bool
        public var tier: HoldingStakes.Tier
    }

    public struct Deal: Equatable {
        public var percent: Double
        public var amount: Double
        public var heldAfter: Double
        public var tierAfter: HoldingStakes.Tier
    }

    public struct MoreQuote: Equatable {
        public var percent: Double
        public var valuation: Double
        public var price: Double
        public var priceFactor: Double
        public var heldAfter: Double
        public var tierAfter: HoldingStakes.Tier
    }

    static func openHolding(_ s: GameState, _ hid: Int) -> Company? {
        guard let h = s.company(hid), h.type == "hold", h.status.isLive else { return nil }
        return h
    }
    static func record(_ s: GameState, holdingID: Int, stakeID: Int) -> JSONValue? {
        HoldingStartups.records(s, holdingID: holdingID).first { $0["id"].int == stakeID }
    }

    public static func stakes(_ s: GameState, holdingID: Int) -> [Stake] {
        HoldingStartups.records(s, holdingID: holdingID).filter { $0["st"].string != "exit" }.map { f in
            let pct = f["pct"].double
            return Stake(id: f["id"].int, name: f["name"].string, sector: f["sec"].string, stage: f["stage"].int, stageName: Startups.stakeStages[min(max(0, f["stage"].int), 3)],
                         live: f["st"].string == "live", failed: f["st"].string == "failed", percent: pct, paid: f["in"].double, valuation: f["val"].double,
                         value: f["st"].string == "live" ? f["val"].double * pct / 100 : 0, boardSeat: f["seat"].bool, tier: HoldingStakes.tier(forPercent: pct))
        }.sorted { $0.percent > $1.percent }
    }

    public static func investQuote(_ s: GameState, holdingID: Int, pitchID: Int, amount: Double, context fc: FinanceContext) -> Result<Startups.InvestQuote, HoldingStakes.Failure> {
        guard openHolding(s, holdingID) != nil else { return .failure(.notAHolding) }
        let q = Startups.investQuote(s, pitchID: pitchID, amount: amount, holdingID: holdingID, context: fc)
        switch q.result {
        case .gone: return .failure(.notFound)
        case .tooSmall: return .failure(.refused("The smallest investment is \(Int(saturating: q.minimum.rounded()))."))
        case .notEnoughMoney: return .failure(.notEnoughCash(needed: q.amount))
        case .ok: return .success(q)
        }
    }

    public static func invest(_ s: inout GameState, holdingID: Int, pitchID: Int, amount: Double, data: GameData, context fc: FinanceContext) -> Result<Deal, HoldingStakes.Failure> {
        switch investQuote(s, holdingID: holdingID, pitchID: pitchID, amount: amount, context: fc) {
        case .failure(let f): return .failure(f)
        case .success(let q):
            guard let hi = s.companyIndex(holdingID), let d = (s.rest["deals_su"]?.array ?? []).first(where: { $0["id"].int == pitchID }) else { return .failure(.notFound) }
            Ledger.moveRaw(&s, .company(holdingID), -q.amount)
            s.companies[hi].addTransaction(week: s.week, amount: -q.amount, label: "Invested in \(q.name)")
            Startups.openStake(&s, pitch: d, amount: q.amount, holdingID: holdingID)
            HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
            let tier = HoldingStakes.tier(forPercent: q.ownershipPercent)
            s.note("\(s.companies[hi].name) holds \(String(format: "%.1f", q.ownershipPercent))% of \(q.name) (\(tier.title.lowercased())).", tone: "good", companyID: holdingID)
            return .success(Deal(percent: q.ownershipPercent, amount: q.amount, heldAfter: q.ownershipPercent, tierAfter: tier))
        }
    }

    public static func buyMoreQuote(_ s: GameState, holdingID: Int, stakeID: Int, percent: Double) -> Result<MoreQuote, HoldingStakes.Failure> {
        guard openHolding(s, holdingID) != nil else { return .failure(.notAHolding) }
        guard let f = record(s, holdingID: holdingID, stakeID: stakeID), f["st"].string == "live" else { return .failure(.notFound) }
        guard percent >= HoldingStakes.minimumPercent else { return .failure(.refused("Choose at least \(HoldingStakes.minimumPercent)%.")) }
        let held = f["pct"].double, after = held + percent
        guard after <= 100.0001 else { return .failure(.refused("The holding already owns \(String(format: "%.1f", held))% of \(f["name"].string).")) }
        if after > HoldingStakes.controlAbove && f["stage"].int == 0 {
            return .failure(.refused("The founders of \(f["name"].string) keep the majority until their first priced round."))
        }
        let factor = held >= HoldingStakes.squeezeOutFrom ? 1 : HoldingStakes.buyFactor(afterPercent: after)
        let val = f["val"].double
        return .success(MoreQuote(percent: percent, valuation: val, price: jsRound(val * percent / 100 * factor), priceFactor: factor, heldAfter: after, tierAfter: HoldingStakes.tier(forPercent: after)))
    }

    public static func buyMore(_ s: inout GameState, holdingID: Int, stakeID: Int, percent: Double, data: GameData) -> Result<Deal, HoldingStakes.Failure> {
        switch buyMoreQuote(s, holdingID: holdingID, stakeID: stakeID, percent: percent) {
        case .failure(let f): return .failure(f)
        case .success(let q):
            guard let hi = s.companyIndex(holdingID), let f = record(s, holdingID: holdingID, stakeID: stakeID) else { return .failure(.notFound) }
            guard s.companies[hi].cash >= q.price else { return .failure(.notEnoughCash(needed: q.price)) }
            Ledger.moveRaw(&s, .company(holdingID), -q.price)
            s.companies[hi].addTransaction(week: s.week, amount: -q.price, label: "Bought \(String(format: "%.1f", percent))% of \(f["name"].string)")
            let controls = q.tierAfter.isConsolidated
            Startups.editStake(&s, stakeID) { x in
                x["pct"] = .number(q.heldAfter); x["in"] = .number(x["in"].double + q.price); x["seat"] = .bool(q.heldAfter >= HoldingStakes.passiveBelow)
                if controls { x["help"] = .number(max(1, x["help"].double)) }
            }
            HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data)
            s.note("\(s.companies[hi].name) now owns \(String(format: "%.1f", q.heldAfter))% of \(f["name"].string) (\(q.tierAfter.title.lowercased())).", tone: "good", companyID: holdingID)
            return .success(Deal(percent: percent, amount: q.price, heldAfter: q.heldAfter, tierAfter: q.tierAfter))
        }
    }

    public static func sellQuote(_ s: GameState, holdingID: Int, stakeID: Int, fraction: Double) -> Result<VentureSale.Quote, HoldingStakes.Failure> {
        guard openHolding(s, holdingID) != nil else { return .failure(.notAHolding) }
        guard let f = record(s, holdingID: holdingID, stakeID: stakeID) else { return .failure(.notFound) }
        let q = Startups.saleQuote(s, f, fraction: fraction)
        return q.ok ? .success(q) : .failure(.refused(q.reason))
    }

    public static func sell(_ s: inout GameState, holdingID: Int, stakeID: Int, fraction: Double, askMultiplier: Double? = nil, data: GameData) -> Result<VentureSale.Outcome, HoldingStakes.Failure> {
        if case .failure(let f) = sellQuote(s, holdingID: holdingID, stakeID: stakeID, fraction: fraction) { return .failure(f) }
        let outcome = Startups.sellAsking(&s, stakeID: stakeID, fraction: fraction, askMultiplier: askMultiplier, holdingID: holdingID)
        if case .sold = outcome { HoldingModel.refreshAssets(&s, holdingID: holdingID, data: data) }
        return .success(outcome)
    }
}
