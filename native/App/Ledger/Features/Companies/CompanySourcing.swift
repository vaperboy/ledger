import SwiftUI
import GameCore
import Businesses
import Simulation

/// Sourcing in Operations: who supplies the goods and repairs, what they cost, the quality they bring, and protection when one of your own
/// companies supplies this one. Reads `sourcingSummary`, `sourcingOffers` and `isSuppliedFromInside`; choosing uses the supplier actions.
/// Supply between your own companies is in `CompanySupply` (Chain).
struct CompanySourcing: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    private let classNames = ["Basic", "Standard", "Premium"]

    var body: some View {
        if let s = engine.sourcingSummary(companyID: company.id), s.buysGoods || s.repairSupplier != nil {
            let offers = engine.sourcingOffers(companyID: company.id)
            LedgerSection(title: "Sourcing", trailing: {
                if engine.isSuppliedFromInside(companyID: company.id) { Chip(text: "Own supplier", tint: Theme.gain) }
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    KeyFigures(items: [
                        .init(label: "Goods from", value: s.goodsSupplier?.name ?? "Market", sub: s.buysGoods ? classNames[min(2, max(0, s.goodsClass))] : "none bought"),
                        .init(label: "Goods cost", value: "\(Int((s.goodsCostFactor * 100).rounded()))%", tint: s.goodsCostFactor <= 1 ? Theme.gain : Theme.caution, sub: "of market price"),
                        .init(label: "Quality", value: String(format: "%+.0f", s.goodsQualityShift), sub: "points"),
                    ])
                    if s.suppliedFromInside {
                        Text("One of your own companies supplies the goods, so outside supplier problems (price rises, failures, cut deliveries) do not hit this company.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.gain).fixedSize(horizontal: false, vertical: true)
                    }
                    if let r = s.repairSupplier {
                        Hairline()
                        HStack {
                            Text("Repairs from \(r.name)").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                            Spacer()
                            Text(s.repairDiscount > 0 ? "\(Int((s.repairDiscount * 100).rounded()))% off bills" : "no discount").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                        }
                    }
                    if !s.boardAgreements.isEmpty {
                        Text("Board agreements: " + agreementText(s.boardAgreements)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    if s.managerMayOverpay {
                        Text("Your manager picks the supplier and is not always good at finding the best deal. Choose one yourself to be sure.")
                            .font(.system(size: 11)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                    }
                    if s.buysGoods && !offers.isEmpty {
                        Hairline()
                        SectionTabs(items: [0, 1, 2], title: { classNames[$0] },
                                    selection: Binding(get: { min(2, max(0, s.goodsClass)) }, set: { v in store.act { $0.chooseGoodsClass(companyID: company.id, goodsClass: v) } }))
                            .padding(.horizontal, -Theme.Space.margin)
                        ForEach(Array(offers.enumerated()), id: \.element.vendor.id) { n, o in
                            if n > 0 { Hairline() }
                            offerRow(o)
                        }
                        Button("Let the manager or market choose") { store.act { $0.chooseGoodsSupplier(companyID: company.id, vendorID: "auto") }; Haptics.tap() }
                            .buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                    }
                }
            }
        }
    }

    private func offerRow(_ o: Sourcing.Offer) -> some View {
        Button { store.act { $0.chooseGoodsSupplier(companyID: company.id, vendorID: o.vendor.id) }; Haptics.choose() } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(o.vendor.name).font(.system(size: 13.5, weight: o.current ? .semibold : .regular)).foregroundStyle(o.current ? Theme.gold : Theme.ivory)
                    Text(String(format: "%.1f", o.vendor.rating) + " ★ · " + o.vendor.relationshipWord + (o.vendor.discount > 0 ? " · \(Int((o.vendor.discount * 100).rounded()))% off" : ""))
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int((o.costFactor * 100).rounded()))% of market").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text(String(format: "quality %+.0f", o.qualityShift)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                }
            }.padding(.vertical, 6).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func agreementText(_ a: [String: String]) -> String {
        let names = ["goods": "goods", "eq": "equipment", "fix": "repairs"]
        return a.keys.sorted().map { (names[$0] ?? $0) + " through " + (a[$0] ?? "") }.joined(separator: ", ")
    }
}
