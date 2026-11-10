import Foundation
import GameCore

public enum PublicRules {
    public static let controlAbove = 50.0
    public static let largeLoanShare = 0.25

    public enum Change: Equatable, Sendable { case close, sellAssets, largeLoan }

    public static func isListed(_ s: GameState, companyID: Int) -> Bool { PublicExchange.isListed(s, companyID: companyID) }

    public static func restriction(_ s: GameState, companyID: Int, change: Change) -> String? {
        guard let co = s.company(companyID), isListed(s, companyID: companyID) else { return nil }
        switch change {
        case .close: return "\(co.name) is listed. Closing it needs a vote of all its shareholders, so it cannot be closed while the shares are public."
        case .sellAssets: return "\(co.name) is listed. Selling its equipment, vehicles or property needs a vote of all its shareholders, so it is not possible while the shares are public."
        case .largeLoan: return "\(co.name) is listed. A loan this large needs a vote of all its shareholders, so it is not possible while the shares are public."
        }
    }
}
