// lib/features/pricing/screens/coupons_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/coupon_service.dart';

class CouponsPage extends StatefulWidget {
  final double orderAmount;
  final String planType;

  const CouponsPage({
    super.key,
    required this.orderAmount,
    required this.planType,
  });

  @override
  State<CouponsPage> createState() => _CouponsPageState();
}

class _CouponsPageState extends State<CouponsPage> with SingleTickerProviderStateMixin {
  final CouponService _couponService = CouponService();
  late TabController _tabController;
  
  List<Coupon> _publicCoupons = [];
  List<Coupon> _exclusiveCoupons = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCoupons();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCoupons() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final allCoupons = await _couponService.getAvailableCoupons();
      
      setState(() {
        _publicCoupons = allCoupons.where((c) => c.isPublic).toList();
        _exclusiveCoupons = allCoupons.where((c) => !c.isPublic).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyCoupon(Coupon coupon) {
    Navigator.pop(context, coupon.code);
  }

  void _copyCouponCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Coupon code copied!',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowColor,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          'Available Coupons',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Order: ₹${widget.orderAmount.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_exclusiveCoupons.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    TabBar(
                      controller: _tabController,
                      indicatorColor: AppColors.primaryBlue,
                      labelColor: AppColors.primaryBlue,
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: [
                        Tab(
                          text: 'All Coupons (${_publicCoupons.length})',
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.star, size: 16),
                              const SizedBox(width: 4),
                              Text('Exclusive (${_exclusiveCoupons.length})'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: AppColors.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Failed to load coupons',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _loadCoupons,
                                child: Text(
                                  'Retry',
                                  style: GoogleFonts.poppins(
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _exclusiveCoupons.isEmpty
                          ? _buildCouponsList(_publicCoupons, false)
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _buildCouponsList(_publicCoupons, false),
                                _buildCouponsList(_exclusiveCoupons, true),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponsList(List<Coupon> coupons, bool isExclusive) {
    if (coupons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isExclusive ? Icons.card_giftcard : Icons.local_offer,
              size: 64,
              color: AppColors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isExclusive 
                  ? 'No exclusive coupons available'
                  : 'No coupons available',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: coupons.length,
      itemBuilder: (context, index) {
        final coupon = coupons[index];
        return _buildCouponCard(coupon, isExclusive);
      },
    );
  }

  Widget _buildCouponCard(Coupon coupon, bool isExclusive) {
    final bool isApplicable = coupon.minimumAmount <= widget.orderAmount &&
        (coupon.applicablePlans.isEmpty || coupon.applicablePlans.contains(widget.planType));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExclusive 
              ? AppColors.warning.withOpacity(0.3)
              : AppColors.borderColor,
          width: isExclusive ? 2 : 1,
        ),
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
          // Coupon Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isExclusive
                    ? [AppColors.warning.withOpacity(0.1), AppColors.warningLight.withOpacity(0.1)]
                    : [AppColors.primaryBlue.withOpacity(0.1), AppColors.lightBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isExclusive ? Icons.star : Icons.local_offer,
                    color: isExclusive ? AppColors.warning : AppColors.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            coupon.code,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isExclusive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'EXCLUSIVE',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        coupon.getDiscountText(),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _copyCouponCode(coupon.code),
                  icon: const Icon(Icons.copy, size: 20),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),

          // Coupon Details
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon.description,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  coupon.applicablePlans.isEmpty 
                      ? 'Applicable on all plans'
                      : 'Applicable on: ${coupon.applicablePlans.join(', ')}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                // Conditions
                if (coupon.minimumAmount > 0) ...[
                  _buildConditionRow(
                    Icons.shopping_cart,
                    'Min order: ₹${coupon.minimumAmount.toStringAsFixed(0)}',
                    coupon.minimumAmount <= widget.orderAmount,
                  ),
                  const SizedBox(height: 8),
                ],
                
                if (coupon.getMaxDiscountText().isNotEmpty) ...[
                  _buildConditionRow(
                    Icons.info_outline,
                    coupon.getMaxDiscountText(),
                    true,
                  ),
                  const SizedBox(height: 8),
                ],
                
                if (coupon.expiryDate != null) ...[
                  _buildConditionRow(
                    Icons.schedule,
                    'Valid till ${DateFormat('dd MMM yyyy').format(coupon.expiryDate!)}',
                    true,
                  ),
                  const SizedBox(height: 8),
                ],
                
                if (coupon.usageLimit > 0) ...[
                  _buildConditionRow(
                    Icons.repeat,
                    'Limited to ${coupon.usageLimit} use${coupon.usageLimit > 1 ? 's' : ''}',
                    true,
                  ),
                ],
              ],
            ),
          ),

          // Apply Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.borderColor),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isApplicable ? () => _applyCoupon(coupon) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isApplicable ? AppColors.primaryBlue : AppColors.grey,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isApplicable ? 'Apply Coupon' : 'Not Applicable',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionRow(IconData icon, String text, bool isMet) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isMet ? AppColors.textSecondary : AppColors.error,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: isMet ? AppColors.textSecondary : AppColors.error,
          ),
        ),
      ],
    );
  }
}