import Foundation

public struct ManagementPolicy: Equatable, Sendable {
    public let reserveWeeks = 2.0
    public let autoRehire = true
    public let autoComplaints = true
    public let autoDividendWeeks = 0.0

    public init() {}
}

public extension GameState {
    var policy: ManagementPolicy { ManagementPolicy() }
}
