import SwiftUI
import GameCore
import Simulation

/// Pro "Insights": net worth over time, how each company's value moved in 30 days, and the cash runway. Drawn with plain paths from
/// the day history (no dependencies). A free player sees the same shapes blurred behind one unlock button.
struct InsightsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(\.popupClose) private var popupClose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CosmeticKeys.theme) private var themeID: String = Cosmetics.defaultThemeID
    var engine: GameEngine
    @State private var drawn: Double = 0

    var body: some View {
        let pro: Bool = ent.isPro
        let accent: Color = Cosmetics.resolvedTheme(themeID, pro: pro).accent
        return VStack(spacing: 0) {
            ZStack {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    netWorthCard(accent: accent)
                    companiesCard(accent: accent)
                    runwayCard(accent: accent)
                }
                .blur(radius: pro ? 0 : 9)
                .allowsHitTesting(pro)
                .accessibilityHidden(!pro)
                if !pro { lockCard }
            }
        }
        .onAppear { Motion.animate(Motion.reveal(reduceMotion)) { drawn = 1 } }
    }

    private var lockCard: some View {
        VStack(spacing: 10) {
            LedgerGlyph(glyph: Glyph.lock, size: Theme.Icon.large, tint: Theme.accent)
            Text("See where your money is going").popupText(.body).multilineTextAlignment(.center)
            Button("Unlock with Ledger Pro") {
                Haptics.tap()
                popupClose?()
                ent.paywall = PaywallRequest(title: "Insights")
            }
            .buttonStyle(PopupPrimaryCapsuleStyle(tone: .prestige))
            .accessibilityIdentifier("insights-unlock")
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: 320)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.surfaceRaised))
        .elevation(.raised)
        .padding(.horizontal, Theme.Space.xl)
    }

    // MARK: Cards

    private func netWorthCard(accent: Color) -> some View {
        let series: [Double] = engine.netWorthSeries(days: 365)
        let change: Double = DayHistory.change(series, days: 365)?.amount ?? 0
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Net worth over time").capsLabel()
                    Spacer()
                    Text((change >= 0 ? "▲ " : "▼ ") + store.short(abs(change))).textStyle(.caption, tint: Theme.change(change), numeric: true, weight: .medium)
                }
                InsightLine(values: series, tint: accent, drawn: drawn).frame(height: 90)
            }
        }
    }

    private struct CompanyMove: Identifiable {
        var id: Int
        var name: String
        var amount: Double
    }

    private func moves() -> [CompanyMove] {
        let hist: DayHistory = engine.dayHistory
        var out: [CompanyMove] = []
        for c in engine.state.companies where c.status.isLive && c.type != "hold" {
            guard let series = hist.perCompany[c.id], let ch = DayHistory.change(series, days: 30) else { continue }
            out.append(CompanyMove(id: c.id, name: c.name, amount: ch.amount))
        }
        out.sort { (a: CompanyMove, b: CompanyMove) -> Bool in a.amount > b.amount }
        return Array(out.prefix(6))
    }

    private func companiesCard(accent: Color) -> some View {
        let list: [CompanyMove] = moves()
        let top: Double = max(1, list.map { (m: CompanyMove) -> Double in abs(m.amount) }.max() ?? 1)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Company value, last 30 days").capsLabel()
                if list.isEmpty {
                    Text("No company history yet.").popupText(.subtitle)
                }
                ForEach(list) { (m: CompanyMove) in
                    moveRow(m, top: top, accent: accent)
                }
            }
        }
    }

    private func moveRow(_ m: CompanyMove, top: Double, accent: Color) -> some View {
        let frac: Double = min(1, abs(m.amount) / top) * drawn
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(m.name).popupText(.body).lineLimit(1)
                Spacer()
                Text((m.amount >= 0 ? "+" : "−") + store.short(abs(m.amount))).textStyle(.caption, tint: Theme.change(m.amount), numeric: true, weight: .medium)
            }
            GeometryReader { (g: GeometryProxy) in
                Capsule().fill(m.amount >= 0 ? accent : Theme.loss)
                    .frame(width: max(3, g.size.width * frac), height: 5)
            }.frame(height: 5)
        }
    }

    private func runwayCard(accent: Color) -> some View {
        let all: [Double] = engine.dayHistory.cash
        let recent: [Double] = Array(all.suffix(30))
        let days: Int? = HomeProgress.runwayDays(cash: recent)
        let headline: String = days.map { (d: Int) -> String in "\(d) days of cash" } ?? "Cash is holding steady"
        let sub: String = days != nil ? "At the pace of the last 30 days, your cash lasts this long." : "Your cash is not falling, so there is no runway to count down."
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cash runway").capsLabel()
                Text(headline).popupText(.figure).foregroundStyle(days != nil && (days ?? 0) < 30 ? Theme.caution : Theme.ivory)
                Text(sub).popupText(.caption).fixedSize(horizontal: false, vertical: true)
                InsightLine(values: recent, tint: accent, drawn: drawn).frame(height: 60)
            }
        }
    }
}

/// A smooth-less line with a soft fill under it, drawn left to right as `drawn` goes from 0 to 1.
struct InsightLine: View {
    var values: [Double]
    var tint: Color
    var drawn: Double

    var body: some View {
        let pts: [Double] = HomeProgress.normalised(values)
        return GeometryReader { (g: GeometryProxy) in
            ZStack {
                InsightShape(points: pts, closed: true)
                    .fill(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .mask(alignment: .leading) { Rectangle().frame(width: g.size.width * HomeProgress.clamp(drawn)) }
                InsightShape(points: pts, closed: false)
                    .trim(from: 0, to: HomeProgress.clamp(drawn))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The path of a normalised series (0 at the bottom, 1 at the top) across the width of its frame.
struct InsightShape: Shape {
    var points: [Double]
    var closed: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count >= 2 else { return p }
        let step: CGFloat = rect.width / CGFloat(points.count - 1)
        let pad: CGFloat = 3
        let h: CGFloat = max(1, rect.height - pad * 2)
        for i in points.indices {
            let x: CGFloat = rect.minX + step * CGFloat(i)
            let y: CGFloat = rect.maxY - pad - h * CGFloat(points[i])
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}
