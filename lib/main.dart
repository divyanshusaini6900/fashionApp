// main.dart - Fixed version with proper background service initialization

import 'package:RatNawnAI_app/core/services/background_GenSpace_service.dart';
import 'package:RatNawnAI_app/core/services/GenSpaceService.dart';
import 'package:RatNawnAI_app/features/export/bloc/export_bloc.dart';
import 'package:RatNawnAI_app/features/upload/services/GenSpace_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_app_check/firebase_app_check.dart'; // Disabled to prevent payment issues
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'core/services/background_video_service.dart';

import 'core/theme/app_theme.dart';
import 'core/routes/app_routes.dart';
import 'core/utils/clean_performance_utils.dart';
import 'core/services/firebase_service.dart' as firebase;
import 'core/services/fashion_ai_service.dart';
import 'core/services/discount_service.dart';

import 'features/auth/bloc/auth_bloc.dart';
import 'features/upload/bloc/upload_bloc.dart';

import 'features/wallet/bloc/wallet_bloc.dart';
import 'features/user/bloc/user_bloc.dart';
import 'firebase_options.dart';

import 'core/services/notification_service.dart';
import 'core/services/queue_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) print('🚀 Initializing RatNawnAI App...');

  try {
    // Initialize performance optimizations
    CleanPerformanceUtils.initialize();

    // Initialize Firebase with options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (kDebugMode) print('✅ Firebase initialized successfully');

    // Initialize Firebase App Check with environment-based providers
    // DISABLED: App Check is causing payment issues in release mode
    // try {
    //   await FirebaseAppCheck.instance.activate(
    //     androidProvider: kDebugMode
    //         ? AndroidProvider.debug // Debug provider for development
    //         : AndroidProvider.playIntegrity, // Play Integrity for production
    //     appleProvider: kDebugMode
    //         ? AppleProvider.debug // Debug provider for development
    //         : AppleProvider.appAttest, // App Attest for production
    //     webProvider: ReCaptchaV3Provider(
    //       '6Lce5aQrAAAAAHuf08NJ_1XUmtdpiZO76lfMjbfQ',
    //     ),
    //   );
    //   if (kDebugMode)
    //     print(
    //         '✅ Firebase App Check activated with ${kDebugMode ? "debug" : "Play Integrity"} provider');
    // } catch (e) {
    //   if (kDebugMode)
    //     print('⚠️ App Check activation failed (continuing without it): $e');
    // }

    if (kDebugMode) print('✅ App Check disabled to prevent payment issues');

    // Wait for Firebase Auth to be ready
    await FirebaseAuth.instance.authStateChanges().first;
    if (kDebugMode) print('✅ Firebase Auth ready');

    // Initialize Firebase services
    try {
      await firebase.FirebaseService.initialize();
      if (kDebugMode) print('✅ Firebase services initialized');
    } catch (e) {
      if (kDebugMode)
        print('⚠️ Warning: Firebase services initialization had issues: $e');
    }

    // Initialize Fashion AI service
    try {
      await FashionAIService().checkApiHealth();
      FashionAIService().initialize();
      if (kDebugMode) print('✅ Fashion AI service initialized');
    } catch (e) {
      if (kDebugMode) print('⚠️ Fashion AI service initialization warning: $e');
    }
    // Initialize Notification Service BEFORE Background Service
    try {
      await NotificationService.initialize();
      // Don't request permissions immediately - do it when needed
      if (kDebugMode) print('✅ Notification service initialized');
    } catch (e) {
      if (kDebugMode)
        print('⚠️ Notification service initialization warning: $e');
    }

    // Initialize Background GenSpace Service (with proper notification setup)
    try {
      await BackgroundGenSpaceService.initialize();
      if (kDebugMode) print('✅ Background GenSpace service initialized');
    } catch (e) {
      if (kDebugMode) print('⚠️ Background service initialization warning: $e');
      // App can continue without background service
    }
    // Initialize Background Video Service and check for stalled jobs
    try {
      final videoService = BackgroundVideoService();
      videoService.initialize(); // Initialize the service first
      await videoService.checkAndRestartStalledVideoJobs();
      if (kDebugMode) print('✅ Background video service initialized');
    } catch (e) {
      if (kDebugMode) print('⚠️ Video service initialization warning: $e');
      // App can continue without video service
    }
  } catch (e) {
    if (kDebugMode) print('❌ Initialization failed: $e');
  }

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  if (kDebugMode) print('🎉 Starting RatNawnAI App...');
  runApp(const RatNawnAIApp());
}

class RatNawnAIApp extends StatefulWidget {
  const RatNawnAIApp({super.key});

  @override
  State<RatNawnAIApp> createState() => _RatNawnAIAppState();
}

class _RatNawnAIAppState extends State<RatNawnAIApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Request notification permissions after a delay
    Future.delayed(Duration(seconds: 2), () {
      NotificationService.requestPermissions();
    });
    // Background service is already initialized in main()
    // No need to re-initialize here
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) print('App lifecycle state: $state');
    // Handle app lifecycle changes
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground
        if (kDebugMode) print('App resumed - checking for completed jobs');
        _checkCompletedJobs();
        break;

      case AppLifecycleState.paused:
        // App is going to background
        if (kDebugMode)
          print('App paused - background service will continue if needed');
        break;

      case AppLifecycleState.detached:
        // App is being terminated
        if (kDebugMode)
          print('App detached - background service will continue');
        break;

      default:
        break;
    }
  }

  Future<void> _checkCompletedJobs() async {
    // Check if any jobs were completed while app was in background
    try {
      // This will be handled by the GenSpaceService which has real-time listeners
      if (kDebugMode) print('Checking for jobs completed in background...');
    } catch (e) {
      if (kDebugMode) print('Error checking completed jobs: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Existing BLoC providers
        BlocProvider(create: (context) => AuthBloc()),
        BlocProvider(create: (context) => UploadBloc()),
        BlocProvider(create: (context) => exportBloc()),
        BlocProvider(create: (context) => WalletBloc()),
        BlocProvider(create: (context) => UserBloc()),
        // GenSpace services
        ChangeNotifierProvider(
          create: (context) {
            final service = GenSpaceAuthService();
            service.listenToAuthChanges();
            service.ensureInitialized().then((_) {
              if (kDebugMode) print('✅ GenSpaceAuthService initialized');
            }).catchError((error) {
              if (kDebugMode)
                print('❌ GenSpaceAuthService initialization error: $error');
            });
            return service;
          },
        ),

        ChangeNotifierProvider(create: (context) => GenSpaceService()),

        ChangeNotifierProvider(
          create: (context) {
            final queueManager = QueueManagerProvider();
            Future.microtask(() => queueManager.initialize());
            return queueManager;
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final discountService = DiscountService();
            Future.microtask(() => discountService.initialize());
            return discountService;
          },
        ),
      ],
      child: MaterialApp.router(
        title: 'RatNawnAI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: AppRoutes.router,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.0),
            ),
            child: child!,
          );
        },
      ),
    );
  }
}
