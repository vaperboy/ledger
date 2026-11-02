import SwiftUI
import Countries
import Simulation

/// Which report to open.
struct ReportRef: Hashable {
    var kind: ReportKind
    var id: Int
}

/// Number formatting shared by the report screens. `short` and `money` come from the store (home currency or a company's).
struct ReportFormat {
    var short: (Double) -> String
    var money: (Double) -> String

    func signed(_ v: Double) -> String { abs(v) < 0.5 ? short(0) : (v > 0 ? "+" : "−") + short(abs(v)) }

    func percent(_ share: Double?) -> String {
        guard let s = share, abs(s) < 10 else { return "–" }
        let p = s * 100
        if abs(p) < 0.05 { return "0%" }
        let text = abs(p) < 10 ? String(format: "%.1f%%", abs(p)) : String(format: "%.0f%%", abs(p))
        return (p > 0 ? "+" : "−") + text
    }

    func count(_ v: Double) -> String { Currency.grouped(v).replacingOccurrences(of: "\u{00A0}", with: ",") }
    func share(_ v: Double?) -> String { v.map { String(format: "%.0f%%", $0 * 100) } ?? "–" }
}

/// One row of a report table: a label and three right-aligned columns.
struct ReportTableRow: View {
    var label: String
    var first: String
    var second: String
    var third: String
    var thirdTint: Color = Theme.ivoryMuted
    var strong = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13.5, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? Theme.ivory : Theme.ivoryMuted)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(first).font(.system(size: 13.5, weight: strong ? .semibold : .regular).monospacedDigit()).foregroundStyle(Theme.ivory)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 66, alignment: .trailing)
            Text(second).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 66, alignment: .trailing)
            Text(third).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(thirdTint)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// The header of a report table, in small caps.
struct ReportTableHeader: View {
    var first: String
    var second: String
    var third: String
    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(first).frame(width: 66, alignment: .trailing)
            Text(second).frame(width: 66, alignment: .trailing)
            Text(third).frame(width: 52, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold)).tracking(0.8).textCase(.uppercase)
        .foregroundStyle(Theme.ivoryFaint)
        .padding(.bottom, 4)
    }
}

/// A label and a figure on one line.
struct ReportLine: View {
    var label: String
    var value: String
    var tint: Color = Theme.ivory
    var strong = false
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13.5, weight: strong ? .semibold : .regular)).foregroundStyle(strong ? Theme.ivory : Theme.ivoryMuted)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13.5, weight: strong ? .semibold : .regular).monospacedDigit()).foregroundStyle(tint)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
