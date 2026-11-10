import SwiftUI
import GameCore
import Businesses
import Simulation

extension Glyph {
    static let deskNotebook = "M6 4 H17 V20 H6 Z M9 4 V20 M12 8 H15 M12 11 H15"
}

extension GameStore {
    var deskWaitingNow: Bool { engine?.deskWaiting(realDay: GameStore.calendarDay()) ?? false }
}

enum RealDay {
    static var today: Int { Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0 }
}

enum NotebookCover {
    static func color(_ name: String) -> Color {
        switch name {
        case "sage": return Color(hex: 0x86B4A0)
        case "clay": return Color(hex: 0xC8706A)
        case "slate": return Color(hex: 0x7F9BC4)
        case "ink": return Color(hex: 0x9A94C4)
        case "sand": return Color(hex: 0xD0A86F)
        case "moss": return Color(hex: 0x86B890)
        default: return Theme.accent
        }
    }
    static func title(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }
}

struct DeskApp: View {
    @EnvironmentObject var store: GameStore
    @AppStorage("desk.cover") private var coverName: String = ""
    @State private var day: Int = RealDay.today
    @State private var choosing = false
    @State private var openChapters: Set<String> = []

    var body: some View {
        if let e = store.engine {
            PhonePageScroll(spacing: Theme.Space.xl) {
                if !e.deskOpen {
                    NoteCard(text: "The Desk opens after a few weeks of trading. One small question a day, never a rush.")
                } else {
                    todayCard(e)
                    playingOut(e)
                    WeeklyPlanCard(showsHistory: true)
                    notebook(e)
                }
            }
            .onAppear {
                day = RealDay.today
                if store.engine?.deskOpen == true { store.act { $0.deskOpenToday(realDay: day) } }
            }
            .hostedPopup(key: "desk-choice", priority: .panel, active: choosing && e.deskToday(realDay: day)?.picked == nil, onClose: { choosing = false }) {
                if let t = store.engine?.deskToday(realDay: day) { DeskChoicePopup(today: t, onPick: { pick($0) }, onClose: { choosing = false }) }
            }
        }
    }

    @ViewBuilder private func todayCard(_ e: GameEngine) -> some View {
        if let t = e.deskToday(realDay: day) {
            CardSection("Today") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(t.item.kind).textStyle(.label)
                    Text(t.item.title).textStyle(.title)
                    Text(t.text).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    if let p = t.picked, t.item.options.indices.contains(p) {
                        CardLine()
                        Text("You chose: \(t.item.options[p].label)").textStyle(.headline)
                        Text("It plays out over the next few days and the result will be in your Inbox. A new question tomorrow.").textStyle(.caption)
                    } else {
                        Button("Decide") { Haptics.tap(); choosing = true }
                            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                            .padding(.top, Theme.Space.xs)
                            .accessibilityIdentifier("desk-decide")
                    }
                }
            }
        } else {
            NoteCard(text: "Nothing on the desk today. Come back tomorrow.", glyph: Glyph.deskNotebook)
        }
    }

    private func pick(_ index: Int) {
        choosing = false
        guard let c: DeskStories.Choice = store.act({ $0.deskChoose(option: index, realDay: day) }) ?? nil else { return }
        Haptics.success()
        store.tell(c.chosen, c.told, tone: "good")
    }

    @ViewBuilder private func playingOut(_ e: GameEngine) -> some View {
        let titles: [String] = e.deskPlayingOut
        if !titles.isEmpty {
            CardSection("Playing out") {
                ForEach(titles, id: \.self) { (t: String) in
                    LedgerRow(leading: .glyph(Glyph.clock), title: t, subtitle: "You will hear in the morning Inbox.")
                }
            }
        }
    }

    private func notebook(_ e: GameEngine) -> some View {
        let pages: [DeskStories.ChapterPage] = e.deskPages()
        let covers: [String] = e.deskCovers()
        let stories: Int = pages.reduce(0) { $0 + $1.stories.count }
        let tint: Color = NotebookCover.color(coverName.isEmpty ? (covers.last ?? "") : coverName)
        return CardSection("Notebook") {
            HStack(spacing: Theme.Space.m) {
                GlyphView(glyph: Glyph.deskNotebook, size: 28, weight: 1.5, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stories) \(stories == 1 ? "story" : "stories") kept").textStyle(.headline)
                    Text(covers.isEmpty ? "Finish a chapter to earn a cover." : "\(covers.count) of \(pages.count) covers earned").textStyle(.caption)
                }
                Spacer(minLength: 0)
            }
            if covers.count > 0 { coverChips(covers) }
            ForEach(pages) { (p: DeskStories.ChapterPage) in
                CardLine()
                chapter(p)
            }
        }
    }

    private func coverChips(_ covers: [String]) -> some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(covers, id: \.self) { (c: String) in
                let on: Bool = coverName == c || (coverName.isEmpty && c == covers.last)
                Button {
                    Haptics.tap(); coverName = c
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(NotebookCover.color(c)).frame(width: 12, height: 12)
                        Text(NotebookCover.title(c)).textStyle(.caption, tint: on ? Theme.ink : Theme.inkSoft)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(on ? Theme.accentWash : Theme.inset))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cover \(NotebookCover.title(c))" + (on ? ", chosen" : ""))
            }
            Spacer(minLength: 0)
        }
    }

    private func chapter(_ p: DeskStories.ChapterPage) -> some View {
        let open: Bool = openChapters.contains(p.id)
        let need: Int = p.chapter.need
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button {
                Haptics.tap()
                if open { openChapters.remove(p.id) } else { openChapters.insert(p.id) }
            } label: {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.chapter.name).textStyle(.headline)
                        Spacer(minLength: 8)
                        Text(p.finished ? "Complete" : "\(min(p.stories.count, need)) of \(need)").textStyle(.caption, tint: p.finished ? Theme.gain : Theme.inkSoft)
                    }
                    Text(p.chapter.blurb).textStyle(.caption)
                    ProgressLine(fraction: min(1, Double(p.stories.count) / Double(max(1, need))), tint: p.finished ? Theme.gain : Theme.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the stories" : "Shows the stories")
            if open {
                if p.finished {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What this chapter taught").textStyle(.label)
                        Text(p.chapter.fact).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if p.stories.isEmpty {
                    Text("No stories yet. They come one a day, whichever fits your business.").textStyle(.caption)
                }
                ForEach(p.stories) { (s: DeskStories.Story) in story(s) }
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func story(_ s: DeskStories.Story) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(s.title).textStyle(.body, weight: .medium)
                Spacer(minLength: 6)
                Text(GameCalendar.dateString(week: s.week)).textStyle(.caption, tint: Theme.inkFaint)
            }
            Text("You: \(s.chosen)").textStyle(.caption, tint: Theme.accent)
            Text(s.result).textStyle(.body).fixedSize(horizontal: false, vertical: true)
            if s.luck != 0 { Text(s.luck > 0 ? "It could have gone either way, and went your way." : "It could have gone either way. This time it did not.").textStyle(.caption, tint: Theme.inkFaint) }
        }
        .padding(.leading, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        .accessibilityElement(children: .combine)
    }
}

struct DeskChoicePopup: View {
    var today: DeskStories.Today
    var onPick: (Int) -> Void
    var onClose: () -> Void

    var body: some View {
        GamePopup(title: today.item.title, showsClose: true, category: .medium, tone: .info, onClose: onClose) {
            PopupBody {
                Text(today.text).popupText(.subtitle)
                ForEach(Array(today.item.options.enumerated()), id: \.offset) { i, o in
                    VStack(alignment: .leading, spacing: PopupSpace.tight) {
                        PopupOptionButton(title: o.label) { onPick(i) }
                        if !o.hint.isEmpty { Text(o.hint).popupText(.caption) }
                    }
                }
            }
        }
    }
}

struct WeeklyPlanCard: View {
    @EnvironmentObject var store: GameStore
    var showsHistory = true

    var body: some View {
        if let e = store.engine, e.weeklyPlanOpen {
            let sum: WeeklyFocus.Summary = e.weeklyPlan
            let results: [WeeklyFocus.Result] = Array(e.weeklyPlanResults.prefix(4))
            CardSection("Weekly plan") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(sum.planned) \(sum.planned == 1 ? "week" : "weeks") planned").textStyle(.headline)
                        Spacer(minLength: 8)
                        if let n = sum.toNext { Text("\(n) more for the next step").textStyle(.caption) }
                    }
                    Text(sum.perkText).textStyle(.caption)
                    if let id = sum.openMessageID {
                        Button("Plan this week") { Haptics.tap(); store.decisionPopup = id }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    } else {
                        Text("A plan for next week comes with the weekly report. Skipping one takes nothing away.").textStyle(.caption, tint: Theme.inkFaint)
                    }
                }
                if showsHistory && !results.isEmpty {
                    ForEach(results) { (r: WeeklyFocus.Result) in
                        CardLine()
                        resultRow(e, r)
                    }
                }
            }
        }
    }

    private func resultRow(_ e: GameEngine, _ r: WeeklyFocus.Result) -> some View {
        let title: String = WeeklyFocus.option(r.pick)?.title ?? "Plan"
        let name: String = e.state.company(r.companyID)?.name ?? ""
        let change: Double? = r.revenueChange
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            EffectArrow(effect: change.map { $0 > 0.005 ? 1 : $0 < -0.005 ? -1 : 0 } ?? 0, size: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.body, weight: .medium)
                Text(name + (change.map { " \u{00B7} takings " + (($0 >= 0 ? "+" : "") + String(Int(($0 * 100).rounded())) + "%") + " on a usual week" } ?? " \u{00B7} too early to compare"))
                    .textStyle(.caption)
            }
            Spacer(minLength: 6)
            Text(GameCalendar.dateString(week: r.week)).textStyle(.caption, tint: Theme.inkFaint)
        }
        .accessibilityElement(children: .combine)
    }
}
