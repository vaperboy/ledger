import SwiftUI
import GameCore
import Businesses
import Finance
import Countries

enum DealText {
    static func describe(_ t: CapTable.DealTerms?, _ cur: Currency, companyName: String) -> String {
        guard let t else { return "The money goes into \(companyName)." }
        func pct(_ v: Double) -> String { String(format: "%.1f", v) + "%" }
        var lines: [String] = []
        switch t.kind {
        case .newIssue:
            lines.append("New shares: \(t.sharesIssued) at \(cur.tidyDisplay(t.pricePerShare)) each. The company is valued at \(cur.tidyShort(t.valuationBefore)) before and \(cur.tidyShort(t.valuationAfter)) after the money.")
            lines.append("Shares in issue: \(t.sharesInIssueBefore) before, \(t.sharesInIssueAfter) after. \(t.buyer) holds \(pct(t.buyerPctAfter)).")
            lines.append("You go from \(pct(t.yourPctBefore)) to \(pct(t.yourPctAfter)); every other holder is diluted the same way (by \(pct(t.dilutionPercent)) of what they had).")
            lines.append("\(cur.tidyShort(t.companyProceeds)) goes to the company; you receive nothing personally.")
        case .founderSale:
            lines.append("You sell \(t.sharesSold) of your shares at \(cur.tidyDisplay(t.pricePerShare)) each. No new shares are made (\(t.sharesInIssueBefore) in issue).")
            lines.append("You go from \(pct(t.yourPctBefore)) to \(pct(t.yourPctAfter)); \(t.buyer) holds \(pct(t.buyerPctAfter)).")
            lines.append("\(cur.tidyShort(t.personalProceeds)) comes to you (gains are taxed); the company receives nothing.")
        case .holderSale:
            lines.append("\(t.sharesSold) shares change hands at \(cur.tidyDisplay(t.pricePerShare)) each; \(t.buyer) holds \(pct(t.buyerPctAfter)).")
            lines.append("You keep \(pct(t.yourPctAfter)). Neither you nor the company receives anything.")
        case .fullExit:
            lines.append("The whole company is sold for \(cur.tidyShort(t.amount)) (\(cur.tidyDisplay(t.pricePerShare)) a share). Your \(pct(t.yourPctBefore)) pays \(cur.tidyShort(t.personalProceeds)).")
        }
        lines.append(contentsOf: t.conditions)
        return lines.joined(separator: "\n")
    }
}
