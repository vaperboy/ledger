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
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let items: [OpeningChecklist.Item] = engine.openingChecklist(companyID: company.id)
        let missing: [OpeningChecklist.Item] = items.filter { !$0.isDone }
        let done: Int = items.count - missing.count
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            ProgressLine(fraction: items.isEmpty ? 1 : Double(done) / Double(items.count), tint: missing.isEmpty ? P.gain : nil,
                         label: missing.isEmpty ? "Ready to open" : "Before opening", value: "\(done) of \(items.count) done")
            LedgerSection(title: missing.isEmpty ? "Ready" : "Still missing", rule: false, trailing: { EmptyView() }) {
                VStack(spacing: 0) {
                    if missing.isEmpty {
                        EmptyState(glyph: Glyph.check, title: "Everything is in place", message: "It opens as soon as the paperwork is approved.", tint: P.gain, centered: false)
                    }
                    ForEach(Array(missing.enumerated()), id: \.element.id) { (n: Int, it: OpeningChecklist.Item) in
                        if n > 0 { Hairline() }
                        row(it)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .centerSheet(isPresented: Binding(get: { signing != nil }, set: { if !$0 { signing = nil } })) {
            if let id = signing { DocumentSignSheet(companyID: company.id, documentID: id) { signing = nil }.environment(\.outsidePalette, OutsidePalette.game).presentationBackground(.clear) }
        }
    }

    private var needsPlace: Bool {
        guard let kind = engine.tradeInfo(companyID: company.id)?.premisesKind else { return false }
        return kind != "none"
    }

    /// Each missing item says where it is fixed and the row opens it: a document its form (check the terms, sign, send) unless it is
    /// already in, premises AirStay, equipment TechPro Store. Opening stock cash has no action here.
    @ViewBuilder private func row(_ it: OpeningChecklist.Item) -> some View {
        let docID: String = it.id.hasPrefix("doc:") ? String(it.id.dropFirst(4)) : ""
        let st: String = docID.isEmpty ? "" : (engine.state.company(company.id)?.value("docs")[docID]["st"].string ?? "")
        if !docID.isEmpty && ["", "rejected", "lapsed"].contains(st) {
            rowBody(it, glyph: Glyph.reports, hint: st == "rejected" ? "Refused: apply again" : "Fill in") { signing = docID }
        } else if !docID.isEmpty {
            rowBody(it, glyph: Glyph.reports, hint: "Under review", action: nil)
        } else if it.id == "prem" && needsPlace {
            rowBody(it, glyph: Glyph.airStay, hint: "Rent in AirStay") { store.openAirStay(companyID: company.id) }
        } else if it.id.hasPrefix("eq:") {
            rowBody(it, glyph: Glyph.techPro, hint: "Buy in TechPro") { store.openTechPro(companyID: company.id) }
        } else {
            rowBody(it, glyph: Glyph.cost, hint: "", action: nil)
        }
    }

    private func rowBody(_ it: OpeningChecklist.Item, glyph: String, hint: String, action: (() -> Void)?) -> some View {
        LedgerRow(leading: .glyph(glyph), leadingTint: P.inkFaint, title: it.title.tidyMoney, subtitle: it.detail.tidyMoney,
                  valueNote: hint, valueNoteTint: action == nil ? P.inkFaint : P.accent, action: action)
    }
}
