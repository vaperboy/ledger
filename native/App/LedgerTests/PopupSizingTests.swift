import XCTest
import SwiftUI
@testable import Ledger

/// The pure rules behind the five popup size classes: which class a measured card gets, hysteresis, widths, swipe-to-dismiss, confetti.
final class PopupSizingTests: XCTestCase {
    private let phone: CGFloat = 800

    private func pick(_ h: CGFloat, requested: CenterSheetSize = .fit, previous: PopupSizeClass? = nil, screen: CGFloat? = nil) -> PopupSizeClass {
        PopupSizing.sizeClass(requested: requested, cardHeight: h, screenHeight: screen ?? phone, previous: previous)
    }

    func testOneLineAndAButtonIsAToast() {
        XCTAssertEqual(pick(130), .toast)
        XCTAssertEqual(pick(PopupSizing.toastMaxHeight), .toast)
    }

    func testAFewRowsAreCompact() {
        XCTAssertEqual(pick(PopupSizing.toastMaxHeight + 1), .compact)
        XCTAssertEqual(pick(300), .compact)
        XCTAssertEqual(pick(PopupSizing.compactMaxHeight), .compact)
    }

    func testAnOrdinaryCardIsStandard() {
        XCTAssertEqual(pick(PopupSizing.compactMaxHeight + 1), .standard)
        XCTAssertEqual(pick(400), .standard)
        XCTAssertEqual(pick(phone * PopupSizing.standardFraction), .standard)
    }

    func testTallContentIsTall() {
        XCTAssertEqual(pick(phone * PopupSizing.standardFraction + 1), .tall)
        XCTAssertEqual(pick(2000), .tall)
    }

    func testRequestedTallIsAlwaysFull() {
        XCTAssertEqual(pick(100, requested: .tall), .full)
        XCTAssertEqual(pick(0, requested: .tall), .full)
        XCTAssertEqual(pick(2000, requested: .tall, previous: .toast), .full)
    }

    func testFitBleedClassifiesLikeFit() {
        XCTAssertEqual(pick(200, requested: .fitBleed), pick(200, requested: .fit))
        XCTAssertEqual(pick(500, requested: .fitBleed), pick(500, requested: .fit))
    }

    func testUnmeasuredIsStandardOrKeepsThePreviousClass() {
        XCTAssertEqual(pick(0), .standard)
        XCTAssertEqual(pick(-1), .standard)
        XCTAssertEqual(pick(0, previous: .compact), .compact)
    }

    func testHysteresisKeepsTheClassJustPastItsBound() {
        let past: CGFloat = PopupSizing.toastMaxHeight + PopupSizing.hysteresis - 1
        XCTAssertEqual(pick(past, previous: .toast), .toast)
        XCTAssertEqual(pick(past), .compact)
        let well: CGFloat = PopupSizing.toastMaxHeight + PopupSizing.hysteresis + 1
        XCTAssertEqual(pick(well, previous: .toast), .compact)
    }

    func testHysteresisHoldsAtTheLowerBoundToo() {
        let under: CGFloat = PopupSizing.toastMaxHeight - PopupSizing.hysteresis + 1
        XCTAssertEqual(pick(under, previous: .compact), .compact)
        XCTAssertEqual(pick(under), .toast)
    }

    func testClassesGrowWithHeight() {
        var last: PopupSizeClass = .toast
        var h: CGFloat = 40
        while h <= 1200 {
            let c: PopupSizeClass = pick(h)
            XCTAssertGreaterThanOrEqual(c, last)
            last = c
            h += 10
        }
        XCTAssertEqual(last, .tall)
    }

    func testShortScreenKeepsStandardUpToItsFraction() {
        let screen: CGFloat = 390
        XCTAssertEqual(PopupSizing.upperBound(of: .standard, screenHeight: screen), PopupSizing.compactMaxHeight)
        XCTAssertEqual(pick(340, screen: screen), .tall)
        XCTAssertEqual(pick(PopupSizing.compactMaxHeight, screen: screen), .compact)
    }

    func testWidthsGrowWithTheClass() {
        var last: CGFloat = 0
        for c in PopupSizeClass.allCases {
            XCTAssertGreaterThan(PopupSizing.maxWidth(of: c), last)
            last = PopupSizing.maxWidth(of: c)
        }
        XCTAssertLessThanOrEqual(last, 600)
    }

    func testRoomAndFullHeight() {
        XCTAssertEqual(PopupSizing.room(screenHeight: 800), 640, accuracy: 0.01)
        XCTAssertEqual(PopupSizing.room(screenHeight: 400), 376, accuracy: 0.01)
        XCTAssertEqual(PopupSizing.fullHeight(screenHeight: 800), 736, accuracy: 0.01)
        XCTAssertEqual(PopupSizing.fullHeight(screenHeight: 200), 260, accuracy: 0.01)
    }

    func testOnlyTallAndFullSwipe() {
        XCTAssertFalse(PopupSizeClass.toast.isSwipeable)
        XCTAssertFalse(PopupSizeClass.compact.isSwipeable)
        XCTAssertFalse(PopupSizeClass.standard.isSwipeable)
        XCTAssertTrue(PopupSizeClass.tall.isSwipeable)
        XCTAssertTrue(PopupSizeClass.full.isSwipeable)
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

    func testReduceMotionRemovesTheEntrance() {
        for c in PopupSizeClass.allCases {
            XCTAssertEqual(PopupSizing.entryScale(of: c, reduceMotion: true), 1)
            XCTAssertEqual(PopupSizing.entryRise(of: c, reduceMotion: true), 0)
            XCTAssertLessThan(PopupSizing.entryScale(of: c, reduceMotion: false), 1)
        }
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
