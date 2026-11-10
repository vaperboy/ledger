import Foundation

public enum ItemTradeGroups {
    public static var all: Set<String> {
        brokered.union(retail).union(food).union(industrial).union(professional).union(appointments).union(jobs).union(rentals).union(venues).union(transport).union(finance)
    }
}
