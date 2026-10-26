import SwiftUI
import GameCore
import Businesses
import Simulation

/// One row of the Projects tab's time-bound work: title, company, a dot per milestone, the next date and what is in the way.
/// Opens `ProjectTimelineDetail`. Read-only: the actions (bid, start, hold) stay in the company's Projects section.
struct ProjectTimelineRow: View {
    @EnvironmentObject var store: GameStore
    var line: ProjectTimeline
    var now: Int

    var body: some View {
        NavigationLink { ProjectTimelineDetail(lineID: line.id) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                        Text("\(line.companyName) · \(kindWord(line.kind)) · \(line.subtitle)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let w = line.dueWeek { Text(dueText(w, now: now)).font(.system(size: 12).monospacedDigit()).foregroundStyle(w - now <= 2 ? Theme.caution : Theme.ivoryMuted) }
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                ProjectStageDots(stages: line.stages)
                if let b = line.blocking {
                    Text(b).font(.system(size: 11)).foregroundStyle(line.delayed ? Theme.caution : Theme.ivoryFaint).lineLimit(2)
                }
            }
            .padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

func kindWord(_ k: ProjectTimeline.Kind) -> String {
    switch k {
    case .job: return "Job"
    case .event: return "Event"
    case .tender: return "Tender to bid"
    case .bid: return "Bid sent"
    case .development: return "Development"
    }
}

func dueText(_ week: Int, now: Int) -> String {
    let left = week - now
    return left <= 0 ? "due" : left == 1 ? "1 wk" : "\(left) wk"
}

/// A short chain of dots, one per milestone: filled when done, ringed when current, faint when ahead.
struct ProjectStageDots: View {
    var stages: [ProjectTimeline.Stage]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(stages.enumerated()), id: \.offset) { n, s in
                if n > 0 { Capsule().fill(s.state == .upcoming ? Theme.hairline : Theme.gold.opacity(0.6)).frame(width: 14, height: 1.5) }
                switch s.state {
                case .done: Circle().fill(Theme.gold).frame(width: 7, height: 7)
                case .current: Circle().strokeBorder(Theme.gold, lineWidth: 1.5).background(Circle().fill(Theme.gold.opacity(0.25))).frame(width: 9, height: 9)
                case .upcoming: Circle().strokeBorder(Theme.ivoryFaint, lineWidth: 1).frame(width: 7, height: 7)
                }
            }
            if let cur = stages.first(where: { $0.state == .current }) {
                Text(cur.name).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryMuted).padding(.leading, 4)
            } else if stages.allSatisfy({ $0.state == .done }) {
                Text("Complete").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryMuted).padding(.leading, 4)
            }
        }
    }
}

/// One project in full: key figures, every milestone with its date, what blocks it, and what lateness costs.
struct ProjectTimelineDetail: View {
    @EnvironmentObject var store: GameStore
    var lineID: String

    var body: some View {
        ScrollView {
            if let e = store.engine, let line = e.projectTimelines().first(where: { $0.id == lineID }), let co = e.state.company(line.companyID) {
                let now = e.state.week
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.title.tidyMoney).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        Text("\(co.name) · \(kindWord(line.kind)) · \(line.subtitle)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    KeyFigures(items: figures(line, co, now))
                    if let p = line.progress { RateBar(label: "Progress", fraction: p, tint: line.delayed ? Theme.caution : Theme.gain) }
                    if let b = line.blocking {
                        LedgerSection("What is in the way") {
                            Text(b).font(.system(size: 13)).foregroundStyle(line.delayed ? Theme.caution : Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    LedgerSection("Milestones") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(line.stages.enumerated()), id: \.offset) { n, s in
                                if n > 0 { Hairline() }
                                stageRow(s, now: now)
                            }
                        }
                    }
                    LedgerSection("If it runs late") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(line.ifLate).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                            if let a = line.atStake, a > 0 { FlatRow(label: line.atStakeLabel, value: store.short(a, in: co)) }
                        }
                    }
                    Button { Haptics.tap(); store.openCompany(co.id, section: .projects) } label: {
                        GroupLinkRow(title: "Open \(co.name) > Projects", sub: line.kind == .tender ? "Bid, or withdraw a bid, there." : "Hold, price or review the order book there.")
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 900).frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Text("This project is finished or has been decided.").foregroundStyle(Theme.ivoryMuted)
                    Text("Finished work is counted in the company's Projects section.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                }.padding(Theme.Space.margin).frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func figures(_ l: ProjectTimeline, _ co: Company, _ now: Int) -> [KeyFigures.Item] {
        var out: [KeyFigures.Item] = [.init(label: l.kind == .development ? "Expected sales" : l.kind == .tender || l.kind == .bid ? "Worth" : "Contract", value: store.short(l.value, in: co))]
        if let c = l.costSoFar {
            out.append(.init(label: l.kind == .bid ? "Bid cost" : "Cost so far", value: store.short(c, in: co), sub: l.costBudget.map { l.kind == .bid ? "" : "of about \(store.short($0, in: co))" } ?? ""))
        } else if let r = l.receivedSoFar {
            out.append(.init(label: "Paid so far", value: store.short(r, in: co), sub: l.value > 0 ? "\(Int((r / l.value * 100).rounded()))% of the contract" : ""))
        } else if let b = l.costBudget {
            out.append(.init(label: "Cost to bid", value: store.short(b, in: co)))
        }
        let soon = (l.dueWeek.map { $0 - now <= 2 } ?? false)
        out.append(.init(label: "Next date", value: l.dueWeek.map { GameCalendar.dateString(week: $0) } ?? "None set", tint: soon ? Theme.caution : Theme.ivory,
                         sub: l.dueWeek.map { dueText($0, now: now) } ?? "no fixed date"))
        return out
    }

    private func stageRow(_ s: ProjectTimeline.Stage, now: Int) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: s.state == .done ? "checkmark.circle.fill" : s.state == .current ? "circle.dotted" : "circle")
                .font(.system(size: 14)).foregroundStyle(s.state == .upcoming ? Theme.ivoryFaint : Theme.gold).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.system(size: 13.5, weight: s.state == .current ? .semibold : .regular)).foregroundStyle(s.state == .upcoming ? Theme.ivoryMuted : Theme.ivory)
                if !s.detail.isEmpty { Text(s.detail.tidyMoney).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if let w = s.week {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(GameCalendar.dateString(week: w)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                    if s.state != .done { Text(dueText(w, now: now)).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint) }
                }
            }
        }.padding(.vertical, 9)
    }
}
