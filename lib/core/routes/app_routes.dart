import 'dart:async';

import 'package:RatNawnAI_app/features/export/presentation/pages/export_page.dart';
import 'package:RatNawnAI_app/features/upload/presentation/pages/smart_GenSpace_page.dart';
import 'package:RatNawnAI_app/features/wallet/walletPage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/signup_page.dart';
import '../../features/home/presentation/pages/home_page.dart';

import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/help_center_page.dart';
import '../../features/fashion_ai/screens/fashion_ai_screen.dart';
import '../../features/pricing/presentation/pages/pricing_page.dart';


class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String GenSpace = '/GenSpace';
  static const String fashionAI = '/fashion-ai';
  static const String export = '/export';
  static const String profile = '/profile';
  static const String helpCenter = '/help-center';
  static const String pricing = '/pricing';
  static const String wallet = '/wallet';

  static final GoRouter router = GoRouter(
    initialLocation: splash,
    refreshListenable: GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
    redirect: (context, state) {
      print('🔄 Router redirect - Location: ${state.matchedLocation}');
      
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final isLoggingIn = state.matchedLocation == login;
      final isSigningUp = state.matchedLocation == signup;
      final isSplash = state.matchedLocation == splash;

      // NEW: allow the app to explicitly request login even if "logged in"
      final forceLogin = state.uri.queryParameters['forceLogin'] == '1';
      
      // NEW: Check if signup is in progress to prevent home redirect during signup
      final signupInProgress = state.uri.queryParameters['signupInProgress'] == '1';

      print('👤 User logged in: $isLoggedIn');
      print('📍 Current location: ${state.matchedLocation}');
      print('🔄 Signup in progress: $signupInProgress');

      // Always allow splash screen
      if (isSplash) {
        print('✅ Allowing splash screen');
        return null;
      }

      // If not logged in and trying to access protected routes, redirect to login
      if (!isLoggedIn && !isLoggingIn && !isSigningUp) {
        print('🔐 Not logged in, redirecting to login');
        return login;
      }

      // If logged in and on login or signup page, redirect to home
      // BUT NOT if signup is in progress or forceLogin is requested
      if (isLoggedIn && (isLoggingIn || isSigningUp) && !forceLogin && !signupInProgress) {
        print('🏠 Logged in, redirecting to home');
        return home;
      }
      
      // If signup is in progress and user is on signup page, stay on signup
      if (signupInProgress && isSigningUp) {
        print('🎯 Signup in progress, staying on signup page');
        return null;
      }

      print('✅ No redirect needed');
      return null;
    },
    routes: [
      GoRoute(
        path: splash,
        name: 'splash',
        pageBuilder: (context, state) => _buildPageWithFadeTransition(
          context,
          state,
          const SplashPage(),
        ),
      ),
      GoRoute(
        path: login,
        name: 'login',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const LoginPage(),
        ),
      ),
      GoRoute(
        path: signup,
        name: 'signup',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const SignUpPage(),
        ),
      ),
      GoRoute(
        path: home,
        name: 'home',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const HomePage(),
        ),
      ),
      GoRoute(
        path: GenSpace,
        name: 'GenSpace',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const SmartGenSpacePage(),
        ),
      ),
      GoRoute(
        path: fashionAI,
        name: 'fashion-ai',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const FashionAIScreen(),
        ),
      ),
      GoRoute(
        path: export,
        name: 'export',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const ExportPage(),
        ),
      ),
      GoRoute(
        path: profile,
        name: 'profile',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const ProfilePage(),
        ),
      ),
      GoRoute(
        path: helpCenter,
        name: 'help-center',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const HelpCenterPage(),
        ),
      ),
      GoRoute(
        path: pricing,
        name: 'pricing',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const RatnawnAIPricingPage(),
        ),
      ),
      GoRoute(
        path: wallet,
        name: 'wallet',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context,
          state,
          const WalletPage(),
        ),
      ),
    ],
  );

  static Page<void> _buildPageWithSlideTransition(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).chain(
              CurveTween(curve: Curves.easeInOut),
            ),
          ),
          child: child,
        );
      },
    );
  }

  static Page<void> _buildPageWithFadeTransition(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation.drive(
            CurveTween(curve: Curves.easeInOut),
          ),
          child: child,
        );
      },
    );
  }
}

// Helper class to make GoRouter listen to auth state changes
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) {
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}