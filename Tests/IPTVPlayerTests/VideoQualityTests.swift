import Testing
@testable import IPTVPlayer

@Test func videoQualityNamesTheCommonSizes() {
    #expect(VideoQuality.label(width: 7680, height: 4320) == "8K")
    #expect(VideoQuality.label(width: 3840, height: 2160) == "4K")
    #expect(VideoQuality.label(width: 4096, height: 2160) == "4K")
    #expect(VideoQuality.label(width: 2560, height: 1440) == "QHD")
    #expect(VideoQuality.label(width: 1920, height: 1080) == "FHD")
    #expect(VideoQuality.label(width: 1280, height: 720) == "HD")
    #expect(VideoQuality.label(width: 1024, height: 576) == "SD")
    #expect(VideoQuality.label(width: 720, height: 576) == "SD")
    #expect(VideoQuality.label(width: 640, height: 360) == "SD")
}

@Test func videoQualityCountsCinemaCropsByTheirWidth() {
    #expect(VideoQuality.label(width: 3840, height: 1600) == "4K")
    #expect(VideoQuality.label(width: 1920, height: 800) == "FHD")
    #expect(VideoQuality.label(width: 1280, height: 536) == "HD")
    #expect(VideoQuality.label(width: 1920, height: 1038) == "FHD", "a few missing lines do not change the tag")
}

@Test func videoQualityIsNilUntilTheSizeIsKnown() {
    #expect(VideoQuality.label(width: 0, height: 0) == nil)
    #expect(VideoQuality.label(width: 1920, height: 0) == nil)
    #expect(VideoQuality.label(width: -1, height: 1080) == nil)
}
