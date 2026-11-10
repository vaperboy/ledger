import Foundation
import GameCore
import XCTest
import SaveSystem
import Businesses

enum Golden {
    static func load(_ name: String) throws -> JSONValue {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    static func state(_ name: String) throws -> GameState {
        var root = try load(name).object
        LegacyIds.migrate(&root)
        var state = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(JSONValue.object(root)))
        Budget.migrate(&state)
        return state
    }
}

func assertClose(_ a: Double, _ b: Double, tol: Double = 1e-9, _ msg: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    let scale = max(1, abs(b))
    XCTAssertTrue(abs(a - b) <= tol * scale, "\(msg()) expected \(b), got \(a)", file: file, line: line)
}

extension GameState {
    mutating func useOriginalInflation() {
        economy.inflationIndex = pow(1 + economy.inflation, Double(week) / 52)
    }
}
