import Foundation
import GameCore
import Finance
import Businesses

public struct DividendRow: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var holdingID: Int?
    public var holdingName: String?
    public var payable: Double
    public var distributed: Double
}

public extension GameEngine {
    func dividendRows() -> [DividendRow] {
        state.companies.filter { $0.status.isLive && $0.type != "hold" }.compactMap { co -> DividendRow? in
            let br = state.chainStores(of: co)
            if br.count >= 2 && br[0].id != co.id { return nil }
            let can = Payments.maximumDividend(co, state: state, context: context)
            let paid = br.count >= 2 ? br.reduce(0) { $0 + $1.distributed } : co.distributed
            guard can > 0 || paid > 0 else { return nil }
            let h: Company? = co.holdingID != 0 ? state.company(co.holdingID) : nil
            let name = br.count >= 2 ? Chains.chain(state, of: co)?["name"].string ?? co.name : co.name
            return DividendRow(id: co.id, name: name, holdingID: h?.id, holdingName: h?.name, payable: can, distributed: paid)
        }.sorted { $0.payable > $1.payable }
    }

    mutating func payDividendShare(companyID: Int, share: Double) -> Double {
        let can = maximumDividend(companyID: companyID)
        let amount = (can * min(max(share, 0), 1)).rounded(.down)
        guard amount > 0 else { return 0 }
        return payDividend(companyID: companyID, amount: amount) == .ok ? amount : 0
    }

    mutating func collectForHolding(holdingID: Int, share: Double) -> (total: Double, companies: Int) {
        var total = 0.0, n = 0
        for row in dividendRows() where row.holdingID == holdingID {
            let paid = payDividendShare(companyID: row.id, share: share)
            if paid > 0 { total += paid; n += 1 }
        }
        return (total, n)
    }
}
