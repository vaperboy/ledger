import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct SupplyCost: View {
    var now: Double?
    var before: Double?
    var currency: Currency
    var step: TextStep = .headline

    var body: some View {
        if let now {
            if let before, before > 0 {
                ArrowAmount(gain: before - now, amount: now, format: { (v: Double) -> String in currency.tidyShort(v) }, step: step)
            } else {
                Text(currency.tidyShort(now)).textStyle(step, numeric: true)
            }
        } else {
            Text("Billed per job").textStyle(.caption, tint: Theme.inkFaint)
        }
    }
}

struct SupplyWords: View {
    var quality: String
    var reliability: String

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text("\(quality) quality").textStyle(.caption, tint: Theme.inkSoft)
            Text("\(reliability) supply").textStyle(.caption, tint: reliability == "Patchy" ? Theme.caution : Theme.inkSoft)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}
