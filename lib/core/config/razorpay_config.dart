import 'package:flutter/foundation.dart';

/// Razorpay Configuration
/// Handles environment-based key selection for test and production
class RazorpayConfig {
  // Private constructor to prevent instantiation
  RazorpayConfig._();

  /// Test/Development Razorpay Key ID
  static const String _testKeyId = 'rzp_test_RGKHJR9OqyYFUF';

  /// Production Razorpay Key ID - Get from environment variable
  static String get _productionKeyId {
    // Try to get from environment variable first
    const String envKey = String.fromEnvironment('RAZORPAY_LIVE_KEY_ID');
    if (envKey.isNotEmpty && envKey != 'rzp_live_YOUR_PRODUCTION_KEY_ID') {
      return envKey;
    }

    // Fallback to actual production key
    return 'rzp_live_nwXGjw3WE3n2jX';
  }

  /// Get the appropriate Razorpay Key ID based on environment
  static String get keyId {
    if (kDebugMode) {
      return _testKeyId;
    } else {
      return _productionKeyId;
    }
  }

  /// Check if running in test mode
  static bool get isTestMode => kDebugMode;

  /// Check if running in production mode
  static bool get isProductionMode => !kDebugMode;

  /// Get environment name for logging
  static String get environmentName => isTestMode ? 'TEST' : 'PRODUCTION';

  /// Validate that production key is set
  static bool get isProductionKeyConfigured {
    if (isProductionMode) {
      return _productionKeyId.isNotEmpty &&
          _productionKeyId.startsWith('rzp_live_');
    }
    return true; // Test mode always has valid key
  }

  /// Get configuration summary for debugging
  static Map<String, dynamic> get configSummary => {
        'environment': environmentName,
        'keyId': keyId,
        'isTestMode': isTestMode,
        'isProductionMode': isProductionMode,
        'isProductionKeyConfigured': isProductionKeyConfigured,
      };
}
