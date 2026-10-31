import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The chain-wide supplier rule, for the chain's Suppliers section: the usual provider of an input set as a rule for every store the chain
/// governs, built on the chain-rule machinery of the knob standards (`Chains.setKnobStandard`) and the one switching path (`SupplyDeals.perform`).
public struct ChainSupplierChoice: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var change: SupplierSwitch
    /// Stores that use it already, stores that would switch, and stores that cannot take it.
    public var using: Int
    public var wouldSwitch: Int
    public var cannot: Int
    public var total: Int
}

public struct ChainSupplierRule: Identifiable, Equatable, Sendable {
    public var id: String { input }
    public var input: String
    public var title: String
    public var change: SupplierSwitch
    public var providerName: String
    public var plan: SupplyDeals.ChainPlan
}

public extension GameEngine {
    /// The rules the chain has now, each with how the stores stand against it (who follows, who kept their own, who is free).
    func chainSupplierRules(chainID: Int) -> [ChainSupplierRule] {
        SupplyDeals.chainRuleInputs(state, chainID: chainID).compactMap { input in
            guard let c = SupplyDeals.chainRule(state, chainID: chainID, input: input), let sum = chainSummary(id: chainID), let first = sum.stores.first(where: { $0.status.isLive }) else { return nil }
            let opts = supplierInputs(companyID: first.id).first { $0.id == input }
            let name = chainSupplierProviderName(chainID: chainID, input: input, change: c) ?? "Chosen provider"
            return ChainSupplierRule(input: input, title: opts?.title ?? SupplyDeals.inputTitle(input).capitalized, change: c, providerName: name,
                                     plan: SupplyDeals.chainPlan(state, data, chainID: chainID, input: input, c))
        }
    }

    private func chainSupplierProviderName(chainID: Int, input: String, change: SupplierSwitch) -> String? {
        guard let sum = chainSummary(id: chainID) else { return nil }
        for st in sum.stores where st.status.isLive {
            if let o = supplierInputs(companyID: st.id).first(where: { $0.id == input })?.options.first(where: { $0.change == change }) { return o.name }
        }
        return nil
    }

    /// The providers that could be made the rule for an input, with how many stores could take each. Built from the options of every store.
    func chainSupplierChoices(chainID: Int, input: String) -> [ChainSupplierChoice] {
        guard let sum = chainSummary(id: chainID) else { return [] }
        var order: [String] = []
        var seen: [String: SupplierOption] = [:]
        for st in sum.stores where st.status.isLive {
            guard let inp = supplierInputs(companyID: st.id).first(where: { $0.id == input }) else { continue }
            for o in inp.options where seen[o.id] == nil { order.append(o.id); seen[o.id] = o }
        }
        return order.compactMap { id in
            guard let o = seen[id] else { return nil }
            let plan = SupplyDeals.chainPlan(state, data, chainID: chainID, input: input, o.change)
            return ChainSupplierChoice(id: id, name: o.name, subtitle: o.subtitle, change: o.change,
                                       using: plan.lines.filter { !$0.changes && !$0.free }.count, wouldSwitch: plan.changing,
                                       cannot: plan.lines.filter { $0.changes && $0.reason != nil && !$0.free }.count, total: plan.lines.count)
        }
    }

    func chainSupplierPlan(chainID: Int, input: String, to change: SupplierSwitch) -> SupplyDeals.ChainPlan {
        SupplyDeals.chainPlan(state, data, chainID: chainID, input: input, change)
    }

    /// Make it the chain's mandatory provider for the input; each store switches on its own terms, those that cannot keep their choice.
    @discardableResult
    mutating func setChainSupplier(chainID: Int, input: String, to change: SupplierSwitch) -> SupplyDeals.ChainPlan {
        var out = SupplyDeals.ChainPlan(lines: [])
        update { s, d, _ in out = SupplyDeals.setChainRule(&s, d, chainID: chainID, input: input, change) }
        return out
    }

    /// "Each store decides": the chain no longer fixes this input.
    @discardableResult
    mutating func releaseChainSupplier(chainID: Int, input: String) -> SettingResult {
        applySetting(refuse: { Chains.chain($0, id: chainID) == nil ? "That chain no longer exists." : nil }, probe: { Chains.chain($0, id: chainID) ?? .null }) { s, _, _ in SupplyDeals.releaseChainRule(&s, chainID: chainID, input: input) }
    }
}
