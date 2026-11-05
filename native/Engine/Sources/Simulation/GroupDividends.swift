import Foundation
import GameCore
import Finance
import Businesses

/// The Group's dividend desk: dividends are never automatic. A company with retained profit can pay a share of what it may pay;
/// a holding collects from the companies under it in one go. The owner chooses whether, when and how much.
public struct DividendRow: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    /// The holding that receives this company's dividend; nil when it goes to the owner.
    public var holdingID: Int?
    public var holdingName: String?
    /// The most it can pay now.
    public var payable: Double
    /// Paid out so far.
    public var distributed: Double
}

public extension GameEngine {
    /// Every live limited company that has something to pay or has paid before, largest payable first.
    func dividendRows() -> [DividendRow] {
        state.companies.filter { $0.status.isLive && $0.form == .limited && $0.type != "hold" }.compactMap { co -> DividendRow? in
            let can = Payments.maximumDividend(co, state: state, context: context)
            guard can > 0 || co.distributed > 0 else { return nil }
            let h: Company? = co.holdingID != 0 ? state.company(co.holdingID) : nil
            return DividendRow(id: co.id, name: co.name, holdingID: h?.id, holdingName: h?.name, payable: can, distributed: co.distributed)
        }.sorted { $0.payable > $1.payable }
    }

    /// Pay `share` (0 to 1) of what one company may pay. Returns the amount paid (0 when nothing could be).
    mutating func payDividendShare(companyID: Int, share: Double) -> Double {
        let can = maximumDividend(companyID: companyID)
        let amount = (can * min(max(share, 0), 1)).rounded(.down)
        guard amount > 0 else { return 0 }
        return payDividend(companyID: companyID, amount: amount) == .ok ? amount : 0
    }

    /// A holding collects `share` of what every company under it may pay. Returns the total and the number of companies that paid.
    mutating func collectForHolding(holdingID: Int, share: Double) -> (total: Double, companies: Int) {
        var total = 0.0, n = 0
        for row in dividendRows() where row.holdingID == holdingID {
            let paid = payDividendShare(companyID: row.id, share: share)
            if paid > 0 { total += paid; n += 1 }
        }
        return (total, n)
    }
}
