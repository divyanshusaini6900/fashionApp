import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive_utils.dart';

class TermsAndConditionsPage extends StatefulWidget {
  const TermsAndConditionsPage({super.key});

  @override
  State<TermsAndConditionsPage> createState() => _TermsAndConditionsPageState();
}

class _TermsAndConditionsPageState extends State<TermsAndConditionsPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolled = false;
  bool _showPrivacyPolicy = true; // Toggle between Terms and Privacy

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _scrollController.addListener(_onScroll);
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

  void _onScroll() {
    if (_scrollController.offset > 50 && !_hasScrolled) {
      setState(() {
        _hasScrolled = true;
      });
    } else if (_scrollController.offset <= 50 && _hasScrolled) {
      setState(() {
        _hasScrolled = false;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  _buildAppBar(),
                  SliverPadding(
                    padding: ResponsiveUtils.getResponsivePadding(
                      context,
                      mobile: const EdgeInsets.all(16),
                      tablet: const EdgeInsets.all(24),
                      desktop: const EdgeInsets.all(32),
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildToggleButtons(),
                        const SizedBox(height: 24),
                        if (_showPrivacyPolicy) ..._buildPrivacyPolicySections(),
                        if (!_showPrivacyPolicy) ..._buildTermsSections(),
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

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      floating: false,
      pinned: true,
      backgroundColor: _hasScrolled ? AppColors.white : Colors.transparent,
      foregroundColor: _hasScrolled ? AppColors.textPrimary : AppColors.white,
      elevation: _hasScrolled ? 2 : 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primaryBlue,
                AppColors.primaryBlue.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                top: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.white.withOpacity(0.1),
                  ),
                ),
              ),
              Positioned(
                left: -30,
                bottom: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.white.withOpacity(0.05),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.description,
                        size: 48,
                        color: AppColors.white,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Privacy & Policy',
                        style: GoogleFonts.poppins(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Last updated: August 20, 2025',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back,
          color: _hasScrolled ? AppColors.textPrimary : AppColors.white,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.verified_user,
              size: 48,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'TechRelieve & RatNawnAI',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Please read these terms and privacy policy carefully before using our services',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButtons() {
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
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showPrivacyPolicy = true;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _showPrivacyPolicy
                      ? AppColors.primaryBlue
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.privacy_tip,
                      size: 20,
                      color: _showPrivacyPolicy
                          ? AppColors.white
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Privacy Policy',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _showPrivacyPolicy
                            ? AppColors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showPrivacyPolicy = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_showPrivacyPolicy
                      ? AppColors.primaryBlue
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.gavel,
                      size: 20,
                      color: !_showPrivacyPolicy
                          ? AppColors.white
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Terms of Service',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: !_showPrivacyPolicy
                            ? AppColors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPrivacyPolicySections() {
    return [
      _buildSection(
        icon: Icons.business,
        title: '🏢 Company Information',
        content: [
          _buildInfoCard(
            'Company',
            'TechRelieve (OPC) Private Limited',
            Icons.domain,
          ),
          _buildInfoCard(
            'Product Platform',
            'RatNawnAI - AI-powered product visual generation',
            Icons.auto_awesome,
          ),
          _buildInfoCard(
            'Our Platforms',
            '🌐 TechRelieve.ai  🤖 RatNawnAI.com',
            Icons.language,
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.warning_amber,
        title: '⚠️ Important Consent Notice',
        content: [
          _buildTermItem(
            'Consent Agreement',
            'By accessing RatNawnAI or TechRelieve services, you consent to the collection, use, and sharing of your personal information as per this Policy. If you do not agree with these terms, please stop using our services.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.data_usage,
        title: '📊 Information We Collect',
        content: [
          _buildTermItem(
            '👤 Personal Information',
            '• Name\n• Email address\n• Phone number\n• Business details\n• Product data',
          ),
          _buildTermItem(
            '🛒 Customer Information',
            '• Product photos uploaded to RatNawnAI\n• Image files and associated metadata\n• Product descriptions and specifications\n• Generated content (images, videos, Excel files)',
          ),
          _buildTermItem(
            '📱 Automatically Collected Data',
            '• IP addresses\n• Device and browser type\n• Login logs and access patterns\n• Platform analytics and usage data',
          ),
          _buildTermItem(
            '🍪 Cookies & Tracking',
            '• Website cookies for functionality\n• Third-party analytics tools\n• User experience optimization data\n• Session management information',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.psychology,
        title: '🎯 How We Use Your Information',
        content: [
          _buildTermItem(
            'Service Provision',
            '• To provide and improve RatNawnAI services\n• To process transactions, generate product visuals, videos, Excel sheets\n• To personalize product recommendations',
          ),
          _buildTermItem(
            'Security & Communication',
            '• For fraud detection, system security, and compliance with applicable laws\n• For updates, offers, transactional & service-related communications (SMS, Email, WhatsApp)',
          ),
          _buildTermItem(
            'Improvement & Support',
            '• To enhance AI algorithms and improve processing quality\n• To provide customer support and technical assistance\n• To analyze usage patterns and optimize platform performance',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.security,
        title: '🔒 Data Security',
        content: [
          _buildTermItem(
            '🛡️ Security Measures',
            'We implement industry-standard measures to protect your data but cannot guarantee 100% security over the internet.\n\nYour account and uploads in RatNawnAI are password-protected. You are responsible for maintaining account confidentiality.',
          ),
          _buildTermItem(
            '🔐 Protection Standards',
            '• Encryption: Data transmission using SSL/TLS encryption\n• Access Control: Limited employee access to personal data\n• Regular Audits: Security assessments and vulnerability testing\n• Secure Storage: Industry-standard data center security\n• Password Protection: Secure user authentication systems',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.share,
        title: '🤝 Sharing of Information',
        content: [
          _buildTermItem(
            '🚫 No Data Sales',
            'We do not sell your personal information. However, we may share limited data with:\n\n• Affiliates, subsidiaries, and service providers - For platform operations and service delivery\n• Regulatory authorities, law enforcement, or courts - If required by law\n• Business partners - For integration and enhanced services (with your consent)\n• Third-party processors - For payment processing and essential services',
          ),
          _buildTermItem(
            '🏢 Business Transfers',
            'If TechRelieve is ever merged or acquired, your information will transfer to the new entity subject to this Policy.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.gavel,
        title: '⚖️ Your Rights',
        content: [
          _buildTermItem(
            '🔧 Data Control Rights',
            '• Access & Update: You can update or modify your personal information through your account\n• Data Deletion: Request complete deletion of your account and associated data by contacting us\n• Data Portability: Request a copy of your data in a machine-readable format\n• Processing Restriction: Request limitation of how we process your data\n• Opt-out: Unsubscribe from marketing communications at any time\n• Correction: Request correction of inaccurate personal information',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.contact_support,
        title: '📞 Grievance Redressal & Data Protection',
        content: [
          _buildContactCard(),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.balance,
        title: '⚖️ Applicable Law',
        content: [
          _buildTermItem(
            '🏛️ Legal Jurisdiction',
            'This Policy is governed by the laws of India. All disputes will be subject to the jurisdiction of competent courts in Bangalore, India.',
          ),
          _buildTermItem(
            '📋 Compliance Standards',
            'TechRelieve and RatNawnAI operate in compliance with:\n\n• Information Technology Act, 2000 and its amendments\n• Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021\n• Personal Data Protection Bill (as applicable)\n• Other applicable Indian data protection regulations',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.rocket_launch,
        title: '🚀 About TechRelieve & RatNawnAI',
        content: [
          _buildTermItem(
            'About Us',
            'TechRelieve (OPC) Private Limited is an innovative technology company dedicated to solving real-world problems through AI-powered solutions.\n\nRatNawnAI is our flagship product platform that revolutionizes product visual creation using artificial intelligence. Upload raw product photos and instantly generate professional images, dynamic videos, and organized Excel data files.',
          ),
          _buildTermItem(
            '🎯 Our Mission',
            'Empowering businesses to create stunning product visuals without the need for models, studios, or complex production processes.',
          ),
          _buildTermItem(
            '⚡ Our Promise',
            'Lightning-fast processing, professional results, and complete data privacy protection.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildFooter(),
    ];
  }

  List<Widget> _buildTermsSections() {
    return [
      _buildSection(
        icon: Icons.gavel,
        title: '1. Acceptance of Terms',
        content: [
          _buildTermItem(
            'Agreement',
            'By accessing RatNawnAI or TechRelieve services, you agree to be bound by these Terms and Conditions. If you disagree with any part of these terms, you may not access our services.',
          ),
          _buildTermItem(
            'Eligibility',
            'You must be at least 18 years old or have parental consent to use our services. By using our platform, you represent that you meet these requirements.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.auto_awesome,
        title: '2. Service Description',
        content: [
          _buildTermItem(
            'RatNawnAI Services',
            'RatNawnAI provides AI-powered product visual generation services including:\n• Professional image creation\n• Dynamic video generation\n• Excel data file organization\n• Background removal and replacement\n• Product enhancement features',
          ),
          _buildTermItem(
            'Service Availability',
            'We strive for 99.9% uptime but cannot guarantee uninterrupted service. Processing times may vary based on server load and content complexity.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.person_pin,
        title: '3. User Responsibilities',
        content: [
          _buildTermItem(
            'Account Management',
            '• Maintain account confidentiality\n• Provide accurate and complete information\n• Keep your password secure\n• Notify us of any unauthorized access\n• Update information as needed',
          ),
          _buildTermItem(
            'Acceptable Use',
            '• Use services lawfully and ethically\n• Respect intellectual property rights\n• Not misuse or abuse the platform\n• Not attempt to breach security\n• Follow platform guidelines',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.copyright,
        title: '4. Content & Intellectual Property',
        content: [
          _buildTermItem(
            'Your Content',
            'You retain ownership of your uploaded content. By using our services, you grant us a license to process and generate outputs based on your content. Generated outputs are yours to use commercially.',
          ),
          _buildTermItem(
            'Platform Content',
            'All platform content, including but not limited to text, graphics, logos, and software, is the property of TechRelieve and protected by intellectual property laws.',
          ),
          _buildTermItem(
            'License Grant',
            'We grant you a limited, non-exclusive, non-transferable license to use our services for your personal or business purposes in accordance with these terms.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.payment,
        title: '5. Payment Terms',
        content: [
          _buildTermItem(
            'Credit System',
            'Services are provided on a credit-based system. Credits can be purchased through our pricing plans. All prices are subject to change with notice.',
          ),
          _buildTermItem(
            'Billing',
            'All purchases are final. Credits expire according to plan terms. We reserve the right to modify pricing with 30 days notice.',
          ),
          _buildTermItem(
            'Refunds',
            'Unused credits are non-refundable. We may offer refunds for technical issues at our discretion. Refund requests must be made within 7 days of purchase.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.block,
        title: '6. Prohibited Activities',
        content: [
          _buildTermItem(
            'You may not:',
            '• Upload illegal, harmful, or offensive content\n• Violate any intellectual property rights\n• Attempt to breach our security measures\n• Use the service for spam, fraud, or deception\n• Resell services without authorization\n• Reverse engineer our technology\n• Use automated systems to access services\n• Impersonate others or misrepresent affiliation',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.shield,
        title: '7. Limitation of Liability',
        content: [
          _buildTermItem(
            'Service Liability',
            'Our liability is limited to the amount paid for services in the last 12 months. We are not liable for indirect, incidental, special, or consequential damages.',
          ),
          _buildTermItem(
            'No Warranties',
            'Services are provided "as is" without warranties of any kind, either express or implied. We do not guarantee specific results or outcomes.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.security,
        title: '8. Indemnification',
        content: [
          _buildTermItem(
            'Your Indemnification',
            'You agree to indemnify and hold harmless TechRelieve, its officers, directors, employees, and agents from any claims, damages, losses, or expenses arising from:\n• Your use of services\n• Violation of these terms\n• Infringement of any rights\n• Your content',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.update,
        title: '9. Modifications',
        content: [
          _buildTermItem(
            'Terms Updates',
            'We reserve the right to modify these terms at any time. Significant changes will be notified via email or platform notifications. Continued use after changes constitutes acceptance.',
          ),
          _buildTermItem(
            'Service Changes',
            'We may modify, suspend, or discontinue any aspect of our services at any time with or without notice.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildSection(
        icon: Icons.cancel,
        title: '10. Termination',
        content: [
          _buildTermItem(
            'Account Termination',
            'We reserve the right to terminate or suspend your account for violation of these terms. You may terminate your account at any time by contacting support.',
          ),
          _buildTermItem(
            'Effect of Termination',
            'Upon termination, your right to use services ceases immediately. Some provisions of these terms survive termination.',
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildFooter(),
    ];
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> content,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermItem(String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.backgroundBlue,
            AppColors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.primaryBlue,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withOpacity(0.05),
            AppColors.success.withOpacity(0.05),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.support_agent,
                  color: AppColors.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '📋 Data Protection Officer (DPO)',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildContactItem(Icons.person, 'Mrs. SUNITA DEVI BARNWAL'),
          _buildContactItem(Icons.business, 'TechRelieve (OPC) Private Limited'),
          _buildContactItem(Icons.email, 'saddam.husain@techrelieve.ai'),
          _buildContactItem(Icons.phone, '+91 94710 24102'),
          _buildContactItem(Icons.web, 'techrelieve.ai/grievances'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                Text(
                  '📝 Response within 48 hours',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.delete_forever,
                  size: 16,
                  color: AppColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🗑️ Data Deletion Request available',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.error,
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

  Widget _buildContactItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'RatNawnAI',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'AI-Powered Product Visual Generation',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              _buildMissionCard(
                '🎯 Our Mission',
                'Empowering businesses',
                AppColors.primaryBlue,
              ),
              _buildMissionCard(
                '⚡ Our Promise',
                'Lightning-fast results',
                AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.success.withOpacity(0.3),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: AppColors.success,
                ),
                Text(
                  'Version 2.0 | Effective: August 20, 2025',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '© 2025 TechRelieve (OPC) Private Limited',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All rights reserved',
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

  Widget _buildMissionCard(String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}