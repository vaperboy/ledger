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

/// Results of heavy screen reads, kept for as long as the game state has not changed. `GameEngine.state` takes a fresh stamp (a number no other
/// state value ever had) on every change, so an entry for an older stamp is never returned: a result can never be stale after an action or a day.
/// A class on purpose, like `NeedsMemo`: copies of the engine share it, and the stamp tells them apart once they differ.
final class ReadMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var stamp: UInt64 = 0
    private var entries: [String: Any] = [:]

    private static let counter = NSLock()
    nonisolated(unsafe) private static var last: UInt64 = 0
    static func nextStamp() -> UInt64 { counter.lock(); defer { counter.unlock() }; last += 1; return last }

    func value<T>(_ stamp: UInt64, _ key: String, _ make: () -> T) -> T {
        lock.lock()
        if self.stamp == stamp, let hit = entries[key] as? T { lock.unlock(); return hit }
        lock.unlock()
        let made = make()
        lock.lock(); defer { lock.unlock() }
        if self.stamp != stamp { self.stamp = stamp; entries = [:] }
        entries[key] = made
        return made
    }
}
