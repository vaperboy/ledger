import Foundation
import Observation
import StoreKit
import Simulation

struct PurchaseNotice: Identifiable, Equatable {
    enum Kind: Equatable { case success, info, failure }
    let id = UUID()
    var kind: Kind
    var title: String
    var lines: [String]
    var retry: PurchaseItem? = nil
}

@MainActor @Observable
final class PurchaseManager {
    private(set) var products: [String: Product] = [:]
    private(set) var catalogLoaded = false
    private(set) var catalogError: String?
    private(set) var trialEligible = false
    private(set) var inFlight: PurchaseItem?
    private(set) var restoring = false
    var confirmation: PendingAction?
    var notice: PurchaseNotice?

    @ObservationIgnored private let entitlements: Entitlements
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var storeAnswered = false
    @ObservationIgnored private var perkGold = 0
    /// Plan transactions already sent to the server this run, so a refresh does not send them again.
    @ObservationIgnored private var reportedPlans: Set<String> = []
    private static let graceWindow: TimeInterval = 16 * 24 * 3600

    init(entitlements: Entitlements) {
        self.entitlements = entitlements
        entitlements.onExpiry = { [weak self] in await self?.refreshEntitlements() }
    }

    var isBusy: Bool { inFlight != nil || restoring }
    var offerCodesAvailable: Bool { !products.isEmpty }

    func price(_ item: PurchaseItem) -> String? { products[PurchaseCatalog.productID(item)]?.displayPrice }

    func isAvailable(_ item: PurchaseItem) -> Bool { products[PurchaseCatalog.productID(item)] != nil }

    var yearlySaving: String {
        guard let m = products[LedgerProduct.plusMonthly.rawValue]?.price, let y = products[LedgerProduct.plusYearly.rawValue]?.price, m > 0 else { return "" }
        let saved: Double = (1 - NSDecimalNumber(decimal: y / (m * 12)).doubleValue) * 100
        return saved >= 1 ? "Save \(Int(saturating: saved.rounded()))%" : ""
    }

    func trialLength(_ p: LedgerProduct) -> String? {
        guard let offer = products[p.rawValue]?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
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
                for await result in StoreKit.Transaction.updates { await self?.handle(result, interactive: false) }
            }
        }
        Task {
            await loadProducts()
            await drainUnfinished()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            let list: [Product] = try await Product.products(for: PurchaseCatalog.allProductIDs)
            var map: [String: Product] = [:]
            for p in list { map[p.id] = p }
            products = map
            storeAnswered = true
            catalogLoaded = true
            catalogError = list.isEmpty ? "Purchases are not available in this build." : nil
            if let sub = map[LedgerProduct.plusYearly.rawValue]?.subscription { trialEligible = await sub.isEligibleForIntroOffer }
        } catch {
            catalogLoaded = true
            catalogError = "The store could not be reached."
        }
    }

    func request(_ item: PurchaseItem) {
        guard !isBusy else { return }
        guard let product = products[PurchaseCatalog.productID(item)] else {
            notice = PurchaseNotice(kind: .failure, title: "Not available", lines: [catalogError ?? "This is not available right now. Try again later."])
            return
        }
        // Gold and the pass are delivered to the account on the server, so they are only sold while it answers.
        if PurchaseCatalog.isConsumable(item), StoreSession.shared.isServerBacked, !StoreSession.shared.canSpend {
            notice = PurchaseNotice(kind: .info, title: "Connect first", lines: ["Gold and the Battle Pass are kept on your account. Connect to the internet, then try again."])
            Task { await StoreSession.shared.load() }
            return
        }
        confirmation = PendingAction(title: Self.confirmTitle(item), message: Self.confirmMessage(item, product: product), button: "Buy for \(product.displayPrice)",
                                     alwaysAsk: true, tone: .investment, icon: Self.icon(item)) { [weak self] in
            guard let self else { return }
            Task { await self.buy(item) }
        }
    }

    func buy(_ item: PurchaseItem) async {
        guard !isBusy else { return }
        guard let product = products[PurchaseCatalog.productID(item)] else {
            notice = PurchaseNotice(kind: .failure, title: "Not available", lines: ["This is not available right now. Try again later."])
            return
        }
        inFlight = item
        defer { inFlight = nil }
        // Ties the purchase to the signed-in account, so the server delivers it to no other.
        var options: Set<Product.PurchaseOption> = []
        if let token = await StoreSession.shared.accountToken() { options.insert(.appAccountToken(token)) }
        do {
            switch try await product.purchase(options: options) {
            case .success(let verification):
                await handle(verification, interactive: true)
            case .pending:
                notice = PurchaseNotice(kind: .info, title: "Waiting for approval",
                                        lines: ["The purchase is waiting for approval. It is added the moment it is approved, nothing is lost."])
            case .userCancelled:
                break
            @unknown default:
                notice = Self.failure("The purchase did not go through. Try again.", retry: item)
            }
        } catch StoreKitError.userCancelled {
        } catch {
            notice = Self.failure(Self.describe(error), retry: item)
        }
    }

    func restore() async {
        guard !isBusy else { return }
        restoring = true
        defer { restoring = false }
        do {
            try await AppStore.sync()
            storeAnswered = true
            await drainUnfinished()
            await refreshEntitlements()
            if entitlements.hasStorePurchase {
                notice = PurchaseNotice(kind: .success, title: "Purchases restored", lines: ["Your Ledger purchases are active again on this device."])
            } else {
                notice = PurchaseNotice(kind: .info, title: "Nothing to restore",
                                        lines: ["No earlier purchases were found for this Apple ID.", "Gold packs are used up when bought and cannot be restored."])
            }
        } catch StoreKitError.userCancelled {
        } catch {
            notice = Self.failure("Restore did not work. Try again.")
        }
    }

    func codeRedeemed() async {
        await drainUnfinished()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned: Set<LedgerProduct> = []
        var receipts: [LedgerProduct: PurchaseReceipt] = [:]
        var plusEnd: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil, let p = LedgerProduct(rawValue: t.productID) else { continue }
            owned.insert(p)
            receipts[p] = PurchaseReceipt(transactionID: String(t.id), originalID: String(t.originalID), jws: result.jwsRepresentation)
            if p.isPlus, let end = t.expirationDate { plusEnd = max(plusEnd ?? end, end) }
        }
        let fresh = EntitlementSnapshot(owned: owned, plusExpires: plusEnd, plusGraceUntil: await graceEnd())
        entitlements.apply(fresh, storeAnswered: storeAnswered)
        await grantPerks(owned, receipts: receipts)
    }

    private func grantPerks(_ owned: Set<LedgerProduct>, receipts: [LedgerProduct: PurchaseReceipt]) async {
        var gold: Int = 0
        let season: Int = SeasonModel.shared.pass.seasonNumber
        for p in owned {
            PlanPerks.cosmetics(for: p).forEach { SeasonModel.shared.grantOwned($0) }
            if StoreSession.shared.isServerBacked {
                // The server pays Pro and Founder gold once per account and keeps Plus for the premium pass.
                guard let receipt = receipts[p], reportedPlans.insert(receipt.originalID).inserted else { continue }
                guard let r = await StoreSession.shared.deliver(.plan(p), receipt: receipt) else { reportedPlans.remove(receipt.originalID); continue }
                if r.delivered { gold += r.gold }
                if r.passTiers > 0 { SeasonModel.shared.unlockTiers(r.passTiers) }
                continue
            }
            guard let perk = PlanPerk.perk(for: p) else { continue }
            let key: String = perk.claimID(season: season)
            let perkReceipt = PurchaseReceipt(transactionID: key, originalID: key, jws: "")
            if let r = await StoreSession.shared.deliver(.perk(perk), receipt: perkReceipt), r.delivered { gold += r.gold }
            if perk == .founder, PlanPerks.founderPassOpen(season: season) {
                let pass: PlanPerk = .founderPass
                let passKey: String = pass.claimID(season: season)
                if let r = await StoreSession.shared.deliver(.perk(pass), receipt: PurchaseReceipt(transactionID: passKey, originalID: passKey, jws: "")), r.delivered {
                    SeasonModel.shared.unlockTiers(GoldPrices.founderPassTiers)
                }
            }
        }
        if gold > 0 {
            perkGold += gold
            notice = PurchaseNotice(kind: .success, title: "Gold added", lines: [StoreText.gold(gold) + " added to your wallet."])
        }
    }

    private func takePerkGold() -> Int {
        defer { perkGold = 0 }
        return perkGold
    }

    private func drainUnfinished() async {
        for await result in StoreKit.Transaction.unfinished { await handle(result, interactive: false) }
    }

    private func graceEnd() async -> Date? {
        guard let sub = (products[LedgerProduct.plusYearly.rawValue] ?? products[LedgerProduct.plusMonthly.rawValue])?.subscription, let statuses = try? await sub.status else { return nil }
        for st in statuses where st.state == .inGracePeriod || st.state == .inBillingRetryPeriod {
            if case .verified(let t) = st.transaction, t.revocationDate == nil, LedgerProduct(rawValue: t.productID)?.isPlus == true {
                return Date().addingTimeInterval(Self.graceWindow)
            }
        }
        return nil
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>, interactive: Bool) async {
        guard case .verified(let transaction) = result else {
            if interactive {
                notice = Self.failure("The App Store could not verify this purchase, so nothing was added. If you were charged, use Restore purchases or contact Apple support.")
            }
            return
        }
        guard let item = PurchaseCatalog.item(forProductID: transaction.productID) else { return }
        storeAnswered = true
        let transactionID: String = String(transaction.id)
        let signed = PurchaseReceipt(transactionID: transactionID, originalID: String(transaction.originalID), jws: result.jwsRepresentation)
        switch item {
        case .plan:
            // A refunded Pro or Founder takes its gold back on the server; the entitlement itself goes with StoreKit.
            if transaction.revocationDate != nil, StoreSession.shared.isServerBacked { await StoreSession.shared.revoke(signed) }
            await transaction.finish()
            await refreshEntitlements()
            let granted: Int = takePerkGold()
            if interactive && transaction.revocationDate == nil { notice = receipt(item, transactionID: transactionID, gold: granted) }
        case .perk:
            return
        case .goldPack, .seasonBundle, .seasonLevels:
            if transaction.revocationDate != nil {
                guard await StoreSession.shared.revoke(signed) else { return }
                await transaction.finish()
                return
            }
            guard let delivery = await StoreSession.shared.deliver(item, receipt: signed) else {
                notice = Self.failure("Your payment went through but the purchase could not be added yet. It is added the next time the app opens.")
                return
            }
            if delivery.delivered {
                if item == .seasonBundle || item == .seasonLevels { SeasonModel.shared.unlockPremium() }
                if item == .seasonLevels { SeasonModel.shared.unlockTiers(delivery.passTiers > 0 ? delivery.passTiers : GoldStore.seasonLevels.tiers) }
                notice = receipt(item, transactionID: transactionID, gold: delivery.gold)
            }
            await transaction.finish()
        }
    }

    private func receipt(_ item: PurchaseItem, transactionID: String, gold: Int) -> PurchaseNotice {
        let product: Product? = products[PurchaseCatalog.productID(item)]
        var lines: [String] = []
        switch item {
        case .plan:
            lines.append((product?.displayName ?? "Your plan") + " is active.")
            if gold > 0 { lines.append(StoreText.gold(gold) + " added to your wallet.") }
        case .goldPack:
            lines.append(StoreText.gold(gold) + " added to your wallet.")
        case .seasonBundle:
            lines.append(StoreText.gold(gold) + " and " + StorePurchase.boxText(GoldStore.seasonBundle) + " added to your Store.")
            lines.append("The premium Battle Pass track is open for season \(SeasonModel.shared.pass.seasonNumber).")
        case .seasonLevels:
            lines.append(StoreText.gold(gold) + " and " + StorePurchase.boxText(GoldStore.seasonLevels) + " added to your Store.")
            lines.append("The premium Battle Pass track is open for season \(SeasonModel.shared.pass.seasonNumber), and \(GoldStore.seasonLevels.tiers) tiers are already unlocked.")
        case .perk:
            break
        }
        if let price = product?.displayPrice { lines.append("Paid " + price + ".") }
        lines.append("Receipt number " + transactionID)
        return PurchaseNotice(kind: .success, title: "Purchase complete", lines: lines)
    }

    private static func failure(_ line: String, retry: PurchaseItem? = nil) -> PurchaseNotice {
        PurchaseNotice(kind: .failure, title: "Payment did not go through", lines: [line], retry: retry)
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? StoreKitError {
            switch e {
            case .networkError: return "Could not reach the App Store. Check your connection and try again."
            case .notAvailableInStorefront: return "This is not available in your country."
            default: break
            }
        }
        if let e = error as? Product.PurchaseError, case .purchaseNotAllowed = e { return "Purchases are turned off on this device." }
        return "The purchase did not go through. Try again."
    }

    private static func icon(_ item: PurchaseItem) -> String {
        switch item {
        case .plan: return "star.circle"
        case .goldPack: return "plus.circle"
        case .seasonBundle, .seasonLevels: return "gift"
        case .perk: return "star.circle"
        }
    }

    private static func confirmTitle(_ item: PurchaseItem) -> String {
        switch item {
        case .plan(let p):
            switch p {
            case .pro: return "Buy Ledger Pro?"
            case .founder: return "Buy Founder's Edition?"
            case .plusMonthly, .plusYearly: return "Subscribe to Ledger Plus?"
            case .proYearly: return "Subscribe to Ledger Pro?"
            }
        case .goldPack(let id): return "Get the " + (GoldStore.packs.first { $0.id == id }?.name ?? "gold pack") + "?"
        case .seasonBundle: return "Get the Battle Pass?"
        case .seasonLevels: return "Get Battle Pass Plus Levels?"
        case .perk: return ""
        }
    }

    private static func confirmMessage(_ item: PurchaseItem, product: Product) -> String {
        let price: String = product.displayPrice
        switch item {
        case .plan(let p):
            let pay: String
            switch p {
            case .plusMonthly: pay = "You pay \(price) a month. It renews until you cancel it in your App Store settings."
            case .plusYearly, .proYearly: pay = "You pay \(price) a year. It renews until you cancel it in your App Store settings."
            case .pro, .founder: pay = "You pay \(price) once. Nothing renews."
            }
            return "If you buy this, you get \(product.displayName): \(product.description) \(pay)"
        case .goldPack(let id):
            guard let pack = GoldStore.packs.first(where: { $0.id == id }) else { return "You pay \(price)." }
            let first: Bool = !StoreSession.shared.state.firstPurchaseDone
            var get: String = "If you buy this, you get \(StoreText.gold(GoldStore.totalGold(pack, firstPurchase: first)))"
            if first { get += ", which includes \(GoldStore.firstPurchaseBonus(pack).formatted()) one-time bonus gold" }
            return "\(get). You pay \(price)."
        case .seasonBundle:
            let b: SeasonBundle = GoldStore.seasonBundle
            return "If you buy this, you get the premium Battle Pass track for this season, \(StoreText.gold(b.gold)) and \(StorePurchase.boxText(b)). You pay \(price)."
        case .seasonLevels:
            let b: SeasonBundle = GoldStore.seasonLevels
            return "If you buy this, you get the premium Battle Pass track for this season with \(b.tiers) tiers already unlocked, \(StoreText.gold(b.gold)) and \(StorePurchase.boxText(b)). You pay \(price)."
        case .perk:
            return ""
        }
    }
}
