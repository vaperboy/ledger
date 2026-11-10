import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    func locationQuote(chainID: Int, cityID: String, size: Double = 1) -> ChainLocations.Quote? {
        ChainLocations.quote(state, chainID: chainID, cityID: cityID, size: size, data: data)
    }

    mutating func openLocation(chainID: Int, cityID: String, size: Double = 1) -> Result<Int, CompanySetup.StartError> {
        var r: Result<Int, CompanySetup.StartError> = .failure(.notAllowedHere)
        update { s, d, c in r = ChainLocations.openByVote(&s, chainID: chainID, cityID: cityID, size: size, data: d, context: c) }
        return r
    }

    @discardableResult
    mutating func proposeLocation(chainID: Int, cityID: String, size: Double = 1, why: String = "") -> Int? {
        var r: Int?
        update { s, d, _ in
            let by = ChainLocations.leadLabel(s, chainID: chainID) ?? "You"
            r = ChainLocations.proposeOpen(&s, chainID: chainID, cityID: cityID, size: size, by: by, why: why, data: d)
        }
        return r
    }

    func locationProposals(chainID: Int) -> [ChainLocations.LocationProposal] { ChainLocations.proposals(state, chainID: chainID) }

    func chainHeadOffice(chainID: Int) -> ChainIdentity.HeadOffice? { ChainIdentity.headOffice(state, chainID: chainID, data: data) }

    func chainStandards(chainID: Int) -> Chains.StoreStandards? { Chains.chainStandards(state, chainID: chainID) }

    @discardableResult
    mutating func setChainStandards(chainID: Int, priceLow: Double? = nil, priceHigh: Double? = nil, headcountFloor: Int? = nil, ordering: Int? = nil) -> SettingResult {
        applySetting(refuse: { Chains.chain($0, id: chainID) == nil ? "That chain no longer exists." : nil }, probe: { Chains.chain($0, id: chainID) ?? .null }) { s, _, _ in
            Chains.setStandards(&s, chainID: chainID, priceLow: priceLow, priceHigh: priceHigh, headcountFloor: headcountFloor, ordering: ordering)
        }
    }
}
