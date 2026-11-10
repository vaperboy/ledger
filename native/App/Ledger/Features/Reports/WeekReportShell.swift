import SwiftUI
import GameCore
import Countries
import Simulation

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

    var body: some View {
        GamePopup(title: digest.title, showsClose: false, dismissOnBackdrop: false, footer: AnyView(footer), category: .detail, tone: .info, onClose: { }) {
            pageContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await start() }
    }

    private var pageContent: AnyView {
        if let r = recap { return recapContent(r) }
        if loaded { return plainContent }
        return AnyView(EmptyView())
    }

    @inline(never) private func recapContent(_ r: WeekRecap) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: PopupSpace.card) {
            recapTop(r)
            recapBottom(r)
        })
    }

    @inline(never) private func recapTop(_ r: WeekRecap) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: PopupSpace.card) {
            AnyView(titleBlock)
            AnyView(numberBlock(r))
            AnyView(storyBlock(r))
            AnyView(barsBlock(r))
        })
    }

    @inline(never) private func recapBottom(_ r: WeekRecap) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: PopupSpace.card) {
            AnyView(extras(r))
            AnyView(nextCard(r))
            AnyView(recordLine(r))
            AnyView(goalsBlock)
            AnyView(moreBlock(r))
        })
    }

    private var plainContent: AnyView {
        AnyView(VStack(alignment: .leading, spacing: PopupSpace.card) {
            AnyView(more())
            AnyView(goalsBlock)
        })
    }

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

    private func dismissFolded() {
        let ids: Set<Int> = Set(foldedGoals.map { (c: Celebration) -> Int in c.id })
        while let first = store.celebrationQueue.first, ids.contains(first.id) { store.dismissCelebration() }
    }

    private var footer: some View {
        VStack(spacing: Theme.Space.xs) {
            if digest.kind == .week { DoubleGrantLink() }
            PopupActionBar {
                PopupOptionButton(title: "Continue", highlighted: true, identifier: "report-continue") { continueTapped() }
            }
        }
    }

    private func continueTapped() {
        let isWeek: Bool = digest.kind == .week
        let week: Int = store.engine?.state.week ?? 0
        let m4: Bool = store.engine.map { (e: GameEngine) -> Bool in PlayerGoals.ladder(e.state)?.first(where: { (g: PlayerGoals.LadderGoal) -> Bool in g.id == "M4" })?.done ?? true } ?? true
        let blocking: Bool = store.blockingMessageID != nil
        dismissFolded()
        store.dismissReportSheet()
        if isWeek { Task { await ads.weekReportContinued(reportWeek: week, m4Done: m4, blockingInboxOpen: blocking) } }
    }

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

    @inline(never) private func numberBlock(_ r: WeekRecap) -> some View {
        let word: String = vsWord(r)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Profit").textStyle(.label, tint: Theme.inkFaint)
            ArrowAmount(gain: r.profit, format: { (v: Double) -> String in store.short(v) }, live: true, font: PopupVariant.report.figureFont, arrowSide: 18)
                .lineLimit(2).minimumScaleFactor(0.8)
                .scaleEffect(numberShown || reduceMotion ? 1 : 0.9, anchor: .leading)
            if r.delta != nil {
                ChangeNote(now: r.profit, before: r.previousProfit, against: word, format: { (v: Double) -> String in store.short(v) }, step: .body)
            }
        }
    }

    @inline(never) private func storyBlock(_ r: WeekRecap) -> some View {
        Text(r.story).popupText(.body)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(storyShown ? 1 : 0)
    }

    @inline(never) private func barsBlock(_ r: WeekRecap) -> some View {
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
                if withSign {
                    ArrowAmount(gain: value, format: { (v: Double) -> String in store.short(v) }, live: true, font: PopupVariant.standard.valueFont).lineLimit(1)
                } else {
                    CountedFigure(value: value, format: { (v: Double) -> String in store.short(v) }, tint: Theme.ivory, duration: Motion.revealSeconds)
                        .font(PopupVariant.standard.valueFont).lineLimit(1)
                }
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

    @inline(never) @ViewBuilder private func extras(_ r: WeekRecap) -> some View {
        if r.kind != .week {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(r.movers.enumerated()), id: \.offset) { (_: Int, m: WeekMover) in moverRow(m) }
                ForEach(Array(r.extremeItems.enumerated()), id: \.offset) { (_: Int, x: WeekExtreme) in
                    HStack(spacing: Theme.Space.xs) {
                        Text(x.heading + ": " + x.title).popupText(.subtitle)
                        ArrowAmount(gain: x.profit, format: { (v: Double) -> String in store.short(v) }, step: .caption)
                    }
                }
                if r.kind == .year { yearBlock(r) }
            }
        }
    }

    private func moverRow(_ m: WeekMover) -> some View {
        return HStack {
            Text(m.label).popupText(.body).lineLimit(1)
            Spacer(minLength: 8)
            ArrowAmount(gain: m.isCost ? -m.change : m.change, amount: m.change, format: { (v: Double) -> String in store.short(v) }, live: true, font: PopupVariant.standard.valueFont)
                .lineLimit(1)
        }
    }

    @inline(never) private func yearBlock(_ r: WeekRecap) -> some View {
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
            if withSign {
                ArrowAmount(gain: value, format: { (v: Double) -> String in store.short(v) }, live: true, font: PopupVariant.standard.figureFont).lineLimit(2).minimumScaleFactor(0.8)
            } else {
                CountedFigure(value: value, format: { (v: Double) -> String in store.short(v) }, tint: tint, duration: Motion.revealSeconds)
                    .font(PopupVariant.standard.figureFont).lineLimit(2).minimumScaleFactor(0.8)
            }
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

    @inline(never) @ViewBuilder private func nextCard(_ r: WeekRecap) -> some View {
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

    @inline(never) @ViewBuilder private func recordLine(_ r: WeekRecap) -> some View {
        if let text = r.record {
            HStack(spacing: 8) {
                Image(systemName: "trophy").popupText(.effect)
                    .scaleEffect((trophyShown || reduceMotion) ? 1 : 0.5)
                Text(text).popupText(.effect)
            }
            .overlay(alignment: .top) { confetti }
        }
    }

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

    @inline(never) @ViewBuilder private func moreBlock(_ r: WeekRecap) -> some View {
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
            try? await Task.sleep(nanoseconds: 600_000_000)
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
