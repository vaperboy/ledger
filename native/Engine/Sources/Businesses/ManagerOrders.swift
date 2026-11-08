import Foundation
import GameCore
import Countries

/// The few orders an owner gives a manager, and what the manager makes of them. The direction is the company's `dir` (shared with the owner's meetings);
/// the others are the manager's budget, the staffing plan, pay and bonus, and the post itself.
public extension ManagerModel {
    /// Where the owner wants the business to go. It sets how far a manager moves prices from the market price and how much of revenue they put into marketing.
    enum Direction: String, CaseIterable, Sendable {
        case grow = "growth", lean, quality, cash

        public var title: String { OwnerMeetings.directiveLabel(rawValue) }

        /// Price steps from the market price: grow lowers, quality and cash raise, lean holds.
        public var priceSteps: Int {
            switch self { case .grow: return -1; case .lean: return 0; case .quality, .cash: return 1 }
        }

        /// Share of a month's revenue the manager may spend on marketing.
        public var marketingShare: Double {
            switch self { case .grow: return 0.12; case .lean: return 0.04; case .quality: return 0.06; case .cash: return 0.03 }
        }

        /// The marketing share of a company the owner has given no direction.
        public static let steadyMarketingShare = 0.05

        /// Why a manager moved a price, for their report ("... one step to draw more customers").
        var priceReason: String {
            switch self {
            case .grow: return "to draw more customers, as you asked"
            case .lean: return "to get back to the market price"
            case .quality: return "to match the quality you asked for"
            case .cash: return "to keep more cash coming in, as you asked"
            }
        }

        /// What the order means in practice.
        public var text: String { Direction.describe(steps: priceSteps, share: marketingShare) }

        static func describe(steps: Int, share: Double) -> String {
            let price = steps == 0 ? "at the market price" : steps < 0 ? "one step under the market price" : "one step over the market price"
            return "Prices \(price); marketing up to \(Int(jsRound(share * 100)))% of revenue."
        }
    }

    /// The direction the owner gave a company, nil when none.
    static func direction(of co: Company) -> Direction? { OwnerMeetings.directive(co).flatMap { Direction(rawValue: $0) } }

    /// Give the company's manager a direction (nil clears it).
    static func setDirection(_ s: inout GameState, companyID: Int, direction: Direction?) {
        guard let ci = s.companyIndex(companyID) else { return }
        s.companies[ci].set("dir", direction?.rawValue ?? "")
    }

    /// One of the owner's orders with what is set now.
    struct Order: Equatable, Identifiable, Sendable {
        public enum Key: String, CaseIterable, Sendable { case direction, budget, headcount, pay, replace }
        public var key: Key
        public var title: String
        /// What is set now, in a few words.
        public var value: String
        /// What it means for the manager's work.
        public var detail: String
        public var id: String { key.rawValue }
    }

    /// The five orders for a company that has a manager (none otherwise): Direction, Budget, Headcount, Pay and bonus, Replace.
    static func orders(_ s: GameState, companyID: Int, data: GameData) -> [Order] {
        guard let co = s.company(companyID), let mid = co.managerID, let n = s.people[mid] else { return [] }
        let cur = World(state: s, data: data).currency(co)
        var out: [Order] = []
        let dir = direction(of: co)
        out.append(Order(key: .direction, title: "Direction", value: dir?.title ?? "Steady",
                         detail: dir?.text ?? Direction.describe(steps: 0, share: Direction.steadyMarketingShare)))
        let b = budget(of: co)
        let revenue = recentMonthlyRevenue(co)
        out.append(Order(key: .budget, title: "Budget", value: b.title,
                         detail: "\(firstName(n.name)) \(b.text)." + (b == .normal ? " Up to \(cur.short(b.spendLimit(cur, monthlyRevenue: revenue))) for one purchase." : "")))
        let rows = StaffingPlan.plan(s, companyID: companyID, data: data).filter { !$0.seasonal && $0.role != StaffingPlan.managerRole }
        let target = rows.reduce(0) { $0 + $1.target }, filled = rows.reduce(0) { $0 + min($1.filled, $1.target) }, open = rows.reduce(0) { $0 + $1.vacancies }
        out.append(Order(key: .headcount, title: "Headcount", value: rows.isEmpty ? "None" : "\(filled) of \(target)",
                         detail: open > 0 ? "\(open) \(open == 1 ? "post is" : "posts are") open and \(firstName(n.name)) is hiring. Targets are set role by role." : "Every post is filled. Targets are set role by role."))
        let bonus = co.managerProfitBonus > 0 ? " and \(Int(jsRound(co.managerProfitBonus * 100)))% of profit" : ""
        let raise = b.payLimit(cur, monthlyRevenue: revenue)
        out.append(Order(key: .pay, title: "Pay and bonus", value: "\(cur.display(co.managerMonthlyWage)) a month\(bonus)",
                         detail: b == .tight ? "Every raise comes to you." : b == .free ? "\(firstName(n.name)) settles pay on their own." : "Raises up to \(cur.short(raise)) a month are settled without asking."))
        let weeks = max(0, s.week - (co.value("mgrW0").isNull ? 0 : co.int("mgrW0")))
        out.append(Order(key: .replace, title: "Replace", value: "\(n.name), \(weeks >= 52 ? "\(weeks / 52) yr" : "\(weeks) wk") in the post",
                         detail: "Let them go with three months of pay and search for a successor."))
        return out
    }
}
