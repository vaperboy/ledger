import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Every supplier that any live company of the group uses now, once each (a supplier used by several companies is one row), biggest
/// spend first. Read from the same data as each company's Suppliers section (`supplierInputs`): the provider in use per input.
/// A row: name, what it supplies, the companies that use it as chips, relationship badge, rating. A tap opens its profile in a centred
/// popup with one line per fact and a button to the Suppliers section of one of the companies. Your own companies that supply others
/// are marked "Own company". Scrolls vertically only (it owns its scroll area: embed it in a page that does not scroll).
struct GroupSupplierDirectory: View {
    @EnvironmentObject var store: GameStore
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
            ScrollScreen {
                if entries.isEmpty {
                    Text("No company of the group uses a named supplier yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
                } else {
                    Text("\(entries.count) \(entries.count == 1 ? "supplier" : "suppliers") across the group").capsLabel(Theme.ivoryFaint)
                    ForEach(entries) { (en: Entry) in row(en, e) }
                }
            }
            .centerSheet(item: $picked) { (p: DirectoryPick) in profile(p.id) }
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

    private func row(_ en: Entry, _ e: GameEngine) -> some View {
        let first: SupplierOption = en.uses[0].option
        let what: String = Self.whatText(en)
        let stars: String = Self.starText(first.reliability)
        return Button {
            Haptics.tap()
            picked = DirectoryPick(id: en.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(en.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    if !stars.isEmpty { Text(stars).font(.system(size: 11)).foregroundStyle(Theme.gold) }
                    GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
                }
                HStack(spacing: 6) {
                    Chip(text: Self.badge(first, own: en.ownCompanyID != nil), tint: en.ownCompanyID != nil ? Theme.gain : Theme.ivoryMuted)
                    Text(what).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                WrapRow(spacing: 5) {
                    ForEach(en.companyIDs, id: \.self) { (id: Int) in
                        Text(companyName(id, e)).font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.surfaceTable))
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(PressableStyle())
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(en.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Chip(text: Self.badge(o, own: en.ownCompanyID != nil), tint: en.ownCompanyID != nil ? Theme.gain : Theme.ivoryMuted)
            }
            Group {
                VStack(alignment: .leading, spacing: 6) {
                    line("Supplies", Self.whatText(en))
                    line("Quality", o.quality ?? "Not rated")
                    line("Lead time", o.delivery)
                    line("Reliability", o.reliability)
                    line("Total spent a year", home.tidyShort(en.spendHome))
                    if discount > 0 { line("Discount", "\(Int((discount * 100).rounded()))% off") }
                    if extra > 0 { line("Negotiated", "\(Int((extra * 100).rounded()))% extra off", tint: Theme.gain) }
                    if !risks.isEmpty { line("Risk", risks.joined(separator: " "), tint: Theme.caution) }
                    Text("Terms by company").capsLabel(Theme.ivoryFaint).padding(.top, 4)
                    ForEach(Array(en.uses.enumerated()), id: \.offset) { pair in
                        line(pair.element.companyName, pair.element.option.terms)
                    }
                }
            }
            openButtons(en)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func openButtons(_ en: Entry) -> some View {
        VStack(spacing: 8) {
            ForEach(en.companyIDs, id: \.self) { (id: Int) in
                let name: String = en.uses.first(where: { $0.companyID == id })?.companyName ?? "company"
                SmallOutlineButton(title: "Open in \(name)") {
                    picked = nil
                    store.openCompany(id, section: .operations, part: OpsPart.suppliers.rawValue)
                }
            }
        }
    }

    private func line(_ label: String, _ value: String, tint: Color = Theme.ivory) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(tint).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }
}
