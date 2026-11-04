import Foundation

/// How urgent a popup is. The lower the raw value, the earlier it is shown. Only one popup is visible at a time.
/// Confirmations and decisions first, then red alerts, notices, reports and the daily report, rewards, and last the panels
/// the player opened himself (worker profile, pickers, forms), so a result or a question raised from a panel shows above it.
enum PopupPriority: Int, Comparable, CaseIterable {
    case confirm = 0
    case decision = 1
    case alert = 2
    case notice = 3
    case report = 4
    case celebration = 5
    case panel = 6

    static func < (a: PopupPriority, b: PopupPriority) -> Bool { a.rawValue < b.rawValue }

    /// A stack (newest on top): what the player opened or asked himself. The others are queues (oldest first, one after another).
    var isStack: Bool { self == .confirm || self == .panel }
}

/// The pure ordering logic of the popup host: which registered popup is the visible one and in which order the others wait.
struct PopupQueue: Equatable {
    struct Item: Equatable {
        var key: String
        var priority: PopupPriority
        /// Registration order, global and increasing.
        var seq: Int
    }

    private(set) var items: [Item] = []

    /// Adds a popup, or changes the priority of one already there (it keeps its place in the order of arrival).
    mutating func upsert(key: String, priority: PopupPriority, seq: Int) {
        if let i = items.firstIndex(where: { (x: Item) -> Bool in x.key == key }) {
            items[i].priority = priority
        } else {
            items.append(Item(key: key, priority: priority, seq: seq))
        }
    }

    mutating func remove(key: String) {
        items.removeAll { (x: Item) -> Bool in x.key == key }
    }

    var ordered: [Item] { PopupQueue.order(items) }
    var visibleKey: String? { PopupQueue.visible(items) }

    /// The order in which popups are shown: by priority; inside a priority a stack shows the newest first, a queue the oldest first.
    static func order(_ items: [Item]) -> [Item] {
        items.sorted { (a: Item, b: Item) -> Bool in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.priority.isStack ? a.seq > b.seq : a.seq < b.seq
        }
    }

    static func visible(_ items: [Item]) -> String? { order(items).first?.key }
}
