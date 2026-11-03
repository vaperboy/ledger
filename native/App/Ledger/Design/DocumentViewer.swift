import SwiftUI
import GameCore
import Simulation

/// A business-report style view of an inbox document: letterhead, serif title, reference and date, sections divided by thin rules,
/// lines as short paragraphs, figure points as a tiny bar list. Shown inside a `.centerSheet` (which scrolls long content itself).
struct DocumentView: View {
    private var P: OutsidePalette { .game }
    var doc: InboxDocument
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            letterhead
            Text(doc.title).font(.serifTitle(24)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(doc.issuer).capsLabel()
            Rectangle().fill(P.accent.opacity(0.6)).frame(height: 1)
        }
    }

    private var metaLine: some View {
        Text(refPrefix + doc.date).font(.caption).foregroundStyle(P.inkFaint)
    }

    private func sectionView(_ sec: InboxDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            Text(sec.heading).font(.system(size: 15, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
            ForEach(Array(sec.lines.enumerated()), id: \.offset) { (i: Int, line: String) in
                Text(line).font(.subheadline).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            if !sec.points.isEmpty { pointList(sec.points) }
        }
    }

    private func pointList(_ pts: [InboxDocument.Point]) -> some View {
        let biggest: Double = pts.map { abs($0.value) }.max() ?? 1
        let top: Double = max(biggest, 0.0001)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(pts.enumerated()), id: \.offset) { (i: Int, pt: InboxDocument.Point) in
                pointRow(pt, top: top)
            }
        }
        .padding(.top, 2)
    }

    private func pointRow(_ pt: InboxDocument.Point, top: Double) -> some View {
        let frac: Double = min(1, abs(pt.value) / top)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(pt.label).font(.caption).foregroundStyle(P.inkSoft)
                Spacer(minLength: 8)
                Text(Self.figure(pt.value)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(P.ink)
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
        VStack(alignment: .leading, spacing: 6) {
            Hairline()
            Text(refPrefix + "Ledger").font(.caption2).foregroundStyle(P.inkDim)
        }
    }

    static func figure(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000_000 { return String(Int(v)) }
        return String(format: "%.1f", v)
    }
}

/// An Identifiable wrapper so a document can drive `.centerSheet(item:)` without making an engine type Identifiable.
struct DocumentItem: Identifiable {
    let id: Int
    let doc: InboxDocument
}
