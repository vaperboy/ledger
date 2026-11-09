import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A company that is still being set up has one screen: progress, then the full checklist of what is still missing, each row with its own
/// action (fill in a document, buy equipment in TechPro Store, rent a place in AirStay). It opens by itself once every item is done and
/// the paperwork is approved.
struct CompanySetupScreen: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var signing: String?
    @State private var appointing = false
    @State private var managerCands: [Int] = []
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let items: [OpeningChecklist.Item] = engine.openingChecklist(companyID: company.id)
        let missing: [OpeningChecklist.Item] = items.filter { !$0.isDone }
        let done: Int = items.count - missing.count
        let cost: Double = missing.reduce(0) { (a: Double, it: OpeningChecklist.Item) -> Double in a + it.cost }
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CompanyHero(label: missing.isEmpty ? "Ready to open" : "Before opening", value: "\(done) of \(items.count)",
                            change: missing.isEmpty ? "Everything is in place" : "\(missing.count) left", changeTint: missing.isEmpty ? P.gain : P.warn,
                            context: missing.isEmpty ? "it opens once the paperwork is approved" : (cost > 0.5 ? "about \(store.short(cost, in: company)) still to spend" : "it opens by itself when all are done"))
                ProgressLine(fraction: items.isEmpty ? 1 : Double(done) / Double(items.count), tint: missing.isEmpty ? P.gain : nil)
            }
            managerCard
            if !missing.isEmpty {
                PageGroup("Still missing") {
                    ForEach(Array(missing.enumerated()), id: \.element.id) { (n: Int, it: OpeningChecklist.Item) in
                        if n > 0 { RowRule() }
                        row(it)
                    }
                }
            }
            let ready: [OpeningChecklist.Item] = items.filter { $0.isDone }
            if !ready.isEmpty {
                PageGroup("Done") {
                    ForEach(Array(ready.enumerated()), id: \.element.id) { (n: Int, it: OpeningChecklist.Item) in
                        if n > 0 { RowRule() }
                        LedgerRow(leading: .glyph(Glyph.check), leadingTint: P.gain, title: it.title.tidyMoney, subtitle: it.detail.tidyMoney, density: .compact)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .centerSheet(isPresented: Binding(get: { signing != nil }, set: { if !$0 { signing = nil } }), category: .detail, tone: .investment) {
            if let id = signing { DocumentSignSheet(companyID: company.id, documentID: id) { signing = nil }.environment(\.outsidePalette, OutsidePalette.game).presentationBackground(.clear) }
        }
    }

    /// A new location of a chain can have a manager appointed instead of the owner doing the set-up by hand: the manager hires within the head
    /// office plan's headcount and orders stock for the demand. With no manager the owner does all of it.
    @ViewBuilder private var managerCard: some View {
        if engine.chainOf(companyID: company.id) != nil {
            let has: Bool = company.managerID != nil
            PageGroup("Appoint a manager") {
                LedgerRow(leading: .glyph(has ? Glyph.check : Glyph.person), leadingTint: has ? P.gain : P.accent,
                          title: has ? "A manager is appointed" : "Appoint a manager",
                          subtitle: "The manager hires staff up to the head office plan, orders stock and equipment for the demand they see, and keeps to the budget you set (tight, normal or free). Without one, you do all of it by hand.",
                          valueNote: has ? "Open orders" : "Choose", valueNoteTint: P.accent) { appointing = true }
            }
            .centerSheet(isPresented: $appointing, category: .detail, tone: .info) {
                ManagerSheet(companyID: company.id, candidates: $managerCands).environmentObject(store)
                    .environment(\.outsidePalette, OutsidePalette.game).presentationBackground(.clear)
            }
        }
    }

    private var needsPlace: Bool {
        guard let kind = engine.tradeInfo(companyID: company.id)?.premisesKind else { return false }
        return kind != "none"
    }

    /// Each missing item says where it is fixed and the row opens it: a document its form (check the terms, sign, send) unless it is
    /// already in. Premises and equipment are bought in their apps; they and opening stock cash have no action here.
    @ViewBuilder private func row(_ it: OpeningChecklist.Item) -> some View {
        let docID: String = it.id.hasPrefix("doc:") ? String(it.id.dropFirst(4)) : ""
        let st: String = docID.isEmpty ? "" : (engine.state.company(company.id)?.value("docs")[docID]["st"].string ?? "")
        if !docID.isEmpty && ["", "rejected", "lapsed"].contains(st) {
            rowBody(it, glyph: Glyph.reports, hint: st == "rejected" ? "Refused: apply again" : "Fill in") { signing = docID }
        } else if !docID.isEmpty {
            rowBody(it, glyph: Glyph.reports, hint: "Under review", action: nil)
        } else if it.id == "prem" && needsPlace {
            rowBody(it, glyph: Glyph.airStay, hint: "Rent in AirStay", action: nil)
        } else if it.id.hasPrefix("eq:") {
            rowBody(it, glyph: Glyph.techPro, hint: "Buy in TechPro", action: nil)
        } else {
            rowBody(it, glyph: Glyph.cost, hint: "", action: nil)
        }
    }

    private func rowBody(_ it: OpeningChecklist.Item, glyph: String, hint: String, action: (() -> Void)?) -> some View {
        LedgerRow(leading: .glyph(glyph), leadingTint: P.inkFaint, title: it.title.tidyMoney, subtitle: it.detail.tidyMoney,
                  valueNote: hint, valueNoteTint: action == nil ? P.inkFaint : P.accent, action: action)
    }
}
