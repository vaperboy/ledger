import Foundation
import GameCore
import Businesses

public extension GameEngine {
    func appointmentAuthority(companyID: Int, role: String) -> AppointmentAuthority {
        Appointments.authority(state, companyID: companyID, role: role, data: data)
    }

    @discardableResult
    mutating func proposeAssistantManager(companyID: Int, personID: Int, monthlyWage: Double) -> Bool {
        var ok = false
        update { s, d, _ in ok = Appointments.propose(&s, companyID: companyID, personID: personID, monthlyWage: monthlyWage, data: d) }
        return ok
    }

    func franchiseeRequirements(_ brand: FranchiseBrands.Brand, country: String) -> [Franchising.Requirement] {
        FranchiseBrands.requirements(brand, state, World(state: state, data: data), country: country)
    }

    func franchiseeSteps(_ brand: FranchiseBrands.Brand, country: String? = nil) -> [FranchiseBrands.Step] {
        let cc = FranchiseBrands.application(state, brand.id)["country"].string
        return FranchiseBrands.steps(brand, state, World(state: state, data: data), country: country ?? (cc.isEmpty ? state.homeCountryCode : cc))
    }

    func messageDocument(messageID: Int) -> InboxDocument? {
        state.inbox.first { $0.id == messageID }?.doc
    }
}
