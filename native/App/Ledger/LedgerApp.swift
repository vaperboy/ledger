import SwiftUI
import UIKit

@main
struct LedgerApp: App {
    @StateObject private var store = GameStore()

    init() {
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.043, alpha: 0.97)
        tabs.shadowColor = UIColor.white.withAlphaComponent(0.08)
        let faint = UIColor(red: 0.643, green: 0.647, blue: 0.643, alpha: 1), gold = UIColor(red: 0.985, green: 0.925, blue: 0.810, alpha: 1)
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
        UITableViewCell.appearance().backgroundColor = UIColor(red: 0.105, green: 0.112, blue: 0.120, alpha: 0.95)
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
