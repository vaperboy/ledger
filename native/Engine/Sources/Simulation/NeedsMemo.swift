import Foundation
import Businesses

/// A small cache of the store's item lists, one per company. A class on purpose: the engine is a value that is copied around the app, and the
/// copies share the cache; an entry is only used when its key (day, cash, what the company owns) still matches.
final class NeedsMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: (key: String, list: [EquipmentMarket.Need])] = [:]

    func get(_ id: Int, _ key: String) -> [EquipmentMarket.Need]? {
        lock.lock(); defer { lock.unlock() }
        if let e = entries[id], e.key == key { return e.list }
        return nil
    }
    func set(_ id: Int, _ key: String, _ list: [EquipmentMarket.Need]) {
        lock.lock(); defer { lock.unlock() }
        entries[id] = (key, list)
    }
}
