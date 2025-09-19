import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to track and calculate credit usage by category
class CreditUsageService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Credit transaction types
  static const String imageGeneration = 'image_generation';
  static const String videoGeneration = 'video_generation';
  static const String excelGeneration = 'excel_generation';
  static const String creditAddition = 'credit_addition';

  /// Get current usage statistics for a user
  static Future<Map<String, dynamic>> getCurrentUsage(String userId) async {
    try {
      // Get all deduction transactions for the user
      final querySnapshot = await _firestore
          .collection('creditTransactions')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'deduction')
          .orderBy('timestamp', descending: true)
          .get();

      int imagesUsed = 0;
      int videosUsed = 0;
      int excelUsed = 0;
      double totalCreditsUsed = 0.0;

      // Get current credit rates
      final creditRates = await _getCreditRates();

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final reason = data['reason'] as String? ?? '';
        final operationType = data['operationType'] as String? ?? '';
        final amount = (data['amount'] ?? 0.0).toDouble();

        totalCreditsUsed += amount;

        // Categorize based on operationType first, then fallback to reason
        if (operationType == imageGeneration || reason == imageGeneration) {
          imagesUsed += (amount / creditRates['image']!).round() as int;
        } else if (operationType == videoGeneration ||
            reason == videoGeneration) {
          videosUsed += (amount / creditRates['video']!).round() as int;
        } else if (operationType == excelGeneration ||
            reason == excelGeneration) {
          excelUsed += (amount / creditRates['excel']!).round() as int;
        } else if (reason == 'GenSpace_generation') {
          // Legacy reason - assume it's image generation
          imagesUsed += (amount / creditRates['image']!).round() as int;
        }
      }

      return {
        'imagesUsed': imagesUsed,
        'videosUsed': videosUsed,
        'excelUsed': excelUsed,
        'totalCreditsUsed': totalCreditsUsed,
        'imageRate': creditRates['image'],
        'videoRate': creditRates['video'],
        'excelRate': creditRates['excel'],
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error getting current usage: $e');
      return {
        'imagesUsed': 0,
        'videosUsed': 0,
        'excelUsed': 0,
        'totalCreditsUsed': 0.0,
        'imageRate': 1.0,
        'videoRate': 1.0,
        'excelRate': 0.5,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Get usage statistics for a specific time period
  static Future<Map<String, dynamic>> getUsageForPeriod(
    String userId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection('creditTransactions')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'deduction')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('timestamp', descending: true)
          .get();

      int imagesUsed = 0;
      int videosUsed = 0;
      int excelUsed = 0;
      double totalCreditsUsed = 0.0;

      final creditRates = await _getCreditRates();

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final reason = data['reason'] as String? ?? '';
        final operationType = data['operationType'] as String? ?? '';
        final amount = (data['amount'] ?? 0.0).toDouble();

        totalCreditsUsed += amount;

        if (operationType == imageGeneration || reason == imageGeneration) {
          imagesUsed += (amount / creditRates['image']!).round() as int;
        } else if (operationType == videoGeneration ||
            reason == videoGeneration) {
          videosUsed += (amount / creditRates['video']!).round() as int;
        } else if (operationType == excelGeneration ||
            reason == excelGeneration) {
          excelUsed += (amount / creditRates['excel']!).round() as int;
        } else if (reason == 'GenSpace_generation') {
          imagesUsed += (amount / creditRates['image']!).round() as int;
        }
      }

      return {
        'imagesUsed': imagesUsed,
        'videosUsed': videosUsed,
        'excelUsed': excelUsed,
        'totalCreditsUsed': totalCreditsUsed,
        'period': {
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
        },
      };
    } catch (e) {
      print('❌ Error getting usage for period: $e');
      return {
        'imagesUsed': 0,
        'videosUsed': 0,
        'excelUsed': 0,
        'totalCreditsUsed': 0.0,
        'period': {
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
        },
      };
    }
  }

  /// Get real-time usage stream
  static Stream<Map<String, dynamic>> getUsageStream(String userId) {
    return _firestore
        .collection('creditTransactions')
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'deduction')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      int imagesUsed = 0;
      int videosUsed = 0;
      int excelUsed = 0;
      double totalCreditsUsed = 0.0;

      final creditRates = await _getCreditRates();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final reason = data['reason'] as String? ?? '';
        final operationType = data['operationType'] as String? ?? '';
        final amount = (data['amount'] ?? 0.0).toDouble();

        totalCreditsUsed += amount;

        if (operationType == imageGeneration || reason == imageGeneration) {
          imagesUsed += (amount / creditRates['image']!).round() as int;
        } else if (operationType == videoGeneration ||
            reason == videoGeneration) {
          videosUsed += (amount / creditRates['video']!).round() as int;
        } else if (operationType == excelGeneration ||
            reason == excelGeneration) {
          excelUsed += (amount / creditRates['excel']!).round() as int;
        } else if (reason == 'GenSpace_generation') {
          imagesUsed += (amount / creditRates['image']!).round() as int;
        }
      }

      return {
        'imagesUsed': imagesUsed,
        'videosUsed': videosUsed,
        'excelUsed': excelUsed,
        'totalCreditsUsed': totalCreditsUsed,
        'imageRate': creditRates['image'],
        'videoRate': creditRates['video'],
        'excelRate': creditRates['excel'],
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    });
  }

  /// Get current credit rates from Firebase
  static Future<Map<String, double>> _getCreditRates() async {
    try {
      final doc =
          await _firestore.collection('credits').doc('creditUsage').get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'image': (data['image'] ?? 1.0).toDouble(),
          'video': (data['video'] ?? 1.0).toDouble(),
          'excel': (data['excel'] ?? 0.5).toDouble(),
        };
      }
    } catch (e) {
      print('❌ Error getting credit rates: $e');
    }

    // Default rates
    return {
      'image': 1.0,
      'video': 1.0,
      'excel': 0.5,
    };
  }

  /// Update user's credit usage in their document
  static Future<void> updateUserCreditUsage(String userId) async {
    try {
      final usage = await getCurrentUsage(userId);

      await _firestore.collection('users').doc(userId).update({
        'creditUsage': {
          'imagesUsed': usage['imagesUsed'],
          'videosUsed': usage['videosUsed'],
          'excelUsed': usage['excelUsed'],
          'imageRate': usage['imageRate'],
          'videoRate': usage['videoRate'],
          'excelRate': usage['excelRate'],
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error updating user credit usage: $e');
    }
  }
}
