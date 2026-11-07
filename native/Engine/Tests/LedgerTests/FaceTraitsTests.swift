import XCTest
import GameCore
import Employees

final class FaceTraitsTests: XCTestCase {
    private func person(_ id: Int, _ name: String, _ age: Int) -> Person {
        Person(raw: ["id": .number(Double(id)), "name": .string(name), "age": .number(Double(age))])
    }

    func testGenderAgeAndRegion() {
        let a = FaceTraits.of(person(1, "Emma Berg", 28), countryCode: "UK")
        XCTAssertEqual(a.gender, "F"); XCTAssertEqual(a.ageBand, "Y"); XCTAssertEqual(a.region, "U")
        let b = FaceTraits.of(person(2, "Lars Dahl", 47), countryCode: "JP")
        XCTAssertEqual(b.gender, "M"); XCTAssertEqual(b.ageBand, "M"); XCTAssertEqual(b.region, "E")
        XCTAssertEqual(FaceTraits.ageBand(60), "O")
        XCTAssertNil(FaceTraits.of(person(3, "Ola Nord", 30), countryCode: "ZZ").region)
        XCTAssertEqual(FaceTraits.region(countryCode: "ng"), "A")
    }

    func testStable() {
        let p = person(9, "Max Hart", 40)
        XCTAssertEqual(FaceTraits.of(p, countryCode: "DE"), FaceTraits.of(p, countryCode: "DE"))
        XCTAssertEqual(FaceTraits.of(p, countryCode: "DE").key, "p9-Max Hart")
    }
}
