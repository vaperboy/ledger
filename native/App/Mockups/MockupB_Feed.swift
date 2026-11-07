import SwiftUI

/// Variant B: Home as one vertical feed. Header (company, cash), today strip, Next day, guide card, Needs you, this week's figures
/// with one briefing sentence, one card per company, last report row. The app grid sits behind the Phone tab (row `Open Phone`).
struct MockupBFeed: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Home").capsLabel()
                    Text(MK.company).font(.serifTitle(28)).foregroundStyle(Theme.ivory)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Cash").font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint)
                    Text(MK.cash).font(.serifTitle(22)).foregroundStyle(Theme.ivory)
                }
            }
            MKTodayStrip()
            MKNextDay()
            MKGuideCard()
            MKNeedsYou()
            MKCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This week so far").capsLabel()
                    HStack {
                        fig("Sales", "41,300", Theme.ivory); Spacer(); fig("Costs", "34,400", Theme.ivory); Spacer(); fig("Profit", "+6,900", Theme.gain)
                    }
                    Text("Lunch sales are up on last week and the coffee margin holds.").font(.serifTitle(14)).foregroundStyle(Theme.ivoryMuted)
                }
            }
            MKCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Company").capsLabel()
                        Text(MK.company).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ivory)
                        Text("Open · 2 staff · rating 4.3").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("+6,900").font(.figure(15)).foregroundStyle(Theme.gain)
                        Text("Open company").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
                    }
                }
            }
            MKCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last report").capsLabel()
                        Text("Week 6 · +4,100 kr").font(.system(size: 14)).foregroundStyle(Theme.ivory)
                    }
                    Spacer()
                    Text("View report").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
                }
            }
            MKCard {
                HStack {
                    Text("Bank, News, Market and 14 more apps").font(.system(size: 14)).foregroundStyle(Theme.ivory)
                    Spacer()
                    Text("Open Phone").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
                }
            }
        }
        .padding(.horizontal, MK.margin).padding(.top, 56)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func fig(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l).font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint)
            Text(v).font(.figure(16)).foregroundStyle(c)
        }
    }
}

struct MockupBScreen: View {
    enum Mode { case home, dayClose, weekReport }
    var mode: Mode
    var body: some View {
        switch mode {
        case .home:
            MKStage { MockupBFeed(); VStack { Spacer(); MKTabBar() } } overlay: { EmptyView() }
        case .dayClose:
            MKStage { MockupBFeed(); VStack { Spacer(); MKTabBar() }; Color.black.opacity(0.55).ignoresSafeArea() } overlay: { MKDayClose() }
        case .weekReport:
            MKStage {
                VStack(alignment: .leading, spacing: 12) {
                    Text(MK.company).capsLabel()
                    Text("Week 7").font(.serifTitle(34)).foregroundStyle(Theme.ivory)
                    Text("Mon 8 – Sun 14 February 2027").font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
                    MKCard(radius: Theme.Radius.hero) {
                        VStack(alignment: .leading, spacing: 12) {
                            MKNumber()
                            Text("Your best week yet.").font(.serifTitle(20)).foregroundStyle(Theme.ivory)
                        }
                    }
                    MKCard { MKBars() }
                    MKGuideCard()
                    MKCard { MKRecordLine() }
                    Spacer()
                }
                .padding(.horizontal, MK.margin).padding(.top, 70)
                VStack { Spacer(); MKReportFooter() }
            } overlay: { EmptyView() }
        }
    }
}

#Preview("B Home") { MockupBScreen(mode: .home).preferredColorScheme(.dark) }
#Preview("B DayClose") { MockupBScreen(mode: .dayClose).preferredColorScheme(.dark) }
#Preview("B WeekReport") { MockupBScreen(mode: .weekReport).preferredColorScheme(.dark) }
