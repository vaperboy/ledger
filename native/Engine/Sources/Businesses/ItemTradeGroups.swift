import Foundation

/// Which trades use real per-item records (`ItemModels`), one registry per trade group, each in its own file
/// (`ItemTradeGroups+Brokered.swift` ... `ItemTradeGroups+Finance.swift`) so groups never edit the same lines. A trade appears in exactly one group.
public enum ItemTradeGroups {
    public static var all: Set<String> {
        brokered.union(retail).union(food).union(industrial).union(professional).union(appointments).union(jobs).union(rentals).union(venues).union(transport).union(finance)
    }
}
