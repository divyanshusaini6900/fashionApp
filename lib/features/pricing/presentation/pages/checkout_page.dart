import 'package:RatNawnAI_app/features/pricing/coupons/coupons_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pricing_page.dart'; // Import BillingPeriod from pricing_page

import '../../../../core/services/razorpay_service_secure.dart';
import '../../../../core/services/coupon_service.dart'; // Import CouponService
import '../../../../core/services/firebase_service.dart'; // Import FirebaseService
import '../../../../core/theme/app_theme.dart';

class CheckoutPage extends StatefulWidget {
  final String planName;
  final String planType;
  final BillingPeriod billingPeriod;
  final int creditsPerMonth;
  final double creditRate;
  final double monthlyPrice;
  final double totalPrice;
  final double discount;
  final int duration; // in months

  const CheckoutPage({
    super.key,
    required this.planName,
    required this.planType,
    required this.billingPeriod,
    required this.creditsPerMonth,
    required this.creditRate,
    required this.monthlyPrice,
    required this.totalPrice,
    required this.discount,
    required this.duration,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final RazorPayService _razorPayService = RazorPayService();
  final CouponService _couponService = CouponService();
  bool _isProcessingPayment = false;

  // Coupon state variables
  final TextEditingController _couponController = TextEditingController();
  String? _appliedCouponCode;
  double _discountAmount = 0.0;
  bool _isValidatingCoupon = false;

  @override
  void initState() {
    super.initState();
    _razorPayService.initialize();
  }

  @override
  void dispose() {
    _couponController.dispose();
    _razorPayService.dispose();
    super.dispose();
  }

  String _getBillingPeriodText() {
    switch (widget.billingPeriod) {
      case BillingPeriod.monthly:
        return 'Monthly (1 month)';
      case BillingPeriod.quarterly:
        return 'Quarterly (3 months)';
      case BillingPeriod.halfYearly:
        return 'Half-Yearly (6 months)';
      case BillingPeriod.yearly:
        return 'Yearly (12 months)';
    }
  }

  String _getDiscountText() {
    if (widget.discount > 0) {
      return '${widget.discount.toStringAsFixed(0)}% off';
    }
    return '';
  }

  String _formatCurrency(double amount) {
    String formatted = amount.toStringAsFixed(2);
    // Add comma separator for Indian numbering system
    if (amount >= 1000) {
      return '₹${amount.toStringAsFixed(2).replaceAllMapped(
            RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))(\.\d+)?'),
            (Match m) => '${m[1]},',
          )}';
    }
    return '₹$formatted';
  }

  @override
  Widget build(BuildContext context) {
    // Calculate final price after discount
    final finalPrice = widget.totalPrice - _discountAmount;
    return Scaffold(
      backgroundColor: AppColors.backgroundBlue,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowColor,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Checkout',
                      style: GoogleFonts.poppins(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowColor,
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Plan Details Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.borderColor,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.planName,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildDetailRow(
                                  'Plan Type:', _getBillingPeriodText(),
                                  bold: true),
                              const SizedBox(height: 12),
                              _buildDetailRow('Credits per month:',
                                  '${widget.creditsPerMonth} credits'),
                              const SizedBox(height: 12),
                              _buildDetailRow('Credit Rate:',
                                  '₹${widget.creditRate.toStringAsFixed(0)} per credit'),
                              if (widget.discount > 0) ...[
                                const SizedBox(height: 12),
                                _buildDetailRow('Discount:', _getDiscountText(),
                                    valueColor: AppColors.success),
                              ],
                            ],
                          ),
                        ),
                        // Coupon Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.lightBlue.withOpacity(0.1),
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.borderColor,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Apply Coupon',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final selectedCode = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => CouponsPage(
                                            orderAmount: widget.totalPrice,
                                            planType: widget.planType,
                                          ),
                                        ),
                                      );
                                      if (selectedCode != null) {
                                        _couponController.text = selectedCode;
                                        _validateCoupon();
                                      }
                                    },
                                    icon: Icon(Icons.local_offer, size: 16),
                                    label: Text(
                                      'View All',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _couponController,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      decoration: InputDecoration(
                                        hintText: 'Enter coupon code',
                                        hintStyle: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                        filled: true,
                                        fillColor: AppColors.white,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.borderColor,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.borderColor,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                            color: AppColors.primaryBlue,
                                            width: 2,
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        suffixIcon: _appliedCouponCode != null
                                            ? IconButton(
                                                icon: Icon(Icons.clear,
                                                    color: AppColors.error),
                                                onPressed: _removeCoupon,
                                              )
                                            : null,
                                      ),
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: _isValidatingCoupon ||
                                            _appliedCouponCode != null
                                        ? null
                                        : _validateCoupon,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryBlue,
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: _isValidatingCoupon
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      AppColors.white),
                                            ),
                                          )
                                        : Text(
                                            _appliedCouponCode != null
                                                ? 'Applied'
                                                : 'Apply',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.white,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                              if (_appliedCouponCode != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.success.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: AppColors.success,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Coupon "$_appliedCouponCode" applied successfully!',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: AppColors.success,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '- ${_formatCurrency(_discountAmount)}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Price Breakdown Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.borderColor,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Price Breakdown',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildPriceRow('Monthly price',
                                  _formatCurrency(widget.monthlyPrice)),
                              const SizedBox(height: 12),
                              _buildPriceRow(
                                  'Duration', '× ${widget.duration} months'),
                              const SizedBox(height: 12),
                              _buildPriceRow(
                                  'Subtotal',
                                  _formatCurrency(
                                      widget.monthlyPrice * widget.duration)),
                              if (widget.discount > 0) ...[
                                const SizedBox(height: 12),
                                _buildPriceRow(
                                  '${_getBillingPeriodText().split(' ')[0]} discount (${widget.discount.toStringAsFixed(0)}%)',
                                  '- ${_formatCurrency(widget.monthlyPrice * widget.duration - widget.totalPrice)}',
                                  valueColor: AppColors.success,
                                ),
                              ],
                              if (_discountAmount > 0) ...[
                                const SizedBox(height: 12),
                                _buildPriceRow(
                                  'Coupon discount',
                                  '- ${_formatCurrency(_discountAmount)}',
                                  valueColor: AppColors.success,
                                ),
                              ],
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    _formatCurrency(finalPrice),
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Important Notes Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.warningLight.withOpacity(0.1),
                            border: Border.all(
                              color: AppColors.warningLight.withOpacity(0.3),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Important Notes',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildNoteItem(
                                  'All packs are monthly by default. At the end of the month, 50% of unused credits roll over to the next month.'),
                              const SizedBox(height: 8),
                              _buildNoteItem(
                                  'Quarterly, Half-Yearly, and Yearly plans offer respective discounts but credits are credited monthly.'),
                              const SizedBox(height: 8),
                              _buildNoteItem(
                                  'Example: Quarterly Ultra Light Pack (20 credits) = 60 credits for 3 months, credited as 20/month.'),
                              const SizedBox(height: 8),
                              _buildNoteItem(
                                  'Pay As You Go credits (₹160 per credit) are available for additional usage.'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Bottom Section with Total and Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowColor,
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _formatCurrency(finalPrice),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isProcessingPayment ? null : _processPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: AppColors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isProcessingPayment
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.white),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Processing...',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'Proceed to Pay',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Go Back to Plans',
                      style: GoogleFonts.poppins(
                        color: AppColors.primaryBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value,
      {bool bold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildNoteItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6, right: 8),
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.textSecondary,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.warning,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  void _processPayment() async {
    if (_isProcessingPayment) return;

    setState(() {
      _isProcessingPayment = true;
    });

    // Show processing indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Initializing payment...',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.primaryBlue,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      // Get billing period string for service
      String billingPeriodString =
          _getBillingPeriodText().split(' ')[0].toLowerCase();

      // Calculate final amount after discount
      final finalAmount = widget.totalPrice - _discountAmount;

      // Process payment through Razorpay with discount
      await _razorPayService.processSubscriptionPayment(
        planName: widget.planName,
        planType: widget.planType,
        amount: finalAmount, // Use discounted amount
        durationMonths: widget.duration,
        creditsPerMonth: widget.creditsPerMonth,
        billingPeriod: billingPeriodString,
        onSuccess: (response) => _onPaymentSuccess(response, finalAmount),
        onError: _onPaymentError,
        onExternalWallet: _onExternalWallet,
      );
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });

      if (kDebugMode) print('❌ Payment initialization error: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to initialize payment: ${e.toString()}',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _onPaymentSuccess(
      PaymentSuccessResponse response, double finalAmount) async {
    setState(() {
      _isProcessingPayment = false;
    });

    if (kDebugMode) print('🎉 Payment Success - Order ID: ${response.orderId}');
    if (kDebugMode) print('💳 Payment ID: ${response.paymentId}');

    // Record coupon usage if applied
    if (_appliedCouponCode != null && _discountAmount > 0) {
      try {
        final validationResult = await _couponService.validateCoupon(
          code: _appliedCouponCode!,
          orderAmount: widget.totalPrice,
          planType: widget.planType,
        );
        if (validationResult.isValid && validationResult.coupon != null) {
          await _couponService.recordCouponUsage(
            couponId: validationResult.coupon!.id,
            orderId: response.paymentId ?? '',
            discountAmount: _discountAmount,
          );
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ Failed to record coupon usage: $e');
      }
    }

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Payment successful! Your subscription has been activated.',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );

    // Navigate back to pricing page or home
    Navigator.of(context).popUntil((route) => route.isFirst);
    // Optionally show success dialog
    _showPaymentSuccessDialog(response, finalAmount);

    // Schedule subscription verification
    _scheduleSubscriptionVerification(response.orderId);
  }

  /// Schedule subscription verification to ensure it was created
  void _scheduleSubscriptionVerification(String? orderId) {
    if (orderId == null) return;

    Future.delayed(const Duration(seconds: 15), () async {
      try {
        if (kDebugMode) print('🔍 Verifying subscription creation...');

        final walletData = await FirebaseService.getWalletData();
        final subscription = walletData['subscription'];

        if (subscription != null && subscription['isActive'] == true) {
          if (kDebugMode) print('✅ Subscription verified in Firebase');
        } else {
          if (kDebugMode)
            print(
                '❌ Subscription not found in Firebase - webhook may have failed');
          // Could show a notification to user or retry
        }
      } catch (e) {
        if (kDebugMode) print('❌ Error verifying subscription: $e');
      }
    });
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() {
      _isProcessingPayment = false;
    });

    // Show error message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '❌ Payment failed: ${response.message ?? 'Unknown error'}',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onExternalWallet() {
    // Handle external wallet selection
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '💳 Redirecting to external wallet...',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.primaryBlue,
      ),
    );
  }

  void _showPaymentSuccessDialog(
      PaymentSuccessResponse response, double finalAmount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.success, size: 24),
              const SizedBox(width: 8),
              Text(
                'Payment Successful!',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your ${widget.planName} subscription has been activated successfully.',
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment ID: ${response.paymentId}',
                      style: GoogleFonts.robotoMono(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Plan: ${widget.planName}',
                      style: GoogleFonts.poppins(),
                    ),
                    Text(
                      'Amount Paid: ${_formatCurrency(finalAmount)}',
                      style: GoogleFonts.poppins(),
                    ),
                    if (_discountAmount > 0) ...[
                      Text(
                        'Discount Applied: ${_formatCurrency(_discountAmount)}',
                        style: GoogleFonts.poppins(color: AppColors.success),
                      ),
                    ],
                    Text(
                      'Duration: ${widget.duration} month(s)',
                      style: GoogleFonts.poppins(),
                    ),
                    Text(
                      'Credits/Month: ${widget.creditsPerMonth}',
                      style: GoogleFonts.poppins(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
              child: Text(
                'Close',
                style: GoogleFonts.poppins(),
              ),
            ),
          ],
        );
      },
    );
  }

  // Coupon validation methods
  Future<void> _validateCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a coupon code',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isValidatingCoupon = true;
    });

    try {
      final result = await _couponService.validateCoupon(
        code: code,
        orderAmount: widget.totalPrice,
        planType: widget.planType,
      );

      if (result.isValid) {
        setState(() {
          _appliedCouponCode = code.toUpperCase();
          _discountAmount = result.discountAmount;
          _isValidatingCoupon = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message,
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() {
          _isValidatingCoupon = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message,
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isValidatingCoupon = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to validate coupon',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _removeCoupon() {
    setState(() {
      _appliedCouponCode = null;
      _discountAmount = 0.0;
      _couponController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Coupon removed',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.warning,
      ),
    );
  }
}
