import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Opening locations under a chain and reading the chain's own identity (its head office), for the chain page.
public extension GameEngine {
    /// What opening a location in a city costs and what it will be called. Nil when the trade cannot open there.
    func locationQuote(chainID: Int, cityID: String, size: Double = 1) -> ChainLocations.Quote? {
        ChainLocations.quote(state, chainID: chainID, cityID: cityID, size: size, data: data)
    }

    /// Open a location: named by place, on the chain's standards, with a manager from the chain level when one is in post.
    mutating func openLocation(chainID: Int, cityID: String, size: Double = 1) -> Result<Int, CompanySetup.StartError> {
        var r: Result<Int, CompanySetup.StartError> = .failure(.notAllowedHere)
        update { s, d, c in r = ChainLocations.open(&s, chainID: chainID, cityID: cityID, size: size, data: d, context: c) }
        return r
    }

    /// The chain's brand, head office, executives and shared services.
    func chainHeadOffice(chainID: Int) -> ChainIdentity.HeadOffice? { ChainIdentity.headOffice(state, chainID: chainID, data: data) }
}
