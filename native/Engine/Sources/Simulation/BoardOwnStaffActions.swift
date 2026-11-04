import Foundation
import GameCore
import Businesses

/// Board seats for your own people (employees and managers keep their jobs). Model: `ManagerBoardOwn.swift`.
public extension GameEngine {
    /// Your own people who qualify for the seat, then the searched candidates, for the board of this company (or its chain).
    func boardCandidates(companyID: Int, seat: String) -> [BoardCandidate] {
        guard let key = boardKey(companyID: companyID) else { return [] }
        return ManagerModel.boardCandidates(state, key: key, role: seat, data: data)
    }
    /// Seat an employee or manager of yours; they keep their job. A person of the board's own company gets half the fee.
    @discardableResult
    mutating func appointOwnToBoard(companyID: Int, seat: String, personID: Int) -> SettingResult {
        guard let key = boardKey(companyID: companyID) else { return .refused("There is no such company.") }
        var why: String?
        let r = applySetting(probe: { ManagerModel.board($0, key: key) }) { s, d, _ in why = ManagerModel.appointOwn(&s, key: key, role: seat, personID: personID, data: d) }
        return why.map { .refused($0) } ?? r
    }
}
