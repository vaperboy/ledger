import Foundation
import Observation
import StoreKit
import UIKit
import Simulation

/// A paywall asked for by a locked item. `title` is the item that triggered it ("Open a bakery in Lithuania").
struct PaywallRequest: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var feature: LockedFeature?
    /// The one-off sheet after the first profitable month: shows the line above the paywall.
    var lead: String = ""
}

/// What the player owns. Every gate reads only this object. The rules live in the engine (`EntitlementSnapshot`,
/// `Monetisation.swift`); this class feeds them from StoreKit 2 and keeps the one-day ad pass.
@MainActor @Observable
final class Entitlements {
    /// Debug builds only: force the plan for testing. Ignored in release builds.
    enum DebugMode: String, CaseIterable { case off, free, pro, plus }

    private(set) var snapshot: EntitlementSnapshot = .free
    private(set) var products: [LedgerProduct: Product] = [:]
    private(set) var trialEligible = false
    private(set) var isBusy = false
    /// One short line for the paywall or Settings after a purchase or restore.
    var message: String?
    /// Set by a locked item; the app root shows it as a centred popup.
    var paywall: PaywallRequest?
    /// True for one session after a Plus subscription lapsed (Home shows `Plus has ended. Your saves are safe.` once).
    var plusEndedNotice = false

    private(set) var debugMode: DebugMode = .off
    func setDebug(_ m: DebugMode) { debugMode = m; UserDefaults.standard.set(m.rawValue, forKey: Keys.debug) }

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var hadPlus = false

    private enum Keys {
        static let pass = "ledger.proPassExpires"
        static let debug = "ledger.debugEntitlements"
        static let hadPlus = "ledger.hadPlus"
        static let gift = "ledger.giftExpires"
        static let giftSerials = "ledger.giftSerials"
    }

    init() {
        #if DEBUG
        debugMode = DebugMode(rawValue: UserDefaults.standard.string(forKey: Keys.debug) ?? "") ?? .off
        #endif
        let t: Double = UserDefaults.standard.double(forKey: Keys.pass)
        if t > 0 { snapshot.passExpires = Date(timeIntervalSince1970: t) }
        let g: Double = UserDefaults.standard.double(forKey: Keys.gift)
        if g > 0 { snapshot.giftExpires = Date(timeIntervalSince1970: g) }
        hadPlus = UserDefaults.standard.bool(forKey: Keys.hadPlus)
    }

    // MARK: Reads (the only thing gates use)

    /// The plan after any debug override.
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
    var isPro: Bool { effective.isPro(now: Date()) }
    var isPlus: Bool { effective.isPlus(now: Date()) }
    var isFounder: Bool { effective.isFounder() }
    var ownsPro: Bool { effective.ownsPro() }
    var hasPass: Bool { effective.hasPass(now: Date()) }
    var plusRenews: Date? { effective.isPlus(now: Date()) ? effective.plusExpires : nil }

    func isUnlocked(_ f: LockedFeature) -> Bool { effective.isUnlocked(f, now: Date()) }

    /// True when the feature is open. Otherwise opens the paywall for `title` and returns false.
    @discardableResult
    func require(_ f: LockedFeature, title: String? = nil) -> Bool {
        if isUnlocked(f) { return true }
        paywall = PaywallRequest(title: title ?? f.paywallTitle, feature: f)
        return false
    }

    /// Prices are never written in strings: always the store's own `displayPrice`.
    func price(_ p: LedgerProduct) -> String { products[p]?.displayPrice ?? "" }

    /// "Save 48%": read from the two Plus prices, never typed.
    var yearlySaving: String {
        guard let m = products[.plusMonthly]?.price, let y = products[.plusYearly]?.price, m > 0 else { return "" }
        let saved: Double = (1 - NSDecimalNumber(decimal: y / (m * 12)).doubleValue) * 100
        return saved >= 1 ? "Save \(Int(saved.rounded()))%" : ""
    }

    // MARK: Store

    /// Call once at launch: watches transactions, loads products, reads what is owned.
    func start() {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in StoreKit.Transaction.updates {
                    if case .verified(let t) = result { await t.finish() }
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
            if let sub = map[.plusYearly]?.subscription { trialEligible = await sub.isEligibleForIntroOffer }
        } catch {
            message = "The store could not be reached."
        }
    }

    /// `StoreKit.StoreKit.Transaction.currentEntitlements`: on launch and on foreground.
    func refresh() async {
        var owned: Set<LedgerProduct> = []
        var plusEnd: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil, let p = LedgerProduct(rawValue: t.productID) else { continue }
            owned.insert(p)
            if p.isPlus, let end = t.expirationDate { plusEnd = max(plusEnd ?? end, end) }
        }
        var next = EntitlementSnapshot(owned: owned, plusExpires: plusEnd, passExpires: snapshot.passExpires, giftExpires: snapshot.giftExpires)
        if let pe = next.passExpires, pe <= Date() { next.passExpires = nil; UserDefaults.standard.removeObject(forKey: Keys.pass) }
        if plusEnd != nil { hadPlus = true; UserDefaults.standard.set(true, forKey: Keys.hadPlus) }
        else if hadPlus { plusEndedNotice = true; hadPlus = false; UserDefaults.standard.set(false, forKey: Keys.hadPlus) }
        snapshot = next
        scheduleExpiryRefresh()
    }

    /// Redeems a gift code on this device: it opens the full game for the code's period, added to any time still left.
    /// Each code works once per device. Returns the line to show.
    @discardableResult
    func redeem(_ text: String) -> String {
        guard let gift = GiftCodes.check(text) else { return "That code is not valid. Check it and try again." }
        var used: [Int] = UserDefaults.standard.array(forKey: Keys.giftSerials) as? [Int] ?? []
        if used.contains(gift.serial) { return "That code has already been used on this device." }
        let start: Date = max(Date(), snapshot.giftExpires ?? Date())
        let end: Date = start.addingTimeInterval(Double(gift.days) * AdPolicy.passDuration)
        used.append(gift.serial)
        UserDefaults.standard.set(used, forKey: Keys.giftSerials)
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Keys.gift)
        snapshot.giftExpires = end
        scheduleExpiryRefresh()
        let f: DateFormatter = DateFormatter(); f.dateStyle = .medium
        return "Unlocked until \(f.string(from: end))."
    }

    func purchase(_ p: LedgerProduct) async {
        guard let product = products[p] else { message = "That product is not available right now."; return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result { await t.finish(); message = nil } else { message = "The purchase could not be verified." }
            case .pending: message = "Waiting for approval."
            default: break
            }
            await refresh()
        } catch {
            message = "The purchase did not go through."
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do { try await AppStore.sync(); await refresh(); message = isPro ? "Purchases restored." : "Nothing to restore." }
        catch { message = "Restore did not work. Try again." }
    }

    func manageSubscription() async {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }

    /// The 24-hour Pro pass from a rewarded ad. The ad rules (once per 7 days) are checked by `AdCoordinator`.
    func grantPass(until end: Date) {
        snapshot.passExpires = end
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Keys.pass)
        scheduleExpiryRefresh()
    }

    /// When the pass or a Plus period ends, look again so the locks come back without a restart.
    private func scheduleExpiryRefresh() {
        expiry?.cancel()
        let next: Date? = [snapshot.passExpires, snapshot.plusExpires, snapshot.giftExpires].compactMap { $0 }.filter { $0 > Date() }.min()
        guard let when = next else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, when.timeIntervalSinceNow + 1) * 1_000_000_000))
            if !Task.isCancelled { await self?.refresh() }
        }
    }
}
