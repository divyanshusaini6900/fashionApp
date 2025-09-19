// File: lib/core/services/free_credits_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for managing "free credits" configuration and applying it to users.
///
/// Firestore structure supported:
/// Collection: FreeCredits
///   - Document: (any ID, e.g., 'config' OR an auto ID like 'TK0MkrgNsJPCA4jLZUv')
///       Fields (any one of):
///         - FreeCredits: number
///         - freeCredits: number
///         - amount: number
///         - credits: number
class FreeCreditsService {
  FreeCreditsService._();
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fetch the free credits value.
  ///
  /// If [docId] is provided, it tries to read that document inside `FreeCredits`.
  /// If not provided, it will read the **first** document in the `FreeCredits` collection.
  ///
  /// Returns 0.0 if nothing is found or on error.
  static Future<double> getFreeCreditsAmount({String? docId}) async {
    try {
      Map<String, dynamic>? data;

      if (docId != null && docId.isNotEmpty) {
        final doc = await _db
            .collection('FreeCredits')
            .doc(docId)
            .get()
            .timeout(const Duration(seconds: 20));
        if (doc.exists) data = doc.data();
      } else {
        final snap = await _db
            .collection('FreeCredits')
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 20));
        if (snap.docs.isNotEmpty) data = snap.docs.first.data();
      }

      if (data == null) {
        // Nothing found
        return 0.0;
      }

      final dynamic raw = data['FreeCredits'] ??
          data['freeCredits'] ??
          data['amount'] ??
          data['credits'];

      if (raw == null) return 0.0;

      // Convert to double safely
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw.toString());
      return parsed ?? 0.0;
    } catch (e) {
      // Log & fallback
      // ignore: avoid_print
      print('❌ getFreeCreditsAmount error: $e');
      return 0.0;
    }
  }

  /// Return the raw config map from `FreeCredits` (by ID or first doc).
  /// Useful if you want to see all fields.
  static Future<Map<String, dynamic>?> getFreeCreditsConfig({String? docId}) async {
    try {
      if (docId != null && docId.isNotEmpty) {
        final doc = await _db
            .collection('FreeCredits')
            .doc(docId)
            .get()
            .timeout(const Duration(seconds: 20));
        return doc.data();
      } else {
        final snap = await _db
            .collection('FreeCredits')
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 20));
        if (snap.docs.isNotEmpty) return snap.docs.first.data();
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('❌ getFreeCreditsConfig error: $e');
      return null;
    }
  }

  /// Apply a free credits amount to a user document at `users/{userId}`.
  ///
  /// This does **not** add—to add, read the existing balance first and sum it yourself,
  /// then call this method with the final amount you want to set.
  static Future<void> applyFreeCreditsToUser({
    required String userId,
    required double creditsAmount,
  }) async {
    try {
      await _db.collection('users').doc(userId).update({
        'creditBalance': creditsAmount,
        'freeCreditsApplied': true,
        'freeCreditsAmount': creditsAmount,
        'freeCreditsAppliedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore: avoid_print
      print('❌ applyFreeCreditsToUser error: $e');
      rethrow;
    }
  }

  /// Convenience helper to fetch and then apply free credits to a user by ID.
  /// - If [docId] is omitted, it reads the first doc in `FreeCredits`.
  /// - Returns the amount applied (0.0 on failure).
  static Future<double> fetchAndApplyFreeCreditsToUser({
    required String userId,
    String? docId,
  }) async {
    final amount = await getFreeCreditsAmount(docId: docId);
    if (amount <= 0) return 0.0;

    await applyFreeCreditsToUser(userId: userId, creditsAmount: amount);
    return amount;
  }
}