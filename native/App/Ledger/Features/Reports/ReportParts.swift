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
    /// The numbers behind the three columns (start, end, change) and their format: when given they count up instead of showing at once.
    var nums: [Double] = []
    var fmt: ReportFormat? = nil

    @ViewBuilder private func cell(_ index: Int, _ text: String, tint: Color) -> some View {
        if nums.count == 3, let fmt {
            let render: (Double) -> String = index == 2 ? { (v: Double) -> String in fmt.signed(v) } : { (v: Double) -> String in fmt.short(v) }
            CountedFigure(value: nums[index], format: render, tint: tint)
        } else {
            Text(text).foregroundStyle(tint)
        }
    }

    /// Column widths grow with Dynamic Type (from 66 and 52 pt), so figures keep their size; the label wraps to a second line instead.
    @ScaledMetric(relativeTo: .body) private var wide: CGFloat = 66
    @ScaledMetric(relativeTo: .body) private var narrow: CGFloat = 52

    var body: some View {
        let weight: Font.Weight? = strong ? .semibold : nil
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(label)
                .textStyle(.body, tint: strong ? Theme.ink : Theme.inkSoft, weight: weight)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            cell(0, first, tint: Theme.ink).textStyle(.body, numeric: true, weight: weight)
                .lineLimit(1).minimumScaleFactor(0.85).frame(width: wide, alignment: .trailing)
            cell(1, second, tint: Theme.inkSoft).textStyle(.body, tint: Theme.inkSoft, numeric: true)
                .lineLimit(1).minimumScaleFactor(0.85).frame(width: wide, alignment: .trailing)
            cell(2, third, tint: thirdTint).textStyle(.caption, tint: thirdTint, numeric: true)
                .lineLimit(1).minimumScaleFactor(0.85).frame(width: narrow, alignment: .trailing)
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}

/// The header of a report table, in small caps, over the same scaled columns as `ReportTableRow`.
struct ReportTableHeader: View {
    var first: String
    var second: String
    var third: String
    @ScaledMetric(relativeTo: .body) private var wide: CGFloat = 66
    @ScaledMetric(relativeTo: .body) private var narrow: CGFloat = 52
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Spacer(minLength: 0)
            Text(first).frame(width: wide, alignment: .trailing)
            Text(second).frame(width: wide, alignment: .trailing)
            Text(third).frame(width: narrow, alignment: .trailing)
        }
        .textStyle(.label, tint: Theme.inkFaint)
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.bottom, Theme.Space.xs)
    }
}

/// A label and a figure on one line.
struct ReportLine: View {
    var label: String
    var value: String
    var tint: Color = Theme.ivory
    var strong = false
    /// The number behind `value` and its text: the figure counts up to it (see `CountedFigure`).
    var live: Double? = nil
    var liveText: ((Double) -> String)? = nil

    @ViewBuilder private var figure: some View {
        if let live, let liveText {
            CountedFigure(value: live, format: liveText, tint: tint)
        } else {
            Text(value).foregroundStyle(tint)
        }
    }

    var body: some View {
        HStack {
            Text(label).textStyle(.body, tint: strong ? Theme.ink : Theme.inkSoft, weight: strong ? .semibold : nil)
            Spacer(minLength: Theme.Space.s)
            figure.textStyle(.body, tint: tint, numeric: true, weight: strong ? .semibold : nil)
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}
