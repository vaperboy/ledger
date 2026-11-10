import SwiftUI
import GameCore
import Countries
import Simulation

struct BankTotalPanel: View {
    @Environment(\.outsidePalette) private var P
    var totalText: String
    var negative: Bool
    var dueText: String
    var covered: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total balance").textStyle(.caption)
                Text(totalText).textStyle(.display, tint: negative ? P.loss : P.ink).minimumScaleFactor(0.8).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Due in 30 days").foregroundStyle(P.inkSoft)
                    Text(dueText).foregroundStyle(P.ink)
                }
                .font(.system(size: 12))
                Text(covered ? "\u{2713} covered" : "Short: not covered").textStyle(.caption, tint: covered ? P.gain : P.loss)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
