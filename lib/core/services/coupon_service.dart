// lib/core/services/coupon_service.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class CouponService {
  static final CouponService _instance = CouponService._internal();
  factory CouponService() => _instance;
  CouponService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get all available coupons for the current user
  Future<List<Coupon>> getAvailableCoupons() async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Get user data to fetch phone number
      final userData = await FirebaseService.getUserData();
      final userPhone = userData?['phoneNumber'] ?? user.phoneNumber ?? '';

      final List<Coupon> allCoupons = [];

      // 1. Get public coupons (available for everyone)
      final publicSnapshot = await _firestore
          .collection('coupons')
          .where('isPublic', isEqualTo: true)
          .where('isActive', isEqualTo: true)
          .get();

      for (final doc in publicSnapshot.docs) {
        final coupon = Coupon.fromFirestore(doc);
        if (coupon.isValid()) {
          allCoupons.add(coupon);
        }
      }

      // 2. Get user-specific coupons (by phone number)
      if (userPhone.isNotEmpty) {
        final userSpecificSnapshot = await _firestore
            .collection('coupons')
            .where('isPublic', isEqualTo: false)
            .where('allowedPhoneNumbers', arrayContains: userPhone)
            .where('isActive', isEqualTo: true)
            .get();

        for (final doc in userSpecificSnapshot.docs) {
          final coupon = Coupon.fromFirestore(doc);
          if (coupon.isValid()) {
            allCoupons.add(coupon);
          }
        }
      }

      // Sort by discount percentage (highest first)
      allCoupons.sort((a, b) => b.discountPercentage.compareTo(a.discountPercentage));

      if (kDebugMode) {
        print('📱 Found ${allCoupons.length} valid coupons for user');
      }

      return allCoupons;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error fetching coupons: $e');
      }
      throw Exception('Failed to fetch coupons: $e');
    }
  }

  /// Validate and apply a coupon code
  Future<CouponValidationResult> validateCoupon({
    required String code,
    required double orderAmount,
    required String planType,
  }) async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) {
        return CouponValidationResult(
          isValid: false,
          message: 'User not authenticated',
        );
      }

      // Get user data
      final userData = await FirebaseService.getUserData();
      final userPhone = userData?['phoneNumber'] ?? user.phoneNumber ?? '';

      // Find coupon by code
      final couponSnapshot = await _firestore
          .collection('coupons')
          .where('code', isEqualTo: code.toUpperCase())
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (couponSnapshot.docs.isEmpty) {
        return CouponValidationResult(
          isValid: false,
          message: 'Invalid coupon code',
        );
      }

      final couponDoc = couponSnapshot.docs.first;
      final coupon = Coupon.fromFirestore(couponDoc);

      // Check if coupon is expired
      if (!coupon.isValid()) {
        return CouponValidationResult(
          isValid: false,
          message: 'This coupon has expired',
        );
      }

      // Check if it's a user-specific coupon
      if (!coupon.isPublic) {
        if (userPhone.isEmpty || !coupon.allowedPhoneNumbers.contains(userPhone)) {
          return CouponValidationResult(
            isValid: false,
            message: 'This coupon is not available for your account',
          );
        }
      }

      // Check minimum order amount
      if (coupon.minimumAmount > 0 && orderAmount < coupon.minimumAmount) {
        return CouponValidationResult(
          isValid: false,
          message: 'Minimum order amount of ₹${coupon.minimumAmount.toStringAsFixed(0)} required',
        );
      }

      // Check applicable plan types
      if (coupon.applicablePlans.isNotEmpty && !coupon.applicablePlans.contains(planType)) {
        return CouponValidationResult(
          isValid: false,
          message: 'This coupon is not valid for the selected plan',
        );
      }

      // Check usage limit
      if (coupon.usageLimit > 0) {
        final usageCount = await _getCouponUsageCount(coupon.id, user.uid);
        if (usageCount >= coupon.usageLimit) {
          return CouponValidationResult(
            isValid: false,
            message: 'You have already used this coupon maximum times',
          );
        }
      }

      // Calculate discount
      double discountAmount = 0;
      if (coupon.discountType == 'percentage') {
        discountAmount = orderAmount * (coupon.discountPercentage / 100);
        if (coupon.maxDiscountAmount > 0) {
          discountAmount = discountAmount.clamp(0, coupon.maxDiscountAmount);
        }
      } else {
        discountAmount = coupon.discountAmount.clamp(0, orderAmount);
      }

      return CouponValidationResult(
        isValid: true,
        message: 'Coupon applied successfully!',
        coupon: coupon,
        discountAmount: discountAmount,
      );

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error validating coupon: $e');
      }
      return CouponValidationResult(
        isValid: false,
        message: 'Failed to validate coupon',
      );
    }
  }

  /// Get coupon usage count for a user
  Future<int> _getCouponUsageCount(String couponId, String userId) async {
    try {
      final snapshot = await _firestore
          .collection('coupon_usage')
          .where('couponId', isEqualTo: couponId)
          .where('userId', isEqualTo: userId)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Record coupon usage
  Future<void> recordCouponUsage({
    required String couponId,
    required String orderId,
    required double discountAmount,
  }) async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) return;

      await _firestore.collection('coupon_usage').add({
        'couponId': couponId,
        'userId': user.uid,
        'orderId': orderId,
        'discountAmount': discountAmount,
        'usedAt': FieldValue.serverTimestamp(),
      });

      // Increment usage count in coupon document
      await _firestore.collection('coupons').doc(couponId).update({
        'totalUsageCount': FieldValue.increment(1),
      });

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error recording coupon usage: $e');
      }
    }
  }
}

/// Coupon model
class Coupon {
  final String id;
  final String code;
  final String description;
  final String discountType; // 'percentage' or 'fixed'
  final double discountPercentage;
  final double discountAmount;
  final double maxDiscountAmount;
  final double minimumAmount;
  final bool isPublic;
  final List<String> allowedPhoneNumbers;
  final List<String> applicablePlans;
  final DateTime? expiryDate;
  final bool isActive;
  final int usageLimit; // 0 = unlimited
  final int totalUsageCount;

  Coupon({
    required this.id,
    required this.code,
    required this.description,
    required this.discountType,
    required this.discountPercentage,
    required this.discountAmount,
    required this.maxDiscountAmount,
    required this.minimumAmount,
    required this.isPublic,
    required this.allowedPhoneNumbers,
    required this.applicablePlans,
    this.expiryDate,
    required this.isActive,
    required this.usageLimit,
    required this.totalUsageCount,
  });

  factory Coupon.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return Coupon(
      id: doc.id,
      code: data['code'] ?? '',
      description: data['description'] ?? '',
      discountType: data['discountType'] ?? 'percentage',
      discountPercentage: (data['discountPercentage'] ?? 0).toDouble(),
      discountAmount: (data['discountAmount'] ?? 0).toDouble(),
      maxDiscountAmount: (data['maxDiscountAmount'] ?? 0).toDouble(),
      minimumAmount: (data['minimumAmount'] ?? 0).toDouble(),
      isPublic: data['isPublic'] ?? true,
      allowedPhoneNumbers: List<String>.from(data['allowedPhoneNumbers'] ?? []),
      applicablePlans: List<String>.from(data['applicablePlans'] ?? []),
      expiryDate: data['expiryDate'] != null 
          ? (data['expiryDate'] as Timestamp).toDate() 
          : null,
      isActive: data['isActive'] ?? true,
      usageLimit: data['usageLimit'] ?? 0,
      totalUsageCount: data['totalUsageCount'] ?? 0,
    );
  }

  bool isValid() {
    if (!isActive) return false;
    if (expiryDate != null && DateTime.now().isAfter(expiryDate!)) return false;
    return true;
  }

  String getDiscountText() {
    if (discountType == 'percentage') {
      return '${discountPercentage.toStringAsFixed(0)}% OFF';
    } else {
      return '₹${discountAmount.toStringAsFixed(0)} OFF';
    }
  }

  String getMaxDiscountText() {
    if (discountType == 'percentage' && maxDiscountAmount > 0) {
      return 'Max ₹${maxDiscountAmount.toStringAsFixed(0)}';
    }
    return '';
  }
}

/// Coupon validation result
class CouponValidationResult {
  final bool isValid;
  final String message;
  final Coupon? coupon;
  final double discountAmount;

  CouponValidationResult({
    required this.isValid,
    required this.message,
    this.coupon,
    this.discountAmount = 0,
  });
}