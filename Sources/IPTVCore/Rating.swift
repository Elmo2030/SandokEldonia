import Foundation

/// A title's rating as the list shows it, 0...10 with one decimal. Panels are loose about it: usually `rating` is 0-10 as text or a number,
/// a few use 0-100, many send "0" or "" for "unrated", and some leave it out and only fill `rating_5based` (0-5).
public enum Rating {
    public static func value(rating: String?, fiveBased: String? = nil) -> Double? {
        func number(_ s: String?) -> Double? {
            guard let t = s?.replacingOccurrences(of: ",", with: "."), let r = t.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
            if r.lowerBound > t.startIndex, t[t.index(before: r.lowerBound)] == "-" { return nil }      // a negative number is a broken value
            return Double(t[r])
        }
        func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        if let r = number(rating), r > 0, r <= 100 { return round1(r <= 10 ? r : r / 10) }
        if let five = number(fiveBased), five > 0, five <= 5 { return round1(five * 2) }
        return nil
    }

    /// What is kept in `item.rating`: the normalized 0-10 number as text ("7.5"), so the rating filter and the screens read one scale.
    public static func stored(rating: String?, fiveBased: String? = nil) -> String? {
        value(rating: rating, fiveBased: fiveBased).map { String($0) }
    }

    /// "7.5" in the reader's number style.
    public static func display(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }
}

extension Item {
    /// The rating from the list data, 0...10; nil when the provider has none (an M3U playlist never does).
    public var ratingValue: Double? { Rating.value(rating: rating) }
}
