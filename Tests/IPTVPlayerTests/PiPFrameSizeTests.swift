import Testing
@testable import IPTVPlayer

@Suite struct PiPFrameSizeTests {
    @Test func bigVideoIsScaledDownKeepingItsShape() {
        let s = PiPFrameSize.fit(videoWidth: 1920, videoHeight: 1080)
        #expect(s.width == 960 && s.height == 540)
    }
    @Test func smallVideoIsNotScaledUp() {
        let s = PiPFrameSize.fit(videoWidth: 640, videoHeight: 360)
        #expect(s.width == 640 && s.height == 360)
    }
    @Test func sizesAreEvenAndPortraitStaysPortrait() {
        let s = PiPFrameSize.fit(videoWidth: 1081, videoHeight: 1921)
        #expect(s.width % 2 == 0 && s.height % 2 == 0 && s.height > s.width)
    }
    @Test func unknownSizeFallsBack() {
        #expect(PiPFrameSize.fit(videoWidth: 0, videoHeight: 0) == PiPFrameSize.fallback)
        #expect(PiPFrameSize.fit(videoWidth: .nan, videoHeight: 10) == PiPFrameSize.fallback)
    }
}
