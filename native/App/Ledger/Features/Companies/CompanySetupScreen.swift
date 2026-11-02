import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A company that is still being set up has one fixed screen (owner decision, 2 Nov): what is still missing and the two apps that fix it,
/// TechPro Store (equipment, software, vehicles) and AirStay (a place), each in its own colour. No stats and no scrolling until it opens;
/// it opens by itself once every item is done and the paperwork is approved.
struct CompanySetupScreen: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var signing: String?

    var body: some View {
        let items: [OpeningChecklist.Item] = engine.openingChecklist(companyID: company.id)
        let missing: [OpeningChecklist.Item] = items.filter { !$0.isDone }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection(title: "Before opening", trailing: {
                Text(missing.isEmpty ? "ready" : "\(items.count - missing.count) of \(items.count) done").font(.system(size: 11.5)).foregroundStyle(missing.isEmpty ? Theme.gain : Theme.ivoryFaint)
            }) {
                VStack(spacing: 0) {
                    if missing.isEmpty { Text("Everything is in place. It opens as soon as the paperwork is approved.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(Array(missing.prefix(6).enumerated()), id: \.element.id) { (n: Int, it: OpeningChecklist.Item) in
                        if n > 0 { Hairline() }
                        row(it)
                    }
                    if missing.count > 6 { Text("and \(missing.count - 6) more").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6) }
                }
            }
            appCard(palette: .techPro, glyph: Glyph.techPro, title: "TechPro Store", note: "Equipment, software, tools and vehicles for your business: brands, used, lease and delivery.", button: "Open TechPro") {
                store.openTechPro(companyID: company.id)
            }
            if needsPlace {
                appCard(palette: .airStay, glyph: Glyph.airStay, title: "AirStay", note: "Find a place to rent for your business: offices, shops and workshops.", button: "Open AirStay") {
                    store.openAirStay(companyID: company.id)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.xs)
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading).frame(maxWidth: .infinity)
        .sheet(isPresented: Binding(get: { signing != nil }, set: { if !$0 { signing = nil } })) {
            if let id = signing { DocumentSignSheet(companyID: company.id, documentID: id) { signing = nil }.environment(\.outsidePalette, OutsidePalette.game).presentationBackground(.clear) }
        }
    }

    private var needsPlace: Bool {
        guard let kind = engine.tradeInfo(companyID: company.id)?.premisesKind else { return false }
        return kind != "none"
    }

    /// A document row opens its form (check the terms, draw a signature, send) unless it is already in or held.
    @ViewBuilder private func row(_ it: OpeningChecklist.Item) -> some View {
        let docID: String = it.id.hasPrefix("doc:") ? String(it.id.dropFirst(4)) : ""
        let st: String = docID.isEmpty ? "" : (engine.state.company(company.id)?.value("docs")[docID]["st"].string ?? "")
        if !docID.isEmpty && ["", "rejected", "lapsed"].contains(st) {
            Button { Haptics.tap(); signing = docID } label: { rowBody(it, hint: st == "rejected" ? "Refused: apply again \u{203A}" : "Fill in \u{203A}") }.buttonStyle(PressableStyle())
        } else {
            rowBody(it, hint: docID.isEmpty ? "" : "Under review")
        }
    }

    private func rowBody(_ it: OpeningChecklist.Item, hint: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "circle").foregroundStyle(Theme.ivoryFaint)
            VStack(alignment: .leading, spacing: 1) {
                Text(it.title.tidyMoney).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                if !it.detail.isEmpty { Text(it.detail.tidyMoney).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
            }
            Spacer(minLength: 6)
            if !hint.isEmpty { Text(hint).font(.system(size: 11.5)).foregroundStyle(hint.hasPrefix("Under") ? Theme.ivoryFaint : Theme.gold).fixedSize() }
        }.padding(.vertical, 8).contentShape(Rectangle())
    }

    /// One app's card in its own palette: icon, name, what it is, and a button in the app's colour.
    private func appCard(palette P: OutsidePalette, glyph: String, title: String, note: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GlyphView(glyph: glyph, size: 24, weight: 1.6, tint: P.accent)
                .frame(width: 46, height: 46).background(Circle().fill(P.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ivory)
                Text(note).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                Button { Haptics.tap(); action() } label: {
                    Text(button).font(.system(size: 14, weight: .semibold)).foregroundStyle(P.onAccent)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(Capsule().fill(P.accent))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(P.accent.opacity(0.45), lineWidth: 1))
    }
}
