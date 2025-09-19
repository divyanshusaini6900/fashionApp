import 'dart:async';
import 'package:RatNawnAI_app/features/export/bloc/export_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../navbar/safe_state_mixin.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../wallet/bloc/wallet_bloc.dart';
import '../../../user/bloc/user_bloc.dart';

class HomeDashboard extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const HomeDashboard({
    super.key,
    this.onNavigateToTab,
  });

  @override
  State<HomeDashboard> createState() => HomeDashboardState();
}

class HomeDashboardState extends State<HomeDashboard>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        SafeStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _hasInitialized = false;

  // Performance metrics (per-user)
  String _successRateText = '--';
  String _avgTimeText = '--';

  // Store bloc references to avoid context lookups during disposal
  exportBloc? _exportBloc;
  WalletBloc? _walletBloc;
  UserBloc? _userBloc;

  // Carousel variables
  int _currentCarouselIndex = 0;
  final PageController _pageController = PageController();
  Timer? _autoPlayTimer;

  // Dynamic list for Firebase banners
  List<Map<String, dynamic>> _carouselItems = [];

  // Real-time listener subscription
  StreamSubscription<QuerySnapshot>? _bannersSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startBannersListener(); // Start real-time listener

    // Delay initialization to avoid build conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasInitialized) {
        _initializeBlocs();
        _loadDashboardData();
        _hasInitialized = true;
      }
    });
  }

  // Start real-time listener for banners
  void _startBannersListener() {
    // Cancel any existing subscription
    _bannersSubscription?.cancel();

    // Create real-time listener
    _bannersSubscription = FirebaseFirestore.instance
        .collection('banners')
        .where('isActive', isEqualTo: true)
        .orderBy('order', descending: false)
        .snapshots()
        .listen(
      (QuerySnapshot snapshot) {
        _handleBannersUpdate(snapshot);
      },
      onError: (error) {
        debugPrint('Error listening to banners: $error');
        _handleBannersError();
      },
    );
  }

  // Handle real-time banner updates
  void _handleBannersUpdate(QuerySnapshot snapshot) {
    final List<Map<String, dynamic>> fetchedBanners = [];

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      fetchedBanners.add({
        'id': doc.id,
        'imageUrl': data['imageUrl'] ?? '',
        'onPressed': data['targetTab'] ?? 1,
        'actionUrl': data['actionUrl'] ?? '',
        'priority': data['order'] ?? 0,
        'createdAt': data['createdAt'],
        'updatedAt': data['updatedAt'],
      });
    }

    if (mounted) {
      setState(() {
        // Check if this is first load
        bool wasEmpty = _carouselItems.isEmpty;

        _carouselItems =
            fetchedBanners.isNotEmpty ? fetchedBanners : _getFallbackBanners();

        // Start auto-play if this is first load and we have items
        if (wasEmpty && _carouselItems.isNotEmpty && _autoPlayTimer == null) {
          _startAutoPlay();
        }

        // Reset to first page if current index is out of bounds
        if (_currentCarouselIndex >= _carouselItems.length) {
          _currentCarouselIndex = 0;
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        }
      });
    }
  }

  // Handle errors in banner loading
  void _handleBannersError() {
    if (mounted) {
      setState(() {
        _carouselItems = _getFallbackBanners();
      });

      // Start auto-play if not already started
      if (_carouselItems.isNotEmpty && _autoPlayTimer == null) {
        _startAutoPlay();
      }
    }
  }

  // Fallback banners in case Firebase fetch fails
  List<Map<String, dynamic>> _getFallbackBanners() {
    return [
      {
        'id': 'fallback_1',
        'imageUrl': '',
        'onPressed': 1,
        'actionUrl': '',
        'priority': 0,
      },
      {
        'id': 'fallback_2',
        'imageUrl': '',
        'onPressed': 2,
        'actionUrl': '',
        'priority': 1,
      },
      {
        'id': 'fallback_3',
        'imageUrl': '',
        'onPressed': 3,
        'actionUrl': '',
        'priority': 2,
      },
    ];
  }

  // Auto-play timer methods
  void _startAutoPlay() {
    _autoPlayTimer?.cancel(); // Cancel any existing timer

    if (_carouselItems.isEmpty) return;

    _autoPlayTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_pageController.hasClients && mounted && _carouselItems.isNotEmpty) {
        int nextPage = _currentCarouselIndex + 1;

        if (nextPage >= _carouselItems.length) {
          nextPage = 0;
        }

        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
  }

  void _resumeAutoPlay() {
    _stopAutoPlay();
    _startAutoPlay();
  }

  void _initializeBlocs() {
    if (!mounted) return;

    try {
      _exportBloc = context.read<exportBloc>();
      _walletBloc = context.read<WalletBloc>();
      _userBloc = context.read<UserBloc>();
    } catch (e) {
      debugPrint('Error initializing blocs: $e');
    }
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: ApiConfig.extraLongAnimation,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutBack),
    ));

    _animationController.forward();
  }

  void _loadDashboardData() {
    if (!mounted) return;

    try {
      _exportBloc?.add(const LoadexportableVideos());
      _walletBloc?.add(const StartWalletStream());
      _userBloc?.add(const StartUserDataStream());
      _loadPerformanceMetrics();
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    }
  }

  Future<void> _loadPerformanceMetrics() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('GenSpace_jobs')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      int completed = 0;
      int failed = 0;
      int totalSeconds = 0;
      int numDurations = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString();
        if (status == 'completed') {
          completed++;
          final created = data['createdAt'];
          final completedAt = data['completedAt'];
          DateTime? createdDt;
          DateTime? completedDt;
          try {
            if (created is Timestamp) createdDt = created.toDate();
            if (completedAt is Timestamp) completedDt = completedAt.toDate();
          } catch (_) {}
          if (createdDt != null && completedDt != null) {
            totalSeconds += completedDt.difference(createdDt).inSeconds;
            numDurations++;
          }
        } else if (status == 'failed') {
          failed++;
        }
      }

      String successText = '--';
      String avgTimeText = '--';
      final attempts = completed + failed;
      if (attempts > 0) {
        final rate = (completed / attempts * 100).clamp(0, 100);
        successText = '${rate.toStringAsFixed(0)}%';
      }
      if (numDurations > 0) {
        final avgSeconds = totalSeconds / numDurations;
        final avgMinutes = avgSeconds / 60.0;
        avgTimeText = '${avgMinutes.toStringAsFixed(1)}m';
      }

      if (mounted) {
        setState(() {
          _successRateText = successText;
          _avgTimeText = avgTimeText;
        });
      }
    } catch (e) {
      debugPrint('Error loading performance metrics: $e');
    }
  }

  // Public method to manually refresh banners (forces re-subscription)
  Future<void> refreshBanners() async {
    _startBannersListener();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _autoPlayTimer?.cancel();
    _bannersSubscription?.cancel(); // Cancel real-time listener
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundBlue,
      body: SafeArea(
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, authState) {
            final user = authState is AuthAuthenticated ? authState.user : null;
            return AnimatedBuilder(
              animation: _fadeAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      children: [
                        // Modern App Bar - Fixed height
                        Container(
                          height: 120,
                          child: _buildModernAppBarFixed(user),
                        ),

                        // Dashboard Content - Takes remaining space
                        Expanded(
                          child: Padding(
                            padding: ResponsiveUtils.getResponsivePadding(
                              context,
                              mobile: const EdgeInsets.all(10),
                              tablet: const EdgeInsets.all(20),
                              desktop: const EdgeInsets.all(28),
                            ),
                            child: Column(
                              children: [
                                // User Overview Card with Carousel
                                SizedBox(
                                  height: 220,
                                  child: _buildUserOverviewCard(user),
                                ),

                                const SizedBox(height: 12),

                                // Quick Actions
                                Expanded(
                                  flex: 1,
                                  child: _buildQuickActions(),
                                ),

                                const SizedBox(height: 12),

                                // Performance Cards
                                Expanded(
                                  flex: 1,
                                  child: _buildPerformanceCards(),
                                ),

                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

// Updated carousel card to fit smaller height
  Widget _buildUserOverviewCard(User? user) {
    return Column(
      children: [
        Expanded(
          // Use Expanded instead of fixed height
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentCarouselIndex = index;
              });
            },
            itemCount: _carouselItems.length,
            itemBuilder: (context, index) {
              final item = _carouselItems[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12), // Reduced padding
                child: _buildCarouselCard(item),
              );
            },
          ),
        ),
        const SizedBox(height: 12), // Reduced spacing
        _buildCarouselIndicators(),
      ],
    );
  }

// Updated quick actions with better spacing
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8), // Reduced spacing
        Expanded(
          // Use Expanded to take available space
          child: Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  title: 'GenSpace',
                  subtitle: 'AI-powered',
                  icon: Icons.auto_awesome,
                  color: AppColors.primaryBlue,
                  onTap: () {
                    widget.onNavigateToTab?.call(1);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildQuickActionCard(
                  title: 'Exports',
                  subtitle: 'Generated content',
                  icon: Icons.download_rounded,
                  color: AppColors.success,
                  onTap: () {
                    widget.onNavigateToTab?.call(2);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

// Updated performance cards with better spacing
  Widget _buildPerformanceCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance',
          style: GoogleFonts.poppins(
            fontSize: 16, // Reduced from 18
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8), // Reduced spacing
        Expanded(
          // Use Expanded to take available space
          child: Row(
            children: [
              Expanded(
                child: _buildPerformanceCard(
                  title: 'Success Rate',
                  value: _successRateText,
                  subtitle: 'Generation success',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10), // Reduced spacing
              Expanded(
                child: _buildPerformanceCard(
                  title: 'Avg. Time',
                  value: _avgTimeText,
                  subtitle: 'Per generation',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

// Updated quick action card without AspectRatio
  Widget _buildQuickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowColor,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

// Updated performance card without AspectRatio
  Widget _buildPerformanceCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Modified app bar for fixed layout
  Widget _buildModernAppBarFixed(User? user) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.white, AppColors.backgroundBlue],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  // User Avatar
                  GestureDetector(
                    onTap: () {
                      context.push(AppRoutes.profile);
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                        border: Border.all(
                          color: AppColors.white,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.person,
                        color: AppColors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // User Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good ${_getGreeting()}!',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        BlocBuilder<UserBloc, UserState>(
                          builder: (context, userState) {
                            String displayName = 'User';

                            if (userState is UserLoaded) {
                              displayName = userState.userFullName;
                            }

                            return Text(
                              displayName,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Wallet credit display and notifications
                  Row(
                    children: [
                      // Wallet credit display - CLICKABLE
                      BlocBuilder<WalletBloc, WalletState>(
                        builder: (context, walletState) {
                          double balance = 0.0;
                          if (walletState is WalletLoaded) {
                            balance = walletState.balance;
                          } else if (walletState is WalletDataLoaded) {
                            balance = walletState.walletData.creditBalance;
                          }
                          return GestureDetector(
                            onTap: () {
                              context.push(AppRoutes.wallet);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.warning.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: AppColors.warning,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '₹',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$balance',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      // Notifications icon
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadowColor.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Icon(
                                Icons.notifications_outlined,
                                color: AppColors.textPrimary,
                                size: 20,
                              ),
                            ),
                            // Notification badge
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  Widget _buildCarouselCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTapDown: (_) => _stopAutoPlay(),
      onTapUp: (_) => _resumeAutoPlay(),
      onTapCancel: () => _resumeAutoPlay(),
      onTap: () {
        if (item['actionUrl'] != null &&
            item['actionUrl'].toString().isNotEmpty) {
          // Handle external URL if needed
          // You can use url_launcher package here
        } else if (item['onPressed'] is int) {
          widget.onNavigateToTab?.call(item['onPressed']);
        }
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child:
              item['imageUrl'] != null && item['imageUrl'].toString().isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item['imageUrl'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (context, url) => Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) =>
                          _buildFallbackBanner(item),
                    )
                  : _buildFallbackBanner(item),
        ),
      ),
    );
  }

  Widget _buildFallbackBanner(Map<String, dynamic> item) {
    final int tabIndex = item['onPressed'] ?? 1;
    IconData iconData;
    String label;

    switch (tabIndex) {
      case 1:
        iconData = Icons.auto_awesome;
        label = 'GenSpace';
        break;
      case 2:
        iconData = Icons.download_rounded;
        label = 'Exports';
        break;
      case 3:
        iconData = Icons.account_balance_wallet;
        label = 'Wallet';
        break;
      default:
        iconData = Icons.dashboard;
        label = 'Dashboard';
    }

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              iconData,
              color: AppColors.white,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselIndicators() {
    return SmoothPageIndicator(
      controller: _pageController,
      count: _carouselItems.length,
      effect: ExpandingDotsEffect(
        activeDotColor: AppColors.primaryBlue,
        dotColor: AppColors.primaryBlue.withOpacity(0.3),
        dotHeight: 8,
        dotWidth: 8,
        expansionFactor: 3,
        spacing: 8,
      ),
      onDotClicked: (index) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      },
    );
  }
}

// Helper widget for responsive building
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(
          BuildContext context, bool isMobile, bool isTablet, bool isDesktop)
      builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 900;
    final isDesktop = screenWidth >= 900;

    return builder(context, isMobile, isTablet, isDesktop);
  }
}
