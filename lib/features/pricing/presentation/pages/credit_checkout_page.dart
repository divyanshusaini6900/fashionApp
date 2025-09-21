import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/razorpay_service_secure.dart';
import '../../../../core/theme/app_theme.dart';

class CreditCheckoutPage extends StatefulWidget {
  final double creditRate;
  final int initialCredits;

  const CreditCheckoutPage({
    super.key,
    required this.creditRate,
    this.initialCredits = 1,
  });

  @override
  State<CreditCheckoutPage> createState() => _CreditCheckoutPageState();
}

class _CreditCheckoutPageState extends State<CreditCheckoutPage> {
  final RazorPayService _razorPayService = RazorPayService();
  bool _isProcessingPayment = false;
  int _selectedCredits = 1;

  @override
  void initState() {
    super.initState();
    _selectedCredits = widget.initialCredits;
    _razorPayService.initialize();
  }

  @override
  void dispose() {
    _razorPayService.dispose();
    super.dispose();
  }

  double get totalAmount => _selectedCredits * widget.creditRate;

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

  void _incrementCredits() {
    setState(() {
      _selectedCredits++;
    });
  }

  void _decrementCredits() {
    if (_selectedCredits > 1) {
      setState(() {
        _selectedCredits--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      'Buy Credits',
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
                        // Credit Selection Section
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
                                'Select Credits',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Credit Selector
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.lightBlue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color:
                                        AppColors.primaryBlue.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      'Number of Credits',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        // Decrement Button
                                        Container(
                                          decoration: BoxDecoration(
                                            color: _selectedCredits <= 1
                                                ? AppColors.lightGrey
                                                : AppColors.primaryBlue,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: IconButton(
                                            onPressed: _selectedCredits <= 1
                                                ? null
                                                : _decrementCredits,
                                            icon: Icon(
                                              Icons.remove,
                                              color: _selectedCredits <= 1
                                                  ? AppColors.textSecondary
                                                  : AppColors.white,
                                              size: 24,
                                            ),
                                          ),
                                        ),

                                        // Credit Display
                                        Container(
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 24),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 32, vertical: 16),
                                          decoration: BoxDecoration(
                                            color: AppColors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: AppColors.primaryBlue,
                                              width: 2,
                                            ),
                                          ),
                                          child: Text(
                                            '$_selectedCredits',
                                            style: GoogleFonts.poppins(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primaryBlue,
                                            ),
                                          ),
                                        ),
                                        // Increment Button
                                        Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryBlue,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: IconButton(
                                            onPressed: _incrementCredits,
                                            icon: const Icon(
                                              Icons.add,
                                              color: AppColors.white,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Tap + or - to adjust the number of credits',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                              _buildPriceRow(
                                  'Credits', '$_selectedCredits credits'),
                              const SizedBox(height: 12),
                              _buildPriceRow('Rate per credit',
                                  '₹${widget.creditRate.toStringAsFixed(0)}'),
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total Amount',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    _formatCurrency(totalAmount),
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryBlue,
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
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
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
                                  'Pay As You Go credits never expire and can be used anytime.'),
                              const SizedBox(height: 8),
                              _buildNoteItem(
                                  'Credits will be added to your account immediately after successful payment.'),
                              const SizedBox(height: 8),
                              _buildNoteItem(
                                  'These credits can be used for any file processing (images, videos, or Excel files).'),
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
                        _formatCurrency(totalAmount),
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
                      onPressed:
                          _isProcessingPayment ? null : _processCreditPayment,
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
                              'Buy $_selectedCredits Credits',
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

  void _processCreditPayment() async {
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
      // Process payment through Razorpay
      await _razorPayService.processPayAsYouGoPayment(
        credits: _selectedCredits,
        amount: totalAmount,
        onSuccess: _onPaymentSuccess,
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

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    setState(() {
      _isProcessingPayment = false;
    });

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Payment successful! $_selectedCredits credits have been added to your account.',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );

    // Navigate back to pricing page
    Navigator.of(context).popUntil((route) => route.isFirst);
    // Show success dialog
    _showPaymentSuccessDialog(response);
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

  void _showPaymentSuccessDialog(PaymentSuccessResponse response) {
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
                'Credits Purchased!',
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
                'Successfully purchased $_selectedCredits credits for ${_formatCurrency(totalAmount)}.',
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
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Credits: $_selectedCredits',
                      style: GoogleFonts.poppins(),
                    ),
                    Text(
                      'Amount: ${_formatCurrency(totalAmount)}',
                      style: GoogleFonts.poppins(),
                    ),
                    Text(
                      'Rate: ₹${widget.creditRate.toStringAsFixed(0)} per credit',
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
}
