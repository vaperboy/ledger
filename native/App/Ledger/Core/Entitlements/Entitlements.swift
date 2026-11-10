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
    enum DebugMode: String, CaseIterable { case off, free, pro, plus }

    private(set) var snapshot: EntitlementSnapshot = .free
    private(set) var products: [LedgerProduct: Product] = [:]
    private(set) var trialEligible = false
    private(set) var isBusy = false
    var message: String?
    var paywall: PaywallRequest?
    var plusEndedNotice = false

    private(set) var debugMode: DebugMode = .off
    func setDebug(_ m: DebugMode) { debugMode = m; UserDefaults.standard.set(m.rawValue, forKey: Keys.debug) }

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var clockSeen: Date = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Keys.clock))
    @ObservationIgnored private var cache: StoredEntitlements?
    @ObservationIgnored private var storeAnswered = false

    private enum Keys {
        static let pass = "ledger.proPassExpires"
        static let debug = "ledger.debugEntitlements"
        static let cache = "ledger.entitlementCache"
        static let clock = "ledger.clockSeen"
    }
    private static let graceWindow: TimeInterval = 16 * 24 * 3600

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

    func price(_ p: LedgerProduct) -> String { products[p]?.displayPrice ?? "" }

    var yearlySaving: String {
        guard let m = products[.plusMonthly]?.price, let y = products[.plusYearly]?.price, m > 0 else { return "" }
        let saved: Double = (1 - NSDecimalNumber(decimal: y / (m * 12)).doubleValue) * 100
        return saved >= 1 ? "Save \(Int(saturating: saved.rounded()))%" : ""
    }

    func trialLength(_ p: LedgerProduct) -> String? {
        guard let offer = products[p]?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let n: Int = offer.period.value
        let unit: String
        switch offer.period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return n == 1 ? "1 \(unit)" : "\(n) \(unit)s"
    }

    func start() {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in StoreKit.Transaction.updates {
                    if case .verified(let t) = result { await t.finish() }
                    self?.storeAnswered = true
                    await self?.refresh()
                }
            }
        }
        Task { await loadProducts(); await refresh() }
    }

    func loadProducts() async {
        do {
            let list: [Product] = try await Product.products(for: LedgerProduct.allCases.map { $0.rawValue })
            var map: [LedgerProduct: Product] = [:]
            for p in list { if let k = LedgerProduct(rawValue: p.id) { map[k] = p } }
            products = map
            storeAnswered = true
            if let sub = map[.plusYearly]?.subscription { trialEligible = await sub.isEligibleForIntroOffer }
        } catch {
            message = "The store could not be reached."
        }
    }

    private func graceEnd() async -> Date? {
        guard let sub = (products[.plusYearly] ?? products[.plusMonthly])?.subscription, let statuses = try? await sub.status else { return nil }
        for st in statuses where st.state == .inGracePeriod || st.state == .inBillingRetryPeriod {
            if case .verified(let t) = st.transaction, t.revocationDate == nil, LedgerProduct(rawValue: t.productID)?.isPlus == true {
                return Date().addingTimeInterval(Self.graceWindow)
            }
        }
        return nil
    }

    func refresh() async {
        var owned: Set<LedgerProduct> = []
        var plusEnd: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil, let p = LedgerProduct(rawValue: t.productID) else { continue }
            owned.insert(p)
            if p.isPlus, let end = t.expirationDate { plusEnd = max(plusEnd ?? end, end) }
        }
        let fresh = EntitlementSnapshot(owned: owned, plusExpires: plusEnd, plusGraceUntil: await graceEnd())
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

    var offerCodesAvailable: Bool { !products.isEmpty }

    func purchase(_ p: LedgerProduct) async {
        guard !isBusy else { return }
        guard let product = products[p] else { message = "That product is not available right now."; return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result { await t.finish(); message = nil; storeAnswered = true } else { message = "The purchase could not be verified." }
            case .pending: message = "Waiting for approval."
            default: break
            }
            await refresh()
        } catch {
            message = "The purchase did not go through."
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            storeAnswered = true
            await refresh()
            message = hasStorePurchase ? "Purchases restored." : "Nothing to restore."
        } catch {
            message = "Restore did not work. Try again."
        }
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

    private func scheduleExpiryRefresh() {
        expiry?.cancel()
        let current: Date = now
        let next: Date? = [snapshot.passExpires, snapshot.plusExpires, snapshot.plusGraceUntil].compactMap { $0 }.filter { $0 > current }.min()
        guard let when = next else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min(max(1, when.timeIntervalSinceNow + 1), 86_400 * 30) * 1_000_000_000))
            if !Task.isCancelled { await self?.refresh() }
        }
    }
}
