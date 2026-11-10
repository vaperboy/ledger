import Foundation
import GameCore
import Businesses

public struct StructureNode: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case you, holding, chain, company, branch, division, headOffice, stake }
    public enum Health: String, Equatable, Sendable {
        case thriving, healthy, tight, struggling
        case setup

        public var title: String {
            switch self {
            case .thriving: return "Thriving"
            case .healthy: return "Healthy"
            case .tight: return "Tight"
            case .struggling: return "Struggling"
            case .setup: return "Setting up"
            }
        }
        fileprivate var severity: Int {
            switch self { case .thriving: return 0; case .healthy: return 1; case .tight: return 2; case .struggling: return 3; case .setup: return -1 }
        }
    }
    public enum Action: Equatable, Sendable {
        case decide(Int)
        case appointManager
        case fix(String)
        case open
    }

    public var id: String
    public var kind: Kind
    public var parentID: String?
    public var companyID: Int?
    public var name: String
    public var roleLabel: String
    public var ownerYouPercent: Double
    public var holdingPercent: Double?
    public var tierTitle: String?
    public var runnerName: String?
    public var runnerTitle: String?
    public var runnerPersonID: Int?
    public var authority: String?
    public var health: Health
    public var value: Double
    public var change: Double?
    public var waitingDecisions: Int
    public var primaryAction: Action
}

public struct OwnerLine: Equatable, Sendable {
    public var youPercent: Double
    public var holdingID: Int?
    public var holdingPercent: Double?
    public var othersPercent: Double

    public init(youPercent: Double, holdingID: Int?, holdingPercent: Double?, othersPercent: Double) {
        self.youPercent = youPercent; self.holdingID = holdingID; self.holdingPercent = holdingPercent; self.othersPercent = othersPercent
    }
}

public struct BranchPosition: Equatable, Sendable {
    public var chainID: Int
    public var headOfficeID: Int
    public var index: Int
    public var count: Int
}

public extension GameEngine {
    func structureTree() -> [StructureNode] {
        let s = state
        let mgmt = Dictionary(groupManagement().lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var healthCache: [Int: CompanyHealth] = [:]
        func health(_ c: Company) -> CompanyHealth {
            if let h = healthCache[c.id] { return h }
            let h = companyHealth(c)
            healthCache[c.id] = h
            return h
        }
        func label(_ c: Company) -> StructureNode.Health {
            if c.status == .setup { return .setup }
            switch health(c).label {
            case "Thriving": return .thriving
            case "Healthy": return .healthy
            case "Tight": return .tight
            case "Struggling": return .struggling
            default: return .setup
            }
        }
        func tradeName(_ c: Company) -> String { data.catalog[c.type]?.name ?? "Company" }

        var nodes: [StructureNode] = []
        var placed = Set<Int>()

        func companyNode(_ c: Company, id: String, kind: StructureNode.Kind, parent: String?, role: String, holdingID: Int?, decisions: Bool) -> StructureNode {
            let h = health(c)
            let line = mgmt[c.id]
            let owner = ownerLine(companyID: c.id)
            let hp = holdingID.map { HoldingStakes.sharePercent(of: c, holdingID: $0) }
            let hl = label(c)
            var waiting = 0
            if decisions, let key = boardKey(companyID: c.id) { waiting = boardOpenDecisions(key: key) }
            var action = StructureNode.Action.open
            if waiting > 0 { action = .decide(waiting) }
            else if hl == .struggling { action = .fix(h.bottleneck ?? (c.cash < 0 ? "The account is overdrawn." : "Cash is running out.")) }
            else if c.status == .open, c.type != "hold", kind != .branch, kind != .division, line?.runner == nil, line?.above.isEmpty ?? true { action = .appointManager }
            return StructureNode(id: id, kind: kind, parentID: parent, companyID: c.id, name: c.name, roleLabel: role,
                                 ownerYouPercent: owner.youPercent + (hp ?? owner.holdingPercent ?? 0), holdingPercent: hp,
                                 tierTitle: hp.map { GameEngine.stakeTierTitle($0) },
                                 runnerName: line?.runner?.name, runnerTitle: line?.runner?.title, runnerPersonID: line?.runner?.personID,
                                 authority: line?.runner?.authorityText, health: hl, value: h.value, change: h.revenueGrowth,
                                 waitingDecisions: waiting, primaryAction: action)
        }

        let live = s.companies.filter { $0.status.isLive }
        let holdings = live.filter { $0.type == "hold" }

        nodes.append(StructureNode(id: "you", kind: .you, parentID: nil, companyID: nil, name: s.player.name, roleLabel: "Owner", ownerYouPercent: 100,
                                   holdingPercent: nil, tierTitle: nil, runnerName: nil, runnerTitle: nil, runnerPersonID: nil, authority: nil,
                                   health: .setup, value: netWorth.companies, change: nil, waitingDecisions: 0, primaryAction: .open))

        func addChain(of c: Company, parent: String) -> Bool {
            let stores = s.chainStores(of: c)
            guard stores.count >= 2, let ch = Chains.chain(s, of: c), let head = stores.first else { return false }
            let cid = "chain:\(ch["id"].int)"
            let key = "ch:\(ch["id"].int)"
            let waiting = boardOpenDecisions(key: key)
            let hl = Self.worstHealth(stores.map(label))
            let boss = mgmt[head.id]?.above.first
            var action = StructureNode.Action.open
            if waiting > 0 { action = .decide(waiting) }
            else if hl == .struggling { action = .fix(stores.filter { label($0) == .struggling }.compactMap { health($0).bottleneck }.first ?? "A location is losing money.") }
            let owner = ownerLine(companyID: head.id)
            nodes.append(StructureNode(id: cid, kind: .chain, parentID: parent, companyID: nil, name: ch["name"].string,
                                       roleLabel: "\(tradeName(head)) chain, \(stores.count) locations",
                                       ownerYouPercent: owner.youPercent + (owner.holdingPercent ?? 0), holdingPercent: owner.holdingPercent, tierTitle: nil,
                                       runnerName: boss?.name, runnerTitle: boss?.title, runnerPersonID: boss?.personID, authority: boss?.authorityText,
                                       health: hl, value: stores.reduce(0) { $0 + health($1).value }, change: nil, waitingDecisions: waiting, primaryAction: action))
            for (i, st) in stores.enumerated() {
                placed.insert(st.id)
                nodes.append(companyNode(st, id: "loc:\(st.id)", kind: i == 0 ? .headOffice : .branch, parent: cid,
                                         role: i == 0 ? "Head office" : "Branch \(i + 1) of \(stores.count)", holdingID: nil, decisions: false))
            }
            return true
        }

        func addAttached(to c: Company, nodeID: String) {
            for d in HoldingStakes.divisions(of: c.id, in: s) where !placed.contains(d.id) {
                placed.insert(d.id)
                nodes.append(companyNode(d, id: "div:\(d.id)", kind: .division, parent: nodeID, role: "Division of \(c.name)", holdingID: nil, decisions: false))
            }
            for b in live where !placed.contains(b.id) && b.id != c.id && b.value("chain").isNull && !b.value("branch")["of"].isNull && b.value("branch")["of"].int == c.id {
                placed.insert(b.id)
                nodes.append(companyNode(b, id: "co:\(b.id)", kind: .branch, parent: nodeID, role: "Branch of \(c.name)", holdingID: nil, decisions: false))
            }
        }

        for h in holdings {
            placed.insert(h.id)
            let hid = "co:\(h.id)"
            let subs = HoldingModel.subsidiaries(of: h.id, in: s).filter { $0.type != "hold" && !HoldingStakes.isDivision($0) }
            let subIDs = Set(subs.map { $0.id })
            let stakes = HoldingStakes.stakeCompanies(of: h.id, in: s).filter { !subIDs.contains($0.id) && !HoldingStakes.isDivision($0) }
            var n = companyNode(h, id: hid, kind: .holding, parent: "you", role: "Holding company", holdingID: nil, decisions: true)
            n.ownerYouPercent = ownerLine(companyID: h.id).youPercent
            n.value = HoldingModel.consolidated(h, s, trades: data.catalog).holdingValue
            n.health = Self.worstHealth(subs.map(label) + [label(h)])
            nodes.append(n)
            addAttached(to: h, nodeID: hid)
            for c in subs where !placed.contains(c.id) {
                if addChain(of: c, parent: hid) { continue }
                placed.insert(c.id)
                nodes.append(companyNode(c, id: "co:\(c.id)", kind: .company, parent: hid, role: tradeName(c), holdingID: h.id, decisions: true))
                addAttached(to: c, nodeID: "co:\(c.id)")
            }
            for c in stakes {
                nodes.append(companyNode(c, id: "stake:\(h.id):\(c.id)", kind: .stake, parent: hid, role: "Stake in \(tradeName(c))", holdingID: h.id, decisions: false))
            }
        }

        for c in live where !placed.contains(c.id) && c.type != "hold" {
            let host = c.value("branch")["of"]
            if HoldingStakes.isDivision(c) || (c.value("chain").isNull && !host.isNull && s.company(host.int)?.status.isLive == true) { continue }
            if addChain(of: c, parent: "you") { continue }
            placed.insert(c.id)
            nodes.append(companyNode(c, id: "co:\(c.id)", kind: .company, parent: "you", role: tradeName(c), holdingID: nil, decisions: true))
            addAttached(to: c, nodeID: "co:\(c.id)")
        }

        for c in live where !placed.contains(c.id) {
            placed.insert(c.id)
            nodes.append(companyNode(c, id: "co:\(c.id)", kind: .company, parent: "you", role: tradeName(c), holdingID: nil, decisions: false))
        }
        return nodes
    }

    func branchParent(companyID: Int) -> BranchPosition? {
        guard let c = state.company(companyID), c.status.isLive, let ch = Chains.chain(state, of: c) else { return nil }
        let stores = state.chainStores(of: c)
        guard stores.count >= 2, let head = stores.first, let i = stores.firstIndex(where: { $0.id == companyID }) else { return nil }
        return BranchPosition(chainID: ch["id"].int, headOfficeID: head.id, index: i + 1, count: stores.count)
    }

    func ownerLine(companyID: Int) -> OwnerLine {
        guard let c = state.company(companyID) else { return OwnerLine(youPercent: 0, holdingID: nil, holdingPercent: nil, othersPercent: 0) }
        let rows = c.value("holders").array
        let others = rows.filter { $0["hid"].int == 0 }.reduce(0) { $0 + $1["pct"].double }
        var hid = c.holdingID
        if hid == 0, let top = rows.filter({ $0["hid"].int != 0 && $0["pct"].double > 0 }).max(by: { $0["pct"].double < $1["pct"].double }) { hid = top["hid"].int }
        guard hid != 0 else { return OwnerLine(youPercent: c.ownership, holdingID: nil, holdingPercent: nil, othersPercent: others) }
        let direct = c.holdingID == hid ? 0 : c.ownership
        return OwnerLine(youPercent: direct, holdingID: hid, holdingPercent: HoldingStakes.sharePercent(of: c, holdingID: hid), othersPercent: others)
    }

    func structureHealth(ids: [String]) -> StructureNode.Health {
        let wanted = Set(ids)
        return Self.worstHealth(structureTree().filter { wanted.contains($0.id) }.map { $0.health })
    }

    func structureHealth(companyIDs: [Int]) -> StructureNode.Health {
        let wanted = Set(companyIDs)
        return Self.worstHealth(structureTree().filter { $0.companyID.map { wanted.contains($0) } ?? false }.map { $0.health })
    }

    private static func worstHealth(_ hs: [StructureNode.Health]) -> StructureNode.Health {
        hs.filter { $0 != .setup }.max { $0.severity < $1.severity } ?? .setup
    }

    internal static func stakeTierTitle(_ percent: Double) -> String {
        switch HoldingStakes.tier(forPercent: percent) {
        case .none, .passive: return "Small stake (under 20%)"
        case .influence: return "Big stake (20-50%)"
        case .control: return "Controlled (over 50%)"
        case .squeezeOut: return "Controlled, can buy out the rest (90%+)"
        case .whole: return "100% yours"
        }
    }
}
