import 'package:RatNawnAI_app/features/export/presentation/pages/export_page.dart';
import 'package:RatNawnAI_app/features/upload/presentation/pages/smart_GenSpace_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/api_config.dart';
import '../../../pricing/presentation/pages/pricing_page.dart';
import '../widgets/home_dashboard.dart';
import '../../../navbar/navigation_wrapper.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _animationController;
  bool _isNavigating = false;
  
  // Track page controllers for cleanup
  final Map<int, GlobalKey> _pageKeys = {
    0: GlobalKey(),
    1: GlobalKey(),
    2: GlobalKey(),
    3: GlobalKey(),
  };

  final List<NavItem> _navItems = [
    NavItem(
      icon: Icons.home_rounded,
      label: 'Home',
      activeColor: AppColors.primaryBlue,
    ),
    NavItem(
      icon: Icons.auto_awesome,
      label: 'GenSpace',
              activeColor: AppColors.primaryBlue,
    ),
    NavItem(
      icon: Icons.download_rounded,
      label: 'Export',
              activeColor: AppColors.primaryAccent,
    ),
    NavItem(
      icon: Icons.monetization_on_rounded,
      label: 'Pricing',
      activeColor: AppColors.primaryAccent,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: ApiConfig.mediumAnimation,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onNavigationTap(int index) {
    if (_isNavigating || _currentIndex == index) return;
    
    _isNavigating = true;
    
    // Use setState safely
    if (mounted) {
      setState(() {
        _currentIndex = index;
      });
    }
    
    // Reset navigation flag after animation
    Future.delayed(ApiConfig.mediumAnimation, () {
      if (mounted) {
        _isNavigating = false;
      }
    });
  }

  Widget _buildPage(int index) {
    Widget page;
    
    switch (index) {
      case 0:
        page = HomeDashboard(
          key: _pageKeys[0],
          onNavigateToTab: _onNavigationTap,
        );
        break;
      case 1:
        page = SmartGenSpacePage(key: _pageKeys[1]);
        break;
      case 2:
        page = ExportPage(key: _pageKeys[2]);
        break;
      case 3:
        page = RatnawnAIPricingPage(key: _pageKeys[3]);
        break;
      default:
        page = const SizedBox();
    }
    
    // Wrap pages with NavigationWrapper for proper lifecycle management
    return NavigationWrapper(
      key: ValueKey(index),
      maintainState: true,
      child: page,
      onActivate: () {
        debugPrint('Page $index activated');
      },
      onDeactivate: () {
        debugPrint('Page $index deactivated');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(4, (index) => _buildPage(index)),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth > 600;
        final isLargeScreen = screenWidth > 900;
        
        return Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isLargeScreen ? 32 : (isTablet ? 24 : 16), 
                vertical: isTablet ? 12 : 8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _navItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final isActive = _currentIndex == index;

                  return _buildNavItem(
                    item, 
                    isActive, 
                    () => _onNavigationTap(index), 
                    isTablet, 
                    isLargeScreen
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem(NavItem item, bool isActive, VoidCallback onTap, bool isTablet, bool isLargeScreen) {
    final iconSize = isLargeScreen ? 28.0 : (isTablet ? 26.0 : 24.0);
    final fontSize = isLargeScreen ? 14.0 : (isTablet ? 13.0 : 12.0);
    final horizontalPadding = isLargeScreen ? 20.0 : (isTablet ? 18.0 : 16.0);
    final verticalPadding = isTablet ? 10.0 : 8.0;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: ApiConfig.shortAnimation,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        decoration: BoxDecoration(
          color: isActive ? item.activeColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(isTablet ? 24 : 20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: ApiConfig.shortAnimation,
              padding: EdgeInsets.all(isTablet ? 10 : 8),
              decoration: BoxDecoration(
                color: isActive ? item.activeColor : Colors.transparent,
                borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
              ),
              child: Icon(
                item.icon,
                size: iconSize,
                color: isActive ? AppColors.white : AppColors.grey,
              ),
            ),
            SizedBox(height: isTablet ? 6 : 4),
            Text(
              item.label,
              style: GoogleFonts.poppins(
                fontSize: fontSize,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? item.activeColor : AppColors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final String label;
  final Color activeColor;

  NavItem({
    required this.icon,
    required this.label,
    required this.activeColor,
  });
}