import Foundation

/// The time the pass, streaks and daily limits read. After the server has answered once it runs on the server's time
/// plus the phone's uptime, so changing the phone's date does nothing; before that it uses the phone's clock but never
/// goes back past the last server time the app remembered.
public enum TrustedClock {
    private struct Anchor { var server: Double; var uptime: TimeInterval }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var anchor: Anchor?
    nonisolated(unsafe) private static var floor: Double = 0

    /// Records a server time (seconds since 1970) read just now.
    public static func sync(serverTime: Double, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard serverTime.isFinite, serverTime > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        anchor = Anchor(server: serverTime, uptime: uptime)
        floor = max(floor, serverTime)
    }

    /// The last server time seen in an earlier run, so a phone date set back before the first sync is ignored.
    public static func remember(lastServerTime: Double) {
        guard lastServerTime.isFinite, lastServerTime > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        floor = max(floor, lastServerTime)
    }

    public static var isSynced: Bool {
        lock.lock(); defer { lock.unlock() }
        return anchor != nil
    }

    public static func now(local: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Date {
        lock.lock(); defer { lock.unlock() }
        if let a = anchor { return Date(timeIntervalSince1970: a.server + max(0, uptime - a.uptime)) }
        return Date(timeIntervalSince1970: max(local.timeIntervalSince1970, floor))
    }

    /// Today as an era day (the count the pass and streak use) on the trusted time.
    public static func today(local: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: now(local: local, uptime: uptime)) ?? 0
    }

    /// Forgets every sync; for tests.
    public static func reset() {
        lock.lock(); defer { lock.unlock() }
        anchor = nil
        floor = 0
    }
}
