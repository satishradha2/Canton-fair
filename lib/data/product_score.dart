/// A quality rating expressed on a stable 0-100 scale.
/// Prices, MOQ and free-text lead times are not comparable without a buying
/// brief, currency conversion and common units; they never influence this score.
class ProductScore {
  static double fromRating(int rating) => rating.clamp(0, 5).toDouble() * 20.0;

  static double leadTimeDays(String value) {
    final match = RegExp(r'^\s*(\d+(?:\.\d+)?)(?:\s*[-–]\s*(\d+(?:\.\d+)?))?\s*(days?|d|weeks?|w|months?|m)\s*$',
        caseSensitive: false).firstMatch(value);
    if (match == null) return double.infinity;
    final amount = double.parse(match.group(2) ?? match.group(1)!);
    final unit = match.group(3)!.toLowerCase();
    return amount * (unit.startsWith('w') ? 7 : unit.startsWith('m') ? 30 : 1);
  }
}
