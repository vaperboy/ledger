import Foundation
import GameCore
import Businesses

/// Reads and actions for the real-life rules: who appoints whom, inbox documents, the chain and franchise paperwork.
public extension GameEngine {
    /// Who decides an appointment to `role` ("general manager", "assistant manager", "deputy", a staff role) and who must confirm it.
    func appointmentAuthority(companyID: Int, role: String) -> AppointmentAuthority {
        Appointments.authority(state, companyID: companyID, role: role, data: data)
    }

    /// The manager proposes an assistant manager to the level above (CEO, else the owner). The assistant exists only once it is confirmed.
    @discardableResult
    mutating func proposeAssistantManager(companyID: Int, personID: Int, monthlyWage: Double) -> Bool {
        var ok = false
        update { s, d, _ in ok = Appointments.propose(&s, companyID: companyID, personID: personID, monthlyWage: monthlyWage, data: d) }
        return ok
    }

    /// The requirement rows of a franchisee's application to a brand (review, signed agreement, financing for the entry fee).
    func franchiseeRequirements(_ brand: FranchiseBrands.Brand, country: String) -> [Franchising.Requirement] {
        FranchiseBrands.requirements(brand, state, World(state: state, data: data), country: country)
    }

    /// The steps of a franchisee's way into a brand: eligibility, entry fee, approval and terms, opening.
    func franchiseeSteps(_ brand: FranchiseBrands.Brand, country: String? = nil) -> [FranchiseBrands.Step] {
        let cc = FranchiseBrands.application(state, brand.id)["country"].string
        return FranchiseBrands.steps(brand, state, World(state: state, data: data), country: country ?? (cc.isEmpty ? state.homeCountryCode : cc))
    }

    /// The structured document a "doc" message carries (a research report, a disclosure result); nil for an ordinary message.
    func messageDocument(messageID: Int) -> InboxDocument? {
        state.inbox.first { $0.id == messageID }?.doc
    }
}
