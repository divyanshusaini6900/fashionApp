import 'package:RatNawnAI_app/features/wallet/bloc/wallet_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:RatNawnAI_app/core/services/firebase_service.dart';

import 'models/subscription_model.dart';
import '../pricing/presentation/pages/pricing_page.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}
//ee
class _WalletPageState extends State<WalletPage> {
  // Subscription data - this would come from Firebase/API
  final Map<String, dynamic> subscriptionData = {
    'planName': 'RatnawnAI Light Pack',
    'planType': 'Monthly Plan',
    'creditsUsed': 18,
    'creditsTotal': 50,
    'renewalDate': DateTime(2023, 8, 28),
    'isActive': true,
    'creditRate': 165,
    'monthlyPrice': 8250,
    'billingCycle': 'Monthly',
    'monthlyCredits': 50,
  };

  final Map<String, dynamic> creditUsage = {
    'images': {'used': 12, 'rate': 1},
    'videos': {'used': 5, 'rate': 1},
    'excel': {'used': 2, 'rate': 0.5},
  };

  final Map<String, dynamic> rolloverData = {
    'lastMonthUnused': 14,
    'rolloverPercentage': 50,
    'rolledCredits': 7,
  };

  @override
  void initState() {
    super.initState();
    context.read<WalletBloc>().add(const LoadWalletData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Wallet',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onPressed: () {},
          ),
        ],
      ),
      body: BlocBuilder<WalletBloc, WalletState>(
        builder: (context, state) {
          if (state is WalletLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else if (state is WalletError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading wallet data',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      context.read<WalletBloc>().add(const LoadWalletData());
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          } else if (state is WalletDataLoaded) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subscription Card
                    _buildSubscriptionCard(state.walletData),
                    const SizedBox(height: 24),

                    // Credit Breakdown Section
                    _buildCreditBreakdownSection(state.walletData),
                    const SizedBox(height: 24),

                    // Credit Usage Section
                    _buildCreditUsageSection(state.walletData),
                    const SizedBox(height: 24),

                    // Rollover Credits Section
                    _buildRolloverCreditsSection(state.walletData),
                    const SizedBox(height: 24),

                    // Plan Details Section
                    _buildPlanDetailsSection(state.walletData),
                    const SizedBox(height: 24),

                    // Action Buttons
                    _buildActionButtons(),
                    const SizedBox(height: 24),

                    // Important Notes
                    _buildImportantNotes(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          } else {
            // Fallback for other states (WalletInitial, WalletLoaded)
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
        },
      ),
    );
  }

  // Helper method to calculate total remaining credits
  // Includes: current balance + rollover credits (subscription credits are already in balance)
  double _calculateTotalRemainingCredits(WalletDataModel walletData) {
    double totalCredits = walletData.creditBalance;

    // Add rollover credits (if not already included in balance)
    // totalCredits += walletData.rolloverData.rolledCredits;

    // Note: subscription credits are already included in creditBalance
    // when the plan is purchased, so we don't add them again

    return totalCredits;
  }

  Widget _buildSubscriptionCard(WalletDataModel walletData) {
    final subscription = walletData.subscription;
    final totalCredits = _calculateTotalRemainingCredits(walletData);

    // Debug logging for subscription card
    print('🔍 Debug - Subscription Card - subscription: $subscription');
    print(
        '🔍 Debug - Subscription Card - subscription is null: ${subscription == null}');
    if (subscription != null) {
      print(
          '🔍 Debug - Subscription Card - planName: ${subscription.planName}');
      print(
          '🔍 Debug - Subscription Card - isActive: ${subscription.isActive}');
      print(
          '🔍 Debug - Subscription Card - creditRate: ${subscription.creditRate}');
      print(
          '🔍 Debug - Subscription Card - monthlyPrice: ${subscription.monthlyPrice}');
    }

    if (subscription == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Active Plan',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Get started with a plan',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Inactive',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credits Available',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${totalCredits.toInt()}',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Status',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No Plan',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      final renewalDate =
          DateFormat('MMM dd, yyyy').format(subscription.expiryDate);

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.displayPlanName,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subscription.planType,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    subscription.isActive ? 'Active' : 'Inactive',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credits Remaining',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${totalCredits.toInt()}',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Renewal Date',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      renewalDate,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  Widget _buildCreditBreakdownSection(WalletDataModel walletData) {
    final totalCredits = _calculateTotalRemainingCredits(walletData);
    final subscription = walletData.subscription;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Credits Breakdown',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF3B82F6).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Available Credits',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${totalCredits.toInt()}',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildBreakdownItem(
                  'Current Balance',
                  '${walletData.creditBalance.toInt()}',
                  const Color(0xFF10B981),
                ),
                const SizedBox(height: 8),
                _buildBreakdownItem(
                  'Rollover Credits',
                  '${walletData.rolloverData.lastRolloverCredits}',
                  const Color(0xFFF59E0B),
                ),
                if (subscription != null && subscription.isActive) ...[
                  const SizedBox(height: 8),
                  _buildBreakdownItem(
                    'Monthly Allocation',
                    '${subscription.monthlyCredits}',
                    const Color(0xFF8B5CF6),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownItem(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildCreditUsageSection(WalletDataModel walletData) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Credit Usage',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              IconButton(
                onPressed: () {
                  // Refresh wallet data to get latest usage
                  context.read<WalletBloc>().add(const LoadWalletData());
                },
                icon: const Icon(
                  Icons.refresh,
                  size: 20,
                  color: Colors.grey,
                ),
                tooltip: 'Refresh Usage Data',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildUsageItem(
            icon: Icons.image_outlined,
            iconColor: const Color(0xFF3B82F6),
            iconBgColor: const Color(0xFFEFF6FF),
            title: 'Images',
            subtitle: '${walletData.creditUsage.imageRate} Credit per image',
            usageCount: walletData.creditUsage.imagesUsed,
          ),
          const SizedBox(height: 16),
          _buildUsageItem(
            icon: Icons.videocam_outlined,
            iconColor: const Color(0xFF8B5CF6),
            iconBgColor: const Color(0xFFF3E8FF),
            title: 'Videos',
            subtitle: '${walletData.creditUsage.videoRate} Credit per video',
            usageCount: walletData.creditUsage.videosUsed,
          ),
          const SizedBox(height: 16),
          _buildUsageItem(
            icon: Icons.table_chart_outlined,
            iconColor: const Color(0xFF10B981),
            iconBgColor: const Color(0xFFD1FAE5),
            title: 'Excel Files',
            subtitle: '${walletData.creditUsage.excelRate} Credit per file',
            usageCount: walletData.creditUsage.excelUsed,
          ),
        ],
      ),
    );
  }

  Widget _buildUsageItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required int usageCount,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        Text(
          '$usageCount',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildRolloverCreditsSection(WalletDataModel walletData) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.autorenew,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Rollover Credits Details',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFBBF24).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                // Table Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withOpacity(0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Description',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Value',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                // Table Rows
                _buildRolloverTableRow(
                  'Unused Credits (Last Month)',
                  '${walletData.rolloverData.lastMonthUnused}',
                  isLast: false,
                ),
                _buildRolloverTableRow(
                  'Rollover Percentage',
                  '${walletData.rolloverData.rolloverPercentage.toInt()}%',
                  isLast: false,
                ),
                _buildRolloverTableRow(
                  'Credits Rolled Over',
                  '${walletData.rolloverData.rolledCredits}',
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF3B82F6).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: const Color(0xFF3B82F6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rollover credits are automatically added to your balance at the beginning of each month.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRolloverTableRow(String description, String value,
      {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: const Color(0xFFFBBF24).withOpacity(0.2),
                  width: 1,
                ),
              ),
        borderRadius: isLast
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              description,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFF59E0B),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanDetailsSection(WalletDataModel walletData) {
    final subscription = walletData.subscription;
    final totalCredits = _calculateTotalRemainingCredits(walletData);

    if (subscription == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plan Details',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            _buildDetailRow('Plan Name', 'No Active Plan'),
            const SizedBox(height: 16),
            _buildDetailRow('Credit Rate', '₹165 per credit'),
            const SizedBox(height: 16),
            _buildDetailRow(
                'Available Credits', '${totalCredits.toInt()} credits'),
            const SizedBox(height: 16),
            _buildDetailRow('Status', 'Inactive'),
            const SizedBox(height: 16),
            _buildDetailRow('Action Required', 'Choose a plan to get started'),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plan Details',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            _buildDetailRow('Plan Name', subscription.displayPlanName),
            const SizedBox(height: 16),
            _buildDetailRow('Credit Rate',
                '₹${subscription.creditRate.toInt()} per credit'),
            const SizedBox(height: 16),
            _buildDetailRow(
                'Max Credits', '${subscription.creditsPerMonth} credits'),
            const SizedBox(height: 16),
            _buildDetailRow('Billing Cycle', subscription.billingPeriod),
            const SizedBox(height: 16),
            _buildDetailRow('Monthly Price',
                '₹${NumberFormat('#,###').format(subscription.monthlyPrice)}'),
          ],
        ),
      );
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Colors.black54,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // SizedBox(
        //   width: double.infinity,
        //   height: 50,
        //   child: ElevatedButton.icon(
        //     onPressed: () {
        //       // Handle upgrade plan
        //     },
        //     icon: const Icon(Icons.trending_up, size: 20),
        //     label: Text(
        //       'Upgrade Plan',
        //       style: GoogleFonts.poppins(
        //         fontSize: 15,
        //         fontWeight: FontWeight.w600,
        //       ),
        //     ),
        //     style: ElevatedButton.styleFrom(
        //       backgroundColor: const Color(0xFF6366F1),
        //       foregroundColor: Colors.white,
        //       shape: RoundedRectangleBorder(
        //         borderRadius: BorderRadius.circular(12),
        //       ),
        //       elevation: 0,
        //     ),
        //   ),
        // ),
        // const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () {
              // Navigate to pricing page and scroll to Pay As You Go section
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RatnawnAIPricingPage(
                    scrollToPayAsYouGo: true,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.add, size: 20),
            label: Text(
              'Buy Extra Credits (₹160/credit)',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6366F1),
              side: const BorderSide(color: Color(0xFF6366F1), width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImportantNotes() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3B82F6).withOpacity(0.2),
          width: 1,
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
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildNoteItem(
            'All packs are monthly by default. At the end of the month, 50% of unused credits roll over to the next month.',
          ),
          const SizedBox(height: 12),
          _buildNoteItem(
            'Quarterly, Half-Yearly, and Yearly plans offer respective discounts but credits are credited monthly.',
          ),
          const SizedBox(height: 12),
          _buildNoteItem(
            'Example: Quarterly Ultra Light Pack (20 credits) = 60 credits for 3 months, credited as 20/month.',
          ),
        ],
      ),
    );
  }

  Widget _buildNoteItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFF3B82F6),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
