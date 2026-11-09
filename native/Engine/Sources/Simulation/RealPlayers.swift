import Foundation
import GameCore
import Businesses

extension GameEngine {
    /// The companies players run, from the online directory: they stand as rivals in their own trade and city and appear in the rankings.
    public mutating func setPlayerCompanies(_ list: [RealCompany]) {
        update { s, _, _ in RealRivals.set(&s, list) }
    }
}
