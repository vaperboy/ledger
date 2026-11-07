import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Every supplier that any live company of the group uses now, once each (a supplier used by several companies is one row), biggest
/// spend first. Read from the same data as each company's Suppliers section (`supplierInputs`): the provider in use per input.
/// A row (`SupplierRow`): name, what it supplies and for which companies, relationship badge, rating. A tap opens its profile in a centred
/// popup with one line per fact and a button to the Suppliers section of one of the companies. Your own companies that supply others
/// are marked "Own company". It owns its scroll area unless `embedded` (the Suppliers tab of Group, inside that tab's own scroll).
struct GroupSupplierDirectory: View {
    @EnvironmentObject var store: GameStore
    var embedded: Bool = false
    @State private var picked: DirectoryPick?

    /// One use of a supplier by one company for one input.
    fileprivate struct Use {
        var companyID: Int
        var companyName: String
        var inputTitle: String
        var spendHome: Double
        var spendLocal: Double
        var currency: Currency
        var option: SupplierOption
    }

    fileprivate struct Entry: Identifiable {
        var id: String
        var name: String
        var ownCompanyID: Int?
        var uses: [Use]
        var spendHome: Double
        var companyIDs: [Int] { var seen: [Int] = []; for u in uses where !seen.contains(u.companyID) { seen.append(u.companyID) }; return seen }
    }

    struct DirectoryPick: Identifiable, Equatable {
        var id: String
    }

    var body: some View {
        if let e = store.engine {
            let entries: [Entry] = Self.entries(e)
            Group {
                if embedded {
                    VStack(alignment: .leading, spacing: Theme.Space.m) { list(entries, e) }
                } else {
                    ScrollScreen { list(entries, e) }
                }
            }
            .centerSheet(item: $picked) { (p: DirectoryPick) in profile(p.id) }
        }
    }

    @ViewBuilder private func list(_ entries: [Entry], _ e: GameEngine) -> some View {
        if entries.isEmpty {
            EmptyState(glyph: Glyph.suppliers, title: "No named suppliers yet")
        } else {
            Text("\(entries.count) \(entries.count == 1 ? "supplier" : "suppliers")").capsLabel(Theme.ivoryFaint)
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { n, en in
                    if n > 0 { Hairline() }
                    row(en, e)
                }
            }
        }
    }

    // MARK: Data

    fileprivate static func entries(_ e: GameEngine) -> [Entry] {
        let home: Currency = e.homeCurrency
        var byKey: [String: Entry] = [:]
        var order: [String] = []
        for co in e.state.liveCompanies {
            let cur: Currency = e.currency(for: co)
            for input in e.supplierInputs(companyID: co.id) {
                guard let o = input.current else { continue }
                if o.kind == .outside || o.kind == .noneFixed || o.kind == .businessCustomer { continue }
                let key: String = supplierKey(o)
                let local: Double = input.yearlySpend ?? 0
                let homeValue: Double = home.rate > 0 ? local * cur.rate / home.rate : local
                let use = Use(companyID: co.id, companyName: co.name, inputTitle: input.title, spendHome: homeValue, spendLocal: local, currency: cur, option: o)
                if var en = byKey[key] {
                    en.uses.append(use)
                    en.spendHome += homeValue
                    byKey[key] = en
                } else {
                    let own: Int? = o.kind == .ownCompany ? ownCompanyID(o) : nil
                    byKey[key] = Entry(id: key, name: o.name, ownCompanyID: own, uses: [use], spendHome: homeValue)
                    order.append(key)
                }
            }
        }
        let list: [Entry] = order.compactMap { byKey[$0] }
        return list.sorted { (a: Entry, b: Entry) in
            if a.spendHome != b.spendHome { return a.spendHome > b.spendHome }
            return a.companyIDs.count > b.companyIDs.count
        }
    }

    /// Same supplier for every company: own companies by their id, named outside suppliers by vendor id.
    private static func supplierKey(_ o: SupplierOption) -> String {
        if o.kind == .ownCompany, let id = ownCompanyID(o) { return "own:\(id)" }
        if let v = o.vendorID { return "v:" + v }
        return "n:" + o.name
    }

    /// Own-company options carry the id "o:<companyID>:<mode>".
    private static func ownCompanyID(_ o: SupplierOption) -> Int? {
        let parts: [Substring] = o.id.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }

    // MARK: Rows

    /// The shared `SupplierRow`: name, what it supplies and to which companies, rating; own companies carry a green badge.
    private func row(_ en: Entry, _ e: GameEngine) -> some View {
        let first: SupplierOption = en.uses[0].option
        let users: String = en.companyIDs.map { companyName($0, e) }.joined(separator: ", ")
        let stars: String = Self.starText(first.reliability)
        let detail: String = [Self.whatText(en) + " for " + users, stars].filter { !$0.isEmpty }.joined(separator: "  ")
        let own: Bool = en.ownCompanyID != nil
        return SupplierRow(name: en.name, detail: detail, badge: Self.badge(first, own: own), badgeTone: own ? .good : .neutral, identifier: "group-supplier-\(en.id)") {
            picked = DirectoryPick(id: en.id)
        }
    }

    private func companyName(_ id: Int, _ e: GameEngine) -> String {
        e.state.company(id)?.name ?? "Company"
    }

    private static func whatText(_ en: Entry) -> String {
        var titles: [String] = []
        for u in en.uses where !titles.contains(u.inputTitle) { titles.append(u.inputTitle) }
        return titles.joined(separator: ", ")
    }

    private static func badge(_ o: SupplierOption, own: Bool) -> String {
        if own { return "Own company" }
        return o.relationshipWord ?? "Outside"
    }

    private static func starText(_ s: String) -> String {
        guard s.hasSuffix("stars"), let first = s.split(separator: " ").first, let v = Double(first) else { return "" }
        let n: Int = min(5, max(0, Int(v.rounded())))
        return String(repeating: "\u{2605}", count: n) + String(repeating: "\u{2606}", count: 5 - n)
    }

    // MARK: Profile popup

    @ViewBuilder private func profile(_ id: String) -> some View {
        if let e = store.engine, let en = Self.entries(e).first(where: { $0.id == id }) {
            profileBody(en, e)
        }
    }

    private func profileBody(_ en: Entry, _ e: GameEngine) -> some View {
        let o: SupplierOption = en.uses[0].option
        let home: Currency = e.homeCurrency
        let discount: Double = en.uses.compactMap { $0.option.discount }.max() ?? 0
        let extra: Double = en.uses.compactMap { $0.option.dealExtra }.max() ?? 0
        let risks: [String] = Array(Set(en.uses.flatMap { $0.option.risks })).sorted()
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                Chip(text: Self.badge(o, own: en.ownCompanyID != nil), tint: en.ownCompanyID != nil ? Theme.gain : Theme.ivoryMuted)
                Spacer(minLength: 0)
            }
            Group {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PopupRow(label: "Supplies", value: Self.whatText(en))
                    PopupRow(label: "Quality", value: o.quality ?? "Not rated")
                    PopupRow(label: "Lead time", value: o.delivery)
                    PopupRow(label: "Reliability", value: o.reliability)
                    PopupRow(label: "Total spent a year", value: home.tidyShort(en.spendHome))
                    if discount > 0 { PopupRow(label: "Discount", value: "\(Int((discount * 100).rounded()))% off") }
                    if extra > 0 { Text("Negotiated: \(Int((extra * 100).rounded()))% extra off.").popupText(.effect) }
                    if !risks.isEmpty { Text("Risk: " + risks.joined(separator: " ")).popupText(.risk) }
                    Text("Terms by company").capsLabel(Theme.ivoryFaint).padding(.top, Theme.Space.xs)
                    ForEach(Array(en.uses.enumerated()), id: \.offset) { pair in
                        PopupRow(label: pair.element.companyName, value: pair.element.option.terms)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .centerSheetTitle(en.name)
    }

}
