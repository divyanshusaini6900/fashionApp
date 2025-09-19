import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/routes/app_routes.dart';
import '../../bloc/auth_bloc.dart';
import '../../utils/signup_validator.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/phone_input_field.dart';
import '../widgets/city_autocomplete_field.dart';
import '../widgets/gradient_button.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
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
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _signUp() {
    if (_formKey.currentState!.validate()) {
      // First, navigate to signup with signupInProgress parameter to prevent home redirect
      context.go('/signup?signupInProgress=1');
      
      // Extract data from form fields
      final rawFullName = _nameController.text;
      final rawEmail = _emailController.text;
      final rawPhoneNumber = _phoneController.text;
      final rawCity = _cityController.text;
      
      print('🎯 SIGNUP: Starting Full Name validation and Firebase save process');
      print('📝 Raw Full Name from CustomTextField: "$rawFullName"');
      
      // Comprehensive validation using our validator
      final validationResult = SignupValidator.validateSignupData(
        fullName: rawFullName,
        email: rawEmail,
        phoneNumber: rawPhoneNumber,
        city: rawCity,
      );
      
      if (!validationResult['isValid']) {
        final errors = validationResult['errors'] as List<String>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errors.first),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        print('❌ Signup validation failed: $errors');
        // Remove signupInProgress parameter on failure
        context.go('/signup');
        return;
      }
      
      // Extract processed data
      final processedData = validationResult['processedData'] as Map<String, String>;
      final formattedFullName = processedData['fullName']!;
      final formattedEmail = processedData['email']!;
      final formattedPhone = processedData['phoneNumber']!;
      final formattedCity = processedData['city']!;
      
      print('✅ SIGNUP: All validation passed');
      print('🎯 Final Full Name for Firebase: "$formattedFullName"');
      print('📧 Final Email: "$formattedEmail"');
      print('📱 Final Phone: "$formattedPhone"');
      print('🏙️ Final City: "$formattedCity"');
      
      // Trigger signup with validated and formatted data
      context.read<AuthBloc>().add(
        AuthSignUpRequested(
          name: formattedFullName, // Use the validated and formatted Full Name
          email: formattedEmail,
          password: _passwordController.text,
          phoneNumber: formattedPhone,
          city: formattedCity,
        ),
      );
      
      print('🚀 SIGNUP: AuthSignUpRequested sent to BLoC with Full Name: "$formattedFullName"');
    } else {
      print('❌ Form validation failed - please check all fields');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthSignUpSuccess) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
            // Navigate to login page without signupInProgress parameter
            // Add small delay to ensure auth state is updated
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) {
                print('✅ Signup successful, navigating to login page');
                context.go(AppRoutes.login);
              }
            });
          } else if (state is AuthError) {
            // Remove signupInProgress parameter on error and show error message
            context.go('/signup');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildHeader(),
                                    const SizedBox(height: 32),
                                    _buildSignUpForm(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.person_add_rounded,
            size: 50,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Create Account',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Join RatNawnAI to start your fashion journey',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppColors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSignUpForm() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign Up',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.darkGrey,
              ),
            ),
            const SizedBox(height: 24),
            
            // Full Name Field - Connected to Firebase saving
            CustomTextField(
              controller: _nameController,
              labelText: 'Full Name',
              hintText: 'Enter your full name ',
              prefixIcon: Icons.person_outline,
              keyboardType: TextInputType.name,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your full name';
                }
                final trimmedValue = value.trim();
                if (trimmedValue.length < 2) {
                  return 'Full name must be at least 2 characters';
                }
                // Check for valid name format (at least first name)
                if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmedValue)) {
                  return 'Full name can only contain letters and spaces';
                }
                // Ensure there's at least one non-space character
                if (trimmedValue.replaceAll(' ', '').isEmpty) {
                  return 'Please enter a valid full name';
                }
                // Debug: Log validation process
                print('📝 Full Name field validated: "${trimmedValue}"');
                return null;
              },
            ),
            
            const SizedBox(height: 20),
            
            // Email Field
            CustomTextField(
              controller: _emailController,
              labelText: 'Email Address',
              hintText: 'Enter your email',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 20),
            
            // Password Field
            CustomTextField(
              controller: _passwordController,
              labelText: 'Password',
              hintText: 'Enter password',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                // Check for strong password
                if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{6,}$').hasMatch(value)) {
                  return 'Password must contain uppercase, lowercase and number';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 20),
            
            // Confirm Password Field
            CustomTextField(
              controller: _confirmPasswordController,
              labelText: 'Confirm Password',
              hintText: 'Re-enter your password',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscureConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 20),
            
            // Phone Number Field
            PhoneInputField(
              controller: _phoneController,
              labelText: 'Phone Number',
              hintText: 'Enter your phone number',
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your phone number';
                }
                if (value.length != 10) {
                  return 'Phone number must be 10 digits';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 20),
            
            // City Field
            CityAutocompleteField(
              controller: _cityController,
              labelText: 'City',
              hintText: 'Type to search cities worldwide',
              prefixIcon: Icons.location_city_outlined,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your city';
                }
                if (value.trim().length < 2) {
                  return 'City name must be at least 2 characters';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 12),
            
            // Password Requirements Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.lightBlue.withOpacity(0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Password must contain at least 6 characters with uppercase, lowercase letters and numbers',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Sign Up Button
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final isLoading = state is AuthLoading;
                
                return GradientButton(
                  onPressed: isLoading ? null : _signUp,
                  gradient: AppColors.buttonGradient,
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.white,
                            ),
                          ),
                        )
                      : Text(
                          'Create Account',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already have an account? ',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.grey,
                ),
              ),
              GestureDetector(
                onTap: () {
                  context.go(AppRoutes.login);
                },
                child: Text(
                  'Login',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '© 2025 RatNawnAI. All rights reserved.',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}