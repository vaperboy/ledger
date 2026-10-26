// swift-tools-version:5.9
import PackageDescription

// Ledger game engine. Pure Swift (Foundation only), so it builds and tests on macOS, iOS and Linux.
// The SwiftUI app lives in ../App and depends on these libraries.
//
//   GameCore     state models, seeded random numbers, calendar, JSON helpers, balance settings
//   Countries    country data (data-driven), currency and exchange rates, taxes, formatting
//   Employees    staff, wages and payroll
//   Finance      cash ledger, loans, credit, net worth, personal tax
//   Businesses   trade definitions and the weekly company model
//   Investments  stocks, funds, deposits
//   Events       random events and inbox decisions
//   SaveSystem   legacy-save import, native saves, backups, migrations
//   Simulation   the order in which one day / week passes
let package = Package(
    name: "LedgerEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LedgerEngine", targets: ["GameCore", "Countries", "Employees", "Finance", "Businesses", "Investments", "Events", "SaveSystem", "Simulation"]),
    ],
    targets: [
        .target(name: "GameCore"),
        .target(name: "Countries", dependencies: ["GameCore"], resources: [.copy("Resources")]),
        .target(name: "Employees", dependencies: ["GameCore", "Countries"]),
        .target(name: "Finance", dependencies: ["GameCore", "Countries", "Employees"]),
        .target(name: "Businesses", dependencies: ["GameCore", "Countries", "Employees", "Finance"], resources: [.copy("Resources")]),
        .target(name: "Investments", dependencies: ["GameCore", "Countries", "Finance"]),
        .target(name: "Events", dependencies: ["GameCore", "Countries", "Finance", "Businesses"], resources: [.copy("Resources")]),
        .target(name: "SaveSystem", dependencies: ["GameCore", "Countries", "Finance", "Businesses"]),
        .target(name: "Simulation", dependencies: ["GameCore", "Countries", "Employees", "Finance", "Businesses", "Investments", "Events", "SaveSystem"]),
        .testTarget(
            name: "LedgerTests",
            dependencies: ["GameCore", "Countries", "Employees", "Finance", "Businesses", "Investments", "Events", "SaveSystem", "Simulation"],
            resources: [.copy("Golden")]
        ),
    ]
)
