/// The quality tag the player shows next to the title, from the size of the decoded picture: "4K", "FHD", "HD", "SD".
/// null while the size is unknown (still loading, or audio only). A wide cinema crop (1920x800) counts as the 16:9 frame of its
/// width, so it is still "FHD". Same rules as VideoQuality.swift in the Apple apps.
String? videoQualityLabel(int width, int height) {
  if (width <= 0 || height <= 0) return null;
  final h = height > width * 9 / 16 ? height : width * 9 / 16;
  if (h >= 4300) return '8K';
  if (h >= 2000) return '4K';
  if (h >= 1300) return 'QHD';
  if (h >= 1000) return 'FHD';
  if (h >= 700) return 'HD';
  return 'SD';
}
