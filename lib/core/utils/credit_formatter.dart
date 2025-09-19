/// Utility class for formatting credit values consistently across the app
class CreditFormatter {
  /// Format credit values nicely - show whole numbers without decimal, decimals with 1 decimal place
  static String formatCredits(double credits) {
    if (credits == credits.toInt()) {
      return credits.toInt().toString(); // Show "1" instead of "1.0"
    } else {
      return credits.toStringAsFixed(1); // Show "0.5" for decimals
    }
  }

  /// Format credits with unit (e.g., "1.5 Credits")
  static String formatCreditsWithUnit(double credits) {
    return '${formatCredits(credits)} Credits';
  }

  /// Format credits for display in pricing (e.g., "+1.5")
  static String formatCreditsForPricing(double credits) {
    return '+${formatCredits(credits)}';
  }

  /// Format credits for discounts (e.g., "-0.5")
  static String formatCreditsForDiscount(double credits) {
    return '-${formatCredits(credits)}';
  }
}
