import SwiftUI

/// Variant A: today's Phone Home (clock, 4-column grid, tab bar) with only these additions: today strip under the header,
/// guide card first above the grid, `Needs you` under it. Static sample data.
struct MockupAHome: View {
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("9:41").font(.serifTitle(52)).foregroundStyle(Theme.ivory)
                Text("Tuesday 2 February 2027").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                Text("\(MK.company) · Cash \(MK.cash)").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }
            MKTodayStrip()
            MKGuideCard()
            MKNeedsYou()
            MKAppGrid().padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MK.margin).padding(.top, 60)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct MockupAScreen: View {
    enum Mode { case home, dayClose, weekReport }
    var mode: Mode
    var body: some View {
        switch mode {
        case .home:
            MKStage { MockupAHome(); VStack { Spacer(); MKTabBar() } } overlay: { EmptyView() }
        case .dayClose:
            MKStage { MockupAHome(); VStack { Spacer(); MKTabBar() }; Color.black.opacity(0.55).ignoresSafeArea() } overlay: { MKDayClose() }
        case .weekReport:
            MKStage {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Week 7").font(.serifTitle(34)).foregroundStyle(Theme.ivory)
                    Text("Mon 8 – Sun 14 February 2027").font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
                    MKNumber()
                    Text("Your best week yet.").font(.serifTitle(20)).foregroundStyle(Theme.ivory)
                    MKBars()
                    MKGuideCard()
                    MKRecordLine()
                    Spacer()
                }
                .padding(.horizontal, MK.margin).padding(.top, 70)
                VStack { Spacer(); MKReportFooter() }
            } overlay: { EmptyView() }
        }
    }
}

#Preview("A Home") { MockupAScreen(mode: .home).preferredColorScheme(.dark) }
#Preview("A DayClose") { MockupAScreen(mode: .dayClose).preferredColorScheme(.dark) }
#Preview("A WeekReport") { MockupAScreen(mode: .weekReport).preferredColorScheme(.dark) }
