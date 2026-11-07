import SwiftUI

// Shared static pieces of the Home mockups. Only `Theme` is referenced from the app; all data is hard-coded.
// This folder is excluded from the Ledger target in project.yml. No animation anywhere.

enum MK {
    static let company = "Nordvik Café"
    static let cash = "184,200 kr"
    static let margin: CGFloat = 20
    static let apps: [(String, String, Color)] = [
        ("Bank", "building.columns", Color(hex: 0x86B4A0)), ("Accounting", "book.closed", Color(hex: 0xA8B88A)),
        ("Inbox", "envelope", Color(hex: 0xCF9A6A)), ("News", "newspaper", Color(hex: 0x7F9BC4)),
        ("Weather", "sun.max", Color(hex: 0x93A9BD)), ("Stats", "chart.bar", Color(hex: 0x9A94C4)),
        ("World", "globe", Color(hex: 0x78B0A8)), ("Luxury", "diamond", Color(hex: 0xC48CB8)),
        ("Rich list", "trophy", Color(hex: 0xD0A86F)), ("Market", "tag", Color(hex: 0x86B890)),
        ("Reviews", "star", Color(hex: 0xD2B97C)), ("Achievements", "rosette", Color(hex: 0xE0A458)),
        ("Settings", "gearshape", Color(hex: 0xA19B8F)), ("AirStay", "bed.double", Color(hex: 0xCF6A6A)),
        ("TechPro Store", "cpu", Color(hex: 0x7FB088)), ("Atlas Insurance", "shield", Color(hex: 0x7F9FC8)),
        ("Marketplace", "bag", Color(hex: 0x4FA39B)),
    ]
}

struct MKCard<Content: View>: View {
    var radius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// The outlined secondary button (never filled).
struct MKOutlineButton: View {
    var title: String
    var full = false
    var body: some View {
        Text(title).font(.system(size: full ? 16 : 14, weight: .semibold)).foregroundStyle(Theme.ivory)
            .padding(.horizontal, 16).frame(maxWidth: full ? .infinity : nil).frame(height: full ? 46 : 36)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table).strokeBorder(Theme.gold, lineWidth: 1))
    }
}

/// The one filled control.
struct MKNextDay: View {
    var body: some View {
        Text("Next day").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.page)
            .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(Theme.gold))
    }
}

struct MKGuideCard: View {
    var body: some View {
        MKCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next goal · M3").capsLabel()
                Text("Hire your first worker").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ivory)
                Text("Your café is busy enough that one person cannot keep up.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
                    .padding(.bottom, 8)
                MKOutlineButton(title: "Find workers")
            }
        }
    }
}

struct MKNeedsYou: View {
    var body: some View {
        MKCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Needs you").capsLabel()
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A supplier wants cash up front").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.ivory)
                        Text("Pay now or lose your 30-day terms.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer(minLength: 0)
                    Text("4 days left").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.caution)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.caution.opacity(0.1))).overlay(Capsule().strokeBorder(Theme.caution.opacity(0.45), lineWidth: 1))
                }
                Hairline()
                Text("Open in Inbox").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
            }
        }
    }
}

struct MKTodayStrip: View {
    var body: some View {
        HStack {
            Text("Tue · Week 7 · Day 3").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            HStack(spacing: 12) {
                fig("Sales", "41,300", Theme.ivory); fig("Costs", "34,400", Theme.ivory); fig("Profit", "+6,900", Theme.gain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
    private func fig(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint)
            Text(value).font(.figure(13)).foregroundStyle(tint)
        }
    }
}

struct MKAppGrid: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 18) {
            ForEach(MK.apps, id: \.0) { app in
                VStack(spacing: 6) {
                    Image(systemName: app.1).font(.system(size: 26, weight: .light)).foregroundStyle(app.2)
                        .frame(width: 62, height: 62)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.appIcon, style: .continuous).fill(Color(hex: 0x17181A)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.appIcon, style: .continuous).strokeBorder(Color(hex: 0x303134), lineWidth: 1))
                    Text(app.0).font(.system(size: 11.5)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
    }
}

/// The unchanged five-tab bar: Ventures, Group, Home, the custom tab (reads "Pick tab"), Phone.
struct MKTabBar: View {
    var body: some View {
        HStack(spacing: 0) {
            tab("Ventures", "chart.bar"); tab("Group", "person.2"); tab("Home", "house", on: true); tab("Pick tab", "square.grid.2x2"); tab("Phone", "iphone")
        }
        .padding(.horizontal, 6).frame(height: 58)
        .background(Capsule().fill(Theme.surfaceTable)).overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .padding(.horizontal, 14).padding(.bottom, 8)
    }
    private func tab(_ title: String, _ icon: String, on: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 18, weight: .light))
            Text(title).font(.system(size: 10.5))
        }
        .foregroundStyle(on ? Theme.gold : Theme.ivoryMuted)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Capsule().fill(on ? Theme.goldWash : Color.clear))
    }
}

/// The 7-segment day bar: `filled` segments gold, the seventh outlined.
struct MKDayBar: View {
    var filled: Int
    var height: CGFloat = 5
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { i in
                Capsule().fill(i < filled ? Theme.gold : Theme.hairline.opacity(1.4))
                    .overlay(Capsule().strokeBorder(Theme.gold, lineWidth: i == 6 ? 1 : 0)).frame(height: height)
            }
        }
    }
}

/// The day close overlay, 40% of an iPhone 15 screen (852 pt), amber because a decision arrived.
struct MKDayClose: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Tue · Day 3").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).padding(.top, 20)
            Text("+1,850 kr").font(.system(size: 34, weight: .bold).monospacedDigit()).foregroundStyle(Theme.gain)
            Text("New in Inbox: A supplier wants cash up front").font(.system(size: 15)).foregroundStyle(Theme.ivory).multilineTextAlignment(.center)
            Text("Tap to dismiss").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).padding(.top, 4)
            Spacer()
            MKDayBar(filled: 3)
        }
        .padding(.horizontal, 28).padding(.bottom, 40)
        .frame(maxWidth: .infinity).frame(height: 340)
        .background(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22).fill(Theme.caution.opacity(0.13)).background(Theme.walnutRaised))
    }
}

struct MKNumber: View {
    var size: CGFloat = 48
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("+15,300 kr").font(.system(size: size, weight: .bold).monospacedDigit()).foregroundStyle(Theme.gain)
            Text("+11,200 kr vs last week").font(.system(size: 17)).foregroundStyle(Theme.gain)
        }
    }
}

struct MKBars: View {
    var body: some View {
        VStack(spacing: 14) {
            bar("Sales", "96,400 kr", 1.0, Theme.gold)
            bar("Costs", "81,100 kr", 0.84, Theme.ivoryDim)
            bar("Profit", "+15,300 kr", 0.16, Theme.gain)
        }
    }
    private func bar(_ l: String, _ t: String, _ f: CGFloat, _ c: Color) -> some View {
        VStack(spacing: 5) {
            HStack { Text(l).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted); Spacer(); Text(t).font(.figure(13)).foregroundStyle(Theme.ivory) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(c).frame(width: g.size.width * f)
                }
            }.frame(height: 12)
        }
    }
}

struct MKRecordLine: View {
    var body: some View {
        Label("Best week so far", systemImage: "trophy").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
    }
}

struct MKReportFooter: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Full report").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
            MKOutlineButton(title: "Continue", full: true)
        }
        .padding(.horizontal, MK.margin).padding(.bottom, 34)
    }
}

/// Phone-sized stage with the page background; `scrim` dims everything under an overlay.
struct MKStage<Content: View, Overlay: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var overlay: Overlay
    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.page.ignoresSafeArea()
            content
            overlay
        }
        .frame(width: 390, height: 844).clipped()
    }
}
