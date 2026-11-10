import Foundation
import Observation
import StoreKit
import UIKit
import Simulation
import GameCore

struct PaywallRequest: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var feature: LockedFeature?
    var lead: String = ""
}

@MainActor @Observable
final class Entitlements {
    private(set) var snapshot: EntitlementSnapshot = .free
    var paywall: PaywallRequest?
    var plusEndedNotice = false

    enum DebugMode: String, CaseIterable { case off, free, pro, plus }
    private(set) var debugMode: DebugMode = .off

    @ObservationIgnored var onExpiry: (() async -> Void)?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var clockSeen: Date = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Keys.clock))
    @ObservationIgnored private var cache: StoredEntitlements?

    private enum Keys {
        static let pass = "ledger.proPassExpires"
        static let debug = "ledger.debugEntitlements"
        static let cache = "ledger.entitlementCache"
        static let clock = "ledger.clockSeen"
    }

    init() {
        #if DEBUG
        debugMode = DebugMode(rawValue: UserDefaults.standard.string(forKey: Keys.debug) ?? "") ?? .off
        #endif
        let t: Double = UserDefaults.standard.double(forKey: Keys.pass)
        if t > 0 { snapshot.passExpires = Date(timeIntervalSince1970: t) }
        noteClock()
        if let d = UserDefaults.standard.data(forKey: Keys.cache), let c = try? JSONDecoder().decode(StoredEntitlements.self, from: d) {
            cache = c
            let kept: EntitlementSnapshot = c.snapshot
            snapshot.owned = kept.owned
            snapshot.plusExpires = kept.plusExpires
            snapshot.plusGraceUntil = kept.plusGraceUntil
        }
    }

    private var now: Date { max(Date(), clockSeen) }

    private func noteClock() {
        clockSeen = now
        UserDefaults.standard.set(clockSeen.timeIntervalSince1970, forKey: Keys.clock)
    }

    var effective: EntitlementSnapshot {
        #if DEBUG
        switch debugMode {
        case .free: return .free
        case .pro: return EntitlementSnapshot(owned: [.pro])
        case .plus: return EntitlementSnapshot(owned: [.plusYearly], plusExpires: Date.distantFuture)
        case .off: break
        }
        #endif
        return snapshot
    }
    var isPro: Bool { effective.isPro(now: now) }
    var isPlus: Bool { effective.isPlus(now: now) }
    var isFounder: Bool { effective.isFounder() }
    var ownsPro: Bool { effective.ownsPro() }
    var hasPass: Bool { effective.hasPass(now: now) }
    var plusRenews: Date? {
        guard effective.isPlus(now: now), let end = effective.plusExpires, end > now else { return nil }
        return end
    }
    var hasStorePurchase: Bool { !snapshot.owned.isEmpty || snapshot.plusExpires != nil || snapshot.plusGraceUntil != nil }

    func isUnlocked(_ f: LockedFeature) -> Bool { effective.isUnlocked(f, now: now) }

    @discardableResult
    func require(_ f: LockedFeature, title: String? = nil) -> Bool {
        if isUnlocked(f) { return true }
        paywall = PaywallRequest(title: title ?? f.paywallTitle, feature: f)
        return false
    }

    func apply(_ fresh: EntitlementSnapshot, storeAnswered: Bool) {
        let out = EntitlementCache.resolve(fresh: fresh, cached: cache, storeAnswered: storeAnswered, now: Date())
        cache = out.stored
        if let c = out.stored, let d = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(d, forKey: Keys.cache)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.cache)
        }
        noteClock()
        var next: EntitlementSnapshot = out.snapshot
        next.passExpires = snapshot.passExpires
        if let pe = next.passExpires, pe <= now { next.passExpires = nil; UserDefaults.standard.removeObject(forKey: Keys.pass) }
        if out.plusEnded { plusEndedNotice = true }
        snapshot = next
        scheduleExpiryRefresh()
    }

    func manageSubscription() async {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }

    func grantPass(until end: Date) {
        snapshot.passExpires = end
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Keys.pass)
        scheduleExpiryRefresh()
    }

    #if DEBUG
    func setDebug(_ m: DebugMode) { debugMode = m; UserDefaults.standard.set(m.rawValue, forKey: Keys.debug) }
    #endif

    private func scheduleExpiryRefresh() {
        expiry?.cancel()
        let current: Date = now
        let next: Date? = [snapshot.passExpires, snapshot.plusExpires, snapshot.plusGraceUntil].compactMap { $0 }.filter { $0 > current }.min()
        guard let when = next else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min(max(1, when.timeIntervalSinceNow + 1), 86_400 * 30) * 1_000_000_000))
            if !Task.isCancelled { await self?.onExpiry?() }
        }
    }
}
