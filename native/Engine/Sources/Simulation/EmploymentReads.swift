import Foundation
import GameCore
import Countries
import Employees
import Businesses

public struct PromiseRow: Equatable, Sendable, Identifiable {
    public var id: Int
    public var personID: Int
    public var employee: String
    public var kind: StaffPromises.Kind
    public var kindTitle: String
    public var promise: String
    public var madeDate: GameCalendar.Date
    public var dueDate: GameCalendar.Date
    public var madeWeek: Int
    public var dueWeek: Int
    public var status: StaffPromises.Status
    public var consequence: String
    public var fulfilledBy: String
    public var canRenegotiate: Bool
}

public extension GameEngine {
    func employmentContract(companyID: Int, personID: Int) -> EmploymentContract.Summary? {
        EmploymentContract.summary(state, companyID: companyID, personID: personID, data: data)
    }

    func contractHistory(companyID: Int, personID: Int) -> [ContractHistory.Entry] {
        state.company(companyID)?.staff.first { $0.id == personID }.map { ContractHistory.entries($0) } ?? []
    }

    func performanceFeedback(companyID: Int, personID: Int) -> WorkLog.Feedback? {
        state.company(companyID)?.staff.first { $0.id == personID }.map { WorkLog.feedback($0, week: state.week) }
    }

    func promises(companyID: Int) -> [PromiseRow] {
        StaffPromises.promises(state, companyID: companyID).map { p in
            PromiseRow(id: p.id, personID: p.personID, employee: state.people[p.personID]?.name ?? "Former employee", kind: p.kind, kindTitle: p.kind.title, promise: p.text,
                       madeDate: p.madeDate, dueDate: p.dueDate, madeWeek: p.madeWeek, dueWeek: p.dueWeek, status: p.status, consequence: p.consequence, fulfilledBy: p.kind.fulfilledBy,
                       canRenegotiate: p.isOpen && p.renegotiations == 0)
        }
    }

    func promises(personID: Int) -> [StaffPromises.Promise] { StaffPromises.promises(state, personID: personID) }

    @discardableResult
    mutating func promise(companyID: Int, personID: Int, draft: StaffPromises.Draft) -> ContractTalk.Reply {
        var r = ContractTalk.Reply.notPossible("")
        update { s, _, _ in r = ContractTalk.promise(&s, companyID: companyID, personID: personID, draft: draft) }
        return r
    }

    @discardableResult
    mutating func renegotiatePromise(personID: Int, promiseID: Int, newDueInWeeks: Int) -> StaffPromises.RenegotiateResult {
        var r = StaffPromises.RenegotiateResult.notPossible("")
        update { s, _, _ in r = StaffPromises.renegotiate(&s, personID: personID, promiseID: promiseID, newDueInWeeks: newDueInWeeks) }
        return r
    }

    @discardableResult mutating func groupRaise(personID: Int, percent: Double) -> Bool { var r = false; update { s, d, _ in r = GroupPeople.raise(&s, personID: personID, percent: percent, data: d) }; return r }
    @discardableResult mutating func groupPromote(personID: Int) -> Bool { var r = false; update { s, d, _ in r = GroupPeople.promote(&s, personID: personID, data: d) }; return r }
    @discardableResult mutating func groupSetLevel(personID: Int, level: Int) -> Bool { var r = false; update { s, _, _ in r = GroupPeople.setLevel(&s, personID: personID, level: level) }; return r }
    @discardableResult mutating func groupTrain(personID: Int) -> Bool { var r = false; update { s, d, _ in r = GroupPeople.train(&s, personID: personID, data: d) }; return r }
    @discardableResult mutating func groupSetExpense(personID: Int, item: String, on: Bool) -> Bool { var r = false; update { s, _, _ in r = GroupPeople.setExpense(&s, personID: personID, item: item, on: on) }; return r }
    @discardableResult mutating func groupSetPercent(personID: Int, percent: Double) -> Bool { var r = false; update { s, _, _ in r = GroupPeople.setPercent(&s, personID: personID, percent: percent) }; return r }

    var publicImageWords: [(axis: String, word: String)] {
        let i = Press.image(state)
        return StandingWords.pressImage(trust: i.trust, bold: i.bold, care: i.care)
    }
}
