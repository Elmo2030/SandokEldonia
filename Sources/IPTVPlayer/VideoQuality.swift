import Foundation

/// The quality tag the player shows next to the title, from the size of the decoded picture: "4K", "FHD", "HD", "SD".
public enum VideoQuality {
    /// nil while the size is unknown (still loading, or audio only). A wide cinema crop (1920x800) counts as the 16:9 frame of its
    /// width, so it is still "FHD".
    public static func label(width: Double, height: Double) -> String? {
        guard width > 0, height > 0 else { return nil }
        switch max(height, width * 9 / 16) {
        case 4300...: return "8K"
        case 2000...: return "4K"
        case 1300...: return "QHD"
        case 1000...: return "FHD"
        case 700...: return "HD"
        default: return "SD"
        }
    }
}
