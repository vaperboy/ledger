import Foundation
import GameCore
import Countries
import Finance
import Businesses

// Accounting access: NAMED USERS ONLY. The owner has full access. Nobody else has any unless the owner adds them for that
// company, the accountant and managers included. Access to one company never gives access to another. Every Accounting read takes `user`
// (nil = the owner) and answers nil when that user may not see the section; every write checks the level.

public enum AccountingLevel: Int, Comparable, CaseIterable, Sendable {
    case none = 0
    /// Transactions, invoices, suppliers, documents.
    case view = 1
    /// View, plus payroll runs, payslips and timesheets.
    case payroll = 2
    /// Payroll and bookkeeping actions (notes, paying invoices), not access management.
    case full = 3
    /// The owner: everything, including who has access.
    case owner = 4
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var title: String {
        switch self { case .none: return "No access"; case .view: return "View"; case .payroll: return "Payroll and view"; case .full: return "Full bookkeeping"; case .owner: return "Owner" }
    }
}

public enum AccountingSection: Sendable {
    case transactions, invoices, suppliers, documents, payroll, timesheets, notes, payments, settings
    var needs: AccountingLevel {
        switch self {
        case .transactions, .invoices, .suppliers, .documents: return .view
        case .payroll, .timesheets: return .payroll
        case .notes, .payments: return .full
        case .settings: return .owner
        }
    }
}

/// A person who could be given access to one company's accounting, and what they have now.
public struct AccountingUser: Equatable, Sendable, Identifiable {
    /// "p<personID>" for an employee or manager, "acc" for the company's appointed accountant (a firm).
    public var id: String
    public var name: String
    public var role: String
    public var level: AccountingLevel
}

public enum AccessChange: Equatable, Sendable { case changed, unchanged, refused(String) }

public extension GameEngine {
    /// What `user` (nil = the owner) may do in this company's Accounting. Never inherited from another company.
    func accountingLevel(companyID: Int, user: String? = nil) -> AccountingLevel {
        guard let co = state.company(companyID) else { return .none }
        guard let user else { return .owner }
        let granted = co.value("acx")[user].int
        return AccountingLevel(rawValue: granted).map { min($0, .full) } ?? .none
    }

    func canAccess(_ section: AccountingSection, companyID: Int, user: String? = nil) -> Bool {
        accountingLevel(companyID: companyID, user: user) >= section.needs
    }

    /// Who has access and who could be added (the company's own people and its accountant). Owner only.
    func accountingRoster(companyID: Int, user: String? = nil) -> (granted: [AccountingUser], candidates: [AccountingUser])? {
        guard let co = state.company(companyID), canAccess(.settings, companyID: companyID, user: user) else { return nil }
        var all: [AccountingUser] = []
        for m in co.staff { all.append(AccountingUser(id: "p\(m.id)", name: state.people[m.id]?.name ?? "Employee", role: m.role, level: accountingLevel(companyID: companyID, user: "p\(m.id)"))) }
        if let mid = co.managerID { all.append(AccountingUser(id: "p\(mid)", name: state.people[mid]?.name ?? "Manager", role: "manager", level: accountingLevel(companyID: companyID, user: "p\(mid)"))) }
        let acc = co.value("acc")
        if !acc["id"].isNull { all.append(AccountingUser(id: "acc", name: acc["name"].string, role: "accountant", level: accountingLevel(companyID: companyID, user: "acc"))) }
        return (all.filter { $0.level > .none }, all.filter { $0.level == .none })
    }

    /// Add someone, or change their level, for THIS company. Owner only.
    @discardableResult
    mutating func setAccountingAccess(companyID: Int, userID: String, level: AccountingLevel, by user: String? = nil) -> AccessChange {
        guard canAccess(.settings, companyID: companyID, user: user) else { return .refused("Only the owner manages access.") }
        guard level != .owner else { return .refused("There is one owner.") }
        guard let roster = accountingRoster(companyID: companyID), (roster.granted + roster.candidates).contains(where: { $0.id == userID }) else {
            return .refused("That person is not part of this company.")
        }
        if accountingLevel(companyID: companyID, user: userID) == level { return .unchanged }
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            var acx = s.companies[i].value("acx")
            if acx.isNull { acx = .object([:]) }
            if level == .none { var o = acx.object; o.removeValue(forKey: userID); acx = .object(o) } else { acx[userID] = .number(Double(level.rawValue)) }
            if acx.object.isEmpty { s.companies[i].raw.removeValue(forKey: "acx") } else { s.companies[i].set("acx", acx) }
        }
        return .changed
    }

    @discardableResult
    mutating func removeAccountingAccess(companyID: Int, userID: String, by user: String? = nil) -> AccessChange {
        setAccountingAccess(companyID: companyID, userID: userID, level: .none, by: user)
    }
}
