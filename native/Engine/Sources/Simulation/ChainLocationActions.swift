import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Opening locations under a chain and reading the chain's own identity (its head office), for the chain page. Opening and closing a location is
/// a decision of the chain's board: the owner proposes and the shares vote at once, or the chain's CEO or chain manager proposes and the owner or
/// the shares decide from `boardDecisionList`.
public extension GameEngine {
    /// What opening a location in a city costs and what it will be called. Nil when the trade cannot open there.
    func locationQuote(chainID: Int, cityID: String, size: Double = 1) -> ChainLocations.Quote? {
        ChainLocations.quote(state, chainID: chainID, cityID: cityID, size: size, data: data)
    }

    /// Open a location: named by place, on the chain's standards, with a manager from the chain level when one is in post. You propose it and the
    /// board votes at once; with co-owners who vote against it, nothing opens (`notAllowedHere`).
    mutating func openLocation(chainID: Int, cityID: String, size: Double = 1) -> Result<Int, CompanySetup.StartError> {
        var r: Result<Int, CompanySetup.StartError> = .failure(.notAllowedHere)
        update { s, d, c in r = ChainLocations.openByVote(&s, chainID: chainID, cityID: cityID, size: size, data: d, context: c) }
        return r
    }

    /// Put opening a location to the chain's board as a proposal in the name of its CEO or chain manager (or yours without one); it waits on the
    /// decision list. Returns the proposal's number; nil when it cannot be quoted, is waiting already or was turned down lately.
    @discardableResult
    mutating func proposeLocation(chainID: Int, cityID: String, size: Double = 1, why: String = "") -> Int? {
        var r: Int?
        update { s, d, _ in
            let by = ChainLocations.leadLabel(s, chainID: chainID) ?? "You"
            r = ChainLocations.proposeOpen(&s, chainID: chainID, cityID: cityID, size: size, by: by, why: why, data: d)
        }
        return r
    }

    /// The proposals waiting on a chain's board.
    func locationProposals(chainID: Int) -> [ChainLocations.LocationProposal] { ChainLocations.proposals(state, chainID: chainID) }

    /// The chain's brand, head office, executives and shared services.
    func chainHeadOffice(chainID: Int) -> ChainIdentity.HeadOffice? { ChainIdentity.headOffice(state, chainID: chainID, data: data) }

    /// What the stores of a chain follow: a price band, a headcount floor and an ordering policy. Store managers read it when they set prices, hire or cut, or order.
    func chainStandards(chainID: Int) -> Chains.StoreStandards? { Chains.chainStandards(state, chainID: chainID) }

    @discardableResult
    mutating func setChainStandards(chainID: Int, priceLow: Double? = nil, priceHigh: Double? = nil, headcountFloor: Int? = nil, ordering: Int? = nil) -> SettingResult {
        applySetting(refuse: { Chains.chain($0, id: chainID) == nil ? "That chain no longer exists." : nil }, probe: { Chains.chain($0, id: chainID) ?? .null }) { s, _, _ in
            Chains.setStandards(&s, chainID: chainID, priceLow: priceLow, priceHigh: priceHigh, headcountFloor: headcountFloor, ordering: ordering)
        }
    }
}
