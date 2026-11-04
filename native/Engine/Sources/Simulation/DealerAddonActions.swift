import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The reads and actions behind the dealer add-on settings screen (warranty, car loans, insurance at the sale). The rules are in `DealerAddons`.
public extension GameEngine {
    func dealerAddonSettings(companyID: Int) -> DealerAddonSettings? {
        state.company(companyID).flatMap { DealerAddons.supports($0) ? DealerAddons.settings($0) : nil }
    }

    func dealerAddonSetup(companyID: Int, addon: DealerAddon) -> DealerSetupStatus? {
        DealerAddons.setupStatus(state, companyID: companyID, addon: addon, data: data)
    }

    /// The preview: what each add-on brings per sale on a car at `priceFactor` times the typical price of the trade.
    func dealerAddonPreview(companyID: Int, priceFactor: Double = 1) -> [DealerAddonOffer] {
        guard let co = state.company(companyID), DealerAddons.supports(co) else { return [] }
        let t = DealerAddons.typicalSale(company: co, state: state, data: data)
        return DealerAddons.offers(forSale: t.price * priceFactor, car: t.car, company: co, state: state, data: data)
    }

    func dealerAddonTotals(companyID: Int) -> DealerAddonTotals? { state.company(companyID).map { DealerAddons.totals($0) } }
    func dealerWarrantyReserve(companyID: Int) -> Double { state.company(companyID).map { DealerAddons.reserve($0) } ?? 0 }
    func dealerPolicies(companyID: Int) -> [DealerPolicyRecord] { state.company(companyID).map { DealerAddons.policies($0) } ?? [] }

    @discardableResult
    mutating func startDealerAddonSetup(companyID: Int, addon: DealerAddon) -> SettingResult {
        var out: DealerSetupResult = .refused("")
        let r = applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.company(companyID)?.value("dap") ?? .null }) { s, d, _ in
            out = DealerAddons.startSetup(&s, companyID: companyID, addon: addon, data: d)
        }
        if case .refused(let why) = out { return .refused(why) }
        return r
    }

    @discardableResult
    mutating func setDealerAddonEnabled(companyID: Int, addon: DealerAddon, on: Bool) -> SettingResult {
        var why: String?
        let r = applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.company(companyID)?.value("dap") ?? .null }) { s, _, _ in
            why = DealerAddons.setEnabled(&s, companyID: companyID, addon: addon, on: on)
        }
        if let w = why { return .refused(w) }
        return r
    }

    @discardableResult
    mutating func setDealerWarranty(companyID: Int, includedMonths: Int? = nil, extraMonths: Int? = nil, extraRate: Double? = nil) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.company(companyID)?.value("dap") ?? .null }) { s, _, _ in
            DealerAddons.setWarranty(&s, companyID: companyID, includedMonths: includedMonths, extraMonths: extraMonths, extraRate: extraRate)
        }
    }

    @discardableResult
    mutating func setDealerCommission(companyID: Int, addon: DealerAddon, rate: Double) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.company(companyID)?.value("dap") ?? .null }) { s, _, _ in
            DealerAddons.setCommission(&s, companyID: companyID, addon: addon, rate: rate)
        }
    }
}
