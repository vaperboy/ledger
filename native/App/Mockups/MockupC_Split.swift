import SwiftUI

/// Variant C: fixed dashboard on top (cash, week profit, 7-segment day bar, Next day), scrolling guide card, Needs you and app grid below.
struct MockupCDashboard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(MK.company) · Week 7").capsLabel()
            Text("Cash").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).padding(.top, 14)
            Text(MK.cash).font(.serifTitle(44)).foregroundStyle(Theme.ivory)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Profit this week").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    Text("+6,900 kr").font(.system(size: 24, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.gain)
                }
                Spacer()
                Text("Sales 41,300\nCosts 34,400").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.trailing)
            }
            .padding(.top, 16)
            HStack {
                Text("Tue · Day 3 of 7"); Spacer(); Text("Report on day 7")
            }
            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).padding(.top, 20).padding(.bottom, 6)
            MKDayBar(filled: 3, height: 8)
            MKNextDay().padding(.top, 22)
            HStack {
                Text("Last report"); Spacer(); Text("Play to end of week")
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold).padding(.top, 12)
        }
        .padding(.horizontal, MK.margin).padding(.top, 56).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

struct MockupCHome: View {
    var body: some View {
        VStack(spacing: 0) {
            MockupCDashboard()
            ScrollView {
                VStack(spacing: 12) {
                    MKGuideCard()
                    MKNeedsYou()
                    MKAppGrid().padding(.top, 6)
                }
                .padding(.horizontal, MK.margin).padding(.top, 14).padding(.bottom, 100)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct MockupCScreen: View {
    enum Mode { case home, dayClose, weekReport }
    var mode: Mode
    var body: some View {
        switch mode {
        case .home:
            MKStage { MockupCHome(); VStack { Spacer(); MKTabBar() } } overlay: { EmptyView() }
        case .dayClose:
            // The dashboard stays undimmed; only the scrolling half is dimmed under the overlay.
            MKStage { MockupCHome(); VStack { Spacer(); MKTabBar() }; Color.black.opacity(0.55).padding(.top, 413) } overlay: { MKDayClose() }
        case .weekReport:
            MKStage {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Week 7").font(.serifTitle(34)).foregroundStyle(Theme.ivory)
                        Text("Mon 8 – Sun 14 February 2027").font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
                        MKNumber(size: 44)
                        MKDayBar(filled: 7, height: 8).padding(.top, 6)
                    }
                    .padding(.horizontal, MK.margin).padding(.top, 70).padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Your best week yet.").font(.serifTitle(20)).foregroundStyle(Theme.ivory)
                            MKBars()
                            MKGuideCard()
                            MKRecordLine()
                        }
                        .padding(.horizontal, MK.margin).padding(.top, 14).padding(.bottom, 140)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                VStack { Spacer(); MKReportFooter() }
            } overlay: { EmptyView() }
        }
    }
}

#Preview("C Home") { MockupCScreen(mode: .home).preferredColorScheme(.dark) }
#Preview("C DayClose") { MockupCScreen(mode: .dayClose).preferredColorScheme(.dark) }
#Preview("C WeekReport") { MockupCScreen(mode: .weekReport).preferredColorScheme(.dark) }
