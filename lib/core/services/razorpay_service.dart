import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class RazorPayService {
  static final RazorPayService _instance = RazorPayService._internal();
  factory RazorPayService() => _instance;
  RazorPayService._internal();

  Razorpay? _razorpay;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isInitialized = false;

  // Razorpay configuration - Using live credentials for production
  static const String _keyId =
      'rzp_live_nwXGjw3WE3n2jX'; // Live key for production

  // Callbacks for handling payment result
  Function(PaymentSuccessResponse)? _onPaymentSuccess;
  Function(PaymentFailureResponse)? _onPaymentError;
  Function()? _onExternalWallet;

  void initialize() {
    if (_isInitialized) {
      if (kDebugMode) print('🏦 RazorPay Service already initialized');
      return;
    }
    try {
      if (kDebugMode)
        print('🏦 Initializing RazorPay Service with key: $_keyId');
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      _isInitialized = true;
      if (kDebugMode)
        print('✅ RazorPay Service initialized successfully with key: $_keyId');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to initialize RazorPay Service: $e');
      _isInitialized = false;
    }
  }

  void dispose() {
    if (_razorpay != null) {
      _razorpay!.clear();
      _isInitialized = false;
      if (kDebugMode) print('🏦 RazorPay Service disposed');
    }
  }

  /// Process payment for subscription plans
  Future<void> processSubscriptionPayment({
    required String planName,
    required String planType,
    required double amount,
    required int durationMonths,
    required int creditsPerMonth,
    required String billingPeriod,
    Function(PaymentSuccessResponse)? onSuccess,
    Function(PaymentFailureResponse)? onError,
    Function()? onExternalWallet,
  }) async {
    try {
      // Get current user details
      final currentUser = FirebaseService.currentUser;
      if (currentUser == null) {
        if (kDebugMode) print('❌ User not authenticated - currentUser is null');
        throw Exception('User not authenticated. Please login and try again.');
      }

      if (kDebugMode) print('👤 User authenticated: ${currentUser.uid}');
      if (kDebugMode) print('📧 User email: ${currentUser.email}');

      // Get user profile data
      final userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data();
      final userName = userData?['name'] ?? userData?['displayName'] ?? 'User';
      final userEmail = userData?['email'] ?? currentUser.email ?? '';
      final userPhone =
          userData?['phoneNumber'] ?? currentUser.phoneNumber ?? '';

      // Set callbacks
      _onPaymentSuccess = onSuccess;
      _onPaymentError = onError;
      _onExternalWallet = onExternalWallet;

      // Generate unique order ID
      final orderId =
          'order_${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid.substring(0, 8)}';

      // Prepare Razorpay options
      var options = {
        'key': _keyId,
        'amount': (amount * 100).toInt(), // Amount in paise (multiply by 100)
        'name': 'TechRelieve AI',
        'description': '$planName - $planType ($billingPeriod)',
        'prefill': {
          'contact': userPhone,
          'email': userEmail,
          'name': userName,
        },
        'theme': {
          'color': '#6366F1', // Your app's primary color
        },
        'notes': {
          'plan_name': planName,
          'plan_type': planType,
          'billing_period': billingPeriod,
          'duration_months': durationMonths.toString(),
          'credits_per_month': creditsPerMonth.toString(),
          'user_id': currentUser.uid,
        }
      };

      // Save payment intent to Firestore before opening Razorpay
      await _savePaymentIntent(
        orderId: orderId,
        userId: currentUser.uid,
        planName: planName,
        planType: planType,
        amount: amount,
        durationMonths: durationMonths,
        creditsPerMonth: creditsPerMonth,
        billingPeriod: billingPeriod,
      );

      if (kDebugMode) print('🏦 Opening Razorpay with amount: ₹$amount');
      if (kDebugMode) print('🔧 Razorpay options: $options');
      if (kDebugMode) print('🔑 Using Razorpay key: $_keyId');
      if (kDebugMode)
        print(
            '👤 User details - Name: $userName, Email: $userEmail, Phone: $userPhone');

      if (!_isInitialized || _razorpay == null) {
        if (kDebugMode)
          print(
              '❌ Razorpay service not initialized - _isInitialized: $_isInitialized, _razorpay: $_razorpay');
        throw Exception('Razorpay service not properly initialized');
      }

      try {
        _razorpay!.open(options);
        if (kDebugMode) print('✅ Razorpay.open() called successfully');
      } catch (e) {
        if (kDebugMode) print('❌ Error calling Razorpay.open(): $e');
        rethrow;
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error processing payment: $e');
      if (_onPaymentError != null) {
        _onPaymentError!(PaymentFailureResponse(
          1, // Generic error code
          'Payment initialization failed: ${e.toString()}',
          null,
        ));
      }
    }
  }

  /// Process payment for Pay As You Go credits
  Future<void> processPayAsYouGoPayment({
    required int credits,
    required double amount,
    Function(PaymentSuccessResponse)? onSuccess,
    Function(PaymentFailureResponse)? onError,
    Function()? onExternalWallet,
  }) async {
    try {
      final currentUser = FirebaseService.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated. Please login and try again.');
      }

      // Get user profile data
      final userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data();
      final userName = userData?['name'] ?? userData?['displayName'] ?? 'User';
      final userEmail = userData?['email'] ?? currentUser.email ?? '';
      final userPhone =
          userData?['phoneNumber'] ?? currentUser.phoneNumber ?? '';

      // Set callbacks
      _onPaymentSuccess = onSuccess;
      _onPaymentError = onError;
      _onExternalWallet = onExternalWallet;

      // Generate unique order ID
      final orderId =
          'payg_${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid.substring(0, 8)}';

      var options = {
        'key': _keyId,
        'amount': (amount * 100).toInt(), // Amount in paise
        'name': 'TechRelieve AI',
        'description': 'Pay As You Go Credits ($credits credits)',
        'prefill': {
          'contact': userPhone,
          'email': userEmail,
          'name': userName,
        },
        'theme': {
          'color': '#6366F1',
        },
        'notes': {
          'payment_type': 'pay_as_you_go',
          'credits': credits.toString(),
          'user_id': currentUser.uid,
        }
      };

      // Save payment intent to Firestore
      await _savePayAsYouGoIntent(
        orderId: orderId,
        userId: currentUser.uid,
        credits: credits,
        amount: amount,
      );

      if (kDebugMode)
        print('🏦 Opening Razorpay for PAYG with amount: ₹$amount');
      if (kDebugMode) print('🔧 PAYG Razorpay options: $options');

      if (!_isInitialized || _razorpay == null) {
        throw Exception('Razorpay service not properly initialized');
      }

      try {
        _razorpay!.open(options);
        if (kDebugMode) print('✅ PAYG Razorpay.open() called successfully');
      } catch (e) {
        if (kDebugMode) print('❌ Error calling PAYG Razorpay.open(): $e');
        rethrow;
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error processing PAYG payment: $e');
      if (_onPaymentError != null) {
        _onPaymentError!(PaymentFailureResponse(
          1,
          'Payment initialization failed: ${e.toString()}',
          null,
        ));
      }
    }
  }

  /// Handle payment success
  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (kDebugMode) print('✅ Payment Success: ${response.paymentId}');
    if (kDebugMode) print('🎯 Razorpay Order ID: ${response.orderId}');
    try {
      // Update payment status in Firestore
      await _updatePaymentStatus(
        paymentId: response.paymentId!,
        orderId: response.orderId,
        signature: response.signature,
        status: 'success',
      );

      // CRITICAL FIX: Update payment intent with Razorpay order ID
      await _updatePaymentIntentWithRazorpayOrderId(response.orderId);

      // Process subscription/credits based on payment type
      await _processSuccessfulPayment(response.orderId);

      // Call success callback
      if (_onPaymentSuccess != null) {
        _onPaymentSuccess!(response);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error processing successful payment: $e');
    }
  }

  /// Handle payment error
  void _handlePaymentError(PaymentFailureResponse response) async {
    if (kDebugMode)
      print('❌ Payment Error: ${response.code} - ${response.message}');

    try {
      // Update payment status in Firestore if order ID is available
      if (response.error != null && response.error!['metadata'] != null) {
        final orderId = response.error!['metadata']['order_id'];
        if (orderId != null) {
          await _updatePaymentStatus(
            paymentId: null,
            orderId: orderId,
            signature: null,
            status: 'failed',
            errorCode: response.code,
            errorMessage: response.message,
          );
        }
      }

      // Call error callback
      if (_onPaymentError != null) {
        _onPaymentError!(response);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error handling payment failure: $e');
    }
  }

  /// Handle external wallet
  void _handleExternalWallet() {
    if (kDebugMode) print('💳 External Wallet Selected');
    if (_onExternalWallet != null) {
      _onExternalWallet!();
    }
  }

  /// Save payment intent to Firestore
  Future<void> _savePaymentIntent({
    required String orderId,
    required String userId,
    required String planName,
    required String planType,
    required double amount,
    required int durationMonths,
    required int creditsPerMonth,
    required String billingPeriod,
  }) async {
    await _firestore.collection('payment_intents').doc(orderId).set({
      'orderId': orderId,
      'userId': userId,
      'type': 'subscription',
      'planName': planName,
      'planType': planType,
      'amount': amount,
      'durationMonths': durationMonths,
      'creditsPerMonth': creditsPerMonth,
      'billingPeriod': billingPeriod,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Save Pay As You Go payment intent
  Future<void> _savePayAsYouGoIntent({
    required String orderId,
    required String userId,
    required int credits,
    required double amount,
  }) async {
    await _firestore.collection('payment_intents').doc(orderId).set({
      'orderId': orderId,
      'userId': userId,
      'type': 'pay_as_you_go',
      'credits': credits,
      'amount': amount,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update payment status in Firestore
  Future<void> _updatePaymentStatus({
    required String? paymentId,
    required String? orderId,
    required String? signature,
    required String status,
    int? errorCode,
    String? errorMessage,
  }) async {
    if (orderId == null) return;

    final updateData = {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (paymentId != null) updateData['paymentId'] = paymentId;
    if (signature != null) updateData['signature'] = signature;
    if (errorCode != null) updateData['errorCode'] = errorCode;
    if (errorMessage != null) updateData['errorMessage'] = errorMessage;

    await _firestore
        .collection('payment_intents')
        .doc(orderId)
        .update(updateData);
  }

  /// CRITICAL FIX: Update payment intent with Razorpay order ID
  Future<void> _updatePaymentIntentWithRazorpayOrderId(
      String? razorpayOrderId) async {
    if (razorpayOrderId == null) return;

    try {
      final currentUser = FirebaseService.currentUser;
      if (currentUser == null) return;

      // Find the most recent pending payment intent for this user
      final querySnapshot = await _firestore
          .collection('payment_intents')
          .where('userId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final customOrderId = doc.id;

        if (kDebugMode)
          print(
              '🔄 Updating payment intent: $customOrderId with Razorpay order: $razorpayOrderId');

        // Update the document with Razorpay order ID
        await doc.reference.update({
          'razorpayOrderId': razorpayOrderId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Create a new document with Razorpay order ID as the document ID
        final paymentData = doc.data();
        await _firestore
            .collection('payment_intents')
            .doc(razorpayOrderId)
            .set({
          ...paymentData,
          'razorpayOrderId': razorpayOrderId,
          'customOrderId': customOrderId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (kDebugMode)
          print('✅ Payment intent updated with Razorpay order ID');
      } else {
        if (kDebugMode) print('⚠️ No pending payment intent found for user');
      }
    } catch (e) {
      if (kDebugMode)
        print('❌ Error updating payment intent with Razorpay order ID: $e');
    }
  }

  /// Process successful payment and update user subscription/credits
  Future<void> _processSuccessfulPayment(String? orderId) async {
    if (orderId == null) return;

    try {
      final paymentDoc =
          await _firestore.collection('payment_intents').doc(orderId).get();
      if (!paymentDoc.exists) return;

      final paymentData = paymentDoc.data()!;
      final userId = paymentData['userId'];
      final type = paymentData['type'];

      // Let the webhook handle credit allocation for subscriptions
      // Only process Pay As You Go payments on client side
      if (type == 'pay_as_you_go') {
        await _processPayAsYouGoPayment(userId, paymentData);
      } else if (type == 'subscription') {
        // For subscriptions, wait for webhook and add fallback
        if (kDebugMode)
          print('✅ Payment successful - webhook will handle credit allocation');

        // Add fallback mechanism - check after 10 seconds if subscription was created
        _scheduleSubscriptionVerification(userId, paymentData);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error processing successful payment: $e');
    }
  }

  /// Schedule subscription verification as fallback
  void _scheduleSubscriptionVerification(
      String userId, Map<String, dynamic> paymentData) {
    Future.delayed(const Duration(seconds: 10), () async {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        final userData = userDoc.data();
        final subscription = userData?['subscription'];

        if (subscription == null || subscription['isActive'] != true) {
          if (kDebugMode)
            print(
                '⚠️ Webhook failed to create subscription, creating manually');
          await _processSubscriptionPayment(userId, paymentData);
        } else {
          if (kDebugMode)
            print('✅ Subscription created successfully by webhook');
        }
      } catch (e) {
        if (kDebugMode) print('❌ Error in subscription verification: $e');
      }
    });
  }

  /// Process subscription payment
  Future<void> _processSubscriptionPayment(
      String userId, Map<String, dynamic> paymentData) async {
    final currentCredits = await _getUserCredits(userId);
    final planCredits = paymentData['creditsPerMonth'] as int;
    final durationMonths = paymentData['durationMonths'] as int;

    // Calculate expiry date
    final now = DateTime.now();
    final expiryDate = DateTime(now.year, now.month + durationMonths, now.day);

    // Update user subscription
    await _firestore.collection('users').doc(userId).update({
      'subscription': {
        'planName': paymentData['planName'],
        'planType': paymentData['planType'],
        'billingPeriod': paymentData['billingPeriod'],
        'creditsPerMonth': planCredits,
        'startDate': FieldValue.serverTimestamp(),
        'expiryDate': Timestamp.fromDate(expiryDate),
        'isActive': true,
        'lastPayment': FieldValue.serverTimestamp(),
      },
      'credits': currentCredits + planCredits, // Add monthly credits
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    if (kDebugMode) print('✅ Subscription activated for user: $userId');
  }

  /// Process Pay As You Go payment
  Future<void> _processPayAsYouGoPayment(
      String userId, Map<String, dynamic> paymentData) async {
    final currentCredits = await _getUserCredits(userId);
    final purchasedCredits = paymentData['credits'] as int;

    // Add purchased credits to user account
    await _firestore.collection('users').doc(userId).update({
      'credits': currentCredits + purchasedCredits,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    if (kDebugMode) print('✅ Added $purchasedCredits credits to user: $userId');
  }

  /// Get user's current credits
  Future<int> _getUserCredits(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      return userDoc.data()?['credits'] ?? 0;
    } catch (e) {
      if (kDebugMode) print('⚠️ Error getting user credits: $e');
      return 0;
    }
  }
}
