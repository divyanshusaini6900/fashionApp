import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'firebase_service.dart';

class WalletService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Save subscription payment data to wallet collection
  static Future<void> saveSubscriptionPayment({
    required PaymentSuccessResponse response,
    required String planName,
    required double originalAmount,
    required double finalAmount,
    required double discountAmount,
    required int duration,
    required int creditsPerMonth,
    String? appliedCouponCode,
  }) async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final walletData = {
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'paymentId': response.paymentId ?? '',
        'orderId': response.orderId ?? '',
        'signature': response.signature ?? '',
        'paymentType': 'subscription',
        'planName': planName,
        'originalAmount': originalAmount,
        'finalAmount': finalAmount,
        'discountAmount': discountAmount,
        'duration': duration,
        'creditBalance': creditsPerMonth,
        'appliedCouponCode': appliedCouponCode,
        'status': 'success',
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // Save to wallet collection
      await _firestore.collection('wallet').add(walletData);

      if (kDebugMode) print('✅ Subscription payment data saved to wallet collection');
    } catch (e) {
      if (kDebugMode) print('❌ Error saving subscription payment to wallet: $e');
      // Don't throw error to prevent breaking the payment flow
    }
  }

  /// Save credit payment data to wallet collection
  static Future<void> saveCreditPayment({
    required PaymentSuccessResponse response,
    required int credits,
    required double totalAmount,
    required double creditRate,
  }) async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final walletData = {
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'paymentId': response.paymentId ?? '',
        'orderId': response.orderId ?? '',
        'signature': response.signature ?? '',
        'paymentType': 'credits',
        'credits': credits,
        'totalAmount': totalAmount,
        'creditRate': creditRate,
        'status': 'success',
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // Save to wallet collection
      await _firestore.collection('wallet').add(walletData);

      if (kDebugMode) print('✅ Credit payment data saved to wallet collection');
    } catch (e) {
      if (kDebugMode) print('❌ Error saving credit payment to wallet: $e');
      // Don't throw error to prevent breaking the payment flow
    }
  }

  /// Get wallet transactions for current user
  static Future<List<Map<String, dynamic>>> getWalletTransactions() async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final QuerySnapshot snapshot = await _firestore
          .collection('wallet')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID
        return data;
      }).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching wallet transactions: $e');
      throw 'Error fetching wallet transactions: ${e.toString()}';
    }
  }

  /// Get wallet transactions stream for real-time updates
  static Stream<List<Map<String, dynamic>>> getWalletTransactionsStream() {
    final user = FirebaseService.currentUser;
    if (user == null) {
      return Stream.error('User not authenticated');
    }

    return _firestore
        .collection('wallet')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Add document ID
        return data;
      }).toList();
    });
  }
}
