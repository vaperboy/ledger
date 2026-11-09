import SwiftUI
import UIKit
import GameCore
import Businesses
import Simulation

// The annual report and shareholder letter (engine: Simulation/AnnualReport.swift) as a full page under Stats, with the archive of past
// years, the quarterly targets and grades, and a share action that renders the page to an image or a PDF.

/// A grade in words, coloured: Beat green, Missed red, Met plain.
struct GradeWord: View {
    var grade: ReviewGrade?
    var body: some View {
        let tint: Color = grade == .beat ? Theme.gain : (grade == .missed ? Theme.loss : Theme.ink)
        Text(grade?.word ?? "Not graded").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(tint)
    }
}

/// The page itself. It reads nothing from the environment but the theme, so the same view is drawn on screen and rendered for sharing.
struct AnnualReportPage: View {
    var report: AnnualReport
    var short: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            masthead
            hero
            figures
            if report.companies.count >= 2 { companies }
            if !report.quarters.isEmpty { quarters }
            letter
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("ANNUAL REPORT").capsLabel()
            Text(String(report.year)).textStyle(.display, numeric: true)
            Text(report.partYear ? "\(report.author)'s group, from the start of the books" : "\(report.author)'s group").textStyle(.caption)
        }
    }

    private var hero: some View {
        let loss: Bool = report.profit < 0
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(loss ? "LOSS AFTER TAX" : "PROFIT AFTER TAX").capsLabel()
            Text(short(abs(report.profit))).textStyle(.display, tint: loss ? Theme.loss : Theme.gain, numeric: true)
            if let before = report.profitBefore {
                HStack(spacing: Theme.Space.xs) {
                    ArrowAmount(gain: report.profit - before, amount: abs(report.profit - before), format: short, step: .caption)
                    Text("on the year before").textStyle(.caption)
                }
            }
        }
    }

    private func figure(_ label: String, _ value: String, change: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label).textStyle(.caption)
            Text(value).textStyle(.figure, numeric: true)
            if let c = change, abs(c) >= 0.5 { ArrowAmount(gain: c, amount: abs(c), format: short, step: .caption) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.surface))
    }

    private var figures: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                figure("Sales", short(report.sales), change: report.salesBefore.map { report.sales - $0 })
                figure("Net worth", short(report.netWorthEnd), change: report.netWorthChange)
            }
            HStack(spacing: Theme.Space.s) {
                figure("Tax paid", short(report.taxPaid))
                figure("People employed", "\(report.staffEnd)")
            }
        }
    }

    private var companies: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("THE COMPANIES").capsLabel()
            ForEach(report.companies) { (c: AnnualReport.Row) in
                HStack(alignment: .firstTextBaseline) {
                    Text(c.name).textStyle(.body)
                    Spacer(minLength: Theme.Space.s)
                    Text(short(c.sales)).textStyle(.caption, numeric: true)
                    ArrowAmount(gain: c.profit, amount: abs(c.profit), format: short, step: .body)
                        .frame(minWidth: 90, alignment: .trailing)
                }
            }
            if let m = report.mover {
                HStack(spacing: Theme.Space.xs) {
                    Text("Biggest change: \(m.name)").textStyle(.caption)
                    ArrowAmount(gain: m.change, amount: abs(m.change), format: short, step: .caption)
                }
            }
        }
    }

    private var quarters: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("QUARTERLY REVIEWS").capsLabel()
                Spacer()
                if let g = report.yearGrade { HStack(spacing: Theme.Space.xs) { Text("Year").textStyle(.caption); GradeWord(grade: g) } }
            }
            ForEach(Array(report.quarters.enumerated()), id: \.offset) { (pair: (offset: Int, element: AnnualReport.QuarterLine)) in
                HStack {
                    Text(pair.element.label).textStyle(.body)
                    Spacer()
                    GradeWord(grade: pair.element.grade)
                }
            }
        }
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("A LETTER FROM THE OWNER").capsLabel()
            Text("To my partners, lenders and staff,").font(.system(size: 16, design: .serif).italic()).foregroundStyle(Theme.ink)
            ForEach(Array(report.letter.enumerated()), id: \.offset) { (pair: (offset: Int, element: String)) in
                Text(pair.element).font(.system(size: 16, design: .serif)).foregroundStyle(Theme.ink)
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            Text(report.closing).font(.system(size: 20, design: .serif).italic()).foregroundStyle(Theme.accent).padding(.top, Theme.Space.s)
        }
    }
}

/// Renders the page for the share sheet: a PDF and a PNG in the temporary folder.
@MainActor
enum AnnualReportExport {
    static func files(_ report: AnnualReport, short: @escaping (Double) -> String) -> (pdf: URL?, image: URL?) {
        let page = AnnualReportPage(report: report, short: short)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.page)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: page)
        renderer.scale = 3
        let dir: URL = FileManager.default.temporaryDirectory
        let name: String = "Annual report \(report.year)"
        var pdfURL: URL? = dir.appendingPathComponent(name + ".pdf")
        renderer.render { (size: CGSize, draw: (CGContext) -> Void) in
            var box = CGRect(origin: .zero, size: size)
            guard let url = pdfURL, let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { pdfURL = nil; return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        var imageURL: URL? = dir.appendingPathComponent(name + ".png")
        if let data = renderer.uiImage?.pngData(), let url = imageURL {
            do { try data.write(to: url, options: .atomic) } catch { imageURL = nil }
        } else { imageURL = nil }
        return (pdfURL, imageURL)
    }
}

struct ShareFiles: Identifiable {
    let id = UUID()
    var urls: [URL]
}

struct ActivityShare: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Stats, then Reviews and annual reports: the standing with the board and lenders, the targets running, the grades so far, and the archive
/// of annual reports (newest first, one page each).
struct AnnualReportsScreen: View {
    @EnvironmentObject var store: GameStore
    @State private var year: Int?
    @State private var sharing: ShareFiles?

    var body: some View {
        if let e = store.engine {
            let reports: [AnnualReport] = e.annualReports
            let shown: AnnualReport? = reports.first(where: { (r: AnnualReport) -> Bool in r.year == year }) ?? reports.first
            PhonePageScroll(spacing: Theme.Space.xl) {
                reviewsSection(e)
                if let shown {
                    yearPicker(reports, shown)
                    AnnualReportPage(report: shown, short: { (v: Double) -> String in store.short(v) })
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.surface.opacity(0.6)))
                    shareBar(shown)
                } else {
                    LedgerSection("Annual report") {
                        Text("The first annual report is written when the year closes: your year in one page, with a letter in your name.")
                            .textStyle(.caption)
                    }
                }
            }
            .appScreen(title: "Reviews and reports", subtitle: "Quarterly targets and the year in one page")
            .sheet(item: $sharing) { (item: ShareFiles) in
                ActivityShare(items: item.urls).presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Quarterly reviews

    private func reviewsSection(_ e: GameEngine) -> some View {
        let targets: [ReviewTarget] = e.reviewTargets
        let history: [QuarterRecord] = Array(e.reviewHistory.reversed().prefix(8))
        return LedgerSection("Quarterly review") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if let s = e.reviewStanding {
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        if s.trend != 0 { StockArrow(up: s.trend > 0, good: s.trend > 0).padding(.top, 5) }
                        Text(s.words).textStyle(.body)
                    }
                } else {
                    Text("Your own review of the group comes at the end of each quarter. Set a target or two, and the books grade it when the next quarter closes.")
                        .textStyle(.caption)
                }
                if !targets.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("RUNNING UNTIL \(e.reviewTargetsLabel.uppercased())").capsLabel()
                        ForEach(targets) { (t: ReviewTarget) in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).textStyle(.body)
                                Text(t.goalText + ". " + t.stretchText + ".").textStyle(.caption)
                            }
                        }
                    }
                    .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface()
                }
                ForEach(history) { (q: QuarterRecord) in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.label).textStyle(.body)
                            Text(q.targets.map { $0.title }.joined(separator: ", ")).textStyle(.caption)
                        }
                        Spacer()
                        GradeWord(grade: q.grade)
                    }
                }
            }
        }
    }

    // MARK: Archive

    private func yearPicker(_ reports: [AnnualReport], _ shown: AnnualReport) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                ForEach(reports) { (r: AnnualReport) in
                    let on: Bool = r.year == shown.year
                    Button { year = r.year } label: {
                        Text(String(r.year)).textStyle(.body, tint: on ? Theme.page : Theme.ink, weight: .semibold)
                            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                            .background(Capsule().fill(on ? Theme.accent : Theme.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shareBar(_ r: AnnualReport) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button { share(r, pdf: false) } label: { Label("Share as image", systemImage: "photo").frame(maxWidth: .infinity) }
                .buttonStyle(.plain).textStyle(.body, tint: Theme.accent)
                .padding(Theme.Space.m).glassSurface()
                .accessibilityIdentifier("annual-share-image")
            Button { share(r, pdf: true) } label: { Label("Share as PDF", systemImage: "doc").frame(maxWidth: .infinity) }
                .buttonStyle(.plain).textStyle(.body, tint: Theme.accent)
                .padding(Theme.Space.m).glassSurface()
                .accessibilityIdentifier("annual-share-pdf")
        }
    }

    private func share(_ r: AnnualReport, pdf: Bool) {
        Haptics.tap()
        let files = AnnualReportExport.files(r, short: { (v: Double) -> String in store.short(v) })
        guard let url = pdf ? files.pdf : files.image else { store.show("The page could not be prepared for sharing.", tone: "warn"); return }
        sharing = ShareFiles(urls: [url])
    }
}

/// The row in Stats' More section: opens once the review and report are unlocked (the second company or a first year), never before.
struct AnnualReportsLink: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine, Gates.reviewOpen(e.state) {
            VStack(spacing: 0) {
                Hairline()
                NavigationLink {
                    AnnualReportsScreen()
                } label: {
                    LedgerRow(leading: .glyph(Glyph.reports), title: "Reviews and annual reports", subtitle: "Quarterly targets, and the year in one page", chevron: true, identifier: "stats-annual")
                }
                .buttonStyle(AcctPressStyle())
            }
        }
    }
}
