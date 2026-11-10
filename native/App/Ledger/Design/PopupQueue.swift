import Foundation

enum PopupPriority: Int, Comparable, CaseIterable {
    case confirm = 0
    case decision = 1
    case alert = 2
    case notice = 3
    case report = 4
    case celebration = 5
    case panel = 6

    static func < (a: PopupPriority, b: PopupPriority) -> Bool { a.rawValue < b.rawValue }

    var isStack: Bool { self == .confirm || self == .panel }

    var isDialog: Bool { self == .confirm || self == .decision || self == .alert || self == .notice }
}

struct PopupQueue: Equatable {
    struct Item: Equatable {
        var key: String
        var priority: PopupPriority
        var seq: Int
    }

    private(set) var items: [Item] = []

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

    static func order(_ items: [Item]) -> [Item] {
        items.sorted { (a: Item, b: Item) -> Bool in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.priority.isStack ? a.seq > b.seq : a.seq < b.seq
        }
    }

    static func visible(_ items: [Item]) -> String? { order(items).first?.key }
}
