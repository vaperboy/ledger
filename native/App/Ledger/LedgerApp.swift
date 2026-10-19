import SwiftUI
import UIKit

@main
struct LedgerApp: App {
    @StateObject private var store = GameStore()

    init() {
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(red: 0.055, green: 0.050, blue: 0.045, alpha: 0.96)
        tabs.shadowColor = UIColor.white.withAlphaComponent(0.08)
        let faint = UIColor(red: 0.60, green: 0.57, blue: 0.53, alpha: 1), gold = UIColor(red: 0.835, green: 0.690, blue: 0.520, alpha: 1)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = faint; item.normal.titleTextAttributes = [.foregroundColor: faint]
            item.selected.iconColor = gold; item.selected.titleTextAttributes = [.foregroundColor: gold]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        let bars = UINavigationBarAppearance()
        bars.configureWithTransparentBackground()
        bars.titleTextAttributes = [.foregroundColor: UIColor(red: 0.965, green: 0.945, blue: 0.910, alpha: 1)]
        bars.largeTitleTextAttributes = [.foregroundColor: UIColor(red: 0.965, green: 0.945, blue: 0.910, alpha: 1)]
        UINavigationBar.appearance().standardAppearance = bars
        UINavigationBar.appearance().scrollEdgeAppearance = bars
        UITableViewCell.appearance().backgroundColor = UIColor(red: 0.105, green: 0.097, blue: 0.090, alpha: 0.95)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
    }
}
