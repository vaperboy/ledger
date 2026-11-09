import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Off the books: illegal routes for a company and dirty tricks against a rival. Near-black with hazard amber. Every one of them goes through
/// the same three beats: a plain warning, a separate "if you do this, this will happen" page, and only then a press-and-hold to go ahead.
/// Nothing here ever shows how close a company is to being found out.
struct ShadowScreen: View {
    var e: GameEngine
    var back: () -> Void
    @EnvironmentObject var store: GameStore

    enum Act: Equatable {
        case route(IllegalRoute)
        case trick(DirtyTrick)
    }

    enum Step { case list, target, warning, confirm }

    @State private var companyID = 0
    @State private var act: Act? = nil
    @State private var step: Step = .list
    @State private var warning: RouteWarning? = nil
    @State private var target = ""
    private let P: OutsidePalette = .shadow

    private var openCompanies: [Company] { e.state.companies.filter { $0.status == .open && $0.type != "hold" } }
    private var company: Company? { openCompanies.first { $0.id == companyID } ?? openCompanies.first }
    private var world: GovernmentWorld { GovernmentBridge.world(e.state) }

    var body: some View {
        CivicPage(spacing: 18) {
            CivicHeader(title: title, subtitle: subtitle, onBack: { goBack() })
            HazardStripe(a: P.accent, b: P.ground).frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 2))
            if let co = company, let a = act, step != .list {
                switch step {
                case .target: targetPage(co, a)
                case .warning: warningPage(co, a)
                case .confirm: confirmPage(co, a)
                case .list: EmptyView()
                }
            } else if let co = company {
                listPage(co)
            } else {
                Text("You need an open company to do this. Nothing here works without one.").textStyle(.body)
            }
        }
        .outsideScreen(.shadow)
        .accessibilityIdentifier("country-shadow")
    }

    private var title: String {
        switch step {
        case .list: return "Off the books"
        case .target: return "Pick the target"
        case .warning: return "Read this first"
        case .confirm: return "If you do this"
        }
    }

    private var subtitle: String {
        switch step {
        case .list: return "These are crimes"
        case .target: return act.map { actTitle($0) } ?? ""
        case .warning: return act.map { actTitle($0) } ?? ""
        case .confirm: return act.map { actTitle($0) } ?? ""
        }
    }

    private func goBack() {
        switch step {
        case .list: back()
        case .target, .warning: step = .list; act = nil; warning = nil
        case .confirm: step = .warning
        }
    }

    private func actTitle(_ a: Act) -> String {
        switch a { case .route(let r): return r.title; case .trick(let k): return k.title }
    }

    // MARK: List

    private func listPage(_ co: Company) -> some View {
        let active: [IllegalRoute] = world.routes.active(co.id)
        return VStack(alignment: .leading, spacing: 18) {
            Text("None of this is allowed. If it is found out you lose what it earned, pay heavily, can lose the company and can be named in public. Think before you open a route.")
                .textStyle(.body).fixedSize(horizontal: false, vertical: true)
            if openCompanies.count > 1 { companyChips(co) }
            if !active.isEmpty { running(co, active) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Routes for \(co.name)").textStyle(.label)
                ForEach(IllegalRoute.allCases.filter { !active.contains($0) }, id: \.rawValue) { (rt: IllegalRoute) in routeRow(co, rt, active: active) }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Dirty tricks").textStyle(.label)
                ForEach(DirtyTrick.allCases, id: \.rawValue) { (k: DirtyTrick) in trickRow(co, k) }
                Text("One a week, no more than \(DirtyTrick.perAccountPerWindow) in \(DirtyTrick.windowWeeks) weeks, and a target never loses more than \(Int(DirtyTrick.targetCap)) reputation points in that time.")
                    .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func companyChips(_ co: Company) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(openCompanies) { (c: Company) in
                    Button {
                        Haptics.choose()
                        companyID = c.id
                    } label: {
                        Text(c.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(c.id == co.id ? P.onAccent : P.inkSoft)
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .background(Capsule().fill(c.id == co.id ? P.accent : Color.clear))
                            .overlay(Capsule().strokeBorder(c.id == co.id ? Color.clear : P.lineStrong, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func running(_ co: Company, _ active: [IllegalRoute]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Running now").textStyle(.label, tint: P.loss)
            ForEach(active, id: \.rawValue) { (rt: IllegalRoute) in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rt.title).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                        Text("Adds about \(CivicWords.pct(rt.gainRate)) of a week's sales").textStyle(.caption)
                    }
                    Spacer(minLength: 8)
                    Button("Stop") { stop(co, rt) }.buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.loss))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.loss.opacity(0.6), lineWidth: 1))
            }
            Text("Stopping does not wipe what it earned from the record. Risk cools only slowly.").textStyle(.caption, tint: P.inkFaint)
        }
    }

    private func routeRow(_ co: Company, _ rt: IllegalRoute, active: [IllegalRoute]) -> some View {
        let full: Bool = active.count >= RouteRules.maxRoutesPerCompany
        let banned: Bool = world.justice.barred(world.account, .trade, week: e.state.week)
        return Button {
            Haptics.tap()
            begin(.route(rt), co)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rt.title).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                    Text("Adds about \(CivicWords.pct(rt.gainRate)) of a week's sales").textStyle(.caption)
                }
                Spacer(minLength: 8)
                CivicTag(text: CivicWords.severity(rt), tint: rt.severity == 3 ? P.loss : P.accent)
                GlyphView(glyph: Glyph.chevron, size: 14, weight: 2, tint: P.inkFaint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(full || banned)
        .opacity(full || banned ? 0.45 : 1)
        .accessibilityHint(full ? "Two routes are open already" : banned ? "You are banned from trading" : "Opens the warning")
    }

    private func trickRow(_ co: Company, _ k: DirtyTrick) -> some View {
        let cost: Double = GovernmentBridge.trickCost(e.state, kind: k, companyID: co.id, context: e.context)
        let cur: Currency = e.context.currency(co.countryCode, e.state)
        return Button {
            Haptics.tap()
            act = .trick(k)
            target = ""
            step = .target
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.title).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
                    Text("Costs \(cur.tidyDisplay(cost)). The target loses up to \(Int(k.hit)) reputation points.").textStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                GlyphView(glyph: Glyph.chevron, size: 14, weight: 2, tint: P.inkFaint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(P.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Target (tricks only)

    private func targetPage(_ co: Company, _ a: Act) -> some View {
        let names: [String] = e.rivalsOpen ? e.rivalMarkets().flatMap { (m: RivalMarket) -> [String] in m.cards.map { (c: RivalStories.Card) -> String in c.name } } : []
        let clean: String = target.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Who is it aimed at? Name a rival or another company.").textStyle(.body)
            TextField("Name", text: $target)
                .font(.system(size: 18, weight: .medium)).foregroundStyle(P.ink).tint(P.accent)
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(P.cardDeep))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.lineStrong, lineWidth: 1))
            if !names.isEmpty {
                ForEach(Array(names.prefix(6).enumerated()), id: \.offset) { (_: Int, n: String) in
                    Button { target = n; Haptics.choose() } label: {
                        HStack {
                            Text(n).textStyle(.body)
                            Spacer(minLength: 8)
                            if target == n { GlyphView(glyph: Glyph.check, size: 16, weight: 2, tint: P.accent) }
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            PrimaryAction(title: "Continue", blockedReason: clean.isEmpty ? "Name the target." : nil, identifier: "shadow-target") { issueWarning(co, a) }
        }
    }

    // MARK: Beat 1: the warning

    private func begin(_ a: Act, _ co: Company) {
        act = a
        issueWarning(co, a)
    }

    /// Asks the engine for the plain warning; it is valid for a week and for one use.
    private func issueWarning(_ co: Company, _ a: Act) {
        var issued: RouteWarning? = nil
        let id: Int = co.id
        store.act { (en: inout GameEngine) -> Void in
            en.update { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in
                switch a {
                case .route(let rt): issued = GovernmentBridge.routeWarning(&s, route: rt, companyID: id)
                case .trick(let k): issued = GovernmentBridge.trickWarning(&s, kind: k, companyID: id)
                }
            }
        }
        warning = issued
        step = issued == nil ? .list : .warning
    }

    private func warningPage(_ co: Company, _ a: Act) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                GlyphView(glyph: Glyph.warning, size: 40, weight: 1.6, tint: P.accent)
                Text("This is a crime.").font(.system(size: 30, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
            }
            Text(warning?.text ?? "").font(.system(size: 17)).foregroundStyle(P.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if case .trick = a {
                Text("A trick can be traced back to you and your company.").textStyle(.body, tint: P.inkSoft)
            }
            Button("I would rather not") { goBack() }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
            Button("I have read this. Continue") { step = .confirm }.buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: P.inkSoft, passive: true))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.accent.opacity(0.7), lineWidth: 1.5))
    }

    // MARK: Beat 2: what will happen

    private func confirmPage(_ co: Company, _ a: Act) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("If you do this, this will happen").font(.system(size: 24, weight: .semibold, design: .serif)).foregroundStyle(P.ink)
            VStack(alignment: .leading, spacing: 0) {
                let lines: [(String, Bool)] = consequences(co, a)
                ForEach(Array(lines.enumerated()), id: \.offset) { (i: Int, l: (String, Bool)) in
                    if i > 0 { Rectangle().fill(P.hairline).frame(height: 1) }
                    HStack(alignment: .top, spacing: 12) {
                        Text(l.1 ? "GAIN" : "RISK").font(.system(size: 10, weight: .bold)).tracking(1.2)
                            .foregroundStyle(l.1 ? P.gain : P.loss).frame(width: 40, alignment: .leading).padding(.top, 3)
                        Text(l.0).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.loss.opacity(0.6), lineWidth: 1))
            CivicHoldButton(title: holdWord(a), tint: P.loss, ink: P.ink, identifier: "shadow-confirm") { go(co, a) }
            Button("Never mind") { step = .list; act = nil; warning = nil }.buttonStyle(TertiaryButtonStyle(fullWidth: true, tint: P.inkSoft))
            Text("The warning is valid for one week, once.").textStyle(.caption, tint: P.inkFaint)
        }
    }

    private func holdWord(_ a: Act) -> String {
        switch a { case .route: return "start it"; case .trick: return "do it" }
    }

    /// The plain consequences, true to the engine's rules. `true` marks the one gain; everything else is a risk. How close the company is to
    /// an audit is never shown, because it is never known.
    private func consequences(_ co: Company, _ a: Act) -> [(String, Bool)] {
        switch a {
        case .route(let rt):
            let back: Double = RouteRules.backMultiple
            let low: Int = Int(back + RouteRules.fineMultiple(level: 1))
            let high: Int = Int(back + RouteRules.fineMultiple(level: 2))
            return [
                ("About \(CivicWords.pct(rt.gainRate)) extra of every week's sales, paid into \(co.name), for as long as it runs.", true),
                ("An audit can come any week. You cannot see how close you are, and the risk never resets.", false),
                ("An audit looks back \(RouteRules.lookbackWeeks) weeks. You hand back everything it earned and pay a fine on top: \(low) to \(high) times what it earned in all.", false),
                ("A serious audit shuts the company for \(RouteRules.suspensionWeeks) weeks.", false),
                ("The worst audit closes the company and seizes its cash, with nothing paid out to you. You are convicted, fined, banned from trading and from office for months, and your credit falls.", false),
                ("The worst cases put your name on the public watchlist.", false),
                ("\(CivicWords.severity(rt)) crimes are met harder. A second offence is met harder again. At most \(RouteRules.maxRoutesPerCompany) routes can run at one company.", false)
            ]
        case .trick(let k):
            let cost: Double = GovernmentBridge.trickCost(e.state, kind: k, companyID: co.id, context: e.context)
            let cur: Currency = e.context.currency(co.countryCode, e.state)
            let clean: String = target.trimmingCharacters(in: .whitespacesAndNewlines)
            return [
                ("\(clean) loses up to \(Int(k.hit)) reputation points, if it is a company in this game.", true),
                ("\(co.name) pays \(cur.tidyDisplay(cost)) for it, whatever happens.", false),
                ("It can be traced back to you. Then \(co.name) pays a fine several times its cost, you are banned from trading for a short time, and a conviction goes on your record.", false),
                ("Every trick adds to the risk your company is watched.", false)
            ]
        }
    }

    // MARK: Beat 3: doing it

    private func go(_ co: Company, _ a: Act) {
        guard let w = warning else { step = .list; return }
        let id: Int = co.id
        let token: Int = w.token
        let who: String = target.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: TrickOutcome? = nil
        let ok: Bool = store.govRun { (s: inout GameState, _: GameData, c: FinanceContext) -> Void in
            switch a {
            case .route(let rt): try GovernmentBridge.beginRoute(&s, route: rt, companyID: id, token: token, confirmed: true)
            case .trick(let k): out = try GovernmentBridge.trick(&s, kind: k, companyID: id, target: who, token: token, confirmed: true, context: c)
            }
        }
        step = .list
        act = nil
        warning = nil
        guard ok else { return }
        switch a {
        case .route(let rt):
            store.outcome(chosen: "Started: \(rt.title)", result: "It is running now. Extra takings arrive each week. Watch your Inbox.")
        case .trick(let k):
            let traced: Bool = out?.detected ?? false
            store.outcome(chosen: "Done: \(k.title)", result: traced ? "It was traced back to you. See your Inbox." : "It was carried out. So far no one knows.")
        }
    }

    private func stop(_ co: Company, _ rt: IllegalRoute) {
        let id: Int = co.id
        let ok: Bool = store.govRun { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in
            GovernmentBridge.stopRoute(&s, route: rt, companyID: id)
        }
        if ok { Haptics.tap() }
    }
}

/// Diagonal hazard stripes.
struct HazardStripe: View {
    var a: Color
    var b: Color

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let h: CGFloat = g.size.height
            Path { (p: inout Path) in
                var x: CGFloat = -h
                while x < g.size.width {
                    p.move(to: CGPoint(x: x, y: h))
                    p.addLine(to: CGPoint(x: x + h, y: 0))
                    p.addLine(to: CGPoint(x: x + h + 9, y: 0))
                    p.addLine(to: CGPoint(x: x + 9, y: h))
                    p.closeSubpath()
                    x += 20
                }
            }
            .fill(a)
        }
        .background(b)
        .accessibilityHidden(true)
    }
}
