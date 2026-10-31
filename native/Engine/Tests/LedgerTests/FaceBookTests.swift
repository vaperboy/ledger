import XCTest
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// Employee portraits: which sheet, exclusive faces, locks that survive a save, candidates giving theirs back, running out.
final class FaceBookTests: XCTestCase {
    private func engine() throws -> GameEngine { try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 5) }

    private func person(_ id: Int, role: String = "cashier", age: Int = 30, name: String = "Emma Berg", hired: Int = 0) -> Person {
        var p = Person(raw: ["id": .number(Double(id)), "name": .string(name), "age": .number(Double(age)), "role": .string(role)])
        p.employerID = hired
        return p
    }

    // MARK: Which sheet

    func testSheetByBusinessAndRole() throws {
        let data = try GameData.bundled()
        let cat = data.catalog
        XCTAssertEqual(FaceBook.style(for: person(1, role: "manager"), trade: cat["cafe"]), .suit)
        XCTAssertEqual(FaceBook.style(for: person(2, role: "lawyer"), trade: cat["law"]), .suit)
        XCTAssertEqual(FaceBook.style(for: person(3, role: "banker"), trade: cat["bank"]), .suit)
        XCTAssertEqual(FaceBook.style(for: person(4, role: "estate"), trade: cat["estate"]), .suit)
        XCTAssertEqual(FaceBook.style(for: person(5, role: "cook"), trade: cat["restaurant"]), .casual)
        XCTAssertEqual(FaceBook.style(for: person(6, role: "plumb"), trade: cat["plumber"]), .casual)
        XCTAssertEqual(FaceBook.style(for: person(7, role: "cleaner"), trade: cat["law"]), .casual)
        XCTAssertEqual(FaceBook.style(for: person(8, role: "recept"), trade: cat["hotel"]), .suit)
        XCTAssertEqual(FaceBook.style(for: person(9, role: "housek"), trade: cat["hotel"]), .casual)
        XCTAssertEqual(FaceBook.style(for: person(10, role: "acct"), trade: nil), .suit)
    }

    // MARK: Exclusive, locked, released

    func testNoTwoPeopleShareAFace() throws {
        var e = try engine()
        e.update { s, data, _ in
            for i in 0..<400 {
                var p = self.person(1000 + i, role: i % 3 == 0 ? "manager" : "cashier", age: 20 + i % 40, name: i % 2 == 0 ? "Emma Berg" : "Lars Dahl", hired: 7)
                p.id = 1000 + i
                s.people[p.id] = p
                FaceBook.assign(personID: p.id, countryCode: "UK", style: FaceBook.style(for: p, trade: nil), state: &s)
            }
        }
        let keys = e.state.people.values.compactMap { $0.faceKey }
        XCTAssertEqual(keys.count, 400)
        XCTAssertEqual(Set(keys).count, keys.count, "every live face is different")
    }

    func testLocksSurviveSaveAndLoadAndHiredKeepFaceForever() throws {
        var e = try engine()
        e.update { s, data, _ in
            s.people[2000] = self.person(2000, hired: 7)
            FaceBook.assign(personID: 2000, countryCode: "UK", style: .casual, state: &s)
            FaceBook.sweep(&s, data: data)
            // the person leaves: the face stays locked
            var p = s.people[2000]!; p.employerID = 0; s.people[2000] = p
            s.week += 40
            FaceBook.sweep(&s, data: data)
        }
        let key = try XCTUnwrap(e.state.people[2000]?.faceKey)
        XCTAssertTrue(FaceBook.locks(e.state).contains(key))
        XCTAssertTrue(e.state.people[2000]!.everHired)
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertEqual(FaceBook.locks(loaded), FaceBook.locks(e.state))
        XCTAssertEqual(loaded.people[2000]?.faceKey, key)
        // a new person cannot get the locked face even though its owner is not employed
        var s2 = loaded
        for i in 0..<1500 {
            s2.people[3000 + i] = person(3000 + i, hired: 0)
            FaceBook.assign(personID: 3000 + i, countryCode: "UK", style: .casual, state: &s2)
        }
        XCTAssertFalse(s2.people.filter { $0.key >= 3000 }.values.contains { $0.faceKey == key })
    }

    func testOldSaveWithoutFacesLoads() throws {
        let e = try engine()
        XCTAssertTrue(FaceBook.locks(e.state).isEmpty)
        XCTAssertNil(e.state.people.values.first?.faceKey)
    }

    func testUnhiredCandidateGivesFaceBack() throws {
        var e = try engine()
        e.update { s, data, _ in
            s.people[4000] = self.person(4000)
            s.people[4001] = self.person(4001, name: "Lars Dahl")
            let a = FaceBook.assign(personID: 4000, countryCode: "UK", style: .casual, state: &s)
            XCTAssertNotNil(a)
            FaceBook.assign(personID: 4001, countryCode: "UK", style: .casual, state: &s)
            // explicit release
            FaceBook.release(personID: 4000, state: &s)
            XCTAssertNil(s.people[4000]?.faceKey)
            // lease runs out
            s.week += FaceBook.leaseWeeks
            FaceBook.sweep(&s, data: data)
            XCTAssertNil(s.people[4001]?.faceKey)
            XCTAssertTrue(FaceBook.locks(s).isEmpty)
            // the freed face can go to someone else
            s.people[4002] = self.person(4002)
            XCTAssertEqual(FaceBook.assign(personID: 4002, countryCode: "UK", style: .casual, state: &s), a)
        }
    }

    func testHiredCandidateIsNotReleased() throws {
        var e = try engine()
        e.update { s, data, _ in
            s.people[5000] = self.person(5000)
            FaceBook.assign(personID: 5000, countryCode: "UK", style: .casual, state: &s)
            var p = s.people[5000]!; p.employerID = 7; s.people[5000] = p
            s.week += 30
            FaceBook.sweep(&s, data: data)
            XCTAssertNotNil(s.people[5000]?.faceKey)
            FaceBook.release(personID: 5000, state: &s)
            XCTAssertNotNil(s.people[5000]?.faceKey)
        }
    }

    func testInitialsWhenEveryFaceIsTaken() throws {
        var e = try engine()
        let total = FaceSheetID.allCases.map { $0.cellCount }.reduce(0, +)
        XCTAssertEqual(total, 504)
        e.update { s, _, _ in
            for i in 0..<(total + 1) {
                s.people[6000 + i] = self.person(6000 + i, role: "cashier", age: 20 + i % 45, name: i % 2 == 0 ? "Emma Berg" : "Lars Dahl", hired: 7)
                FaceBook.assign(personID: 6000 + i, countryCode: i % 3 == 0 ? "IN" : "UK", style: i % 2 == 0 ? .casual : .suit, state: &s)
            }
        }
        let keys = e.state.people.values.compactMap { $0.faceKey }
        XCTAssertEqual(keys.count, total, "every original used once, none repeated")
        XCTAssertEqual(Set(keys).count, total)
        XCTAssertNil(e.state.people[6000 + total]?.faceKey, "the 505th person gets no face")
    }

    func testWidensWhenMatchesAreTakenAndNeverVaries() {
        let traits = FaceTraits(key: "x", gender: "F", ageBand: "Y", region: "S")
        var taken: Set<String> = []
        let tags = FaceCatalog.tags(.casual)
        let best = Set((0..<tags.count).filter { tags[$0].gender == "F" && tags[$0].age == "Y" && tags[$0].region == "S" })
        for _ in best {
            let k = FaceCatalog.pick(traits, style: .casual) { taken.contains($0.string) }!
            XCTAssertEqual(k.sheet, .casual); XCTAssertTrue(best.contains(k.cell))
            taken.insert(k.string)
        }
        // the best matches are gone: the next is a wider match, still an original that nobody holds
        let next = FaceCatalog.pick(traits, style: .casual) { taken.contains($0.string) }!
        XCTAssertFalse(taken.contains(next.string))
        XCTAssertEqual(FaceKey(next.string), next)
        XCTAssertEqual(FaceKey("c12.2"), FaceKey(sheet: .casual, cell: 12), "an old save's variant reads as the plain cell")
    }
}
