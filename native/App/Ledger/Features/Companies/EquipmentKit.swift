import SwiftUI
import GameCore
import Businesses

// Opens a shop on the exact thing a company screen is asking for.
extension GameStore {
    func openTechPro(companyID: Int, equipmentID: String) {
        openApp(.techPro, request: .techPro(companyID: companyID, equipmentID: equipmentID))
    }

    func openAirStay(companyID: Int) {
        openApp(.airStay, request: .airStay(companyID: companyID))
    }

    func openAtlas(companyID: Int) {
        openApp(.atlas, request: .atlas(companyID: companyID))
    }
}

struct EquipmentWearBar: View {
    @Environment(\.outsidePalette) private var P
    var condition: Double
    var height: CGFloat = 6

    var body: some View {
        let share: CGFloat = CGFloat(min(1, max(0, condition)))
        GeometryReader { (g: GeometryProxy) in
            ZStack(alignment: .leading) {
                Capsule().fill(P.hairline)
                Capsule().fill(condition >= 0.8 ? P.gain : condition >= 0.48 ? P.inkSoft : P.loss)
                    .frame(width: max(height, g.size.width * share))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// One slim row: photo, name, wear bar, one status word, chevron.
struct EquipmentListRow: View {
    @Environment(\.outsidePalette) private var P
    var equipmentID: String
    var name: String
    var detail: String = ""
    var condition: Double? = nil
    var status: String
    var tone: AcctPill.Tone = .neutral
    var glyph: String = Glyph.settings
    var identifier: String = ""
    var action: () -> Void
    @Environment(\.equipmentTrade) private var trade

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                SlotImage(asset: ArtAsset.equipment(equipmentID, trade: trade), glyph: glyph, size: 52)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(name.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    if !detail.isEmpty { Text(detail.tidyText).textStyle(.caption).lineLimit(1).multilineTextAlignment(.leading) }
                    if let condition { EquipmentWearBar(condition: condition) }
                }
                Spacer(minLength: Theme.Space.s)
                AcctPill(text: status, tone: tone)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AcctPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}
