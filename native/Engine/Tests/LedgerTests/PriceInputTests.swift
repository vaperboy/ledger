import XCTest
import GameCore
import Countries
import Businesses

final class PriceInputTests: XCTestCase {
    func testTypedPriceIsConvertedAndHeldInTheRange() throws {
        let cur = try UKCurrency()
        let lo = 10 * cur.rate, hi = 100 * cur.rate
        XCTAssertEqual(PriceInput.parse("25,50", currency: cur, range: lo...hi)?.value ?? 0, 25.5 * cur.rate, accuracy: 1e-9)
        XCTAssertEqual(PriceInput.parse("1 000", currency: cur, range: lo...hi), PriceInput.Result(value: hi, clamped: true))
        XCTAssertEqual(PriceInput.parse("1", currency: cur, range: lo...hi), PriceInput.Result(value: lo, clamped: true))
        XCTAssertFalse(try XCTUnwrap(PriceInput.parse("40", currency: cur, range: lo...hi)).clamped)
        XCTAssertNil(PriceInput.parse("abc", currency: cur, range: lo...hi))
        XCTAssertNil(PriceInput.parse("-5", currency: cur, range: lo...hi))
        XCTAssertNil(PriceInput.parse("", currency: cur, range: lo...hi))
    }

    func testFieldTextShowsCentsOnlyWhenThereAre() throws {
        let cur = try UKCurrency()
        XCTAssertEqual(PriceInput.text(40 * cur.rate, currency: cur), "40")
        XCTAssertEqual(PriceInput.text(12.5 * cur.rate, currency: cur), "12.50")
    }
}
