import Foundation
import GameCore
import Countries
import Employees
import Businesses

// Stage 3 read models and actions for the Team screens: the employment contract (type, working percentage, real dates, notice, history), the work-log
// feedback, and Company > Team > Promises. Changes to a contract go through the ONE door, `contractPropose` (ContractTalkActions.swift):
// working percentage = Proposal(.hours, amount: 80, choice: "percent"); hourly wage / pay rise = .payRise; fixed salary = .payBasis "salary";
// contract type and seasonal duration = .term ("perm", "fixed:<weeks>", "seasons:<n>") and .hours "season:<id>"; benefits = .benefits; responsibilities and
// position = .promotion. `contractPreview` shows current against new employer cost, monthly and annual difference, hours, payroll and operational impact.

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
    /// The employment contract of one team member: type labels, working percentage, hours, real start and end dates, season, notice from the labour data,
    /// renewal question and the history of every change.
    func employmentContract(companyID: Int, personID: Int) -> EmploymentContract.Summary? {
        EmploymentContract.summary(state, companyID: companyID, personID: personID, data: data)
    }

    /// Every change to this contract with its date, oldest first.
    func contractHistory(companyID: Int, personID: Int) -> [ContractHistory.Entry] {
        state.company(companyID)?.staff.first { $0.id == personID }.map { ContractHistory.entries($0) } ?? []
    }

    /// What the work log says about this person, in sentences built from what happened (never a rating, never a figure).
    func performanceFeedback(companyID: Int, personID: Int) -> WorkLog.Feedback? {
        state.company(companyID)?.staff.first { $0.id == personID }.map { WorkLog.feedback($0, week: state.week) }
    }

    /// Company > Team > Promises: every promise made to the company's people, open ones first.
    func promises(companyID: Int) -> [PromiseRow] {
        StaffPromises.promises(state, companyID: companyID).map { p in
            PromiseRow(id: p.id, personID: p.personID, employee: state.people[p.personID]?.name ?? "Former employee", kind: p.kind, kindTitle: p.kind.title, promise: p.text,
                       madeDate: p.madeDate, dueDate: p.dueDate, madeWeek: p.madeWeek, dueWeek: p.dueWeek, status: p.status, consequence: p.consequence, fulfilledBy: p.kind.fulfilledBy,
                       canRenegotiate: p.isOpen && p.renegotiations == 0)
        }
    }

    /// The promises made to one person.
    func promises(personID: Int) -> [StaffPromises.Promise] { StaffPromises.promises(state, personID: personID) }

    /// Promise something to someone who works for you (a salary review, training ...), in place of deciding now. The same door the contract talk uses.
    @discardableResult
    mutating func promise(companyID: Int, personID: Int, draft: StaffPromises.Draft) -> ContractTalk.Reply {
        var r = ContractTalk.Reply.notPossible("")
        update { s, _, _ in r = ContractTalk.promise(&s, companyID: companyID, personID: personID, draft: draft) }
        return r
    }

    /// Ask to move the date of an open promise (once per promise); they may refuse.
    @discardableResult
    mutating func renegotiatePromise(personID: Int, promiseID: Int, newDueInWeeks: Int) -> StaffPromises.RenegotiateResult {
        var r = StaffPromises.RenegotiateResult.notPossible("")
        update { s, _, _ in r = StaffPromises.renegotiate(&s, personID: personID, promiseID: promiseID, newDueInWeeks: newDueInWeeks) }
        return r
    }
}
