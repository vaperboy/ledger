import SwiftUI
import GameCore
import Countries
import Simulation

/// The reveal shown when a week, month or year closes: title and period, one big profit number that
/// counts up, one story sentence, three bars on one scale, one thing to do, a record line, then "Full report" and "Continue".
/// Month and year add a movers list and one extreme line (the year also a 12-bar strip, tax and net worth) and keep their existing
/// detail below a "More" divider. Finished goals that need no claim are listed inside the report (and leave the reward queue with it),
/// so a week close is one popup, not a chain. Real figures only; Reduce Motion shows everything at once. Continue works from the first frame.
struct WeekReportShell<More: View>: View {
    @EnvironmentObject var store: GameStore
    @Environment(AdCoordinator.self) private var ads
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var digest: ReportDigest
    @ViewBuilder var more: () -> More
    @State private var recap: WeekRecap?
    @State private var loaded = false
    @State private var titleShown = false
    @State private var numberShown = false
    @State private var bars: [Double] = [0, 0, 0]
    @State private var strip = false
    @State private var storyShown = false
    @State private var cardShown = false
    @State private var trophyShown = false
    @State private var burst = 0

    // MARK: Body

    var body: some View {
        GamePopup(title: digest.title, showsClose: false, dismissOnBackdrop: false, footer: AnyView(footer), category: .detail, tone: .info, onClose: { }) {
            pageContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await start() }
    }

    @ViewBuilder private var pageContent: some View {
        if let r = recap {
            VStack(alignment: .leading, spacing: PopupSpace.card) {
                titleBlock
                numberBlock(r)
                storyBlock(r)
                barsBlock(r)
                extras(r)
                nextCard(r)
                recordLine(r)
                goalsBlock
                moreBlock(r)
            }
        } else if loaded {
            VStack(alignment: .leading, spacing: PopupSpace.card) {
                more()
                goalsBlock
            }
        }
    }

    // MARK: Goals reached this week

    /// The finished goals waiting behind this report, in queue order, that need no claim of their own.
    private var foldedGoals: [Celebration] {
        Array(store.celebrationQueue.prefix(while: { (c: Celebration) -> Bool in CelebrationPopup.foldsIntoReport(c) }))
    }

    @ViewBuilder private var goalsBlock: some View {
        let goals: [Celebration] = foldedGoals
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(goals.count == 1 ? "Goal reached" : "Goals reached").capsLabel()
                ForEach(goals) { (g: Celebration) in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.small, tint: Theme.gain)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(g.title).popupText(.body)
                            if !g.reward.isEmpty { Text(g.reward).popupText(.caption) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Hairline() }
        }
    }

    /// The goals shown here have been seen: they leave the reward queue so no popup repeats them.
    private func dismissFolded() {
        let ids: Set<Int> = Set(foldedGoals.map { (c: Celebration) -> Int in c.id })
        while let first = store.celebrationQueue.first, ids.contains(first.id) { store.dismissCelebration() }
    }

    private var footer: some View {
        PopupActionBar {
            PopupOptionButton(title: "Continue", highlighted: true, identifier: "report-continue") { continueTapped() }
        }
    }

    /// Closes the report; a week report then offers the interstitial the ad rules allow (placement 1). Never blocks the player.
    private func continueTapped() {
        let isWeek: Bool = digest.kind == .week
        let week: Int = store.engine?.state.week ?? 0
        let m4: Bool = store.engine.map { (e: GameEngine) -> Bool in PlayerGoals.ladder(e.state)?.first(where: { (g: PlayerGoals.LadderGoal) -> Bool in g.id == "M4" })?.done ?? true } ?? true
        let blocking: Bool = store.blockingMessageID != nil
        dismissFolded()
        store.dismissReportSheet()
        if isWeek { Task { await ads.weekReportContinued(reportWeek: week, m4Done: m4, blockingInboxOpen: blocking) } }
    }

    // MARK: Parts

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(digest.range).popupText(.rowLabel)
        }
        .opacity(titleShown ? 1 : 0)
    }

    private func vsWord(_ r: WeekRecap) -> String {
        switch r.kind {
        case .week: return "last week"
        case .month: return "last month"
        case .year: return "last year"
        }
    }

    private func numberBlock(_ r: WeekRecap) -> some View {
        let word: String = vsWord(r)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Profit").textStyle(.label, tint: Theme.inkFaint)
            CountedFigure(value: r.profit, format: { (v: Double) -> String in signed(v) }, tint: Theme.change(r.profit), duration: Motion.revealSeconds)
                .font(PopupVariant.report.figureFont).lineLimit(2).minimumScaleFactor(0.8)
                .scaleEffect(numberShown || reduceMotion ? 1 : 0.9, anchor: .leading)
            if let d = r.delta {
                CountedFigure(value: d, format: { (v: Double) -> String in signed(v) + " vs " + word }, tint: Theme.change(d), duration: Motion.revealSeconds)
                    .font(PopupVariant.standard.valueFont).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func storyBlock(_ r: WeekRecap) -> some View {
        Text(r.story).popupText(.body)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(storyShown ? 1 : 0)
    }

    private func barsBlock(_ r: WeekRecap) -> some View {
        let top: Double = max(1, max(r.sales, max(r.costs, abs(r.profit))))
        return VStack(spacing: 12) {
            barRow("Sales", r.sales, Theme.ink.opacity(0.75), 0, top, false)
            barRow("Costs", r.costs, Theme.inkFaint, 1, top, false)
            barRow("Profit", r.profit, Theme.change(r.profit), 2, top, true)
        }
    }

    private func barRow(_ label: String, _ value: Double, _ color: Color, _ index: Int, _ top: Double, _ withSign: Bool) -> some View {
        let share: Double = min(1, abs(value) / top)
        let grown: Double = reduceMotion ? 1 : bars[index]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).popupText(.rowLabel)
                Spacer(minLength: 8)
                CountedFigure(value: value, format: { (v: Double) -> String in withSign ? signed(v) : store.short(v) }, tint: Theme.ivory, duration: Motion.revealSeconds)
                    .font(PopupVariant.standard.valueFont).lineLimit(1)
            }
            GeometryReader { (geo: GeometryProxy) in
                let full: CGFloat = max(6, geo.size.width * CGFloat(share))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(color).frame(width: full * CGFloat(grown))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: Month and year depth

    @ViewBuilder private func extras(_ r: WeekRecap) -> some View {
        if r.kind != .week {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(r.movers.enumerated()), id: \.offset) { (_: Int, m: WeekMover) in moverRow(m) }
                if let line = r.extremes {
                    Text(line).popupText(.subtitle)
                }
                if r.kind == .year { yearBlock(r) }
            }
        }
    }

    private func moverRow(_ m: WeekMover) -> some View {
        let tint: Color = m.isCost ? (m.change > 0 ? Theme.loss : Theme.gain) : Theme.change(m.change)
        return HStack {
            Text(m.label).popupText(.body).lineLimit(1)
            Spacer(minLength: 8)
            CountedFigure(value: m.change, format: { (v: Double) -> String in signed(v) }, tint: tint, duration: Motion.revealSeconds)
                .font(PopupVariant.standard.valueFont).lineLimit(1)
        }
    }

    private func yearBlock(_ r: WeekRecap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            monthStrip(r.monthStrip)
            HStack(alignment: .top, spacing: 12) {
                yearFigure("Tax paid", r.taxPaid, Theme.ivory, false)
                yearFigure("Net worth", r.netWorthChange, Theme.change(r.netWorthChange), true)
            }
            YearTaxBlock()
        }
    }

    private func yearFigure(_ label: String, _ value: Double, _ tint: Color, _ withSign: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).popupText(.rowLabel)
            CountedFigure(value: value, format: { (v: Double) -> String in withSign ? signed(v) : store.short(v) }, tint: tint, duration: Motion.revealSeconds)
                .font(PopupVariant.standard.figureFont).lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func monthStrip(_ values: [Double]) -> some View {
        if !values.isEmpty {
            let top: Double = max(1, values.map { abs($0) }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { (i: Int, p: Double) in
                    let h: CGFloat = max(3, 40 * CGFloat(abs(p) / top))
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.change(p))
                        .frame(height: h)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: 1, y: (strip || reduceMotion) ? 1 : 0.001, anchor: .bottom)
                        .animation(Motion.reveal(reduceMotion)?.delay(Double(i) * 0.04), value: strip)
                }
            }
            .frame(height: 40, alignment: .bottom)
        }
    }

    // MARK: One thing to do, record, More

    @ViewBuilder private func nextCard(_ r: WeekRecap) -> some View {
        if let n = r.next {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("One thing to do").textStyle(.label, tint: Theme.inkFaint)
                Text(n.title.tidyMoney).popupText(.rowValue)
                Text(n.detail.tidyMoney).popupText(.subtitle)
                Button {
                    Haptics.tap()
                    dismissFolded()
                    store.dismissReportSheet()
                    store.go(popup: n.action)
                } label: {
                    Text(n.buttonTitle)
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.accent)).padding(.top, Theme.Space.s).accessibilityIdentifier("report-next")
            }
            .padding(Theme.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.inset))
            .offset(y: (cardShown || reduceMotion) ? 0 : 24)
            .opacity((cardShown || reduceMotion) ? 1 : 0)
        }
    }

    @ViewBuilder private func recordLine(_ r: WeekRecap) -> some View {
        if let text = r.record {
            HStack(spacing: 8) {
                Image(systemName: "trophy").popupText(.effect)
                    .scaleEffect((trophyShown || reduceMotion) ? 1 : 0.5)
                Text(text).popupText(.effect)
            }
            .overlay(alignment: .top) { confetti }
        }
    }

    /// One small burst of 12 dots in the accent colour, falling out of view in 0.9 s. Never shown under Reduce Motion.
    @ViewBuilder private var confetti: some View {
        if !reduceMotion {
            ZStack {
                ForEach(0..<12, id: \.self) { (i: Int) in
                    Circle().fill(Theme.gold).frame(width: 5, height: 5)
                        .offset(x: CGFloat(i * 14) - 70, y: burst == 2 ? 80 : -6)
                        .opacity(burst == 1 ? 1 : 0)
                }
            }
            .allowsHitTesting(false)
            .animation(Motion.revealAnimation, value: burst)
        }
    }

    @ViewBuilder private func moreBlock(_ r: WeekRecap) -> some View {
        if r.kind != .week {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: Theme.Space.m) {
                    Text("More").capsLabel()
                    Hairline()
                }
                more()
            }
        }
    }

    // MARK: Helpers and timing

    private func signed(_ v: Double) -> String {
        abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "-") + store.short(abs(v))
    }

    /// Sets the recap, then plays the reveal: title 0.2 s, number and bars 0.6 s (bars staggered 0.08 s), story, card, record.
    private func start() async {
        let made: WeekRecap? = store.engine?.weekRecap(kind: digest.kind, id: digest.reportID)
        recap = made
        loaded = true
        if reduceMotion {
            titleShown = true; numberShown = true; bars = [1, 1, 1]; strip = true; storyShown = true; cardShown = true; trophyShown = true
            Haptics.countDone()
            if made?.record != nil { Haptics.goalDone(); SoundCues.play(.record) }
            return
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        Motion.animate(Motion.quickAnimation) { titleShown = true }
        Motion.animate(Motion.reveal(false)) { numberShown = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)   // the number has finished counting
            Haptics.countDone()
        }
        for i in 0..<3 {
            Motion.animate(Motion.reveal(false)?.delay(0.08 * Double(i))) { bars[i] = 1 }
        }
        Motion.animate(Motion.reveal(false)?.delay(0.2)) { strip = true }
        Motion.animate(Motion.quickAnimation.delay(0.7)) { storyShown = true }
        Motion.animate(Motion.move(false)?.delay(1.0)) { cardShown = true }
        guard made?.record != nil else { return }
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        Haptics.goalDone()
        SoundCues.play(.record)
        Motion.animate(Motion.move(false)) { trophyShown = true }
        burst = 1
        try? await Task.sleep(nanoseconds: 60_000_000)
        burst = 2
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        burst = 0
    }
}
