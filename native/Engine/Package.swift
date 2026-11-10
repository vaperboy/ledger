import PackageDescription

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
