import Foundation
import Businesses

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
