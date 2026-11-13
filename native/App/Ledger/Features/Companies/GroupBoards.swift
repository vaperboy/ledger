import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct BoardLinkRow: View {
    var engine: GameEngine
    var key: String

    var body: some View {
        let waiting: Int = engine.boardOpenDecisions(key: key)
        let jobs: Int = engine.boardFollowUps(key: key).filter { $0.status.isEmpty }.count
        let kind: String = key.hasPrefix("ch:") ? "Chain board" : "Company board"
        let sub: String = kind + (waiting > 0 ? " \u{00B7} \(waiting) to decide" : "") + (jobs > 0 ? " \u{00B7} \(jobs) follow-up \(jobs == 1 ? "job" : "jobs")" : "")
        CardRow(glyph: key.hasPrefix("ch:") ? Glyph.group : Glyph.achievements, title: engine.boardName(key: key), subtitle: sub, badge: waiting)
    }
}

struct BoardView: View {
    @EnvironmentObject var store: GameStore
    var key: String

    var body: some View {
        if let engine = store.engine, !ManagerModel.boardCompanies(engine.state, key: key).isEmpty {
            let companies: [Company] = ManagerModel.boardCompanies(engine.state, key: key)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    BoardroomContent(engine: engine, key: key, keys: [key], companies: Array(companies.prefix(1)))
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.page)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag()
            .ledgerBackground()
            .appScreen(title: "Board of " + engine.boardName(key: key), subtitle: key.hasPrefix("ch:") ? "\(companies.count) \(companies.count == 1 ? "location" : "locations")" : "Board of the company", tab: .group)
        } else {
            Text("This board no longer meets.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }
}

struct BoardDecisions: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var keys: [String]
    @State private var pending: PendingAction?
    @State private var meetingOpen = false

    private struct KeyedJob: Identifiable {
        var key: String
        var job: ManagerModel.FollowUp
        var id: String { key + ":\(job.id)" }
    }

    var body: some View {
        let list: [ManagerModel.BoardDecision] = keys.flatMap { (k: String) -> [ManagerModel.BoardDecision] in engine.boardDecisionList(key: k) }
        let sorted: [ManagerModel.BoardDecision] = list.filter { $0.recommends } + list.filter { !$0.recommends }
        let emergencies: [ManagerModel.BoardMeeting] = keys.flatMap { (k: String) -> [ManagerModel.BoardMeeting] in engine.boardMeetings(key: k).filter { $0.isOpen && $0.isEmergency } }
        let jobs: [KeyedJob] = keys.flatMap { (k: String) -> [KeyedJob] in
            engine.boardFollowUps(key: k).filter { $0.status.isEmpty }.map { (f: ManagerModel.FollowUp) -> KeyedJob in KeyedJob(key: k, job: f) }
        }
        let n: Int = sorted.count + emergencies.count
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("To decide").textStyle(.label, tint: Theme.inkFaint)
                Text(n == 0 ? "Nothing waits" : "\(n) \(n == 1 ? "point" : "points")").textStyle(.display, tint: n == 0 ? Theme.inkSoft : nil)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(n == 0 ? "The board raises a point when the numbers or the people running it call for one." : "Call a board meeting to put them to a vote.")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            ForEach(emergencies) { (m: ManagerModel.BoardMeeting) in emergency(m, key: keyOf(m)) }
            ForEach(sorted) { (d: ManagerModel.BoardDecision) in decisionCard(d) }
            callMeeting()
            if !jobs.isEmpty { followUps(jobs) }
        }
        .confirmAction($pending)
        .navigationDestination(isPresented: $meetingOpen) { BoardMeetingScreen(keys: keys) }
    }

    @ViewBuilder private func callMeeting() -> some View {
        let points: [ManagerModel.BoardDecision] = engine.boardMeetingAgenda(keys: keys)
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Call a board meeting").textStyle(.label, tint: Theme.inkFaint)
                Text("\(points.count) \(points.count == 1 ? "question" : "questions") go to the owners one at a time. Shares decide, and the winner is carried out at once. A large holder who stays away can hold a point up.")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                Button("Call the meeting") { Haptics.tap(); meetingOpen = true }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("board-call-meeting")
            }
        }
    }

    private func keyOf(_ m: ManagerModel.BoardMeeting) -> String {
        keys.first { (k: String) -> Bool in engine.boardMeetings(key: k).contains { (x: ManagerModel.BoardMeeting) -> Bool in x.id == m.id } } ?? (keys.first ?? "")
    }

    private func decisionCard(_ d: ManagerModel.BoardDecision) -> some View {
        let co: Company? = engine.state.company(d.companyID)
        let cost: String = d.cost > 0 ? (co.map { (c: Company) -> String in store.short(d.cost, in: c) } ?? store.short(d.cost)) : "Nothing"
        return Card(padding: Theme.Space.l, radius: Theme.Radius.hero, fill: Theme.surface) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(d.title.tidyMoney).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if !d.advisor.isEmpty { Text(d.advisor).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1) }
                    if !d.reason.isEmpty { Text(d.reason.tidyMoney).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    detailLine("If it passes", d.effect.tidyMoney)
                    detailLine("Cost now", cost)
                    detailLine("Risk", d.risk)
                }
            }
        }
    }

    @ViewBuilder private func detailLine(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(label).textStyle(.caption, tint: Theme.inkFaint, weight: .medium).frame(width: 92, alignment: .leading)
                Text(value).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func emergency(_ m: ManagerModel.BoardMeeting, key: String) -> some View {
        Card(padding: Theme.Space.l, radius: Theme.Radius.hero, fill: Theme.surface) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    IconCircle(glyph: Glyph.warning, size: 36, tint: Theme.caution)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(m.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium).fixedSize(horizontal: false, vertical: true)
                        Text(GameCalendar.dateString(week: m.week)).textStyle(.caption, tint: Theme.inkSoft)
                        if !m.why.isEmpty { Text(m.why.tidyMoney).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                ForEach(Array(m.options.enumerated()), id: \.offset) { (i: Int, o: String) in
                    Button(o) {
                        pending = PendingAction(title: "Decide: \(o)?", message: "An emergency decision of the board takes effect at once and cannot be undone.", button: "Decide", destructive: true) {
                            let meetingID: Int = m.id
                            let r: String? = store.act { $0.pickEmergency(key: key, meetingID: meetingID, option: i) } ?? nil
                            let said: String = r == "hire" ? "Decided. Pick a new manager in the company's Team." : "Decided: \(o)."
                            Haptics.success()
                            store.outcome(chosen: "Decide: \(o)", result: said)
                        }
                    }.buttonStyle(GreyOutlineButtonStyle())
                }
            }
        }
    }

    private func followUps(_ jobs: [KeyedJob]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text("Follow-up jobs").textStyle(.label, tint: Theme.inkFaint)
                RedBubble(count: jobs.count, size: .small)
            }
            ForEach(jobs) { (j: KeyedJob) in
                Card(padding: Theme.Space.m, radius: Theme.Radius.card) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(j.job.text.tidyMoney).textStyle(.body, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Text(j.job.assignee + " \u{00B7} lapses " + GameCalendar.dateString(week: j.job.due)).textStyle(.caption, tint: Theme.inkFaint)
                        Button("Mark done") {
                            let k: String = j.key
                            let id: Int = j.job.id
                            _ = store.act { $0.completeBoardFollowUp(key: k, id: id) }
                        }.buttonStyle(GreyOutlineButtonStyle())
                    }
                }
            }
        }
    }
}
