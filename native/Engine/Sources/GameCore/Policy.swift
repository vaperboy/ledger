import Foundation

/// Standing rules the game applies for the owner. They are fixed (a manager replaces people who leave, staff answer routine complaints, campaigns keep a two-week cash reserve,
/// dividends are never automatic) and `Delegation` is where the rules live. This type only keeps the old names readable.
public struct ManagementPolicy: Equatable, Sendable {
    public let reserveWeeks = 2.0
    public let autoRehire = true
    public let autoComplaints = true
    public let autoDividendWeeks = 0.0

    public init() {}
}

public extension GameState {
    /// The fixed rules; a stored `policy` in an older save is ignored.
    var policy: ManagementPolicy { ManagementPolicy() }
}
