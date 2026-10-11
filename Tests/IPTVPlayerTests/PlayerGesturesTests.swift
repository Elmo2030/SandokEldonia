import Testing
import Foundation
@testable import IPTVPlayer

@Test func aTouchBelongsToTheHalfItStartedIn() {
    #expect(PlayerGestures.side(x: 10, width: 800) == .left)
    #expect(PlayerGestures.side(x: 399, width: 800) == .left)
    #expect(PlayerGestures.side(x: 400, width: 800) == .right)
    #expect(PlayerGestures.side(x: 790, width: 800) == .right)
}

@Test func aDragPicksItsAxisOnceAndAfterTheSlop() {
    #expect(PlayerGestures.axis(dx: 4, dy: 6) == nil)
    #expect(PlayerGestures.axis(dx: 30, dy: 8) == .horizontal)
    #expect(PlayerGestures.axis(dx: -3, dy: -25) == .vertical)
    #expect(PlayerGestures.axis(dx: 15, dy: 15) == .horizontal)                   // a tie goes to scrubbing
    #expect(PlayerGestures.axis(dx: .nan, dy: 50) == nil)
}

@Test(arguments: [(0.0, 60.0), (120.0, 60.0), (1200.0, 300.0), (7200.0, 600.0), (36000.0, 600.0), (.nan, 60.0), (-5.0, 60.0)])
func scrubSpanScalesWithTheDurationBetweenAMinuteAndTenMinutes(_ duration: Double, _ span: Double) {
    #expect(PlayerGestures.scrubSpan(duration: duration) == span)
}

@Test func scrubbingMovesFromWhereItStartedAndStaysInsideTheFile() {
    // 2 hours, 800 pt wide: the whole width is ten minutes, so 80 pt are 60 s
    #expect(PlayerGestures.scrubTarget(start: 1000, translation: 80, width: 800, duration: 7200) == 1060)
    #expect(PlayerGestures.scrubTarget(start: 1000, translation: -80, width: 800, duration: 7200) == 940)
    #expect(PlayerGestures.scrubTarget(start: 30, translation: -800, width: 800, duration: 7200) == 0)
    #expect(PlayerGestures.scrubTarget(start: 7190, translation: 800, width: 800, duration: 7200) == 7200)
    #expect(PlayerGestures.scrubTarget(start: 50, translation: 100, width: 0, duration: 7200) == 50)    // no width yet
    #expect(PlayerGestures.scrubTarget(start: 50, translation: .infinity, width: 800, duration: 7200) == 50)
    #expect(PlayerGestures.scrubTarget(start: 50, translation: 100, width: 800, duration: 0) == 50)     // unknown duration
}

@Test func draggingUpRaisesTheLevelAndThreeQuartersOfTheHeightCoverTheRange() {
    #expect(PlayerGestures.level(start: 0.5, translationY: 0, height: 400) == 0.5)
    #expect(PlayerGestures.level(start: 0, translationY: -150, height: 400) == 0.5)
    #expect(abs(PlayerGestures.level(start: 0.5, translationY: 150, height: 400) - 0) < 1e-9)
    #expect(PlayerGestures.level(start: 0.9, translationY: -300, height: 400) == 1)
    #expect(PlayerGestures.level(start: 0.1, translationY: 300, height: 400) == 0)
    #expect(PlayerGestures.level(start: 0.4, translationY: 100, height: 0) == 0.4)
    #expect(PlayerGestures.level(start: 3, translationY: .nan, height: 400) == 1)
}

@Test func onlyALongFastDownwardFlickDismissesThePlayer() {
    #expect(PlayerGestures.verticalEnd(translationY: 200, velocityY: 2200) == .dismiss)
    #expect(PlayerGestures.verticalEnd(translationY: 200, velocityY: 600) == .commit)     // a slow brightness drag down
    #expect(PlayerGestures.verticalEnd(translationY: 60, velocityY: 3000) == .commit)     // too short
    #expect(PlayerGestures.verticalEnd(translationY: -250, velocityY: -3000) == .commit)  // upwards is never dismiss
}

@Test func pinchingStepsFitFillStretchAndBack() {
    #expect(PlayerGestures.scale(after: 1.4, from: .fit) == .fill)
    #expect(PlayerGestures.scale(after: 1.4, from: .fill) == .stretch)
    #expect(PlayerGestures.scale(after: 1.4, from: .stretch) == .stretch)
    #expect(PlayerGestures.scale(after: 0.6, from: .stretch) == .fill)
    #expect(PlayerGestures.scale(after: 0.6, from: .fill) == .fit)
    #expect(PlayerGestures.scale(after: 0.6, from: .fit) == .fit)
    #expect(PlayerGestures.scale(after: 1.05, from: .fit) == .fit)                          // a small pinch is noise
    #expect(PlayerGestures.scale(after: 0.95, from: .fill) == .fill)
    #expect(PlayerGestures.scale(after: .nan, from: .fill) == .fill)
}

@Test func repeatedDoubleTapsOnOneSideAddUp() {
    let t0 = Date(timeIntervalSince1970: 100)
    var a = SkipAccumulator()
    #expect(a.isChaining(now: t0) == false)
    let v1 = a.skip(.right, step: 10, now: t0)
    #expect(v1 == 10)
    #expect(a.isChaining(now: t0.addingTimeInterval(0.5)))
    let v2 = a.skip(.right, step: 10, now: t0.addingTimeInterval(0.5))
    #expect(v2 == 20)
    let v3 = a.skip(.right, step: 10, now: t0.addingTimeInterval(1.2))
    #expect(v3 == 30)             // each tap renews the window
    let v4 = a.skip(.left, step: 10, now: t0.addingTimeInterval(1.5))
    #expect(v4 == -10)             // another side starts over
    let v5 = a.skip(.left, step: 10, now: t0.addingTimeInterval(1.6))
    #expect(v5 == -20)
    #expect(a.isChaining(now: t0.addingTimeInterval(2.7)) == false)                     // a pause of a second ends the chain
    let v6 = a.skip(.left, step: 15, now: t0.addingTimeInterval(5))
    #expect(v6 == -15)
    a.reset()
    #expect(a.count == 0 && a.side == nil)
}

@Test func skipLabelsUseARealMinusSignAndNoUnit() {
    #expect(SkipAccumulator.label(30) == "+30")
    #expect(SkipAccumulator.label(-10) == "\u{2212}10")
    #expect(SkipAccumulator.label(0) == "+0")
}
