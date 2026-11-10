import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events

public enum PortfolioOwner: Hashable, Sendable {
    case player
    case holding(Int)

    public var id: String {
        switch self {
        case .player: return "me"
        case .holding(let h): return "h\(h)"
        }
    }

    public init?(id: String) {
        if id == "me" { self = .player; return }
        guard id.hasPrefix("h"), let n = Int(id.dropFirst()) else { return nil }
        self = .holding(n)
    }
}

public enum MarketAssetKind: String, Sendable, CaseIterable {
    case indexFund, bondFund, moneyMarketFund, crypto
    case stock
    case managedFund
    case fixedDeposit
    case startupStake, privateEquity, groupStake, companyStake

    public var title: String {
        switch self {
        case .indexFund: return "Index fund"
        case .bondFund: return "Bond fund"
        case .moneyMarketFund: return "Money-market fund"
        case .crypto: return "Crypto"
        case .stock: return "Shares"
        case .managedFund: return "Fund manager"
        case .fixedDeposit: return "Fixed deposit"
        case .startupStake: return "Startup stake"
        case .privateEquity: return "Private equity"
        case .groupStake: return "Group stake"
        case .companyStake: return "Company stake"
        }
    }
    public var isPrivate: Bool { [.startupStake, .privateEquity, .groupStake, .companyStake].contains(self) }
}

public enum MarketRisk: String, Sendable, CaseIterable {
    case low = "Low", medium = "Medium", high = "High", veryHigh = "Very high"
}

public struct PortfolioPosition: Identifiable, Equatable, Sendable {
    public var id: String
    public var owner: PortfolioOwner
    public var ownerName: String
    public var kind: MarketAssetKind
    public var assetID: String?
    public var name: String
    public var symbol: String
    public var units: Double
    public var price: Double
    public var costBasis: Double
    public var value: Double
    public var pnl: Double
    public var pnlPercent: Double?
    public var pnlToday: Double
    public var pnlWeek: Double
    public var allocation: Double
    public var ownerAllocation: Double
    public var history: [Double]
    public var risk: MarketRisk
    public var canSell: Bool
    public var sellNote: String?
    public var delisted: Bool
}

public struct PortfolioTotals: Equatable, Sendable {
    public var value = 0.0, costBasis = 0.0, pnl = 0.0, pnlToday = 0.0, pnlWeek = 0.0
    public var positions = 0
    public var pnlPercent: Double? { costBasis > 0 ? pnl / costBasis : nil }

    mutating func add(_ p: PortfolioPosition) {
        value += p.value; costBasis += p.costBasis; pnl += p.pnl; pnlToday += p.pnlToday; pnlWeek += p.pnlWeek; positions += 1
    }
}

public struct PortfolioOwnerSummary: Identifiable, Equatable, Sendable {
    public var id: String { owner.id }
    public var owner: PortfolioOwner
    public var name: String
    public var cash: Double
    public var totals: PortfolioTotals
}

public struct Portfolio: Equatable, Sendable {
    public var positions: [PortfolioPosition]
    public var owners: [PortfolioOwnerSummary]
    public var totals: PortfolioTotals
    public var history: [Double]
    public func positions(of owner: PortfolioOwner) -> [PortfolioPosition] { positions.filter { $0.owner == owner } }
    public func totals(of owner: PortfolioOwner) -> PortfolioTotals { owners.first { $0.owner == owner }?.totals ?? PortfolioTotals() }
}

public extension GameEngine {
    var portfolio: Portfolio { MarketBook.portfolio(state, data: data) }

    var marketOwners: [PortfolioOwnerSummary] { portfolio.owners }
}

enum MarketBook {
    static let fundNames = ["idx": "Index fund", "bond": "Bond fund", "mm": "Money-market fund"]
    static func fundKind(_ sym: String) -> MarketAssetKind { sym == "idx" ? .indexFund : sym == "bond" ? .bondFund : .moneyMarketFund }
    static func fundRisk(_ sym: String) -> MarketRisk { sym == "idx" ? .medium : .low }
    static func cryptoRisk(_ c: JSONValue) -> MarketRisk { c["vol"].double >= 0.09 ? .veryHigh : .high }

    static func history(_ s: GameState, kind: Brokerage.Kind, _ sym: String) -> [Double] {
        switch kind {
        case .fund: return Markets.fundHistory(s, sym)
        case .crypto: return (s.rest["crypto"]?[sym]["h"].array ?? []).map { $0.double }
        case .stock: return (s.rest["stocks"]?[sym]["h"].array ?? []).map { $0.double }
        }
    }

    static func weekMove(_ s: GameState, history h: [Double], units: Double, lastBuy: (week: Int, units: Double)?) -> Double {
        guard h.count >= 2 else { return 0 }
        let fresh = lastBuy.map { $0.week >= s.week ? $0.units : 0 } ?? 0
        let held = max(0, units - fresh)
        return held * (h[h.count - 1] - h[h.count - 2])
    }

    static func lastBuy(_ pos: JSONValue) -> (week: Int, units: Double)? {
        let b = pos["buy"]
        return b.isNull ? nil : (b["w"].int, b["q"].double)
    }

    static func make(_ s: GameState, id: String, owner: PortfolioOwner, ownerName: String, kind: MarketAssetKind, assetID: String?, name: String, symbol: String,
                     units: Double, price: Double, cost: Double, value: Double, pnl: Double? = nil, week: Double = 0, history: [Double] = [],
                     risk: MarketRisk, canSell: Bool = true, note: String? = nil, delisted: Bool = false) -> PortfolioPosition {
        let r = pnl ?? value - cost
        return PortfolioPosition(id: id, owner: owner, ownerName: ownerName, kind: kind, assetID: assetID, name: name, symbol: symbol, units: units, price: price,
                                 costBasis: cost, value: value, pnl: r, pnlPercent: cost > 0 ? r / cost : nil, pnlToday: s.day == 0 ? week : 0, pnlWeek: week,
                                 allocation: 0, ownerAllocation: 0, history: history, risk: risk, canSell: canSell, sellNote: note, delisted: delisted)
    }

    static func personalPositions(_ s: GameState) -> [PortfolioPosition] {
        var out: [PortfolioPosition] = []
        let inv = s.rest["inv"] ?? .null
        let me = PortfolioOwner.player
        func add(_ kind: Brokerage.Kind, _ key: String, _ assetKind: (String) -> MarketAssetKind, _ name: (String) -> String, _ risk: (String) -> MarketRisk, buyable: Bool) {
            for (sym, pos) in inv[key].object.sorted(by: { $0.key < $1.key }) where pos["q"].double > 1e-9 {
                let px = Brokerage.price(s, kind, sym)
                let q = pos["q"].double
                let h = history(s, kind: kind, sym)
                let dead = kind == .crypto && s.rest["crypto"]?[sym]["dead"].bool == true
                out.append(make(s, id: "me:\(kind.rawValue):\(sym)", owner: me, ownerName: "You", kind: assetKind(sym), assetID: buyable ? "\(kind.rawValue):\(sym)" : nil,
                                name: name(sym), symbol: sym, units: q, price: px, cost: pos["cost"].double, value: q * px,
                                week: weekMove(s, history: h, units: q, lastBuy: lastBuy(pos)), history: h, risk: risk(sym),
                                note: kind == .stock ? "Shares can be sold; new purchases are not offered." : nil, delisted: dead))
            }
        }
        add(.fund, "funds", fundKind, { fundNames[$0] ?? $0 }, fundRisk, buyable: true)
        add(.crypto, "crypto", { _ in .crypto }, { s.rest["crypto"]?[$0]["n"].string ?? $0 }, { cryptoRisk(s.rest["crypto"]?[$0] ?? .null) }, buyable: true)
        add(.stock, "stocks", { _ in .stock }, { s.rest["stocks"]?[$0]["n"].string ?? $0 }, { _ in .high }, buyable: false)
        if let a = FinanceManager.account(s), a.balance > 0 || a.cost > 0 {
            out.append(make(s, id: "me:managed:fm", owner: me, ownerName: "You", kind: .managedFund, assetID: "managed:fm", name: "Managed by \(a.name)", symbol: a.mandate.title,
                            units: 1, price: a.balance, cost: a.cost, value: a.balance,
                            risk: a.mandate == .cautious ? .low : a.mandate == .balanced ? .medium : .high))
        }
        for d in inv["deposits"].array {
            let left = max(0, d["wEnd"].int - s.week)
            out.append(make(s, id: "me:deposit:\(d["id"].int)", owner: me, ownerName: "You", kind: .fixedDeposit, assetID: nil, name: "Fixed deposit",
                            symbol: Currency.percent(d["rate"].double, decimals: 2), units: 1, price: d["bal"].double, cost: d["bal"].double, value: d["bal"].double,
                            risk: .low, canSell: false, note: "Locked until it matures in \(left) week\(left == 1 ? "" : "s"); it pays back with interest then."))
        }
        for st in Startups.stakes(s) where st.live || st.failed {
            out.append(make(s, id: "me:startup:\(st.id)", owner: me, ownerName: "You", kind: .startupStake, assetID: nil, name: st.name, symbol: st.stageName,
                            units: st.ownership, price: st.ownership > 0 ? st.value / st.ownership : 0, cost: st.invested, value: st.value, risk: .veryHigh,
                            canSell: st.live, note: st.live ? "A private sale: buyers pay about 72% of the estimated value." : "The startup has failed."))
        }
        for f in PrivateEquity.funds(s) where f.live {
            out.append(make(s, id: "me:pe:\(f.id)", owner: me, ownerName: "You", kind: .privateEquity, assetID: nil, name: f.name, symbol: f.style,
                            units: 1, price: f.nav, cost: f.paidIn, value: f.nav, pnl: f.nav + f.distributed - f.paidIn, risk: .high,
                            note: "Sold whole on the secondary market, \(Int(saturating: (PrivateEquity.secondaryDiscount(s, fundID: f.id) * 100).rounded()))% under its value."))
        }
        for g in GroupDeals.stakes(s) {
            out.append(make(s, id: "me:group:\(g.id)", owner: me, ownerName: "You", kind: .groupStake, assetID: nil, name: g.name, symbol: "\(Int(saturating: (g.ownership * 100).rounded()))%",
                            units: g.ownership * 100, price: g.ownership > 0 ? g.value / (g.ownership * 100) : 0, cost: g.cost, value: g.value, risk: .medium,
                            canSell: false, note: "A stake in a group is held for its share of the group's value; there is no buyer for it."))
        }
        for (n, raw) in (s.rest["stakes"]?.array ?? []).enumerated() {
            let v = raw["val"].double
            out.append(make(s, id: "me:big:\(raw["id"].isNull ? n : raw["id"].int)", owner: me, ownerName: "You", kind: .companyStake, assetID: nil, name: raw["name"].string,
                            symbol: "\(raw["pct"].int)%", units: raw["pct"].double, price: raw["pct"].double > 0 ? v / raw["pct"].double : 0,
                            cost: raw["cost"].isNull ? v : raw["cost"].double, value: v, risk: .medium, canSell: false,
                            note: "A strategic stake: it pays its share of profit every year and is not for sale."))
        }
        return out
    }

    static func holdingPositions(_ s: GameState) -> [PortfolioPosition] {
        var out: [PortfolioPosition] = []
        for h in HoldingModel.holdings(in: s, openOnly: false) {
            let owner = PortfolioOwner.holding(h.id)
            for sym in HoldingModel.treasuryFunds {
                let pos = HoldingModel.fundPosition(h, sym)
                guard pos.units > 1e-9 else { continue }
                let px = HoldingModel.fundPrice(s, sym)
                let hist = Markets.fundHistory(s, sym)
                out.append(make(s, id: "\(owner.id):fund:\(sym)", owner: owner, ownerName: h.name, kind: fundKind(sym), assetID: "fund:\(sym)", name: fundNames[sym] ?? sym,
                                symbol: sym, units: pos.units, price: px, cost: pos.cost, value: pos.units * px,
                                week: weekMove(s, history: hist, units: pos.units, lastBuy: HoldingModel.fundLastBuy(h, sym)), history: hist, risk: fundRisk(sym),
                                canSell: h.status == .open, note: h.status == .open ? nil : "The holding is not open."))
            }
        }
        return out
    }

    static func portfolio(_ s: GameState, data: GameData) -> Portfolio {
        var list = personalPositions(s) + holdingPositions(s)
        var totals = PortfolioTotals()
        var byOwner: [PortfolioOwner: PortfolioTotals] = [:]
        for p in list { totals.add(p); byOwner[p.owner, default: PortfolioTotals()].add(p) }
        for i in list.indices {
            list[i].allocation = totals.value > 0 ? max(0, list[i].value) / totals.value : 0
            let ov = byOwner[list[i].owner]?.value ?? 0
            list[i].ownerAllocation = ov > 0 ? max(0, list[i].value) / ov : 0
        }
        var owners = [PortfolioOwnerSummary(owner: .player, name: "You", cash: Payments.liquid(s), totals: byOwner[.player] ?? PortfolioTotals())]
        for h in HoldingModel.holdings(in: s, openOnly: false) where h.status == .open || byOwner[.holding(h.id)] != nil {
            owners.append(PortfolioOwnerSummary(owner: .holding(h.id), name: h.name, cash: h.cash, totals: byOwner[.holding(h.id)] ?? PortfolioTotals()))
        }
        let order = Dictionary(owners.enumerated().map { ($0.element.owner, $0.offset) }, uniquingKeysWith: { (a, _) in a })
        list.sort { (order[$0.owner] ?? 0, -$0.value) < (order[$1.owner] ?? 0, -$1.value) }
        return Portfolio(positions: list, owners: owners, totals: totals, history: (s.rest["pfH"]?.array ?? []).map { $0["v"].double })
    }

    static func recordHistory(_ s: inout GameState, data: GameData) {
        let t = portfolio(s, data: data).totals
        var h = s.rest["pfH"]?.array ?? []
        if let last = h.last, last["w"].int == s.week { h.removeLast() }
        h.append(.object(["w": .number(Double(s.week)), "v": .number(jsRound(t.value)), "p": .number(jsRound(t.pnl))]))
        if h.count > 104 { h.removeFirst(h.count - 104) }
        s.rest["pfH"] = .array(h)
    }

    static func backfillCostBases(_ s: inout GameState) {
        HoldingModel.backfillCostBasis(&s)
        if var inv = s.rest["inv"], !inv.isNull {
            var changed = false
            for (key, kind) in [("funds", Brokerage.Kind.fund), ("crypto", .crypto), ("stocks", .stock)] {
                var bag = inv[key]
                for (sym, pos) in bag.object where pos["q"].double > 0 && (pos["cost"].isNull || pos["cost"].double <= 0) {
                    var p = pos
                    p["cost"] = .number(jsRound(pos["q"].double * Brokerage.price(s, kind, sym) * 100) / 100)
                    bag[sym] = p
                    changed = true
                }
                inv[key] = bag
            }
            if changed { s.rest["inv"] = inv }
        }
        if var stakes = s.rest["stakes"]?.array, stakes.contains(where: { $0["cost"].isNull }) {
            for i in stakes.indices where stakes[i]["cost"].isNull { stakes[i]["cost"] = stakes[i]["val"] }
            s.rest["stakes"] = .array(stakes)
        }
    }
}
