import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/razorpay_service_secure.dart';
import 'checkout_page.dart'; // ADD THIS IMPORT
import 'credit_checkout_page.dart';

// Model Classes
class PricingPlan {
  final String id;
  final String name;
  final String description;
  final double creditRate;
  final int maxCredits;
  final double monthlyPrice;
  final double quarterlyDiscount;
  final double halfYearlyDiscount;
  final double yearlyDiscount;
  final bool isPopular;
  final bool isEnterprise;
  final int displayOrder;

  PricingPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.creditRate,
    required this.maxCredits,
    required this.monthlyPrice,
    this.quarterlyDiscount = 10,
    this.halfYearlyDiscount = 15,
    this.yearlyDiscount = 25,
    this.isPopular = false,
    this.isEnterprise = false,
    required this.displayOrder,
  });

  factory PricingPlan.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return PricingPlan(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      creditRate: (data['creditRate'] ?? 0).toDouble(),
      maxCredits: data['maxCredits'] ?? 0,
      monthlyPrice: (data['monthlyPrice'] ?? 0).toDouble(),
      quarterlyDiscount: (data['quarterlyDiscount'] ?? 10).toDouble(),
      halfYearlyDiscount: (data['halfYearlyDiscount'] ?? 15).toDouble(),
      yearlyDiscount: (data['yearlyDiscount'] ?? 25).toDouble(),
      isPopular: data['isPopular'] ?? false,
      isEnterprise: data['isEnterprise'] ?? false,
      displayOrder: data['displayOrder'] ?? 999,
    );
  }

  double getQuarterlyPrice() =>
      monthlyPrice * 3 * (1 - quarterlyDiscount / 100);
  double getHalfYearlyPrice() =>
      monthlyPrice * 6 * (1 - halfYearlyDiscount / 100);
  double getYearlyPrice() => monthlyPrice * 12 * (1 - yearlyDiscount / 100);
}

enum BillingPeriod { monthly, quarterly, halfYearly, yearly }

class RatnawnAIPricingPage extends StatefulWidget {
  final bool scrollToPayAsYouGo;

  const RatnawnAIPricingPage({
    super.key,
    this.scrollToPayAsYouGo = false,
  });

  @override
  State<RatnawnAIPricingPage> createState() => _RatnawnAIPricingPageState();
}

class _RatnawnAIPricingPageState extends State<RatnawnAIPricingPage> {
  BillingPeriod _selectedBillingPeriod = BillingPeriod.monthly;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RazorPayService _razorPayService = RazorPayService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _payAsYouGoKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _razorPayService.initialize();

    // Auto-scroll to Pay As You Go section if requested
    if (widget.scrollToPayAsYouGo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToPayAsYouGo();
      });
    }
  }

  @override
  void dispose() {
    _razorPayService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll to Pay As You Go section
  void _scrollToPayAsYouGo() {
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_payAsYouGoKey.currentContext != null) {
        Scrollable.ensureVisible(
          _payAsYouGoKey.currentContext!,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOut,
          alignment: 0.0, // Scroll to top of the section
        );
      }
    });
  }

  // Real-time credit usage stream
  Stream<Map<String, dynamic>> get _creditUsageStream {
    return _firestore
        .collection('credits')
        .doc('creditUsage')
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return {
          'image': (data['image'] ?? 1.0).toDouble(),
          'video': (data['video'] ?? 1.0).toDouble(),
          'excel': (data['excel'] ?? 0.5).toDouble(),
          'updatedAt': data['updatedAt'],
        };
      } else {
        return {
          'image': 1.0,
          'video': 1.0,
          'excel': 0.5,
          'updatedAt': null,
        };
      }
    }).handleError((error) {
      print('Error in credit usage stream: $error');
      return {
        'image': 1.0,
        'video': 1.0,
        'excel': 0.5,
        'updatedAt': null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundBlue,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RatnawnAI',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryBlue,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header
            Container(
              width: double.infinity,
              color: AppColors.white,
              padding: const EdgeInsets.only(
                  left: 20, right: 20, top: 8, bottom: 24),
              child: Column(
                children: [
                  Text(
                    'Pricing Plans',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose the plan that fits your needs',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Main Content Container
            Container(
              width: MediaQuery.of(context).size.width > 600
                  ? 400
                  : double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Credit Usage Card with Real-time Updates
                  StreamBuilder<Map<String, dynamic>>(
                    stream: _creditUsageStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildCreditUsageLoadingCard();
                      }

                      if (snapshot.hasError) {
                        return _buildCreditUsageErrorCard();
                      }

                      final creditUsage = snapshot.data ??
                          {
                            'image': 1.0,
                            'video': 1.0,
                            'excel': 0.5,
                            'updatedAt': null,
                          };

                      return _buildCreditUsageCard(creditUsage);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Billing Period Selector
                  _buildBillingSelector(),
                  const SizedBox(height: 20),

                  // Pricing Plans from Firebase
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('pricing_plans')
                        .where('isEnterprise', isEqualTo: false)
                        .orderBy('displayOrder')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryBlue,
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _buildNoPlansMessage();
                      }

                      List<PricingPlan> plans = snapshot.data!.docs
                          .map((doc) => PricingPlan.fromFirestore(doc))
                          .where((plan) => !plan.name.toLowerCase().replaceAll(' ', '').replaceAll('-', '').contains('payasyougo'))
                          .toList();

                      return Column(
                        children: plans
                            .map((plan) => Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _buildPlanCard(plan),
                                ))
                            .toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Enterprise Pack
                  _buildEnterpriseCard(),
                  const SizedBox(height: 20),

                  // Pay As You Go
                  Container(
                    key: _payAsYouGoKey,
                    child: _buildPayAsYouGoCard(),
                  ),
                  const SizedBox(height: 20),

                  // Important Notes
                  _buildImportantNotes(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditUsageCard(Map<String, dynamic> creditUsage) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 8,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_sync,
                      size: 12,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Live',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCreditUsageRow('1 Image', creditUsage['image']),
          const SizedBox(height: 8),
          _buildCreditUsageRow('1 Video', creditUsage['video']),
          const SizedBox(height: 8),
          _buildCreditUsageRow('1 Excel', creditUsage['excel']),
          const SizedBox(height: 8),
          Text(
            '(output file generation)',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (creditUsage['updatedAt'] != null) ...[
            const SizedBox(height: 8),
            _buildLastUpdatedInfo(creditUsage['updatedAt']),
          ],
        ],
      ),
    );
  }

  Widget _buildCreditUsageRow(String service, double credits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          service,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        credits > 0
            ? Text(
                '= ${credits.toStringAsFixed(credits % 1 == 0 ? 0 : 1)} Credit${credits != 1 ? 's' : ''}',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              )
            : const SizedBox.shrink(), // shows blank space instead of "1"
      ],
    );
  }

  Widget _buildLastUpdatedInfo(dynamic updatedAt) {
    if (updatedAt == null) return const SizedBox.shrink();

    String timeText = 'Recently';
    try {
      if (updatedAt is Timestamp) {
        final now = DateTime.now();
        final updateTime = updatedAt.toDate();
        final diff = now.difference(updateTime);

        if (diff.inMinutes < 1) {
          timeText = 'Just now';
        } else if (diff.inHours < 1) {
          timeText = '${diff.inMinutes}m ago';
        } else if (diff.inDays < 1) {
          timeText = '${diff.inHours}h ago';
        } else {
          timeText = '${diff.inDays}d ago';
        }
      }
    } catch (e) {
      timeText = 'Recently';
    }

    return Row(
      children: [
        Icon(
          Icons.schedule,
          size: 12,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          'Updated $timeText',
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCreditUsageLoadingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 8,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildLoadingRow(),
          const SizedBox(height: 8),
          _buildLoadingRow(),
          const SizedBox(height: 8),
          _buildLoadingRow(),
        ],
      ),
    );
  }

  Widget _buildLoadingRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          width: 60,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        Container(
          width: 80,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }

  Widget _buildCreditUsageErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 20,
                color: AppColors.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Credit Usage',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Unable to load current credit rates. Using default values.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _buildCreditUsageRow('1 Image', 1.0),
          const SizedBox(height: 8),
          _buildCreditUsageRow('1 Video', 1.0),
          const SizedBox(height: 8),
          _buildCreditUsageRow('1 Excel', 0.5),
        ],
      ),
    );
  }

  Widget _buildBillingSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildBillingOption('Monthly', BillingPeriod.monthly),
          _buildBillingOption('Quarterly', BillingPeriod.quarterly),
          _buildBillingOption('Half\nYearly', BillingPeriod.halfYearly),
          _buildBillingOption('Yearly', BillingPeriod.yearly),
        ],
      ),
    );
  }

  Widget _buildBillingOption(String label, BillingPeriod period) {
    final isSelected = _selectedBillingPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedBillingPeriod = period),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isSelected ? AppColors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(PricingPlan plan) {
    // Skip enterprise plans in this section
    if (plan.isEnterprise) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: plan.isPopular
            ? Border.all(color: AppColors.primaryBlue, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (plan.isPopular)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
              ),
              child: Text(
                'POPULAR',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: AppColors.white,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.lightBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '↓',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildPlanDetail(
                    'Credit Rate', 'Rs.${plan.creditRate.toStringAsFixed(0)}'),
                _buildPlanDetail('Max Credits', '${plan.maxCredits}'),
                const Divider(height: 24),
                _buildPlanDetail(
                  'Monthly Price',
                  'Rs.${plan.monthlyPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                  isGray: _selectedBillingPeriod != BillingPeriod.monthly,
                  isBold: _selectedBillingPeriod == BillingPeriod.monthly,
                ),
                _buildPlanDetail(
                  'Quarterly (-${plan.quarterlyDiscount.toStringAsFixed(0)}%)',
                  'Rs.${plan.getQuarterlyPrice().toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                  isGray: _selectedBillingPeriod != BillingPeriod.quarterly,
                  isBold: _selectedBillingPeriod == BillingPeriod.quarterly,
                ),
                _buildPlanDetail(
                  'Half-Yearly (-${plan.halfYearlyDiscount.toStringAsFixed(0)}%)',
                  'Rs.${plan.getHalfYearlyPrice().toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                  isGray: _selectedBillingPeriod != BillingPeriod.halfYearly,
                  isBold: _selectedBillingPeriod == BillingPeriod.halfYearly,
                ),
                _buildPlanDetail(
                  'Yearly (-${plan.yearlyDiscount.toStringAsFixed(0)}%)',
                  'Rs.${plan.getYearlyPrice().toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                  isGray: _selectedBillingPeriod != BillingPeriod.yearly,
                  isBold: _selectedBillingPeriod == BillingPeriod.yearly,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => _selectPlan(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Select Plan',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildPlanDetail(String label, String value,
      {bool isGray = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              color: isGray ? AppColors.grey : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: isGray
                  ? AppColors.grey
                  : (isBold ? AppColors.primaryBlue : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterpriseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enterprise Pack',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.lightBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '↓',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Icon(
            Icons.business_center_outlined,
            size: 48,
            color: AppColors.primaryBlue.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Contact us for custom enterprise\nsolutions',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () {
                // Handle contact sales
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primaryBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Contact Sales',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayAsYouGoCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('pricing_plans').doc('pay_as_you_go').snapshots(),
      builder: (context, snapshot) {
        double creditRate = 160;

        if (snapshot.hasData && snapshot.data!.exists) {
          Map<String, dynamic> data =
              snapshot.data!.data() as Map<String, dynamic>;
          creditRate = (data['creditRate'] ?? 160).toDouble();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowColor,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pay As You Go',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.lightBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '→',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Extra Credit',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    'Rs.${creditRate.toStringAsFixed(0)} per credit',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Purchase additional credits anytime',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppColors.grey,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _navigateToCreditCheckout(creditRate),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Buy Credits',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImportantNotes() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.warningLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.warningLight.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Important Notes',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 12),
          _buildNote(
              '📄 All packs are monthly by default. At the end of the month, 50% of unused credits roll over to the next month.'),
          const SizedBox(height: 8),
          _buildNote(
              '📅 Quarterly, Half-Yearly, and Yearly plans offer respective discounts but credits are credited monthly.'),
          const SizedBox(height: 8),
          _buildNote(
              '💡 Example: Quarterly Ultra Light Pack (20 credits) = 60 credits for 3 months, credited as 20/month.'),
          const SizedBox(height: 8),
          _buildNote(
              '🛒 Pay As You Go credits (Rs.160 per credit) are available for additional usage.'),
        ],
      ),
    );
  }

  Widget _buildNote(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.warning,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoPlansMessage() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.info_outline,
            size: 48,
            color: AppColors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            'No pricing plans available',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check back later',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // UPDATED METHOD - This is the main change
  void _selectPlan(PricingPlan plan) {
    double displayPrice;
    int duration;
    double discountPercent = 0;

    switch (_selectedBillingPeriod) {
      case BillingPeriod.quarterly:
        displayPrice = plan.getQuarterlyPrice();
        duration = 3;
        discountPercent = plan.quarterlyDiscount;
        break;
      case BillingPeriod.halfYearly:
        displayPrice = plan.getHalfYearlyPrice();
        duration = 6;
        discountPercent = plan.halfYearlyDiscount;
        break;
      case BillingPeriod.yearly:
        displayPrice = plan.getYearlyPrice();
        duration = 12;
        discountPercent = plan.yearlyDiscount;
        break;
      default:
        displayPrice = plan.monthlyPrice;
        duration = 1;
        discountPercent = 0;
    }

    // Navigate directly to checkout page instead of showing dialog
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          planName: plan.name,
          planType: plan.name,
          billingPeriod: _selectedBillingPeriod,
          creditsPerMonth: plan.maxCredits,
          creditRate: plan.creditRate,
          monthlyPrice: plan.monthlyPrice,
          totalPrice: displayPrice,
          discount: discountPercent,
          duration: duration,
        ),
      ),
    );
  }

  void _navigateToCreditCheckout(double creditRate) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreditCheckoutPage(
          creditRate: creditRate,
          initialCredits: 1,
        ),
      ),
    );
  }
}
