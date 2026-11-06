import SwiftUI
import GameCore
import Businesses
import Simulation

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

/// One project in full: key figures, every milestone with its date, what blocks it, and what lateness costs.
struct ProjectTimelineDetail: View {
    @EnvironmentObject var store: GameStore
    var lineID: String

    var body: some View {
        let found = store.engine.flatMap { e in e.projectTimelines().first(where: { $0.id == lineID }).map { (e, $0) } }
        return ScrollView {
            if let (e, line) = found, let co = e.state.company(line.companyID) {
                let now = e.state.week
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    KeyFigures(items: figures(line, co, now))
                    if let p = line.progress { RateBar(label: "Progress", fraction: p, tint: line.delayed ? Theme.caution : Theme.gain) }
                    if let b = line.blocking {
                        LedgerSection("What is in the way") {
                            Text(b).textStyle(.body, tint: line.delayed ? Theme.warn : Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
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
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(line.ifLate).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                            if let a = line.atStake, a > 0 { FlatRow(label: line.atStakeLabel, value: store.short(a, in: co)) }
                        }
                    }
                    Button { Haptics.tap(); store.openCompany(co.id, section: .projects) } label: {
                        GroupLinkRow(title: "Open \(co.name) > Projects", sub: line.kind == .tender ? "Bid, or withdraw a bid, there." : "Hold, price or review the order book there.")
                    }.buttonStyle(PressableStyle())
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.page)
                .frame(maxWidth: 900).frame(maxWidth: .infinity)
            } else {
                VStack(spacing: Theme.Space.s) {
                    Text("This project is finished or has been decided.").foregroundStyle(Theme.ivoryMuted)
                    Text("Finished work is counted in the company's Projects section.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                }.padding(Theme.Space.margin).frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden).noSidewaysDrag()
        .appScreen(title: found.map { $0.1.title.tidyMoney } ?? "Project",
                   subtitle: found.map { "\($0.1.companyName) · \(kindWord($0.1.kind)) · \($0.1.subtitle)" } ?? "", tab: .projects)
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
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(s.name).font(.system(size: 13.5, weight: s.state == .current ? .semibold : .regular)).foregroundStyle(s.state == .upcoming ? Theme.ivoryMuted : Theme.ivory)
                if !s.detail.isEmpty { Text(s.detail.tidyMoney).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if let w = s.week {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(GameCalendar.dateString(week: w)).textStyle(.caption, tint: Theme.inkSoft, numeric: true)
                    if s.state != .done { Text(dueText(w, now: now)).textStyle(.caption, tint: Theme.inkFaint) }
                }
            }
        }.padding(.vertical, Theme.Space.s)
    }
}


/// The weeks chart of the Timeline tab: one bar per running project over `back` weeks before today and `ahead` weeks after, a white
/// line for today, amber for late, grey for work that has not started. Drawn with shapes from `ProjectTimeline` start and due weeks.
struct ProjectWeeksChart: View {
    var lines: [ProjectTimeline]
    var now: Int
    var back = 2
    var ahead = 12

    private var span: Double { Double(back + ahead) }
    private func x(_ week: Int, _ w: CGFloat) -> CGFloat { CGFloat(min(max(Double(week - (now - back)) / span, 0), 1)) * w }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 96)
                GeometryReader { g in
                    ForEach(Array(stride(from: now - back, to: now + ahead, by: 2).enumerated()), id: \.offset) { _, wk in
                        Text(shortDate(week: wk)).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.8).fixedSize()
                            .position(x: x(wk, g.size.width) + 14, y: 7)
                    }
                }.frame(height: 14)
            }
            ForEach(lines.sorted { ($0.startWeek ?? now) < ($1.startWeek ?? now) }) { l in
                HStack(spacing: Theme.Space.xs) {
                    Text(l.title.tidyMoney).textStyle(.caption, tint: Theme.ink, weight: .medium).lineLimit(2).frame(width: 92, alignment: .leading)
                    GeometryReader { g in
                        let start = l.startWeek ?? now
                        let rawEnd = l.dueWeek ?? (now + 4)
                        let late = l.delayed || l.overdueWeeks > 0
                        let end = max(rawEnd, late ? now + 1 : start + 1)
                        let a = x(start, g.size.width), b = max(x(end, g.size.width), a + 6)
                        ZStack(alignment: .leading) {
                            ForEach(0..<(back + ahead + 1), id: \.self) { i in
                                Rectangle().fill(Color(hex: 0x1E1F21)).frame(width: 1).offset(x: CGFloat(i) / CGFloat(span) * g.size.width)
                            }
                            Capsule().fill(color(l, late)).opacity(0.85).frame(width: b - a, height: 12).offset(x: a)
                            Rectangle().fill(Theme.ivory).frame(width: 2, height: 18).offset(x: x(now, g.size.width) - 1)
                        }.frame(maxHeight: .infinity)
                    }.frame(height: 22)
                }
                .padding(.top, Theme.Space.s)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
            Text("White line is today. Amber bars are running late.").textStyle(.caption, tint: Theme.inkFaint)
        }
        .padding(.horizontal, Theme.Space.l).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline of \(lines.count) projects: " + lines.map { "\($0.title) due \($0.dueWeek.map { shortDate(week: $0) } ?? "no date")" }.joined(separator: ", "))
    }

    private func color(_ l: ProjectTimeline, _ late: Bool) -> Color {
        if late { return Theme.caution }
        return (l.progress ?? 0) > 0 || l.stages.contains { $0.state == .done && $0.name != "Taken on" && $0.name != "Booked" } ? Theme.gain : Theme.ivoryFaint
    }
}
