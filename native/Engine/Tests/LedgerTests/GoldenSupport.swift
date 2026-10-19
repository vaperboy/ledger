import Foundation
import GameCore
import XCTest
import SaveSystem

/// Reference data produced by running the ORIGINAL HTML game (see native/tools/ref). Tests compare the Swift
/// engine with these numbers.
enum Golden {
    static func load(_ name: String) throws -> JSONValue {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    /// A save made by the original game, with its old ids turned into the native ones (as the importer does).
    static func state(_ name: String) throws -> GameState {
        var root = try load(name).object
        LegacyIds.migrate(&root)
        return try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(JSONValue.object(root)))
    }
}

func assertClose(_ a: Double, _ b: Double, tol: Double = 1e-9, _ msg: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    let scale = max(1, abs(b))
    XCTAssertTrue(abs(a - b) <= tol * scale, "\(msg()) expected \(b), got \(a)", file: file, line: line)
}
