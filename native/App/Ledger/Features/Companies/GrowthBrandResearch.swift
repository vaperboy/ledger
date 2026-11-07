import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Minimal screens for the 2 Nov 2026 systems, each inside an existing screen: a Growth block in the worker profile, one Brand line
/// (Group overview, company Sales), and a Research row with its popup (company Sales, Market app).

// MARK: - Growth (worker profile)

struct WorkerGrowthSection: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    var companyID: Int
    var employeeID: Int
    @State private var pending: PendingAction?
    @State private var shown: Double = 0

    var body: some View {
        if let g = engine.growthPath(companyID: companyID, employeeID: employeeID), g.nextRole != nil {
            card(g)
        }
    }

    private func card(_ g: GrowthPath) -> some View {
        let tint: Color = g.isReady ? Theme.gain : Theme.gold
        return Card(padding: 12, radius: Theme.Radius.row) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Growth").capsLabel()
                    Spacer(minLength: 6)
                    Text(g.currentRoleName + " \u{2192} " + g.nextRoleName).textStyle(.caption, tint: Theme.ink, weight: .medium).lineLimit(1)
                }
                readinessBar(g, tint)
                Text(missingLine(g)).font(.system(size: 11.5)).foregroundStyle(g.isReady ? Theme.gain : Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                buttons(g)
                successorRow(g)
            }
        }
        .confirmAction($pending)
    }

    private func readinessBar(_ g: GrowthPath, _ tint: Color) -> some View {
        let target: Double = min(1, max(0, g.readiness))
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Readiness").textStyle(.caption)
                Spacer(minLength: 6)
                Text(String(Int((target * 100).rounded())) + "%").textStyle(.caption, tint: Theme.ink, numeric: true)
            }
            GeometryReader { (geo: GeometryProxy) -> AnyView in
                AnyView(ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, shown)))
                })
            }
            .frame(height: 4)
        }
        .onAppear { fill(target) }
        .onChange(of: target) { _, new in fill(new) }
    }

    private func fill(_ v: Double) {
        if reduceMotion { shown = v } else { Motion.animate(Motion.revealAnimation) { shown = v } }
    }

    private func missingLine(_ g: GrowthPath) -> String {
        if g.isReady { return "Ready for the step up." }
        guard let first = g.missing.first else { return "Not ready yet." }
        let more: String = g.missing.count > 1 ? " (+\(g.missing.count - 1) more)" : ""
        return "Missing: " + first + more
    }

    private func buttons(_ g: GrowthPath) -> some View {
        WrapRow {
            if let tid = g.suggestedTrainingID, let name = g.suggestedTraining {
                TeamAction(title: "Train: " + name, tint: Theme.ivoryMuted) { askTraining(tid, name) }
            }
            TeamAction(title: "Promote", tint: g.isReady ? Theme.gold : Theme.ivoryFaint) { promote(g) }
                .disabled(!g.isReady)
        }
    }

    @ViewBuilder private func successorRow(_ g: GrowthPath) -> some View {
        if let mgr = engine.state.company(companyID)?.managerID, mgr != employeeID {
            HStack {
                Text("Make successor").textStyle(.caption, tint: Theme.ink)
                Spacer(minLength: 6)
                LedgerSwitch(isOn: Binding<Bool>(get: { g.isSuccessor }, set: { (on: Bool) in setSuccessor(mgr, on) })).hitHeight(28)
            }
        }
    }

    private func setSuccessor(_ manager: Int, _ on: Bool) {
        let cid: Int = companyID
        let eid: Int = employeeID
        let ok: Bool = store.act { $0.setSuccessor(companyID: cid, employeeID: manager, successorID: on ? eid : nil) } ?? false
        if ok { Haptics.success(); store.show(on ? "Named as the manager's successor." : "No longer the named successor.", tone: "n") }
        else { Haptics.warning(); store.show("That cannot be set now.", tone: "warn") }
    }

    private func promote(_ g: GrowthPath) {
        let cid: Int = companyID
        let eid: Int = employeeID
        let r: PromoteResult? = store.act { $0.promote(companyID: cid, employeeID: eid) }
        switch r {
        case .promoted(let text)?: Haptics.success(); store.show(text.isEmpty ? "Promoted." : text, tone: "good")
        case .notReady(let why)?: Haptics.warning(); store.show(why.first ?? "Not ready yet.", tone: "warn")
        case .blocked(let why)?: Haptics.warning(); store.show(why.isEmpty ? "That promotion is not possible now." : why, tone: "warn")
        case nil: break
        }
    }

    private func askTraining(_ tid: String, _ name: String) {
        guard let p = engine.staffProfile(companyID: companyID, staffID: employeeID), let c = p.courses.first(where: { (x: StaffProfile.Course) -> Bool in x.id == tid }),
              let co = engine.state.company(companyID) else { return }
        let cur: Currency = engine.currency(for: co)
        let cid: Int = companyID
        let eid: Int = employeeID
        let cost: Double = c.cost
        pending = PendingAction(title: "Send \(p.name) on \(name)?", message: "Costs \(cur.tidyDisplay(cost)) from company cash. \(c.benefit) It may also change nothing.", button: "Send for \(cur.tidyShort(cost))", amount: cost, currency: cur, tone: .info, icon: "airplane") {
            let r: StaffProfile.CourseResult? = store.act { $0.sendOnCourse(companyID: cid, staffID: eid, courseID: tid) }
            switch r {
            case .done(let msg)?: Haptics.success(); store.show("\(name): \(msg).", tone: "good")
            case .cash?: Haptics.warning(); store.show("Not enough cash for \(name).", tone: "warn")
            case nil: break
            default: Haptics.warning(); store.show("That course is not available.", tone: "warn")
            }
        }
    }
}

// MARK: - Brand lines

/// Group overview: "Brand" in words, with what lifts it explained in an (i) popover.
struct GroupBrandLine: View {
    var engine: GameEngine

    var body: some View {
        let b: BrandValue = engine.groupBrandValue()
        let parts: String = "Reputation: \(BrandWords.level(value: b.reputation, of: 40))\nYears trading: \(BrandWords.level(value: b.yearsTrading, of: 15))\nReach: \(BrandWords.level(value: b.reach, of: 25))\nAwards: \(BrandWords.level(value: b.awards, of: 20))"
        let help: String = "How well people know and trust the group's name. It lifts sale offers and franchise fees. It grows with a good reputation, more years trading, wider reach and awards.\n" + parts
        return HStack(spacing: 6) {
            Text("Brand").textStyle(.caption)
            Text(BrandWords.label(score: b.score)).textStyle(.caption, tint: Theme.accent, weight: .semibold)
            BrandBar(score: b.score)
            InfoPopoverButton(title: "Brand", text: help)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
    }
}

/// Company Sales header: "Brand" in words.
struct CompanyBrandLine: View {
    var engine: GameEngine
    var companyID: Int

    var body: some View {
        let score: Double = engine.brandValue(companyID: companyID)
        return HStack(spacing: 6) {
            Text("Brand").textStyle(.caption)
            Text(BrandWords.label(score: score)).textStyle(.caption, tint: Theme.accent, weight: .semibold)
            BrandBar(score: score)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Research

/// A "Research" row that opens the research popup. Used in the Sales card and in the Market app.
struct ResearchRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var open = false

    var body: some View {
        if let lock = engine.unlockItem("research", companyID: company.id), !lock.unlocked {
            LedgerRow(leading: .glyph(Glyph.lock), leadingTint: Theme.inkFaint, title: "Research", subtitle: lock.reason, valueNote: "Locked",
                      lineLimit: 1, identifier: "sales-research") { store.show(lock.reason, tone: "n") }
                .opacity(0.6)
        } else {
            openRow
        }
    }

    private var openRow: some View {
        let reports: Int = engine.research(companyID: company.id).count
        let waiting: Int = MarketResearch.pending(company).count
        let value: String = waiting > 0 ? "\(waiting) on its way" : (reports > 0 ? "\(reports) delivered" : "Buy a report")
        return LedgerRow(leading: .glyph(Glyph.stats), leadingTint: Theme.inkSoft, title: "Research", subtitle: "Reports on customers, rivals and prices",
                         valueNote: value, valueNoteTint: waiting > 0 ? Theme.gain : nil, identifier: "sales-research") { open = true }
            .centerSheet(isPresented: $open, category: .medium, tone: .info) { ResearchSheet(companyID: company.id) }
    }
}

struct ResearchSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var pending: PendingAction?
    @State private var shownDoc: InboxDocument?

    var body: some View {
        if let d = shownDoc {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                DocumentView(doc: d, close: { shownDoc = nil })
                QuietButton(title: "Back to research", fullWidth: true) { shownDoc = nil }
            }
        } else if let e = store.engine, let co = e.state.company(companyID) {
            content(e, co)
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists")
        }
    }

    private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        let options: [ResearchOption] = e.researchOptions(companyID: companyID)
        let reports: [ResearchReport] = Array(e.research(companyID: companyID).reversed())
        let waiting: [String] = MarketResearch.pending(co).map { (x: (optionID: String, dueWeek: Int)) -> String in x.optionID }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(options) { (o: ResearchOption) -> AnyView in AnyView(optionRow(o, cur, waiting.contains(o.id))) }
            Text("A market advisor halves cost and time.").popupText(.caption)
            reportList(reports)
        }
        .centerSheetTitle("Market research")
        .confirmAction($pending)
    }

    private func optionRow(_ o: ResearchOption, _ cur: Currency, _ onItsWay: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(o.title).popupText(.rowValue)
                Text(o.detail).popupText(.caption)
                Text(cur.tidyShort(o.cost) + " \u{00B7} " + o.weeks.weeksText).popupText(.effect)
            }
            Spacer(minLength: 4)
            if onItsWay {
                Text("On its way").popupText(.caption)
            } else {
                TeamAction(title: "Buy") { ask(o, cur) }
            }
        }
    }

    @ViewBuilder private func reportList(_ reports: [ResearchReport]) -> some View {
        if !reports.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Delivered").capsLabel()
                ForEach(reports) { (r: ResearchReport) -> AnyView in AnyView(reportBlock(r)) }
            }
        }
    }

    /// The inbox document that delivered this report (matched by its reference number), if it is still in the inbox.
    private func reportDocument(_ r: ResearchReport) -> InboxDocument? {
        let ref: String = "LMR-" + String(format: "%05d", r.id)
        guard let e = store.engine else { return nil }
        for m in e.state.inbox where m.doc?.reference == ref { return m.doc }
        return nil
    }

    private func reportBlock(_ r: ResearchReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.title + " \u{00B7} " + GameCalendar.dateString(week: r.day / 7)).popupText(.rowValue)
            ForEach(r.findings, id: \.self) { (f: String) -> AnyView in
                AnyView(Text(f.tidyText).popupText(.caption))
            }
            if let d = reportDocument(r) {
                Button { shownDoc = d } label: { LinkLabel(text: "Open report") }
                    .buttonStyle(PressableStyle())
            }
        }
    }

    private func ask(_ o: ResearchOption, _ cur: Currency) {
        let cid: Int = companyID
        let oid: String = o.id
        let title: String = o.title
        let weeks: Int = o.weeks
        pending = PendingAction(title: "Order \(title.lowercased())?", message: "Paid now from company cash. The report arrives in \(weeks.weeksText).", button: "Order for \(cur.tidyShort(o.cost))", amount: o.cost, currency: cur, tone: .info, icon: "doc.text.magnifyingglass") {
            let r = store.act { $0.buyResearch(companyID: cid, optionID: oid) }
            if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
            else { Haptics.success(); store.show("\(title) ordered.", tone: "good") }
        }
    }
}
