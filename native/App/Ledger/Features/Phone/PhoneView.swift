import SwiftUI

/// The phone: banking, investing, tax, news, stats, the activity log and settings, plus starting a company.
struct PhoneView: View {
    @EnvironmentObject var store: GameStore
    @State private var path: [PhoneDestination] = []

    private let apps: [(PhoneDestination, String, String)] = [
        (.newCompany, "New company", "plus.square.on.square"),
        (.bank, "Bank", "banknote"),
        (.invest, "Invest", "chart.line.uptrend.xyaxis"),
        (.tax, "Finance", "chart.pie"),
        (.news, "News", "newspaper"),
        (.stats, "Stats", "chart.bar"),
        (.activity, "Activity", "list.bullet.rectangle"),
        (.settings, "Settings", "gearshape"),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                    ForEach(apps, id: \.0) { dest, title, symbol in
                        Button { Haptics.tap(); path.append(dest) } label: {
                            Card {
                                VStack(spacing: 10) {
                                    IconBadge(symbol: symbol, tint: Theme.gold, size: 48)
                                    Text(title).font(.system(.subheadline, design: .default).weight(.semibold)).foregroundStyle(Theme.ivory)
                                }
                                .frame(maxWidth: .infinity, minHeight: 70)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Phone")
            .navigationDestination(for: PhoneDestination.self) { dest in
                Group {
                    switch dest {
                    case .newCompany: NewCompanyView()
                    case .bank: BankView()
                    case .invest: InvestView()
                    case .tax: FinanceView()
                    case .news: NewsView()
                    case .stats: StatsView()
                    case .activity: ActivityView()
                    case .settings: SettingsView()
                    }
                }
            }
            .onAppear { openRequested() }
            .onChange(of: store.phoneDestination) { _, _ in openRequested() }
        }
    }

    private func openRequested() {
        if let d = store.phoneDestination { path = [d]; store.phoneDestination = nil }
    }
}
