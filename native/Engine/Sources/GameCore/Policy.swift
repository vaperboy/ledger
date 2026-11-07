import Foundation

/// How much the player wants the game to decide for them. Stored in the save (`policy`), read by the weekly simulation.
/// Defaults suit a player who wants to run the empire, not the paperwork: routine payroll is approved automatically when the
/// company can pay it, and campaigns are paid in advance, so they pause instead of running the company into debt.
public struct ManagementPolicy: Equatable, Sendable {
    /// Approve the monthly payroll by itself when the company has the money. Otherwise the owner is asked.
    public var autoPayroll = true
    /// Weeks of running costs a company keeps in cash before it pays for marketing.
    public var reserveWeeks = 2.0
    /// Replace people who leave: recruit through the company's network at the going rate when there is cash for it.
    public var autoRehire = true
    /// Let staff answer routine complaints (minor and moderate ones) with an apology or a small refund. Serious ones still come to you.
    public var autoComplaints = true
    /// Pay dividends by itself when a limited company holds more than this many weeks of costs beyond the reserve (0 = never).
    public var autoDividendWeeks = 0.0

    public init() {}
    public init(_ v: JSONValue) {
        if !v["autoPayroll"].isNull { autoPayroll = v["autoPayroll"].bool }
        if !v["autoRehire"].isNull { autoRehire = v["autoRehire"].bool }
        if !v["autoComplaints"].isNull { autoComplaints = v["autoComplaints"].bool }
        if !v["reserveWeeks"].isNull { reserveWeeks = max(0, v["reserveWeeks"].double) }
        if !v["autoDividendWeeks"].isNull { autoDividendWeeks = max(0, v["autoDividendWeeks"].double) }
    }
    public var json: JSONValue { .object(["autoPayroll": .bool(autoPayroll), "autoRehire": .bool(autoRehire), "autoComplaints": .bool(autoComplaints), "reserveWeeks": .number(reserveWeeks), "autoDividendWeeks": .number(autoDividendWeeks)]) }
}

public extension GameState {
    var policy: ManagementPolicy {
        get { ManagementPolicy(rest["policy"] ?? .null) }
        set { rest["policy"] = newValue.json }
    }
}
