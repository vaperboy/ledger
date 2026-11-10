import Foundation
import GameCore
import Businesses

extension GameEngine {
    public mutating func setPlayerCompanies(_ list: [RealCompany]) {
        update { s, _, _ in RealRivals.set(&s, list) }
    }
}
