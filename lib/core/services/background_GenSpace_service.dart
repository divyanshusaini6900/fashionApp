// lib/core/services/background_GenSpace_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/api_config.dart';
import 'battery_optimization_helper.dart';
import 'firebase_service.dart';

/// Connection state tracking
class ConnectionState {
  bool isConnected = true;
  int connectionRetries = 0;
  DateTime? lastConnectionLost;
  DateTime? lastConnectionRestored;
  Map<String, dynamic>? lastKnownData;
  Map<String, dynamic> toMap() {
    return {
      'isConnected': isConnected,
      'connectionRetries': connectionRetries,
      'lastConnectionLost': lastConnectionLost?.toIso8601String(),
      'lastConnectionRestored': lastConnectionRestored?.toIso8601String(),
    };
  }
}

/// Background task names for WorkManager
class BackgroundTasks {
  static const String pollGenSpaces = 'poll_GenSpaces_task';
  static const String checkIncomplete = 'check_incomplete_GenSpaces';
  static const String resumeProcessing = 'resume_processing_task';
}

/// Background GenSpace Service with Full Features
class BackgroundGenSpaceService {
  static final BackgroundGenSpaceService _instance =
      BackgroundGenSpaceService._internal();
  factory BackgroundGenSpaceService() => _instance;
  BackgroundGenSpaceService._internal();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;
  static bool _notificationChannelCreated = false;
  static bool _monitoringActive = false;
  static final Map<String, ConnectionState> _jobConnectionStates = {};
  static Timer? _healthCheckTimer;
  static Timer? _quickCheckTimer;

  /// Initialize background service and WorkManager with persistence
  static Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) print('⚠️ Background service already initialized');
      return;
    }

    try {
      if (kDebugMode) print('🔄 Starting background service initialization...');

      // Initialize notifications first with silent channel
      await _initializeSilentNotifications();
      if (kDebugMode) print('✅ Notifications initialized');

      // Initialize WorkManager
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode, // Enable debug logs in debug mode
      );
      if (kDebugMode) print('✅ WorkManager initialized');

      // Cancel any existing periodic tasks to ensure clean state
      await Workmanager().cancelAll();
      if (kDebugMode) print('✅ Existing WorkManager tasks cancelled');

      // Ensure any existing background service is stopped on app start
      try {
        final service = FlutterBackgroundService();
        final isRunning = await service.isRunning();
        if (isRunning) {
          service.invoke('stop');
          if (kDebugMode)
            print('✅ Stopped existing background service on app start');
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ Failed to check/stop existing service: $e');
      }

      // Initialize Flutter Background Service with persistence
      await _initializeBackgroundService();
      if (kDebugMode) print('✅ Flutter Background Service configured');

      // Service monitoring will be set up only when service is actually started
      if (kDebugMode)
        print('✅ Service ready (monitoring disabled until needed)');

      _isInitialized = true;
      if (kDebugMode)
        print(
            '🎉 Background GenSpace Service fully initialized with persistence');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to initialize background service: $e');
      if (kDebugMode) print('Stack trace: ${StackTrace.current}');
    }
  }

  /// Set up service monitoring and auto-restart mechanisms
  static Future<void> _setupServiceMonitoring() async {
    try {
      // Cancel existing timers if any
      _healthCheckTimer?.cancel();
      _quickCheckTimer?.cancel();
      // Schedule regular service health checks every 2 minutes
      _healthCheckTimer = Timer.periodic(Duration(minutes: 2), (timer) async {
        await _performServiceHealthCheck();
      });
      // Additional monitoring for critical situations every 30 seconds
      _quickCheckTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
        await _quickHealthCheck();
      });

      if (kDebugMode)
        print('✅ Service monitoring and auto-restart established');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to setup service monitoring: $e');
    }
  }

  /// Stop service monitoring timers
  static void _stopServiceMonitoring() {
    try {
      _healthCheckTimer?.cancel();
      _quickCheckTimer?.cancel();
      _healthCheckTimer = null;
      _quickCheckTimer = null;
      _monitoringActive = false;
      if (kDebugMode) print('✅ Service monitoring stopped');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to stop service monitoring: $e');
    }
  }

  /// Perform quick health check and restart if needed
  static Future<void> _quickHealthCheck() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (!isRunning) {
        if (kDebugMode)
          print(
              '🔄 Quick check: Service not running, attempting immediate restart...');

        try {
          await service.startService();
          if (kDebugMode) print('✅ Service restarted via quick check');
        } catch (e) {
          if (kDebugMode) print('❌ Quick restart failed: $e');
        }
      }
    } catch (e) {
      // Silent fail for quick checks
    }
  }

  /// Perform comprehensive service health check
  static Future<void> _performServiceHealthCheck() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (!isRunning) {
        if (kDebugMode)
          print(
              '🔄 Service health check: Service not running, attempting restart...');

        // Attempt to restart the service
        try {
          await service.startService();
          if (kDebugMode) print('✅ Service restarted successfully');

          // Wait a bit and verify it's actually running
          await Future.delayed(Duration(seconds: 2));
          final isNowRunning = await service.isRunning();

          if (!isNowRunning) {
            if (kDebugMode)
              print('⚠️ Service restart failed, falling back to WorkManager');
            await _registerPeriodicTasks(); // Re-register as fallback
          }
        } catch (e) {
          if (kDebugMode) print('❌ Failed to restart service: $e');
          // Re-register WorkManager tasks as fallback
          await _registerPeriodicTasks();
        }
      }

      // Check for stalled jobs regardless of service status
      await _checkForStalledJobs();

      // Check for stalled jobs regardless of service status
      await _checkForStalledJobs();
    } catch (e) {
      if (kDebugMode) print('⚠️ Service health check failed: $e');
    }
  }

  /// Check for jobs that might be stalled and need intervention
  static Future<void> _checkForStalledJobs() async {
    try {
      if (!await _checkInternetConnection()) return;

      final firestore = FirebaseFirestore.instance;
      final cutoffTime =
          DateTime.now().subtract(Duration(hours: 1)); // Reduced from 2 hours

      final snapshot = await firestore
          .collection('GenSpace_jobs')
          .where('status', isEqualTo: 'processing')
          .where('lastUpdated', isLessThan: Timestamp.fromDate(cutoffTime))
          .get();

      if (snapshot.docs.isNotEmpty) {
        if (kDebugMode)
          print('🔄 Found ${snapshot.docs.length} stalled jobs, restarting...');

        for (final doc in snapshot.docs) {
          await startBackgroundProcessing(doc.id);
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to check for stalled jobs: $e');
    }
  }

  /// Initialize silent notification channel
  static Future<void> _initializeSilentNotifications() async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(initSettings);
      if (Platform.isAndroid && !_notificationChannelCreated) {
        // Create silent notification channel for background service
        const silentChannel = AndroidNotificationChannel(
          'silent_background_service',
          'Background Processing',
          description: 'Silent background processing',
          importance: Importance.min, // Minimal importance
          playSound: false,
          enableVibration: false,
          enableLights: false,
        );

        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(silentChannel);

        // Create user notification channel for completion alerts
        const userChannel = AndroidNotificationChannel(
          'user_notifications',
          'GenSpace Updates',
          description: 'Important notifications about your GenSpaces',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );

        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(userChannel);

        _notificationChannelCreated = true;
        if (kDebugMode) print('✅ Notification channels created');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Failed to initialize notifications: $e');
    }
  }

  /// Initialize background service with persistence
  static Future<void> _initializeBackgroundService() async {
    try {
      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onServiceStart,
          autoStart: false, // Don't auto-start - only start when needed
          autoStartOnBoot: false, // Don't start on device boot
          isForegroundMode: true,
          notificationChannelId: 'silent_background_service',
          initialNotificationTitle: 'RatNawnAI Background',
          initialNotificationContent: 'Processing GenSpaces in background',
          foregroundServiceNotificationId: 999,
          foregroundServiceTypes: [AndroidForegroundType.dataSync],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false, // Don't auto-start - only start when needed
          onForeground: onServiceStart,
          onBackground: onIosBackground,
        ),
      );

      if (kDebugMode) print('✅ Persistent background service configured');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to configure background service: $e');
    }
  }

  /// Register periodic background tasks with enhanced persistence
  static Future<void> _registerPeriodicTasks() async {
    try {
      await Workmanager().cancelAll();

      // Check incomplete GenSpaces every 15 minutes with enhanced persistence
      await Workmanager().registerPeriodicTask(
        BackgroundTasks.checkIncomplete,
        BackgroundTasks.checkIncomplete,
        frequency: Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false, // Allow even when battery is low
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: Duration(seconds: 10),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        inputData: {
          'persistent': true,
          'high_priority': true,
          'keep_alive': true,
        },
      );

      // Poll active GenSpaces every 15 minutes with enhanced persistence
      await Workmanager().registerPeriodicTask(
        BackgroundTasks.pollGenSpaces,
        BackgroundTasks.pollGenSpaces,
        frequency: Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false, // Allow even when battery is low
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: Duration(seconds: 10),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        inputData: {
          'persistent': true,
          'high_priority': true,
          'keep_alive': true,
        },
      );

      // Add a heartbeat task to keep WorkManager active and restart services
      await Workmanager().registerPeriodicTask(
        'heartbeat_task',
        'heartbeat_task',
        frequency: Duration(minutes: 15), // Minimum allowed by Android
        constraints: Constraints(
          networkType:
              NetworkType.notRequired, // No network needed for heartbeat
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: Duration(seconds: 5),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        inputData: {
          'heartbeat': true,
          'restart_services': true,
        },
      );

      if (kDebugMode)
        print('✅ Enhanced periodic tasks registered with persistence');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to register periodic tasks: $e');
    }
  }

  /// Start processing with connection monitoring
  static Future<void> startBackgroundProcessing(String jobId) async {
    try {
      if (kDebugMode)
        print('🚀 Starting background processing for job: $jobId');

      // Ensure service is initialized
      if (!_isInitialized) {
        if (kDebugMode)
          print('⚠️ Service not initialized, initializing now...');
        await initialize();
      }

      // Initialize connection state for this job
      _jobConnectionStates[jobId] = ConnectionState();

      // Ensure notification channel exists
      if (Platform.isAndroid && !_notificationChannelCreated) {
        await _initializeSilentNotifications();
      }

      // Register periodic tasks only when starting actual work
      await _registerPeriodicTasks();
      if (kDebugMode) print('✅ Periodic tasks registered for active job');

      // Start monitoring when service is actually needed
      if (!_monitoringActive) {
        await _setupServiceMonitoring();
        _monitoringActive = true;
        if (kDebugMode) print('✅ Service monitoring activated');
      }

      // Start service if not running
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (!isRunning) {
        try {
          await service.startService();
          if (kDebugMode) print('✅ Background service started');
          await Future.delayed(Duration(milliseconds: 500));
        } catch (e) {
          if (kDebugMode) print('⚠️ Could not start background service: $e');
        }
      }
      // Send job to background service
      service.invoke('process_GenSpace', {
        'jobId': jobId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Register WorkManager task as backup
      await Workmanager().registerOneOffTask(
        'process_$jobId',
        BackgroundTasks.resumeProcessing,
        inputData: {'jobId': jobId},
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: Duration(seconds: 10),
      );

      if (kDebugMode) print('✅ Started background processing for job: $jobId');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to start background processing: $e');
    }
  }

  /// Start webhook-based processing (new method for webhook flow)
  static Future<void> startWebhookBasedProcessing(String jobId) async {
    try {
      if (kDebugMode)
        print('🚀 Starting webhook-based processing for job: $jobId');

      // Ensure service is initialized
      if (!_isInitialized) {
        if (kDebugMode)
          print('⚠️ Service not initialized, initializing now...');
        await initialize();
      }

      // Initialize connection state for this job
      _jobConnectionStates[jobId] = ConnectionState();

      // Ensure notification channel exists
      if (Platform.isAndroid && !_notificationChannelCreated) {
        await _initializeSilentNotifications();
      }

      // Register periodic tasks only when starting actual work
      await _registerPeriodicTasks();
      if (kDebugMode) print('✅ Periodic tasks registered for active job');

      // Start monitoring when service is actually needed
      if (!_monitoringActive) {
        await _setupServiceMonitoring();
        _monitoringActive = true;
        if (kDebugMode) print('✅ Service monitoring activated');
      }

      // Start service if not running
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (!isRunning) {
        try {
          await service.startService();
          if (kDebugMode) print('✅ Background service started');
          await Future.delayed(Duration(milliseconds: 500));
        } catch (e) {
          if (kDebugMode) print('⚠️ Could not start background service: $e');
        }
      }

      // Send job to background service with webhook flag
      service.invoke('process_GenSpace_webhook', {
        'jobId': jobId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'useWebhook': true,
      });

      // Register WorkManager task as backup
      await Workmanager().registerOneOffTask(
        'process_webhook_$jobId',
        BackgroundTasks.resumeProcessing,
        inputData: {'jobId': jobId, 'useWebhook': true},
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: Duration(seconds: 10),
      );

      if (kDebugMode)
        print('✅ Started webhook-based processing for job: $jobId');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to start webhook-based processing: $e');
    }
  }

  static Future<bool> isServiceRunning() async {
    try {
      final service = FlutterBackgroundService();
      return await service.isRunning();
    } catch (e) {
      return false;
    }
  }

  static Future<void> stopService() async {
    try {
      final service = FlutterBackgroundService();
      // First check if service is actually running
      final isRunning = await service.isRunning();
      if (!isRunning) {
        if (kDebugMode) print('ℹ️ Background service is already stopped');
        return;
      }

      if (kDebugMode) print('🛑 Forcefully stopping background service...');

      // Send stop signal to service
      service.invoke('stop');

      // Give it a moment to respond to the stop signal
      await Future.delayed(Duration(milliseconds: 500));

      // Force stop if still running
      final stillRunning = await service.isRunning();
      if (stillRunning) {
        if (kDebugMode) print('🔄 Service still running, forcing stop...');
        // Force stop the service
        service.invoke('force_stop');
        await Future.delayed(Duration(milliseconds: 500));
      }

      // Cancel all WorkManager tasks when stopping service
      await Workmanager().cancelAll();
      if (kDebugMode) print('✅ All WorkManager tasks cancelled');

      // Stop monitoring when service is stopped
      _stopServiceMonitoring();

      if (kDebugMode) print('✅ Background service stop completed');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to stop service: $e');
    }
  }

  /// Show battery optimization guide to user (call from UI)
  static Future<void> showBatteryOptimizationGuide(BuildContext context) async {
    try {
      await BatteryOptimizationHelper.ensureBatteryOptimizationSetup(context);
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to show battery optimization guide: $e');
    }
  }
}

/// WorkManager callback dispatcher
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('🔄 [WorkManager] Executing background task: $task');
      print('🔄 [WorkManager] Input data: $inputData');
      await Firebase.initializeApp();
      print('✅ [WorkManager] Firebase initialized');

      switch (task) {
        case BackgroundTasks.checkIncomplete:
          await _checkAndResumeIncompleteGenSpaces();
          break;

        case BackgroundTasks.pollGenSpaces:
          await _pollActiveGenSpacesWithConnectionRecovery();
          break;

        case BackgroundTasks.resumeProcessing:
          final jobId = inputData?['jobId'] as String?;
          if (jobId != null) {
            await _resumeGenSpaceProcessingWithRecovery(jobId);
          }
          break;
        case 'heartbeat_task':
          await _performHeartbeat(inputData);
          break;
      }

      print('✅ [WorkManager] Task $task completed successfully');
      return Future.value(true);
    } catch (e) {
      print('❌ [WorkManager] Background task error: $e');
      print('❌ [WorkManager] Stack trace: ${StackTrace.current}');
      return Future.value(false);
    }
  });
}

/// Background service entry point
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  print('🚀 [BackgroundService] Background service started');
  print('🚀 [BackgroundService] Service type: ${service.runtimeType}');

  try {
    await Firebase.initializeApp();
  } catch (e) {
    if (kDebugMode) print('⚠️ Firebase init error: $e');
  }

  final dio = _createRobustDio(isBackgroundService: true);

  // Android service configuration
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    // Update notification minimally
    Timer.periodic(Duration(minutes: 1), (timer) async {
      try {
        if (await service.isForegroundService()) {
          final activeJobs = await _getActiveJobsCount();
          // Update notification with current job count
          if (activeJobs > 0) {
            service.setForegroundNotificationInfo(
              title: "RatNawnAI",
              content:
                  "Processing $activeJobs GenSpace${activeJobs > 1 ? 's' : ''}",
            );
          } else {
            // Show idle state but don't auto-stop - wait for explicit stop
            service.setForegroundNotificationInfo(
              title: "RatNawnAI Background",
              content: "Processing GenSpaces in background",
            );
          }
        }
      } catch (e) {
        // Silent fail
      }
    });
  }

  // Listen for processing requests
  service.on('process_GenSpace').listen((event) async {
    final jobId = event?['jobId'] as String?;
    if (jobId != null) {
      if (kDebugMode) print('📋 Processing GenSpace: $jobId');
      await _processGenSpaceWithFullRecovery(jobId, dio);
    }
  });

  // Listen for webhook-based processing requests
  service.on('process_GenSpace_webhook').listen((event) async {
    final jobId = event?['jobId'] as String?;
    if (jobId != null) {
      if (kDebugMode) print('📋 Processing GenSpace with webhook: $jobId');
      await _processGenSpaceWithWebhook(jobId, dio);
    }
  });

  // Main processing loop with connection monitoring
  Timer.periodic(Duration(seconds: 10), (timer) async {
    try {
      await _processAllActiveJobsWithRecovery(dio);

      // Periodically check if we should stop the service (every 30 seconds)
      if (timer.tick % 3 == 0) {
        // Every 3rd iteration (30 seconds)
        await _checkAndStopServiceIfNoJobs();
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Processing loop error: $e');
    }
  });

  // Additional monitoring for Android Doze mode - runs less frequently but more persistently
  Timer.periodic(Duration(minutes: 5), (timer) async {
    try {
      await _handleDozeMode();
    } catch (e) {
      if (kDebugMode) print('⚠️ Doze mode handler error: $e');
    }
  });

  // Stop signal
  service.on('stop').listen((event) {
    service.stopSelf();
    if (kDebugMode) print('🛑 Service stopped');
  });
  // Force stop signal - immediate shutdown
  service.on('force_stop').listen((event) {
    if (kDebugMode) print('🚨 Force stopping service immediately');
    service.stopSelf();
  });
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  try {
    await Firebase.initializeApp();
    final dio = _createRobustDio(isBackgroundService: true);

    await _processAllActiveJobsWithRecovery(dio);
  } catch (e) {
    if (kDebugMode) print('⚠️ iOS background error: $e');
  }
  return true;
}

// ============= ENHANCED HELPER FUNCTIONS WITH ALL FEATURES =============

/// Create a robust Dio instance with proper configuration for release builds
Dio _createRobustDio({bool isBackgroundService = true}) {
  final dio = Dio();
  dio.options.baseUrl = ApiConfig.baseUrl; // Uses new URL from ApiConfig
  dio.options.headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'x-api-key': ApiConfig.apiKey,
    'User-Agent': 'RatNawnAI/1.0.0 (Android)',
    'Cache-Control': 'no-cache',
  };
  // Configure timeouts based on context
  if (isBackgroundService) {
    dio.options.connectTimeout = Duration(seconds: 30);
    dio.options.receiveTimeout = Duration(seconds: 60);
    dio.options.sendTimeout = Duration(seconds: 60);
  } else {
    dio.options.connectTimeout = Duration(seconds: 15);
    dio.options.receiveTimeout = Duration(seconds: 30);
    dio.options.sendTimeout = Duration(seconds: 30);
  }

  // Add robust connection handling
  dio.options.followRedirects = true;
  dio.options.maxRedirects = 3;

  // Add DNS and connection retry interceptor
  dio.interceptors.add(InterceptorsWrapper(
    onError: (DioException error, ErrorInterceptorHandler handler) {
      if (kDebugMode) {
        print('🔴 Dio Error: ${error.type}');
        print('🔴 Message: ${error.message}');
        print('🔴 Response: ${error.response?.statusCode}');

        // Log specific DNS/connection errors
        if (error.type == DioExceptionType.connectionError ||
            error.message?.contains('Failed host lookup') == true ||
            error.message?.contains('No address associated with hostname') ==
                true) {
          print(
              '🔴 DNS Resolution Error detected - this usually happens in release builds');
          print('🔴 Check network security config and DNS settings');
        }
      }
      handler.next(error);
    },
    onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
      if (kDebugMode) {
        print('➡️ ${options.method} ${options.uri}');
      }
      handler.next(options);
    },
    onResponse: (Response response, ResponseInterceptorHandler handler) {
      if (kDebugMode) {
        print('⬅️ ${response.statusCode} ${response.requestOptions.uri}');
      }
      handler.next(response);
    },
  ));
  return dio;
}

/// Check internet connection with double verification
Future<bool> _checkInternetConnection() async {
  try {
    // First check with connectivity_plus
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();

    if (result.contains(ConnectivityResult.none)) {
      return false;
    }

    // Double-check with actual network request to Google and our API
    try {
      final testDio = Dio();
      testDio.options.connectTimeout = Duration(seconds: 5);
      testDio.options.receiveTimeout = Duration(seconds: 5);
      testDio.options.followRedirects = true;
      testDio.options.maxRedirects = 3;
      // First test Google (reliable DNS test)
      try {
        final googleResponse = await testDio.get('https://www.google.com');
        if (googleResponse.statusCode != 200) {
          return false;
        }
      } catch (e) {
        if (kDebugMode) print('❌ Google connection test failed: $e');
        return false;
      }

      // Skip API endpoint test for now to avoid 404 errors
      // Just rely on Google connectivity test for DNS verification
      if (kDebugMode) print('✅ Network connectivity verified (Google reachable)');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Connection test failed: $e');
      return false;
    }
  } catch (e) {
    if (kDebugMode) print('❌ Connection check error: $e');
    return false;
  }
}

/// Wait for internet connection with status updates
Future<void> _waitForInternetConnection(String jobId) async {
  if (kDebugMode) print('🌐 Waiting for internet connection for job: $jobId');

  final connectionState =
      BackgroundGenSpaceService._jobConnectionStates[jobId] ??
          ConnectionState();
  connectionState.isConnected = false;
  connectionState.lastConnectionLost = DateTime.now();

  // Update Firestore with connection lost status
  try {
    await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .doc(jobId)
        .update({
      'connectionStatus': connectionState.toMap(),
      'message': 'Internet connection lost. Waiting to reconnect...',
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // Firestore might not be accessible without internet
  }

  // Check every 2 seconds
  while (true) {
    connectionState.connectionRetries++;

    if (await _checkInternetConnection()) {
      connectionState.isConnected = true;
      connectionState.lastConnectionRestored = DateTime.now();

      if (kDebugMode)
        print(
            '✅ Connection restored after ${connectionState.connectionRetries} attempts');

      // Update Firestore with connection restored
      try {
        await FirebaseFirestore.instance
            .collection('GenSpace_jobs')
            .doc(jobId)
            .update({
          'connectionStatus': connectionState.toMap(),
          'message': 'Connection restored. Resuming processing...',
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Continue anyway
      }

      break;
    }

    // Update retry count in Firestore if possible
    if (connectionState.connectionRetries % 10 == 0) {
      try {
        await FirebaseFirestore.instance
            .collection('GenSpace_jobs')
            .doc(jobId)
            .update({
          'connectionRetries': connectionState.connectionRetries,
          'message':
              'Waiting for connection... (${connectionState.connectionRetries} checks)',
        });
      } catch (e) {
        // Silent fail
      }
    }
    await Future.delayed(Duration(seconds: 2));
  }
}

/// Process GenSpace with webhook-based flow
Future<void> _processGenSpaceWithWebhook(String jobId, Dio dio) async {
  try {
    final firestore = FirebaseFirestore.instance;

    // Get job details
    final doc = await firestore.collection('GenSpace_jobs').doc(jobId).get();
    if (!doc.exists) {
      if (kDebugMode) print('❌ Job not found: $jobId');
      return;
    }

    final data = doc.data()!;
    final status = data['status'] as String?;

    if (status != 'processing') {
      if (kDebugMode) print('⚠️ Job $jobId status is $status, skipping');
      return;
    }

    // In the new webhook system, the background service should only monitor jobs
    // that already have a conversionId (initiated by the foreground app)
    final conversionId = data['conversionId'] as String?;

    if (conversionId == null || conversionId.isEmpty) {
      if (kDebugMode)
        print(
            '⚠️ Job $jobId has no conversionId - webhook initiation expected from foreground app');

      // Update job status to indicate it's waiting for webhook initiation
      await firestore.collection('GenSpace_jobs').doc(jobId).update({
        'status': 'waiting_for_webhook',
        'message': 'Waiting for webhook initiation from foreground app...',
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      return; // Exit early - don't try to initiate webhook from background
    }

    // If we have a conversionId, monitor the job status
    if (kDebugMode)
      print(
          '✅ Job $jobId has conversionId: $conversionId - monitoring for completion');

    // Update job to indicate webhook monitoring is active
    await firestore.collection('GenSpace_jobs').doc(jobId).update({
      'webhookMonitoringActive': true,
      'webhookMonitoringStartedAt': FieldValue.serverTimestamp(),
      'message': 'Monitoring webhook-based generation...',
    });

    // Monitor the job status (this will be handled by the existing polling logic)
    // The actual webhook completion is handled by the ai-completion-handler function
  } catch (e) {
    if (kDebugMode) print('❌ Error in webhook processing for job $jobId: $e');
  }
}

/// Process GenSpace with full recovery capabilities
Future<void> _processGenSpaceWithFullRecovery(String jobId, Dio dio) async {
  try {
    final firestore = FirebaseFirestore.instance;
    // Get job details
    final doc = await firestore.collection('GenSpace_jobs').doc(jobId).get();
    if (!doc.exists) {
      if (kDebugMode) print('❌ Job not found: $jobId');
      return;
    }

    final data = doc.data()!;
    final status = data['status'] as String?;
    if (status != 'processing') {
      if (kDebugMode) print('⚠️ Job $jobId status is $status, skipping');
      return;
    }

    // Check for existing conversion ID (recovery scenario)
    var conversionId = data['conversionId'] as String?;

    if (conversionId == null || conversionId.isEmpty) {
      // In the new webhook system, conversion should be initiated from the foreground app
      // The background service should only monitor existing jobs
      if (kDebugMode)
        print(
            '⚠️ No conversion ID found for job $jobId - webhook initiation expected from foreground app');

      // Update job status to indicate it's waiting for webhook initiation
      await firestore.collection('GenSpace_jobs').doc(jobId).update({
        'status': 'waiting_for_webhook',
        'message': 'Waiting for webhook initiation from foreground app...',
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Continue to polling - conversionId will be retrieved during polling
    }

    // Monitor the job status (with or without conversion ID)
    // For webhook jobs, conversionId will be null initially and retrieved during polling
    await _pollJobStatusWithRecovery(jobId, conversionId, dio);
  } catch (e) {
    if (kDebugMode) print('❌ Error processing job $jobId: $e');

    // Save error but don't mark as failed
    try {
      await FirebaseFirestore.instance
          .collection('GenSpace_jobs')
          .doc(jobId)
          .update({
        'lastError': e.toString(),
        'errorTime': FieldValue.serverTimestamp(),
        'message': 'Encountered error, will retry...',
      });
    } catch (_) {}
  }
}

/// Trigger conversion with smart retry logic
// In background_GenSpace_service.dart
Future<String?> _triggerConversionWithRetry(
  String jobId,
  Map<String, dynamic> jobData,
  Dio dio,
) async {
  const maxRetries = 5;
  int retryCount = 0;
  while (retryCount < maxRetries) {
    try {
      // Check internet before attempting
      if (!await _checkInternetConnection()) {
        await _waitForInternetConnection(jobId);
      }
      // Build request from jobData
      final requestData = jobData['requestData'] as Map<String, dynamic>?;
      if (requestData == null) {
        if (kDebugMode) print('❌ No request data found for job $jobId');
        return null;
      }

      // Extract all parameters including generateCsv
      final productType = requestData['productType'] as String?;
      final gender = requestData['gender'] as String?;
      final generateCsv =
          requestData['generateCsv'] ?? false; // ✅ Extract the actual value

      if (kDebugMode)
        print(
            '🚀 POST Triggering conversion (attempt ${retryCount + 1}) - generateCsv: $generateCsv');

      // Build input images array from uploaded URLs
      final uploadedImageUrls = jobData['uploadedImageUrls'] as List<dynamic>?;
      final inputImages = <Map<String, String>>[];

      if (uploadedImageUrls != null && uploadedImageUrls.isNotEmpty) {
        for (int i = 0; i < uploadedImageUrls.length; i++) {
          String view = 'front';
          if (i == 0)
            view = 'front';
          else if (i == 1)
            view = 'back';
          else if (i == 2)
            view = 'side';
          else
            view = 'detail';

          inputImages.add({
            'url': uploadedImageUrls[i].toString(),
            'view': view,
          });
        }
      }
      // Make API call using the OpenAPI endpoint
      final response = await dio.post(
        ApiConfig.fashionAIEndpoint,
        data: {
          'inputImages': inputImages,
          'text': requestData['text'] ?? '',
          'numberOfOutputs': requestData['imagesToGenerate'] ?? 1,
          'isVideo': requestData['generateVideo'] ?? false,
          'generateCsv': generateCsv, // ✅ Use the actual value from requestData
          'upscale': true,
          if (productType != null && productType.isNotEmpty)
            'productType': productType,
          if (gender != null && gender.isNotEmpty)
            'gender': gender == 'Male' ? 'man' : 'woman',
        },
        options: Options(
          receiveTimeout: Duration(seconds: 60),
          sendTimeout: Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final conversionId = response.data['id']?.toString();

        if (conversionId != null && conversionId.isNotEmpty) {
          if (kDebugMode) print('✅ Conversion triggered: $conversionId');

          // NO IMMEDIATE CREDITS DEDUCTION - Credits will be deducted via webhook after completion
          try {
            final creditCost = jobData['creditCost'] as double?;
            if (creditCost != null && creditCost > 0) {
              if (kDebugMode)
                print(
                    '💳 Credits will be deducted after completion via webhook: $creditCost (conversionId: $conversionId)');

              // Update job to indicate credits will be deducted after completion
              await FirebaseFirestore.instance
                  .collection('GenSpace_jobs')
                  .doc(jobId)
                  .update({
                'creditsPending': true,
                'creditsAmount': creditCost,
                'creditsDeductionMethod': 'webhook_after_completion',
                'message':
                    'AI processing started. Credits will be deducted after completion...',
              });
            }
          } catch (e) {
            if (kDebugMode) print('❌ Failed to update credit status: $e');
          }

          return conversionId;
        }
      }
    } catch (e) {
      retryCount++;

      if (kDebugMode) print('⚠️ Trigger attempt $retryCount failed: $e');

      // Update retry status
      try {
        await FirebaseFirestore.instance
            .collection('GenSpace_jobs')
            .doc(jobId)
            .update({
          'triggerRetries': retryCount,
          'lastTriggerError': e.toString(),
          'message':
              'Retrying API connection... (attempt $retryCount/$maxRetries)',
        });
      } catch (_) {}

      if (retryCount < maxRetries) {
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }
  }
  return null;
}

/// Poll job status with infinite retry and connection recovery
Future<void> _pollJobStatusWithRecovery(
    String jobId, String? conversionId, Dio dio) async {
  int pollAttempt = 0;
  int consecutiveErrors = 0;
  final connectionState =
      BackgroundGenSpaceService._jobConnectionStates[jobId] ??
          ConnectionState();

  // INFINITE LOOP - will never give up
  while (true) {
    pollAttempt++;

    try {
      // Check internet connection
      if (!await _checkInternetConnection()) {
        consecutiveErrors = 0; // Reset error count during connection loss
        await _waitForInternetConnection(jobId);
        continue; // Resume from where we left off
      }

      // Get job data and conversionId (for webhook jobs)
      bool shouldGenerateCsv = false;
      String? currentConversionId = conversionId;
      try {
        final jobDoc = await FirebaseFirestore.instance
            .collection('GenSpace_jobs')
            .doc(jobId)
            .get();
        if (jobDoc.exists) {
          final jobData = jobDoc.data()!;
          final requestData = jobData['requestData'] as Map<String, dynamic>?;
          shouldGenerateCsv = requestData?['generateCsv'] ?? false;

          // For webhook jobs, get conversionId from job document
          if (currentConversionId == null) {
            currentConversionId = jobData['conversionId'] as String?;
            if (currentConversionId == null) {
              if (kDebugMode)
                print('⚠️ No conversionId found for job $jobId, waiting...');
              await Future.delayed(Duration(seconds: 10));
              continue;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ Could not fetch job data: $e');
        await Future.delayed(Duration(seconds: 5));
        continue;
      }

      if (kDebugMode)
        print(
            '🔄 GET Poll #$pollAttempt for job $jobId - generateCsv: $shouldGenerateCsv');

      // Use the OpenAPI GET endpoint with proper parameters
      final response = await dio.get(
        ApiConfig.fashionAIEndpoint, // '/ratnawnai/fashionai'
        queryParameters: {
          'id': currentConversionId!,
          if (shouldGenerateCsv) 'generateCsv': shouldGenerateCsv,
        },
        options: Options(
          receiveTimeout: Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final responseData = response.data as Map<String, dynamic>;
        
        // Handle both direct data and nested data structure
        Map<String, dynamic>? data;
        if (responseData.containsKey('data') && responseData['data'] is Map) {
          data = responseData['data'] as Map<String, dynamic>;
        } else if (responseData.containsKey('status')) {
          // Direct status response
          data = responseData;
        }

        if (data != null) {
          // Save last known data for connection state
          connectionState.lastKnownData = data;
        }

        final status = data?['status']?.toString();

        if (kDebugMode) print('📊 Status: $status');

        consecutiveErrors = 0; // Reset error count on success

        // Update progress in Firestore with better error handling
        try {
          await _updateJobProgress(jobId, pollAttempt, status, data);
        } catch (e) {
          if (kDebugMode) print('⚠️ Error updating job progress: $e');
          // Continue processing even if progress update fails
        }

        if (status == 'completed') {
          try {
            if (data != null) {
              await _handleCompletedJobWithSaving(jobId, data, dio);
            } else {
              if (kDebugMode) print('⚠️ Completed status but no data available');
              // Mark as completed anyway
              await FirebaseFirestore.instance
                  .collection('GenSpace_jobs')
                  .doc(jobId)
                  .update({
                'status': 'completed',
                'progress': 1.0,
                'message': 'Generation completed (no detailed data available)',
                'completedAt': FieldValue.serverTimestamp(),
              });
            }
          } catch (e) {
            if (kDebugMode) print('❌ Error handling completed job: $e');
            // Mark as failed due to processing error
            await FirebaseFirestore.instance
                .collection('GenSpace_jobs')
                .doc(jobId)
                .update({
              'status': 'failed',
              'message': 'Error processing completion: ${e.toString()}',
              'failedAt': FieldValue.serverTimestamp(),
            });
          }
          break; // Exit loop on completion
        } else if (status == 'failed') {
          // Only mark as failed if backend explicitly says failed
          await FirebaseFirestore.instance
              .collection('GenSpace_jobs')
              .doc(jobId)
              .update({
            'status': 'failed',
            'message': 'Backend processing failed',
            'failedAt': FieldValue.serverTimestamp(),
            'failureData': data,
          });
          await _sendUserNotification(
            'GenSpace Failed',
            'Failed to generate GenSpace',
            importance: Importance.high,
          );

          // Check if there are other processing jobs after failure
          if (kDebugMode)
            print('🔍 Checking for other active jobs after failure...');

          try {
            final activeJobs = await FirebaseFirestore.instance
                .collection('GenSpace_jobs')
                .where('status', isEqualTo: 'processing')
                .get();

            if (kDebugMode)
              print(
                  '📊 Found ${activeJobs.docs.length} active jobs after failure');

            if (activeJobs.docs.isEmpty) {
              // No more active jobs, stop the background service
              if (kDebugMode)
                print(
                    '🛑 Stopping background service after failure - no more active jobs');
              await BackgroundGenSpaceService.stopService();
              if (kDebugMode)
                print('✅ Background GenSpace service stopped after failure');
            } else {
              if (kDebugMode) {
                print(
                    '🔄 Background GenSpace service continues after failure - ${activeJobs.docs.length} jobs still processing');
                final activeJobIds =
                    activeJobs.docs.take(3).map((doc) => doc.id).toList();
                print(
                    '📋 Active job IDs after failure (first 3): $activeJobIds');
              }
            }
          } catch (e) {
            if (kDebugMode)
              print('❌ Error checking active jobs after failure: $e');
          }

          break; // Exit loop on failure
        }
      }
    } catch (e) {
      consecutiveErrors++;

      if (kDebugMode) print('⚠️ Poll error #$consecutiveErrors: $e');

      // Save error information
      try {
        await FirebaseFirestore.instance
            .collection('GenSpace_jobs')
            .doc(jobId)
            .update({
          'lastPollError': e.toString(),
          'consecutiveErrors': consecutiveErrors,
          'pollAttempts': pollAttempt,
          'message':
              'Retrying... (poll #$pollAttempt, errors: $consecutiveErrors)',
        });
      } catch (_) {}
    }

    // Delay before next poll
    final delay = _getPollingDelay(pollAttempt, consecutiveErrors > 0);
    await Future.delayed(delay);
  }
}

/// Update job progress in Firestore
Future<void> _updateJobProgress(
  String jobId,
  int pollAttempt,
  String? status,
  Map<String, dynamic>? data,
) async {
  try {
    // Ensure safe numeric values
    final safeProgress = _calculateProgress(pollAttempt).clamp(0.0, 1.0);
    final safeMessage = _getProgressMessage(pollAttempt, status);
    final safePollAttempt = pollAttempt.clamp(0, 1000); // Reasonable limits
    
    final updateData = <String, dynamic>{
      'progress': safeProgress,
      'message': safeMessage,
      'lastPollingAttempt': safePollAttempt,
      'lastUpdated': FieldValue.serverTimestamp(),
    };
    
    // Only add status if it's not null or empty
    if (status != null && status.isNotEmpty) {
      updateData['lastPollingStatus'] = status;
    }
    
    await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .doc(jobId)
        .update(updateData);
        
    if (kDebugMode) {
      print('📊 Job $jobId progress updated: ${(safeProgress * 100).toInt()}% - $safeMessage');
    }
  } catch (e) {
    if (kDebugMode) {
      print('⚠️ Failed to update progress for job $jobId: $e');
      print('⚠️ Poll attempt: $pollAttempt, Status: $status');
    }
    // Don't rethrow - allow polling to continue
  }
}

/// Handle completed job with comprehensive data saving
Future<void> _handleCompletedJobWithSaving(
  String jobId,
  Map<String, dynamic> data,
  Dio dio,
) async {
  try {
    if (kDebugMode) print('✅ Job $jobId completed');
    // Extract all data from OpenAPI response format
    final generatedImages = (data['generatedImages'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final upscaledImages = (data['upscaledImages'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final generatedVideos = (data['generatedVideos'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    // Extract URLs
    final imageUrls = generatedImages
        .map((e) => e['imageSrc']?.toString())
        .whereType<String>()
        .toList();
    final upscaledUrls = upscaledImages
        .map((e) => e['imageSrc']?.toString())
        .whereType<String>()
        .toList();
    final videoUrls = generatedVideos
        .map((e) => e['videoUrl']?.toString())
        .whereType<String>()
        .toList();

    // Use upscaled images if available, otherwise use regular images
    final finalImageUrls = upscaledUrls.isNotEmpty ? upscaledUrls : imageUrls;

    // Get uploaded image URLs from the job document
    List<String> uploadedImageUrls = [];
    try {
      final jobDoc = await FirebaseFirestore.instance
          .collection('GenSpace_jobs')
          .doc(jobId)
          .get();
      
      if (jobDoc.exists) {
        final jobData = jobDoc.data()!;
        // Extract uploaded image URLs from job data
        if (jobData['uploadedImageUrls'] != null) {
          if (jobData['uploadedImageUrls'] is List) {
            uploadedImageUrls = (jobData['uploadedImageUrls'] as List)
                .map((e) => e.toString())
                .toList();
          }
        }
        
        // If not found in direct field, check in requestData or other fields
        if (uploadedImageUrls.isEmpty) {
          final requestData = jobData['requestData'] as Map<String, dynamic>?;
          if (requestData?['uploadedImageUrls'] != null) {
            if (requestData!['uploadedImageUrls'] is List) {
              uploadedImageUrls = (requestData['uploadedImageUrls'] as List)
                  .map((e) => e.toString())
                  .toList();
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Could not retrieve uploaded image URLs: $e');
    }

    // Save comprehensive result data
    final resultData = {
      'status': 'completed',
      'progress': 1.0,
      'message': 'GenSpace generated successfully!',
      'completedAt': FieldValue.serverTimestamp(),
      'completedInBackground': true,
      'uploadedImageUrls': uploadedImageUrls, // ✅ Save uploaded image URLs
      'result': {
        'image_variations': finalImageUrls,
        'original_image_urls': imageUrls,
        'upscaled_image_urls': upscaledUrls,
        'output_video_url': videoUrls.isNotEmpty ? videoUrls.first : null,
        'excel_export_url': data['csv'],
        'description': data['description'],
        'key_features': data['keyFeatures'],
        'search_keywords': data['searchKeywords'],
        'request_id': data['id'] ?? '',
        'metadata': data,
        'products_processed': 1,
        'success_count': 1,
      },
      'connectionStatistics':
          BackgroundGenSpaceService._jobConnectionStates[jobId]?.toMap(),
    };

    await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .doc(jobId)
        .update(resultData);
    // Show completion notification
    await _sendUserNotification(
      'GenSpace Complete',
      'Your smart GenSpace has been generated successfully!',
      importance: Importance.high,
    );

    // Check if there are other processing jobs after completion
    if (kDebugMode)
      print('🔍 Checking for other active jobs after completion...');

    try {
      final activeJobs = await FirebaseFirestore.instance
          .collection('GenSpace_jobs')
          .where('status', isEqualTo: 'processing')
          .get();

      if (kDebugMode)
        print(
            '📊 Found ${activeJobs.docs.length} active jobs after completion');

      if (activeJobs.docs.isEmpty) {
        // No more active jobs, stop the background service immediately
        if (kDebugMode)
          print(
              '🛑 Stopping background service after completion - no more active jobs');
        await BackgroundGenSpaceService.stopService();
        if (kDebugMode)
          print('✅ Background GenSpace service stopped after completion');
      } else {
        if (kDebugMode) {
          print(
              '🔄 Background GenSpace service continues - ${activeJobs.docs.length} jobs still processing');
          final activeJobIds =
              activeJobs.docs.take(3).map((doc) => doc.id).toList();
          print('📋 Active job IDs (first 3): $activeJobIds');
        }
      }
    } catch (e) {
      if (kDebugMode)
        print('❌ Error checking active jobs after completion: $e');
    }
  } catch (e) {
    if (kDebugMode) print('❌ Error handling completed job: $e');

    // Save partial data even if processing fails
    try {
      await FirebaseFirestore.instance
          .collection('GenSpace_jobs')
          .doc(jobId)
          .update({
        'status': 'completed_with_errors',
        'completionError': e.toString(),
        'partialData': data,
      });
    } catch (_) {}
  }
}

/// Process all active jobs with recovery
Future<void> _processAllActiveJobsWithRecovery(Dio dio) async {
  try {
    // Check internet first
    if (!await _checkInternetConnection()) {
      if (kDebugMode) print('📡 No internet, skipping job processing');
      return;
    }

    final firestore = FirebaseFirestore.instance;

    final snapshot = await firestore
        .collection('GenSpace_jobs')
        .where('status', isEqualTo: 'processing')
        .get();

    if (snapshot.docs.isEmpty) return;

    if (kDebugMode) print('📊 Found ${snapshot.docs.length} active jobs');

    final futures = <Future>[];
    for (final doc in snapshot.docs) {
      final jobId = doc.id;
      futures.add(_processGenSpaceWithFullRecovery(jobId, dio));
    }

    await Future.wait(futures, eagerError: false);
  } catch (e) {
    if (kDebugMode) print('❌ Error processing active jobs: $e');
  }
}

/// Poll active GenSpaces with connection recovery
Future<void> _pollActiveGenSpacesWithConnectionRecovery() async {
  try {
    if (!await _checkInternetConnection()) {
      if (kDebugMode) print('📡 No internet for polling');
      return;
    }

    final dio = Dio();
    dio.options.baseUrl = ApiConfig.baseUrl;
    dio.options.headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'x-api-key': ApiConfig.apiKey,
      'User-Agent': 'RatNawnAI/1.0.0 (Android)',
    };
    // Configure timeouts for background service
    dio.options.connectTimeout = Duration(seconds: 30);
    dio.options.receiveTimeout = Duration(seconds: 60);
    dio.options.sendTimeout = Duration(seconds: 60);
    // Add better DNS and connection handling
    dio.options.followRedirects = true;
    dio.options.maxRedirects = 3;

    await _processAllActiveJobsWithRecovery(dio);
  } catch (e) {
    if (kDebugMode) print('❌ Error polling GenSpaces: $e');
  }
}

/// Resume processing with recovery
Future<void> _resumeGenSpaceProcessingWithRecovery(String jobId) async {
  try {
    if (kDebugMode) print('♻️ Resuming job: $jobId');

    final dio = Dio();
    dio.options.baseUrl = ApiConfig.baseUrl;
    dio.options.headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'x-api-key': ApiConfig.apiKey,
      'User-Agent': 'RatNawnAI/1.0.0 (Android)',
    };
    // Configure timeouts for background service
    dio.options.connectTimeout = Duration(seconds: 30);
    dio.options.receiveTimeout = Duration(seconds: 60);
    dio.options.sendTimeout = Duration(seconds: 60);
    // Add better DNS and connection handling
    dio.options.followRedirects = true;
    dio.options.maxRedirects = 3;

    await _processGenSpaceWithFullRecovery(jobId, dio);
  } catch (e) {
    if (kDebugMode) print('❌ Error resuming: $e');
  }
}

/// Check and resume incomplete GenSpaces
Future<void> _checkAndResumeIncompleteGenSpaces() async {
  try {
    if (!await _checkInternetConnection()) {
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final cutoffTime = DateTime.now().subtract(Duration(minutes: 5));

    final snapshot = await firestore
        .collection('GenSpace_jobs')
        .where('status', isEqualTo: 'processing')
        .where('createdAt', isLessThan: Timestamp.fromDate(cutoffTime))
        .get();

    if (snapshot.docs.isEmpty) {
      if (kDebugMode) print('✅ No stuck GenSpaces');
      return;
    }

    for (final doc in snapshot.docs) {
      await BackgroundGenSpaceService.startBackgroundProcessing(doc.id);
    }
  } catch (e) {
    if (kDebugMode) print('❌ Error checking incomplete: $e');
  }
}

/// Get active jobs count
Future<int> _getActiveJobsCount() async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .where('status', isEqualTo: 'processing')
        .count()
        .get();
    return snapshot.count ?? 0;
  } catch (e) {
    return 0;
  }
}

/// Send user notification (not persistent)
Future<void> _sendUserNotification(
  String title,
  String body, {
  Importance importance = Importance.defaultImportance,
}) async {
  try {
    final androidDetails = AndroidNotificationDetails(
      'user_notifications',
      'GenSpace Updates',
      channelDescription: 'Notifications about GenSpace updates',
      importance: importance,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await FlutterLocalNotificationsPlugin().show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  } catch (e) {
    if (kDebugMode) print('❌ Failed to send notification: $e');
  }
}

/// Calculate progress
double _calculateProgress(int pollCount) {
  if (pollCount < 5) return 0.3;
  if (pollCount < 10) return 0.4;
  if (pollCount < 20) return 0.5;
  if (pollCount < 30) return 0.6;
  if (pollCount < 40) return 0.7;
  if (pollCount < 50) return 0.8;
  if (pollCount < 60) return 0.85;
  return 0.95;
}

/// Get progress message
String _getProgressMessage(int pollCount, String? status) {
  if (status == 'processing') {
    if (pollCount < 10) return 'AI is analyzing your images...';
    if (pollCount < 30) return 'Generating product variations...';
    if (pollCount < 60) return 'Creating optimized content...';
    if (pollCount < 90) return 'Finalizing your GenSpace...';
    return 'Almost done, please wait...';
  }
  return 'Processing... (attempt $pollCount)';
}

/// Get polling delay
Duration _getPollingDelay(int attempt, bool hasErrors) {
  if (hasErrors) return Duration(seconds: 5);
  if (attempt < 10) return Duration(seconds: 2);
  if (attempt < 30) return Duration(seconds: 3);
  if (attempt < 60) return Duration(seconds: 5);
  if (attempt < 120) return Duration(seconds: 10);
  return Duration(seconds: 15);
}

/// Perform heartbeat to keep WorkManager alive and monitor system state
Future<void> _performHeartbeat(Map<String, dynamic>? inputData) async {
  try {
    if (kDebugMode) print('💓 Heartbeat - WorkManager is alive');
    // Check if Firebase is available
    bool firebaseAvailable = false;
    try {
      await Firebase.initializeApp();
      firebaseAvailable = true;
    } catch (e) {
      if (kDebugMode) print('⚠️ Firebase not available in heartbeat: $e');
    }

    // Check internet connectivity
    final hasInternet = await _checkInternetConnection();

    // Check if background service is still running
    bool serviceRunning = false;
    try {
      final service = FlutterBackgroundService();
      serviceRunning = await service.isRunning();
    } catch (e) {
      if (kDebugMode) print('⚠️ Cannot check service status: $e');
    }
    // Log system state
    if (kDebugMode) {
      print('💓 System State Check:');
      print('   📶 Internet: $hasInternet');
      print('   🔥 Firebase: $firebaseAvailable');
      print('   🔧 Service: $serviceRunning');
    }

    // If service is not running but we have internet, try to restart it
    if (!serviceRunning && hasInternet) {
      if (kDebugMode)
        print('🔄 Heartbeat detected service down, attempting restart...');
      try {
        await BackgroundGenSpaceService.initialize();
      } catch (e) {
        if (kDebugMode) print('⚠️ Heartbeat service restart failed: $e');
      }
    }
    // Update heartbeat timestamp in Firestore if available
    if (firebaseAvailable && hasInternet) {
      try {
        await FirebaseFirestore.instance
            .collection('system')
            .doc('heartbeat')
            .set({
          'lastHeartbeat': FieldValue.serverTimestamp(),
          'serviceRunning': serviceRunning,
          'internetAvailable': hasInternet,
          'workManagerActive': true,
          'deviceModel': Platform.isAndroid ? 'Android' : 'iOS',
        }, SetOptions(merge: true));
      } catch (e) {
        // Silent fail - heartbeat is not critical
      }
    }
    // Check for any jobs that might need attention during heartbeat
    if (firebaseAvailable && hasInternet) {
      await _checkAndResumeIncompleteGenSpaces();
    }
  } catch (e) {
    if (kDebugMode) print('❌ Heartbeat error: $e');
  }
}

/// Check if there are no active jobs and stop service if needed
Future<void> _checkAndStopServiceIfNoJobs() async {
  try {
    if (!await _checkInternetConnection()) {
      return; // Don't stop during connection issues
    }
    final activeJobs = await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .where('status', isEqualTo: 'processing')
        .get();

    if (activeJobs.docs.isEmpty) {
      if (kDebugMode)
        print(
            '🔍 Periodic check: No active jobs found, stopping background service...');
      await BackgroundGenSpaceService.stopService();
      if (kDebugMode) print('✅ Background service stopped automatically');
    } else {
      if (kDebugMode)
        print(
            '🔄 Periodic check: ${activeJobs.docs.length} jobs still processing, service continues');
    }
  } catch (e) {
    if (kDebugMode) print('⚠️ Error in periodic service check: $e');
  }
}

/// Handle Android Doze mode and power management
Future<void> _handleDozeMode() async {
  try {
    if (!Platform.isAndroid) return;

    // Check if we're in a potential Doze mode situation
    final hasInternet = await _checkInternetConnection();

    if (hasInternet) {
      // Internet is available, make sure service is running
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (!isRunning) {
        if (kDebugMode)
          print(
              '🌙 Doze mode handler: Service not running, attempting restart...');

        try {
          await service.startService();
          if (kDebugMode) print('✅ Service restarted from Doze mode handler');
        } catch (e) {
          if (kDebugMode) print('❌ Doze mode restart failed: $e');
          // Fallback to WorkManager registration
          await BackgroundGenSpaceService._registerPeriodicTasks();
        }
      }
      // Process any pending jobs
      try {
        await Firebase.initializeApp();
        final dio = _createRobustDio(isBackgroundService: true);
        await _processAllActiveJobsWithRecovery(dio);
      } catch (e) {
        if (kDebugMode) print('⚠️ Doze mode job processing failed: $e');
      }
    }
  } catch (e) {
    if (kDebugMode) print('❌ Doze mode handler error: $e');
  }
}
