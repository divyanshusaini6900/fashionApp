import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'firebase_service.dart';

class RazorPayService {
  static final RazorPayService _instance = RazorPayService._internal();
  factory RazorPayService() => _instance;
  RazorPayService._internal();

  Razorpay? _razorpay;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  bool _isInitialized = false;

  // Razorpay configuration - Only Key ID needed (public)
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
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      _isInitialized = true;

      if (kDebugMode) print('🏦 RazorPay Service initialized successfully');
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

  /// Process payment for subscription plans (SECURE - Uses Firebase Functions)
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

      // Call Firebase Function to create payment intent
      if (kDebugMode)
        print('🔧 Calling Firebase Function: createPaymentIntent');

      final callable = _functions.httpsCallable('createPaymentIntent');
      final result = await callable.call({
        'planName': planName,
        'planType': planType,
        'amount': amount,
        'durationMonths': durationMonths,
        'creditsPerMonth': creditsPerMonth,
        'billingPeriod': billingPeriod,
        'userId': currentUser.uid,
      });

      final orderData = result.data;

      // Prepare Razorpay options with order details from Firebase Function
      var options = {
        'key': _keyId,
        'amount': orderData['amount'],
        'currency': orderData['currency'],
        'name': 'TechRelieve AI',
        'description': '$planName - $planType ($billingPeriod)',
        'order_id': orderData['orderId'], // Use order ID from Firebase Function
        'prefill': {
          'contact': userPhone,
          'email': userEmail,
          'name': userName,
        },
        'theme': {
          'color': '#6366F1',
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

      if (kDebugMode)
        print('🏦 Opening Razorpay with secure order: ${orderData['orderId']}');
      if (kDebugMode) print('🔧 Razorpay options: $options');

      if (!_isInitialized || _razorpay == null) {
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

      // Provide user-friendly error messages
      String userMessage = _getUserFriendlyErrorMessage(e);

      if (_onPaymentError != null) {
        _onPaymentError!(PaymentFailureResponse(
          1, // Generic error code
          userMessage,
          null,
        ));
      }
    }
  }

  /// Process payment for Pay As You Go credits (SECURE - Uses Firebase Functions)
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

      // Call Firebase Function to create payment intent
      final callable = _functions.httpsCallable('createPayAsYouGoIntent');
      final result = await callable.call({
        'credits': credits,
        'amount': amount,
        'userId': currentUser.uid,
      });

      final orderData = result.data;

      var options = {
        'key': _keyId,
        'amount': orderData['amount'],
        'currency': orderData['currency'],
        'name': 'TechRelieve AI',
        'description': 'Pay As You Go Credits ($credits credits)',
        'order_id': orderData['orderId'], // Use order ID from Firebase Function
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

      if (kDebugMode)
        print(
            '🏦 Opening Razorpay for PAYG with secure order: ${orderData['orderId']}');
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

      // Provide user-friendly error messages
      String userMessage = _getUserFriendlyErrorMessage(e);

      if (_onPaymentError != null) {
        _onPaymentError!(PaymentFailureResponse(
          1,
          userMessage,
          null,
        ));
      }
    }
  }

  /// Handle payment success (Simplified - Webhook handles the heavy lifting)
  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (kDebugMode) print('✅ Payment Success: ${response.paymentId}');

    try {
      // Optional: Verify payment with Firebase Function for additional security
      final callable = _functions.httpsCallable('verifyPayment');
      final result = await callable.call({
        'paymentId': response.paymentId,
        'orderId': response.orderId,
        'signature': response.signature,
      });

      if (result.data['isValid'] == true) {
        if (kDebugMode) print('✅ Payment verified successfully');

        // Call success callback
        if (_onPaymentSuccess != null) {
          _onPaymentSuccess!(response);
        }
      } else {
        if (kDebugMode) print('❌ Payment verification failed');
        if (_onPaymentError != null) {
          _onPaymentError!(PaymentFailureResponse(
            1,
            'Payment verification failed',
            null,
          ));
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Payment verification error: $e');
      // Still call success callback as webhook will handle the processing
      if (_onPaymentSuccess != null) {
        _onPaymentSuccess!(response);
      }
    }
  }

  /// Handle payment error
  void _handlePaymentError(PaymentFailureResponse response) async {
    if (kDebugMode)
      print('❌ Payment Error: ${response.code} - ${response.message}');

    // Call error callback
    if (_onPaymentError != null) {
      _onPaymentError!(response);
    }
  }

  /// Handle external wallet
  void _handleExternalWallet() {
    if (kDebugMode) print('💳 External Wallet Selected');
    if (_onExternalWallet != null) {
      _onExternalWallet!();
    }
  }

  /// Convert technical errors to user-friendly messages
  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    // Firebase Functions errors
    if (errorString.contains('unavailable')) {
      return 'Payment service is temporarily unavailable. Please try again in a moment.';
    }
    if (errorString.contains('permission-denied')) {
      return 'You do not have permission to make payments. Please contact support.';
    }
    if (errorString.contains('unauthenticated')) {
      return 'Please log in again to continue with payment.';
    }
    if (errorString.contains('invalid-argument')) {
      return 'Invalid payment details. Please check your information and try again.';
    }
    if (errorString.contains('failed-precondition')) {
      return 'Payment cannot be processed at this time. Please try again later.';
    }
    if (errorString.contains('deadline-exceeded')) {
      return 'Payment request timed out. Please check your internet connection and try again.';
    }
    if (errorString.contains('resource-exhausted')) {
      return 'Payment service is busy. Please try again in a few minutes.';
    }
    if (errorString.contains('cancelled')) {
      return 'Payment was cancelled. Please try again if you want to continue.';
    }
    if (errorString.contains('already-exists')) {
      return 'A payment is already in progress. Please wait for it to complete.';
    }
    if (errorString.contains('not-found')) {
      return 'Payment service not found. Please contact support.';
    }
    if (errorString.contains('aborted')) {
      return 'Payment was interrupted. Please try again.';
    }
    if (errorString.contains('out-of-range')) {
      return 'Invalid payment amount. Please check your selection.';
    }
    if (errorString.contains('unimplemented')) {
      return 'This payment method is not available yet. Please try a different option.';
    }
    if (errorString.contains('internal')) {
      return 'Something went wrong on our end. Please try again in a moment.';
    }
    if (errorString.contains('data-loss')) {
      return 'Payment data was lost. Please try again.';
    }

    // Network errors
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Please check your internet connection and try again.';
    }

    // Razorpay specific errors
    if (errorString.contains('razorpay')) {
      return 'Payment gateway is temporarily unavailable. Please try again later.';
    }

    // Default fallback
    return 'Payment failed. Please try again or contact support if the problem persists.';
  }
}
