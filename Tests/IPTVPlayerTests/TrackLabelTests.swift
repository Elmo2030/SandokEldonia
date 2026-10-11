import Testing
import Foundation
@testable import IPTVPlayer

private func track(_ id: Int, lang: String? = nil, title: String? = nil) -> Track { Track(id: id, type: "audio", lang: lang, title: title, selected: false) }

@Test func aTrackIsNamedByItsLanguageInTheUsersLanguage() {
    let en = Locale(identifier: "en")
    #expect(TrackLabel.text(for: track(1, lang: "eng"), locale: en) == "English")
    #expect(TrackLabel.text(for: track(2, lang: "he"), locale: en) == "Hebrew")
    #expect(TrackLabel.text(for: track(2, lang: "heb"), locale: Locale(identifier: "de")) == "Hebräisch")
}

@Test func theProvidersTitleIsAddedOnlyWhenItSaysMore() {
    let en = Locale(identifier: "en")
    #expect(TrackLabel.text(for: track(1, lang: "eng", title: "Commentary"), locale: en) == "English · Commentary")
    #expect(TrackLabel.text(for: track(1, lang: "eng", title: "english"), locale: en) == "English")
    #expect(TrackLabel.text(for: track(1, lang: "eng", title: "Eng"), locale: en) == "English")
    #expect(TrackLabel.text(for: track(3, title: "Director"), locale: en) == "Director")
}

@Test func anUnknownTrackFallsBackToItsCodeOrNumber() {
    let en = Locale(identifier: "en")
    #expect(TrackLabel.text(for: track(4), locale: en) == "#4")
    #expect(TrackLabel.text(for: track(4, lang: "und"), locale: en) == "#4")
    #expect(TrackLabel.text(for: track(5, lang: "zzz"), locale: en) == "ZZZ")
    #expect(TrackLabel.text(for: track(6, lang: "", title: ""), locale: en) == "#6")
}
