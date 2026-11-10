import Foundation
import GameCore
import Countries
import Finance

public enum OfficeChecks {
    public struct Reference: Equatable, Sendable {
        public var skillBand: String
        public var experience: Double
        public var trait: String?
        public var claimedBand: String
        public var matchesCV: Bool { skillBand == claimedBand }
    }

    public enum ReferenceResult: Equatable, Sendable { case ok(Reference), notEnoughCash, unknownPerson }

    public static func reference(_ n: Person) -> Reference {
        Reference(skillBand: StaffProfile.band(n.skill), experience: n.num("exp"), trait: n.value("trait").isNull ? nil : n.value("trait").string,
                  claimedBand: StaffProfile.band(n.claimedSkill))
    }

    public static func referenceCheckCandidate(_ s: inout GameState, personID: Int, data: GameData) -> ReferenceResult {
        guard var n = s.people[personID], n.employerID == 0 else { return .unknownPerson }
        if !n.flag("checked") {
            let fee = ManagerModel.playerCurrency(s, data).scaledPrice(600)
            guard s.cash >= fee else { return .notEnoughCash }
            Payments.playerPays(&s, fee, label: "Reference check")
            n.set("checked", true)
            s.people[personID] = n
        }
        return .ok(reference(n))
    }

    public enum ReviewResult: Equatable, Sendable { case ok(Headquarters.Scorecard), notEnoughCash, noManager }

    public static func reviewManagerNow(_ s: inout GameState, companyID: Int, data: GameData) -> ReviewResult {
        guard let co = s.company(companyID), co.isOpenOrClosed, co.managerID != nil else { return .noManager }
        if !Headquarters.has(s, "perf") {
            let fee = ManagerModel.playerCurrency(s, data).scaledPrice(25000)
            guard s.cash >= fee else { return .notEnoughCash }
            Payments.playerPays(&s, fee, label: "External manager review", companyID: companyID)
        }
        guard let card = Headquarters.review(s, companyID: companyID), let i = s.companyIndex(companyID) else { return .noManager }
        s.companies[i].set("lastRev", .object(["score": .number(Double(card.score)), "w": .number(Double(s.week))]))
        return .ok(card)
    }
}
