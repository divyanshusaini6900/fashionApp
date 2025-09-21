import 'dart:async';
import 'dart:io';
import 'package:RatNawnAI_app/features/export/bloc/export_bloc.dart';
import 'package:RatNawnAI_app/features/profile/presentation/pages/terms_and_conditions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../navbar/safe_state_mixin.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../user/bloc/user_bloc.dart';
import '../../../wallet/bloc/wallet_bloc.dart';
import 'profile_settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with
        SingleTickerProviderStateMixin,
        SafeStateMixin,
        AutomaticKeepAliveClientMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final TextEditingController _nameController = TextEditingController();
  File? _profileImage;
  bool _hasInitialized = false;
  int _totalGenSpaces = 0;
  
  // Store user data from Firebase
  String? _displayName;
  String? _email;
  String? _phoneNumber;
  String? _photoUrl;
  String? _bio;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();

    // Delay initialization to avoid build conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasInitialized) {
        _loadUserData();
        _hasInitialized = true;
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
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

  Future<void> _loadUserData() async {
    if (!mounted) return;

    try {
      // Load from UserBloc
      context.read<UserBloc>().add(const StartUserDataStream());
      context.read<WalletBloc>().add(const StartWalletStream());
      context.read<exportBloc>().add(const LoadexportableVideos());
      
      // Load directly from Firebase
      await _loadFirebaseUserData();
      _loadUserGenSpacesCount();
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _loadFirebaseUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Get data from Firebase Auth
      setState(() {
        _displayName = user.displayName;
        _email = user.email;
        _phoneNumber = user.phoneNumber;
        _photoUrl = user.photoURL;
      });

      // Also try to get additional data from Firestore
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (doc.exists && mounted) {
          final data = doc.data();
          if (data != null) {
            setState(() {
              _displayName = data['displayName'] ?? _displayName;
              _phoneNumber = data['phoneNumber'] ?? _phoneNumber;
              _bio = data['bio'];
              _photoUrl = data['photoUrl'] ?? _photoUrl;
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading Firestore data: $e');
      }
    }
  }

  Future<void> _loadUserGenSpacesCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final baseQuery = FirebaseFirestore.instance
          .collection('GenSpace_jobs')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed');

      int count = 0;
      try {
        final aggregate = await baseQuery.count().get();
        count = aggregate.count ?? 0;
      } catch (_) {
        final snapshot = await baseQuery.get();
        count = snapshot.docs.length;
      }

      if (mounted) {
        setState(() {
          _totalGenSpaces = count;
        });
      }
    } catch (e) {
      debugPrint('Error loading GenSpaces count: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.backgroundBlue,
      body: BlocListener<UserBloc, UserState>(
        listener: (context, state) {
          if (state is UserLoaded && mounted) {
            setState(() {
              _displayName = state.displayName.isNotEmpty ? state.displayName : _displayName;
              _phoneNumber = state.phoneNumber ?? _phoneNumber;
              // Reload Firebase data to get latest updates
              _loadFirebaseUserData();
            });
          }
        },
        child: AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: SlideTransition(
                position: _slideAnimation,
                child: CustomScrollView(
                  slivers: [
                    // Modern App Bar
                    _buildModernAppBar(),

                    // Profile Content
                    SliverPadding(
                      padding: ResponsiveUtils.getResponsivePadding(
                        context,
                        mobile: const EdgeInsets.all(16),
                        tablet: const EdgeInsets.all(24),
                        desktop: const EdgeInsets.all(32),
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // Profile Header Card
                          _buildProfileHeaderCard(user),

                          // const SizedBox(height: 24),

                          // // Account Statistics
                          // _buildAccountStatistics(),

                          const SizedBox(height: 24),

                          // Account Management
                          _buildAccountManagement(),

                          const SizedBox(height: 24),

                          // Support & Info
                          _buildSupportInfo(),

                          const SizedBox(height: 24),

                          // Logout Section
                          _buildLogoutSection(),

                          const SizedBox(height: 100), // Bottom padding
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildModernAppBar() {
    return SliverAppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
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
                  Text(
                    'My Profile',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Manage your account and preferences',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
        centerTitle: false,
        title: Container(), // Empty title since we handle it in background
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            _loadFirebaseUserData();
            _loadUserGenSpacesCount();
          },
          tooltip: 'Refresh Data',
        ),
      ],
    );
  }

  Widget _buildProfileHeaderCard(User? user) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Avatar Section
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: (_profileImage == null && _photoUrl == null) 
                      ? AppColors.primaryGradient 
                      : null,
                  border: Border.all(
                    color: AppColors.primaryBlue,
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: _profileImage != null
                      ? Image.file(
                          _profileImage!,
                          fit: BoxFit.cover,
                        )
                      : _photoUrl != null && _photoUrl!.isNotEmpty
                          ? Image.network(
                              _photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildDefaultAvatar(),
                            )
                          : _buildDefaultAvatar(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // User Name Section
          Text(
            _displayName ?? user?.displayName ?? user?.email?.split('@').first ?? 'User',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Email
          Text(
            _email ?? user?.email ?? 'No email',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),

          // Phone Number if available
          if (_phoneNumber != null && _phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.phone,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _phoneNumber!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ],

          // Bio if available
          if (_bio != null && _bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _bio!,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: const Icon(
        Icons.person,
        size: 50,
        color: AppColors.white,
      ),
    );
  }

  // Widget _buildAccountStatistics() {
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       Text(
  //         'Account Overview',
  //         style: GoogleFonts.poppins(
  //           fontSize: 20,
  //           fontWeight: FontWeight.w600,
  //           color: AppColors.textPrimary,
  //         ),
  //       ),
  //       const SizedBox(height: 16),
  //       Row(
  //         children: [
  //           Expanded(
  //             child: BlocBuilder<WalletBloc, WalletState>(
  //               builder: (context, state) {
  //                 final balance = state is WalletLoaded ? state.balance : 0;
  //                 // Calculate trend based on previous balance
  //                 final trend = balance > 50
  //                     ? '+${((balance - 50) / 50 * 100).toInt()}%'
  //                     : balance > 0
  //                         ? '+0%'
  //                         : '0%';
  //                 final isPositive = balance >= 50;

  //                 return _buildAnalyticsCard(
  //                   title: 'Credit Balance',
  //                   value: balance.toString(),
  //                   subtitle: 'Available Credits',
  //                   icon: Icons.monetization_on,
  //                   color: AppColors.primaryBlue,
  //                   trend: trend,
  //                   isPositive: isPositive,
  //                 );
  //               },
  //             ),
  //           ),
  //           const SizedBox(width: 16),
  //           Expanded(
  //             child: _buildAnalyticsCard(
  //               title: 'Total GenSpaces',
  //               value: '$_totalGenSpaces',
  //               subtitle: 'Generated GenSpaces',
  //               icon: Icons.auto_awesome,
  //               color: AppColors.success,
  //               trend: '—',
  //               isPositive: true,
  //             ),
  //           ),
  //         ],
  //       ),
  //     ],
  //   );
  // }

  Widget _buildAnalyticsCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String trend,
    required bool isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPositive ? AppColors.success : AppColors.error)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trend != '—')
                      Icon(
                        isPositive ? Icons.trending_up : Icons.trending_down,
                        size: 12,
                        color: isPositive ? AppColors.success : AppColors.error,
                      ),
                    if (trend != '—')
                      const SizedBox(width: 4),
                    Text(
                      trend,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: trend == '—' 
                            ? AppColors.textSecondary
                            : (isPositive ? AppColors.success : AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountManagement() {
    return _buildSection(
      title: 'Account Management',
      children: [
        _buildSettingsItem(
          icon: Icons.person_outline,
          title: 'Profile Settings',
          subtitle: 'Change account information',
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const ProfileSettingsPage(),
              ),
            );
            // Reload data when returning from settings
            _loadFirebaseUserData();
          },
        ),
      ],
    );
  }

  Widget _buildSupportInfo() {
    return _buildSection(
      title: 'Support & Information',
      children: [
        _buildSettingsItem(
          icon: Icons.help_outline,
          title: 'Help Center',
          subtitle: 'FAQs and support articles',
          onTap: () {
            context.push(AppRoutes.helpCenter);
          },
        ),
        _buildSettingsItem(
          icon: Icons.description_outlined,
          title: 'Terms & Privacy',
          subtitle: 'Legal information',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const TermsAndConditionsPage(),
              ),
            );
          },
        ),
        _buildSettingsItem(
          icon: Icons.info_outline,
          title: 'About',
          subtitle: 'App version and information',
          onTap: () {
            // TODO: Show about dialog
          },
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
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
            children: children.map((child) {
              final index = children.indexOf(child);
              return Column(
                children: [
                  child,
                  if (index < children.length - 1)
                    Divider(
                      color: AppColors.borderColor,
                      height: 1,
                      indent: 60,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showBadge = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: AppColors.textPrimary,
          size: 24,
        ),
      ),
      title: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (showBadge) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'PRO',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }

  Widget _buildLogoutSection() {
    return GestureDetector(
      onTap: () {
        _showLogoutDialog();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.logout,
                size: 24,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Sign Out',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Sign Out',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out?',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (mounted) {
                  context.read<AuthBloc>().add(const AuthLogoutRequested());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.white,
              ),
              child: Text(
                'Sign Out',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}