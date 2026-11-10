import SwiftUI
import GameCore
import Simulation

struct DocumentView: View {
    private var P: OutsidePalette { .game }
    var doc: InboxDocument
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            letterhead
            Text(doc.title).textStyle(.title, tint: P.ink).fixedSize(horizontal: false, vertical: true)
            metaLine
            ForEach(Array(doc.sections.enumerated()), id: \.offset) { (i: Int, sec: InboxDocument.Section) in
                sectionView(sec)
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var refPrefix: String { doc.reference.isEmpty ? "" : "Ref \(doc.reference)  \u{00B7}  " }

    private var letterhead: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(doc.issuer).capsLabel()
            Rectangle().fill(P.accent.opacity(0.6)).frame(height: 1)
        }
    }

    private var metaLine: some View {
        Text(refPrefix + doc.date).textStyle(.caption, tint: P.inkFaint)
    }

    private func sectionView(_ sec: InboxDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Hairline()
            Text(sec.heading).textStyle(.headline, tint: P.ink, weight: .semibold)
            ForEach(Array(sec.lines.enumerated()), id: \.offset) { (i: Int, line: String) in
                Text(line).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            if !sec.points.isEmpty { pointList(sec.points) }
        }
    }

    private func pointList(_ pts: [InboxDocument.Point]) -> some View {
        let biggest: Double = pts.map { abs($0.value) }.max() ?? 1
        let top: Double = max(biggest, 0.0001)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(pts.enumerated()), id: \.offset) { (i: Int, pt: InboxDocument.Point) in
                pointRow(pt, top: top)
            }
        }
        .padding(.top, Theme.Space.xxs)
    }

    private func pointRow(_ pt: InboxDocument.Point, top: Double) -> some View {
        let frac: Double = min(1, abs(pt.value) / top)
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack {
                Text(pt.label).textStyle(.caption, tint: P.inkSoft)
                Spacer(minLength: Theme.Space.s)
                Text(Self.figure(pt.value)).textStyle(.caption, tint: P.ink, numeric: true, weight: .semibold)
            }
            GeometryReader { (g: GeometryProxy) in
                ZStack(alignment: .leading) {
                    Capsule().fill(P.line.opacity(0.6))
                    Capsule().fill(P.accent).frame(width: g.size.width * CGFloat(frac))
                }
            }
            .frame(height: 3)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Hairline()
            Text(refPrefix + "Ledger").textStyle(.caption, tint: P.inkDim)
        }
    }

    static func figure(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000_000 { return String(Int(v)) }
        return String(format: "%.1f", v)
    }
}
