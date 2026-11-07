import XCTest
import SwiftUI
@testable import Ledger

/// The popup rules: three categories, content-driven heights with no minimum, one tone per event, swipe-to-close, confetti.
final class PopupSizingTests: XCTestCase {
    private let phone: CGFloat = 852

    func testThereAreExactlyThreeCategories() {
        XCTAssertEqual(PopupCategory.allCases, [.compact, .medium, .detail])
    }

    func testCategoryRoomsGrowAndNeverFillTheScreen() {
        let c: CGFloat = PopupLayout.maxHeight(.compact, screenHeight: phone)
        let m: CGFloat = PopupLayout.maxHeight(.medium, screenHeight: phone)
        let d: CGFloat = PopupLayout.maxHeight(.detail, screenHeight: phone)
        XCTAssertLessThan(c, m)
        XCTAssertLessThan(m, d)
        XCTAssertLessThan(d, phone)
    }

    func testOnlyASelfScrollingRequestIsADetailPanelByDefault() {
        XCTAssertEqual(PopupLayout.category(for: .tall), .detail)
        XCTAssertEqual(PopupLayout.category(for: .fit), .medium)
        XCTAssertEqual(PopupLayout.category(for: .fitBleed), .medium)
    }

    func testWideScreenWidthsFollowTheCategory() {
        XCTAssertLessThan(PopupLayout.regularCardWidth(.compact), PopupLayout.regularCardWidth(.medium))
        XCTAssertLessThan(PopupLayout.regularCardWidth(.medium), PopupLayout.regularCardWidth(.detail))
    }

    func testOldVariantsMapToTones() {
        XCTAssertEqual(PopupTone(variant: .destructive), .danger)
        XCTAssertEqual(PopupTone(variant: .alert), .danger)
        XCTAssertEqual(PopupTone(variant: .expensive), .investment)
        XCTAssertEqual(PopupTone(variant: .reward), .investment)
        XCTAssertEqual(PopupTone(variant: .report), .info)
        XCTAssertEqual(PopupTone(variant: .standard), .neutral)
    }

    func testEveryToneHasItsOwnColourAndSymbol() {
        let symbols: [String] = PopupTone.allCases.map { (t: PopupTone) -> String in t.defaultSymbol }
        XCTAssertEqual(Set(symbols).count, PopupTone.allCases.count)
    }

    func testSwipeDownDismissRule() {
        XCTAssertFalse(PopupSizing.shouldDismiss(translation: 40, predictedEnd: 90))
        XCTAssertTrue(PopupSizing.shouldDismiss(translation: 120, predictedEnd: 130))
        XCTAssertTrue(PopupSizing.shouldDismiss(translation: 60, predictedEnd: 400))
        XCTAssertFalse(PopupSizing.shouldDismiss(translation: -200, predictedEnd: -300))
    }

    func testDragNeverGoesUpAndFadesTheBackdrop() {
        XCTAssertEqual(PopupSizing.dragOffset(translation: -50), 0)
        XCTAssertEqual(PopupSizing.dragOffset(translation: 100), 90, accuracy: 0.001)
        XCTAssertEqual(PopupSizing.dragDimFactor(offset: 0), 1, accuracy: 0.001)
        XCTAssertEqual(PopupSizing.dragDimFactor(offset: 400), 0.4, accuracy: 0.001)
        XCTAssertEqual(PopupSizing.dragDimFactor(offset: 4000), 0.4, accuracy: 0.001)
    }

    func testVariantCues() {
        XCTAssertEqual(PopupVariant.reward.appearCue, .success)
        XCTAssertEqual(PopupVariant.alert.appearCue, .warning)
        XCTAssertEqual(PopupVariant.destructive.appearCue, .warning)
        XCTAssertEqual(PopupVariant.standard.appearCue, .tap)
        XCTAssertEqual(PopupVariant.expensive.appearCue, .tap)
    }

    func testConfettiIsRepeatableAndFades() {
        let a: [ConfettiPiece] = ConfettiPiece.make(count: 30)
        XCTAssertEqual(a.count, 30)
        XCTAssertEqual(a, ConfettiPiece.make(count: 30))
        XCTAssertEqual(ConfettiPiece.make(count: 0).count, 0)
        XCTAssertEqual(ConfettiPiece.opacity(at: 0.5), 1)
        XCTAssertEqual(ConfettiPiece.opacity(at: ConfettiPiece.duration), 0, accuracy: 0.001)
        for p in a {
            XCTAssertLessThan(p.position(at: 0.3).y, p.position(at: 1.8).y)
        }
    }
}
