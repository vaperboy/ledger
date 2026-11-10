import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    func supplierCandidates(companyID: Int, scope: String) -> [Suppliers.Vendor] { state.company(companyID).map { Suppliers.candidates(state, company: $0, scope: scope, data: data) } ?? [] }
    func currentGoodsSupplier(companyID: Int) -> Suppliers.Vendor? { state.company(companyID).flatMap { Suppliers.goodsVendor(state, company: $0, data: data) } }
    func currentRepairSupplier(companyID: Int) -> Suppliers.Vendor? { state.company(companyID).flatMap { Suppliers.repairVendor(state, company: $0, data: data) } }
    func goodsCostFactor(companyID: Int) -> Double? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type], Suppliers.hasGoods(bd, co) else { return nil }
        return Suppliers.goodsEffect(state, company: co, bd, data: data, classes: marketing.goodsClasses).m
    }
    var knownSuppliers: [Suppliers.Vendor] { Suppliers.known(state, data: data) }
    func boardAgreement(scope: String) -> String? { Suppliers.agreement(state, scope: scope) }

    mutating func chooseGoodsClass(companyID: Int, goodsClass: Int) { update { s, _, _ in Suppliers.chooseGoodsClass(&s, companyID: companyID, goodsClass: goodsClass) } }
    @discardableResult mutating func lunchWithSupplier(vendorID: String) -> Suppliers.MeetResult {
        var r = Suppliers.MeetResult.unknown
        update { s, d, _ in r = Suppliers.meet(&s, vendorID: vendorID, data: d) }
        return r
    }
    @discardableResult mutating func agreeSupplierDeal(scope: String, vendorID: String?) -> Suppliers.AgreeResult {
        var r = Suppliers.AgreeResult.unknown
        update { s, d, _ in r = Suppliers.agree(&s, scope: scope, vendorID: vendorID, data: d) }
        return r
    }
}

public struct LogoChoice: Identifiable, Equatable, Sendable {
    public var logo: LogoCatalogue.Logo
    public var unlocked: Bool
    public var how: String
    public var id: String { logo.id }
}

public extension GameEngine {
    func ownedLogos() -> Set<String> { Set((state.rest["logos"] ?? .null).array.map { (v: JSONValue) -> String in v.string }) }

    func logoChoices() -> [LogoChoice] {
        let level: Int = PlayerLevel.info(state).level
        let ladder: Bool = Gates.ladderOn(state)
        let owned: Set<String> = ownedLogos()
        return LogoCatalogue.all.map { (l: LogoCatalogue.Logo) -> LogoChoice in
            LogoChoice(logo: l, unlocked: LogoCatalogue.isUnlocked(l, level: level, ladderOn: ladder, owned: owned), how: LogoCatalogue.how(l))
        }
    }

    func companyLogoID(companyID: Int) -> String { state.company(companyID)?.value("logo").string ?? "" }

    @discardableResult
    mutating func setCompanyLogo(companyID: Int, logoID: String) -> SettingResult {
        let choices: [LogoChoice] = logoChoices()
        return applySetting(refuse: { s in
            guard s.company(companyID) != nil else { return "That company no longer exists." }
            guard let c = choices.first(where: { (x: LogoChoice) -> Bool in x.id == logoID }) else { return "That logo does not exist." }
            return c.unlocked ? nil : "Not unlocked yet: " + c.how.lowercased() + "."
        }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            for j in s.companies.indices where j != i && s.companies[j].value("logo").string == logoID { s.companies[j].set("logo", "") }
            s.companies[i].set("logo", logoID)
        }
    }

    func companyUsingLogo(_ logoID: String, besides companyID: Int) -> Company? {
        state.companies.first { (c: Company) -> Bool in c.id != companyID && c.status.isLive && c.value("logo").string == logoID }
    }

    @discardableResult
    mutating func clearCompanyLogo(companyID: Int) -> SettingResult {
        applySetting(refuse: { (s: GameState) -> String? in s.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            s.companies[i].set("logo", "")
        }
    }

    func companyStyle(companyID: Int) -> (theme: String, badge: String) {
        let c: Company? = state.company(companyID)
        return (c?.value("hue").string ?? "", c?.value("mark").string ?? "")
    }

    @discardableResult
    mutating func setCompanyStyle(companyID: Int, theme: String? = nil, badge: String? = nil) -> SettingResult {
        applySetting(refuse: { (s: GameState) -> String? in s.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            if let theme { s.companies[i].set("hue", theme) }
            if let badge { s.companies[i].set("mark", badge) }
        }
    }

    mutating func grantLogo(_ id: String) {
        guard LogoCatalogue.logo(id) != nil, !ownedLogos().contains(id) else { return }
        update { s, _, _ in
            var list: [JSONValue] = (s.rest["logos"] ?? .null).array
            list.append(.string(id))
            s.rest["logos"] = .array(list)
        }
    }
}
