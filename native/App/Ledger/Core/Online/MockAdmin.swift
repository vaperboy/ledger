import Foundation

struct MockAdminBook {
    var rules: [WorldRule] = MockAdminBook.defaults
    var confirmations: [PendingConfirmation] = MockAdminBook.sampleConfirmations()
    var audit: [AuditEntry] = []
    private var nextAudit = 1

    private static func rule(_ key: String, _ group: RuleGroup, _ label: String, _ unit: RuleUnit, _ value: Double, _ low: Double, _ high: Double) -> WorldRule {
        WorldRule(key: key, group: group, label: label, unit: unit, value: value, defaultValue: value, minimum: low, maximum: high)
    }

    static let defaults: [WorldRule] = [
        rule("print.single_limit", .printing, "Largest single printing", .share, 0.05, 0.01, 0.10),
        rule("print.window_limit", .printing, "Printing allowed in one window", .share, 0.15, 0.03, 0.30),
        rule("print.window_weeks", .printing, "Weeks in the printing window", .weeks, 12, 4, 26),
        rule("tax.transfer_max", .taxes, "Highest transfer tax", .share, 0.05, 0.01, 0.10),
        rule("tax.gains_min", .taxes, "Lowest gains tax", .share, 0.05, 0, 0.15),
        rule("tax.gains_max", .taxes, "Highest gains tax", .share, 0.40, 0.20, 0.60),
        rule("tax.step", .taxes, "Largest move of a rate at a time", .share, 0.01, 0.005, 0.03),
        rule("tax.gap_weeks", .taxes, "Weeks between rate changes", .weeks, 7, 1, 26),
        rule("band.exchange_low", .bands, "Exchange price, lowest vs value", .factor, 0.75, 0.50, 0.95),
        rule("band.exchange_high", .bands, "Exchange price, highest vs value", .factor, 1.25, 1.05, 2.00),
        rule("band.startup_low", .bands, "Startup resale, lowest vs value", .factor, 0.80, 0.50, 0.95),
        rule("band.startup_high", .bands, "Startup resale, highest vs value", .factor, 1.25, 1.05, 2.00),
        rule("band.venture_low", .bands, "Venture stake, lowest vs fair", .factor, 0.70, 0.40, 0.95),
        rule("band.venture_high", .bands, "Venture stake, highest vs fair", .factor, 1.50, 1.05, 2.50),
        rule("power.band_low", .electricity, "Electricity price index, floor", .factor, 0.60, 0.30, 0.90),
        rule("power.band_high", .electricity, "Electricity price index, ceiling", .factor, 1.80, 1.20, 3.00),
        rule("support.percent_max", .funding, "Largest support share of sales", .share, 0.10, 0.02, 0.20),
        rule("support.weeks_max", .funding, "Longest support run", .weeks, 8, 1, 16),
        rule("support.budget_share", .funding, "Weekly budget, share of treasury", .share, 0.05, 0.01, 0.10),
        rule("support.max_open", .funding, "Supports open at once", .count, 2, 1, 5),
        rule("support.account_share", .funding, "One account, share of a budget", .share, 0.25, 0.05, 0.50),
    ]

    private static func sampleConfirmations() -> [PendingConfirmation] {
        [PendingConfirmation(id: "c1", kind: .policy, country: "NO", proposer: "Mara Voss", summary: "Transfer tax 3.0%, gains tax 21.0%", at: Date().addingTimeInterval(-3600 * 20)),
         PendingConfirmation(id: "c2", kind: .electionResult, country: "FR", proposer: "Lukas Brandt", summary: "Election result: Lukas Brandt wins the presidency of FR", at: Date().addingTimeInterval(-3600 * 6))]
    }

    private func value(_ key: String) -> Double { rules.first { $0.key == key }?.value ?? 0 }

    mutating func setRule(key: String, value v: Double, reason: String) throws {
        let why: String = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard why.count >= 3 else { throw OnlineError.rejected("Give a reason of at least three characters.") }
        guard let i = rules.firstIndex(where: { $0.key == key }) else { throw OnlineError.rejected("That rule does not exist.") }
        let r: WorldRule = rules[i]
        guard v >= r.minimum - 1e-9, v <= r.maximum + 1e-9 else { throw OnlineError.rejected("That value is outside the fixed limits of this rule.") }
        guard abs(v - r.value) > 1e-9 else { return }
        rules[i].value = v
        let ok: Bool = value("print.single_limit") <= value("print.window_limit") && value("tax.gains_min") < value("tax.gains_max")
            && value("band.exchange_low") < 1 && value("band.exchange_high") > 1 && value("band.startup_low") < 1 && value("band.startup_high") > 1
            && value("band.venture_low") < 1 && value("band.venture_high") > 1 && value("power.band_low") < 1 && value("power.band_high") > 1
        if !ok { rules[i].value = r.value; throw OnlineError.rejected("That would make two rules contradict each other.") }
        log("rule_change", key, r.value, v, why)
    }

    mutating func decide(id: String, approve: Bool, reason: String) throws {
        let why: String = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = confirmations.firstIndex(where: { $0.id == id }) else { throw OnlineError.notFound }
        if !approve && why.count < 3 { throw OnlineError.rejected("Give a reason of at least three characters.") }
        let c: PendingConfirmation = confirmations.remove(at: i)
        log(approve ? "confirm" : "reject", c.kind.rawValue + ":" + c.country, nil, nil, why, summary: c.summary)
    }

    private mutating func log(_ action: String, _ target: String, _ before: Double?, _ after: Double?, _ reason: String, summary: String? = nil) {
        let r: WorldRule? = rules.first { $0.key == target }
        let b: String? = before.flatMap { v in r?.text(v) } ?? summary
        let a: String? = after.flatMap { v in r?.text(v) } ?? (summary == nil ? nil : action == "confirm" ? "confirmed" : "rejected")
        audit.insert(AuditEntry(id: nextAudit, at: Date(), actor: "Preview administrator", action: action, target: target, before: b, after: a, reason: reason), at: 0)
        nextAudit += 1
    }
}
