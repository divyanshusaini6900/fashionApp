import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive_utils.dart';

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  String _searchQuery = '';
  String? _expandedCategory;
  String? _expandedQuestion;

  final Map<String, List<FAQItem>> _faqCategories = {
    'Getting Started': [
      FAQItem(
        question: 'What is RatNawnAI?',
        answer: 'RatNawnAI is an AI workspace that transforms mannequin photos into model-ready images in under 5 minutes. Along with images, you can also generate videos and product descriptions. If required, RatNawnAI can further add that description into an Excel sheet—making your catalog ready in minutes.',
        icon: Icons.auto_awesome,
      ),
      FAQItem(
        question: 'How do I get started?',
        answer: '1. Create an account (sign up) or log in.\n2. Upload product photos (front, side, back, and detail views).\n3. In case you have design in sleeves or other details you can add those images in "Additional Images"\n4. Select how many images you want to generate\n5. If you want to generate a video too, just toggle on the video button\n6. Tap Generate.\n\nYour results will appear in under 5 minutes and can be exported anytime.',
        icon: Icons.rocket_launch,
      ),
    ],
    'Product Categories': [
      FAQItem(
        question: 'Which product categories does RatNawnAI support?',
        answer: 'RatNawnAI is built to handle a wide range of fashion categories. For best results, upload mannequin/product shots and then select Male or Female.\n\n**Men\'s Categories:**\n• Western Wear: T-Shirts, Shirts, Polo Shirts, Hoodies & Sweatshirts, Jackets & Coats, Jeans, Pants/Trousers, Shorts, Blazers & Suits, Activewear\n• Ethnic Wear: Kurta, Sherwani, Nehru Jacket, Pathani Suit, Indo-Western Sets\n\n**Women\'s Categories:**\n• Western Wear: Tops, Shirts, Dresses, Jumpsuits/Rompers, Jeans, Pants/Trousers, Skirts, Shorts, Hoodies & Sweaters, Jackets & Coats, Blazers/Suits, Activewear\n• Ethnic Wear: Kurti/Kurta, Salwar Suit, Lehenga Choli, Anarkali Suit, Palazzo & Dupatta Sets, Ethnic Gowns\n\nTip: For items like dupattas ensure they are neatly draped on the mannequin for best generation results.\n\nPlease note saree and dhoti draping may not produce satisfactory outputs with RatNawnAI at this stage.',
        icon: Icons.category,
      ),
    ],
    'Image Guidelines': [
      FAQItem(
        question: 'What kind of images should I upload to ensure the best result?',
        answer: 'You can get best results if you provide clear, evenly lit mannequin photos on a plain background.\n\nBest practices:\n• Clear, high-resolution images\n• Even lighting\n• Plain background\n• Multiple angles (front, back, side, detail)',
        icon: Icons.check_circle,
      ),
      FAQItem(
        question: 'What kind of images should I not upload?',
        answer: 'Avoid:\n• Blurry or low-quality images\n• Complex backgrounds\n• Poor lighting\n• Incomplete product views\n• Images with watermarks or text overlays\n• Heavily edited or filtered images',
        icon: Icons.cancel,
      ),
    ],
    'Generation Process': [
      FAQItem(
        question: 'Do I need to write prompts or choose styles?',
        answer: 'No prompts or style settings needed! First, upload images: include a clear front view, back view, and a close view; if the sleeves have any design, add those as "additional images." Then choose the number of outputs needed and enter a short description (up to 50 characters). Click Generate.\n\nIf the same description is required in Excel form, toggle on the Excel option. If a video is needed, toggle on the video option as well. That\'s it!',
        icon: Icons.edit_note,
      ),
      FAQItem(
        question: 'How long does generation take?',
        answer: 'Images, videos, and descriptions are generated simultaneously. Total time depends on how many you request in one session, but results usually appear within 5 minutes.',
        icon: Icons.timer,
      ),
      FAQItem(
        question: 'Can I process multiple items at once?',
        answer: 'Yes. You can upload and start a new session while your previous session is still generating. This lets multiple items run in parallel without waiting for one to finish.',
        icon: Icons.multiple_stop,
      ),
    ],
    'Credits & Pricing': [
      FAQItem(
        question: 'How are credits charged?',
        answer: '• 1 credit = one image\n• 1 credit = one video\n• 0.5 credit = Product Description text in an Excel sheet for one dress',
        icon: Icons.monetization_on,
      ),
      FAQItem(
        question: 'Can I refine the results?',
        answer: 'Direct editing isn\'t supported. You can re‑generate instead, with simple, upfront pricing:\n\n• First re‑generation for an image or video: free.\n• Second re‑generation: half credits (0.5 per image, 0.5 per video).\n• Further attempts: standard rate, 1 credit per image and 1 credit per video.\n\nThis keeps the first retry free, the second discounted, and only additional iterations billed at the full rate.',
        icon: Icons.refresh,
      ),
    ],
    'Output & Export': [
      FAQItem(
        question: 'What do I receive after generation?',
        answer: '• Model-ready images sized for common marketplaces and social media\n• Optional: Video, product description text in an Excel sheet\n\nYou can download these files from the "My Downloads" section.',
        icon: Icons.download,
      ),
      FAQItem(
        question: 'Which marketplaces are supported?',
        answer: 'Export presets are available for major platforms with the right image sizes and aspect ratios.',
        icon: Icons.store,
      ),
    ],
    'Troubleshooting': [
      FAQItem(
        question: 'What if a generation fails?',
        answer: 'If something fails, you\'ll see a status message. Credits are automatically refunded for failed jobs. You can try again or contact Support.',
        icon: Icons.error_outline,
      ),
    ],
    'Privacy & Support': [
      FAQItem(
        question: 'How is my data handled?',
        answer: 'Your files are processed securely. See Privacy Policy for full details.',
        icon: Icons.security,
      ),
      FAQItem(
        question: 'How do I contact Support?',
        answer: 'Go to Profile → Help & Support. You can email us — typical response time is 24 to 48 business hours.',
        icon: Icons.support_agent,
      ),
    ],
  };

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _searchController.addListener(_onSearchChanged);
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

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  Map<String, List<FAQItem>> _getFilteredFAQs() {
    if (_searchQuery.isEmpty) {
      return _faqCategories;
    }

    Map<String, List<FAQItem>> filtered = {};
    
    _faqCategories.forEach((category, items) {
      List<FAQItem> matchingItems = items.where((item) {
        return item.question.toLowerCase().contains(_searchQuery) ||
               item.answer.toLowerCase().contains(_searchQuery);
      }).toList();
      
      if (matchingItems.isNotEmpty) {
        filtered[category] = matchingItems;
      }
    });
    
    return filtered;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredFAQs = _getFilteredFAQs();
    
    return Scaffold(
      backgroundColor: AppColors.backgroundBlue,
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: SlideTransition(
              position: _slideAnimation,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  _buildModernAppBar(),
                  SliverPadding(
                    padding: ResponsiveUtils.getResponsivePadding(
                      context,
                      mobile: const EdgeInsets.all(16),
                      tablet: const EdgeInsets.all(24),
                      desktop: const EdgeInsets.all(32),
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildSearchBar(),
                        const SizedBox(height: 24),
                        _buildQuickActions(),
                        const SizedBox(height: 24),
                        _buildPopularQuestions(),
                        const SizedBox(height: 24),
                        if (filteredFAQs.isEmpty)
                          _buildNoResultsFound()
                        else
                          ...filteredFAQs.entries.map((entry) => Column(
                            children: [
                              _buildFAQSection(entry.key, entry.value),
                              const SizedBox(height: 20),
                            ],
                          )).toList(),
                        _buildContactSupport(),
                        const SizedBox(height: 100),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildModernAppBar() {
    return SliverAppBar(
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.help_outline,
                          color: AppColors.primaryBlue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Help Center',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Find answers to your questions',
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
        title: Container(),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(4),
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
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search for help...',
          hintStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.textSecondary,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withOpacity(0.05),
            AppColors.primaryBlue.withOpacity(0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryBlue.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionItem(
                  icon: Icons.email,
                  label: 'Email Support',
                  onTap: () {
                    // Handle email support
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionItem(
                  icon: Icons.chat,
                  label: 'Live Chat',
                  onTap: () {
                    // Handle live chat
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionItem(
                  icon: Icons.book,
                  label: 'User Guide',
                  onTap: () {
                    // Handle user guide
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionItem(
                  icon: Icons.videocam,
                  label: 'Video Tutorials',
                  onTap: () {
                    // Handle video tutorials
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowColor.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: AppColors.primaryBlue,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularQuestions() {
    final popularQuestions = [
      'How do I get started?',
      'How are credits charged?',
      'What kind of images should I upload?',
    ];

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
            children: [
              Icon(
                Icons.trending_up,
                color: AppColors.success,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Popular Questions',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...popularQuestions.map((question) => GestureDetector(
            onTap: () {
              _searchController.text = question;
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.backgroundBlue,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.borderColor,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 16,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      question,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildFAQSection(String title, List<FAQItem> items) {
    final isExpanded = _expandedCategory == title;
    
    return Container(
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
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _expandedCategory = isExpanded ? null : title;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryBlue.withOpacity(0.05),
                    AppColors.primaryBlue.withOpacity(0.02),
                  ],
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getCategoryIcon(title),
                      color: AppColors.primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${items.length}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Column(
              children: items.map((item) {
                final index = items.indexOf(item);
                return Column(
                  children: [
                    if (index > 0)
                      Divider(
                        color: AppColors.borderColor,
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                      ),
                    _buildFAQItem(item),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFAQItem(FAQItem item) {
    final isExpanded = _expandedQuestion == item.question;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedQuestion = isExpanded ? null : item.question;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.icon,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.question,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.backgroundBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.answer,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsFound() {
    return Container(
      padding: const EdgeInsets.all(40),
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
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: AppColors.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching with different keywords',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSupport() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withOpacity(0.1),
            AppColors.success.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryBlue.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.support_agent,
            size: 48,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(height: 16),
          Text(
            'Still need help?',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Our support team is here to assist you',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Handle contact support
                  },
                  icon: const Icon(Icons.email),
                  label: Text(
                    'Email Support',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                Text(
                  'Response within 24-48 hours',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Getting Started':
        return Icons.rocket_launch;
      case 'Product Categories':
        return Icons.category;
      case 'Image Guidelines':
        return Icons.image;
      case 'Generation Process':
        return Icons.settings;
      case 'Credits & Pricing':
        return Icons.monetization_on;
      case 'Output & Export':
        return Icons.download;
      case 'Troubleshooting':
        return Icons.build;
      case 'Privacy & Support':
        return Icons.security;
      default:
        return Icons.help_outline;
    }
  }
}

class FAQItem {
  final String question;
  final String answer;
  final IconData icon;

  FAQItem({
    required this.question,
    required this.answer,
    required this.icon,
  });
}