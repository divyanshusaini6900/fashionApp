// Background Video Service - Handles video generation using the API with background processing
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/api_config.dart';
import 'battery_optimization_helper.dart';
import 'notification_service.dart';

/// Connection state tracking for video generation
class VideoConnectionState {
  bool isConnected = true;
  int connectionRetries = 0;
  int pollAttempts = 0;
  DateTime? lastConnectionLost;
  DateTime? lastConnectionRestored;
  Map<String, dynamic>? lastKnownData;
  
  Map<String, dynamic> toMap() {
    return {
      'isConnected': isConnected,
      'connectionRetries': connectionRetries,
      'pollAttempts': pollAttempts,
      'lastConnectionLost': lastConnectionLost?.toIso8601String(),
      'lastConnectionRestored': lastConnectionRestored?.toIso8601String(),
    };
  }
}

/// Background task names for Video WorkManager
class VideoBackgroundTasks {
  static const String pollVideos = 'poll_videos_task';
  static const String checkIncompleteVideos = 'check_incomplete_videos';
  static const String resumeVideoProcessing = 'resume_video_processing_task';
}

class BackgroundVideoService {
  static final BackgroundVideoService _instance = BackgroundVideoService._internal();
  factory BackgroundVideoService() => _instance;
  BackgroundVideoService._internal();

  final Dio _dio = Dio();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Background service management
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _isBackgroundServiceInitialized = false;
  static bool _notificationChannelCreated = false;
  static bool _monitoringActive = false;
  static final Map<String, VideoConnectionState> _jobConnectionStates = {};
  static final Map<String, int> _activeVideoGenerations = {}; // Track active video generations per job
  static Timer? _healthCheckTimer;
  static Timer? _quickCheckTimer;

  /// Initialize the service with proper configuration
  void initialize() {
    _dio.options = BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,
      headers: {
        'x-api-key': ApiConfig.apiKey,
        'Content-Type': 'application/json',
      },
    );

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (object) => print('🎬 VideoService API: $object'),
      ));
    }
  }

  /// Initialize background service and WorkManager for video processing
  static Future<void> initializeBackgroundService() async {
    if (_isBackgroundServiceInitialized) {
      if (kDebugMode) print('⚠️ Background video service already initialized');
      return;
    }
    
    try {
      if (kDebugMode) print('🔄 Starting background video service initialization...');
      
      // Initialize notifications first with silent channel
      await _initializeSilentNotifications();
      if (kDebugMode) print('✅ Video notifications initialized');
      
      // Initialize WorkManager
      await Workmanager().initialize(
        videoCallbackDispatcher,
        isInDebugMode: kDebugMode,
      );
      if (kDebugMode) print('✅ Video WorkManager initialized');

      // Cancel any existing periodic tasks to ensure clean state
      await Workmanager().cancelAll();
      if (kDebugMode) print('✅ Existing video WorkManager tasks cancelled');

      // Ensure any existing background service is stopped on app start
      try {
        final service = FlutterBackgroundService();
        final isRunning = await service.isRunning();
        if (isRunning) {
          service.invoke('stop');
          if (kDebugMode) print('✅ Stopped existing video background service on app start');
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ Failed to check/stop existing video service: $e');
      }

      // Initialize Flutter Background Service with persistence
      await _initializeVideoBackgroundService();
      if (kDebugMode) print('✅ Flutter Video Background Service configured');

      _isBackgroundServiceInitialized = true;
      if (kDebugMode) print('🎉 Background Video Service fully initialized');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to initialize background video service: $e');
      if (kDebugMode) print('Stack trace: ${StackTrace.current}');
    }
  }

  /// Initialize silent notification channel for video processing
  static Future<void> _initializeSilentNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
        // Create silent notification channel for background video service
        const silentChannel = AndroidNotificationChannel(
          'silent_video_background_service',
          'Video Background Processing',
          description: 'Silent video generation processing',
          importance: Importance.min,
          playSound: false,
          enableVibration: false,
          enableLights: false,
        );

        await _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(silentChannel);
        
        // Create user notification channel for video completion alerts
        const userChannel = AndroidNotificationChannel(
          'video_user_notifications',
          'Video Generation Updates',
          description: 'Important notifications about your video generation',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );
        
        await _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(userChannel);
        
        _notificationChannelCreated = true;
        if (kDebugMode) print('✅ Video notification channels created');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Failed to initialize video notifications: $e');
    }
  }

  /// Initialize video background service with persistence
  static Future<void> _initializeVideoBackgroundService() async {
    try {
      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onVideoServiceStart,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          notificationChannelId: 'silent_video_background_service',
          initialNotificationTitle: 'RatNawnAI Video',
          initialNotificationContent: 'Processing videos in background',
          foregroundServiceNotificationId: 998,
          foregroundServiceTypes: [AndroidForegroundType.dataSync],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onVideoServiceStart,
          onBackground: onVideoIosBackground,
        ),
      );

      if (kDebugMode) print('✅ Persistent video background service configured');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to configure video background service: $e');
    }
  }

  /// Start video generation for a specific job
  /// 
  /// [jobId] - The Firebase job document ID
  /// [selectedImageUrl] - The image URL to generate video from
  /// [imageId] - The image ID from refImg data (optional but recommended)
Future<String> startVideoGeneration({
  required String jobId,
  required String selectedImageUrl,
  String? imageId,
}) async {
  try {
    // Increment active video generation counter for this job
    _activeVideoGenerations[jobId] = (_activeVideoGenerations[jobId] ?? 0) + 1;
    
    if (kDebugMode) {
      print('🎬 Starting video generation for job: $jobId (${_activeVideoGenerations[jobId]} active)');
      print('🖼️ Image URL: ${selectedImageUrl.substring(0, 50)}...');
      print('🆔 Image ID: $imageId');
    }

    // Initialize dio if not already done
    if (_dio.options.baseUrl.isEmpty) {
      initialize();
    }

    // Update Firebase status to indicate video generation started
    await _updateVideoStatus(jobId, 'starting', 'Initializing video generation...');

    // Prepare request body according to OpenAPI spec
    // The 'id' field is what the API expects for the imageId
    final requestBody = {
      'imageUrl': selectedImageUrl,
      if (imageId != null && imageId.isNotEmpty) 'imageId': imageId,  // Send as 'id' not 'imageId'
    };

    if (kDebugMode) {
      print('🚀 Sending video generation request: $requestBody');
    }

    // Make API call to video generation endpoint
    final response = await _dio.post(
      ApiConfig.fashionAIVideoEndpoint,
      data: requestBody,
      options: Options(
        validateStatus: (status) {
          // Accept 200-299 and retry on 502/503/504
          return status != null && ((status >= 200 && status < 300) || status == 502 || status == 503 || status == 504);
        },
        receiveTimeout: Duration(seconds: 60),
        sendTimeout: Duration(seconds: 60),
      ),
    );

    // Handle gateway errors with retry
    if (response.statusCode == 502 || response.statusCode == 503 || response.statusCode == 504) {
      if (kDebugMode) print('⚠️ Gateway error, retrying...');
      await Future.delayed(Duration(seconds: 2));
      
      // Retry once
      final retryResponse = await _dio.post(
        ApiConfig.fashionAIVideoEndpoint,
        data: requestBody,
        options: Options(
          receiveTimeout: Duration(seconds: 60),
          sendTimeout: Duration(seconds: 60),
        ),
      );
      
      if (retryResponse.statusCode == 200 && retryResponse.data != null) {
        final responseImageId = retryResponse.data['id']?.toString() ?? '';
        if (responseImageId.isNotEmpty) {
          await _updateVideoStatus(
            jobId,
            'processing',
            'Video generation in progress...',
            imageId: responseImageId,
          );
          _startVideoPolling(jobId, responseImageId);
          return responseImageId;
        }
      }
      
      throw Exception('Video generation service temporarily unavailable');
    }

    if (kDebugMode) {
      print('📡 Video generation API response: ${response.statusCode}');
      print('📄 Response data: ${response.data}');
    }

    // Extract image ID from response
    final responseData = response.data as Map<String, dynamic>;
    final responseImageId = responseData['id']?.toString() ?? '';

    if (responseImageId.isEmpty) {
      throw Exception('No image ID returned from video API');
    }

    // Update Firebase with image ID and processing status
    await _updateVideoStatus(
      jobId,
      'processing',
      'Video generation in progress...',
      imageId: responseImageId,
    );

    // Start background polling for video completion
    _startVideoPolling(jobId, responseImageId);

    if (kDebugMode) {
      print('✅ Video generation started successfully');
      print('🔗 Image ID: $responseImageId');
    }

    return responseImageId;

  } catch (e) {
    if (kDebugMode) {
      print('❌ Error starting video generation: $e');
    }

    // Update Firebase with error status
    await _updateVideoStatus(
      jobId,
      'failed',
      'Failed to start video generation: ${e.toString()}',
    );

    rethrow;
  }
}
  /// Update video generation status in Firebase
  Future<void> _updateVideoStatus(
    String jobId,
    String status,
    String message, {
    String? imageId,
    String? videoUrl,
  }) async {
    try {
      final updateData = {
        'videoGenerationStatus': status,
        'videoMessage': message,
        'videoUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (imageId != null) {
        updateData['videoImageId'] = imageId;
      }

      if (videoUrl != null) {
        // Append to existing video URLs array or create new array
        updateData['result.output_video_url'] = FieldValue.arrayUnion([videoUrl]);
      }

      await _firestore
          .collection('GenSpace_jobs')
          .doc(jobId)
          .update(updateData);

      // Handle video completion or failure - decrement counter and stop service if all videos done
      if ((status == 'completed' && videoUrl != null) || status == 'failed') {
        // Decrement active video generation counter for this job
        if (_activeVideoGenerations.containsKey(jobId)) {
          _activeVideoGenerations[jobId] = _activeVideoGenerations[jobId]! - 1;
          
          if (kDebugMode) {
            final statusText = status == 'completed' ? 'completed' : 'failed';
            print('🎬 Video $statusText for job: $jobId (${_activeVideoGenerations[jobId]} remaining)');
          }
          
          // If no more active video generations for this job, check if we should stop the service
          if (_activeVideoGenerations[jobId]! <= 0) {
            _activeVideoGenerations.remove(jobId);
            
            // Check if there are any other jobs with active video generations
            final totalActiveVideos = _activeVideoGenerations.values.fold<int>(0, (sum, count) => sum + count);
            
            if (totalActiveVideos == 0) {
              await stopBackgroundVideoService();
              
              if (kDebugMode) {
                print('🛑 Background video service stopped - all video generations completed/failed');
              }
            } else {
              if (kDebugMode) {
                print('🔄 Background video service continues - $totalActiveVideos videos still processing');
              }
            }
          }
        }
      }

      if (kDebugMode) {
        print('📊 Updated video status for job $jobId: $status - $message');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error updating video status: $e');
      }
    }
  }

  /// Start polling for video generation completion with proper timeout and retry limits
  void _startVideoPolling(String jobId, String imageId) {
    int pollingAttempts = 0;
    int consecutiveErrors = 0;
    final maxPollingAttempts = 120; // 120 attempts * 3 seconds = 6 minutes max
    final maxConsecutiveErrors = 5;
    
    Timer.periodic(ApiConfig.standardPollInterval, (timer) async {
      try {
        pollingAttempts++;
        
        if (kDebugMode) {
          print('🔄 Polling video status for image: $imageId (attempt $pollingAttempts/$maxPollingAttempts)');
        }

        // Check if we've exceeded maximum polling attempts (timeout)
        if (pollingAttempts > maxPollingAttempts) {
          timer.cancel();
          await _updateVideoStatus(
            jobId,
            'failed',
            'Video generation timed out after ${maxPollingAttempts * 3} seconds',
          );
          if (kDebugMode) {
            print('⏰ Video generation polling timed out');
          }
          return;
        }

        // Check video generation status via API
        final status = await _checkVideoStatus(imageId);
        
        // Reset error counter on successful API call
        consecutiveErrors = 0;
        
        if (status['completed'] == true) {
          timer.cancel();
          
          final videoUrl = status['videoUrl'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            await _updateVideoStatus(
              jobId,
              'completed',
              'Video generation completed successfully!',
              videoUrl: videoUrl,
            );
            
            // Show completion notification
            await _showVideoCompletionNotification(jobId, videoUrl);
            
            // Stop background video service immediately after completion
            await stopBackgroundVideoService();
            
            if (kDebugMode) {
              print('✅ Video generation completed: $videoUrl');
              print('🛑 Background video service stopped after completion');
            }
          } else {
            await _updateVideoStatus(
              jobId,
              'failed',
              'Video generation completed but no video URL received',
            );
          }
        } else if (status['failed'] == true) {
          timer.cancel();
          
          final errorMessage = status['error'] as String? ?? 'Video generation failed';
          await _updateVideoStatus(jobId, 'failed', errorMessage);
          
          if (kDebugMode) {
            print('❌ Video generation failed: $errorMessage');
          }
        } else {
          // Still processing, update status message if available
          final message = status['message'] as String? ?? 'Video generation in progress...';
          await _updateVideoStatus(jobId, 'processing', message);
          
          if (kDebugMode) {
            print('📊 Video status: $message');
          }
        }

      } catch (e) {
        consecutiveErrors++;
        
        if (kDebugMode) {
          print('⚠️ Error during video polling (attempt $consecutiveErrors/$maxConsecutiveErrors): $e');
        }
        
        // Cancel timer if too many consecutive errors
        if (consecutiveErrors >= maxConsecutiveErrors) {
          timer.cancel();
          await _updateVideoStatus(
            jobId,
            'failed',
            'Video generation polling failed after $maxConsecutiveErrors consecutive errors',
          );
          if (kDebugMode) {
            print('❌ Video polling stopped due to consecutive errors');
          }
        } else {
          // Update status with retry message
          await _updateVideoStatus(
            jobId,
            'processing',
            'Temporary error checking status, retrying... (${consecutiveErrors}/$maxConsecutiveErrors)',
          );
        }
      }
    });
  }

  /// Check video generation status using the actual API endpoint
  Future<Map<String, dynamic>> _checkVideoStatus(String imageId) async {
    try {
      if (kDebugMode) {
        print('🔍 Checking video status for image: $imageId');
      }

      // Call the actual status endpoint from OpenAPI spec
      final response = await _dio.get(
        ApiConfig.fashionAIEndpoint, // GET /ratnawnai/fashionai
        queryParameters: {
          'id': imageId,
        },
      );

      if (kDebugMode) {
        print('📡 Status API response: ${response.statusCode}');
        print('📄 Status data: ${response.data}');
      }

      final responseData = response.data as Map<String, dynamic>;
      final data = responseData['data'] as Map<String, dynamic>?;
      
      if (data == null) {
        return {
          'completed': false,
          'failed': true,
          'error': 'No data in status response',
        };
      }

      final status = data['status'] as String?;
      final generatedVideos = data['generatedVideos'] as List<dynamic>?;

      if (kDebugMode) {
        print('📊 Current status: $status');
        print('🎬 Generated videos count: ${generatedVideos?.length ?? 0}');
      }

      // Check if video generation is completed
      if (status == 'completed') {
        // Look for video URL in generatedVideos
        String? videoUrl;
        if (generatedVideos != null && generatedVideos.isNotEmpty) {
          final firstVideo = generatedVideos.first as Map<String, dynamic>?;
          videoUrl = firstVideo?['videoUrl'] as String?;
        }

        if (videoUrl != null && videoUrl.isNotEmpty) {
          return {
            'completed': true,
            'failed': false,
            'videoUrl': videoUrl,
            'message': 'Video generation completed successfully!',
          };
        } else {
          return {
            'completed': false,
            'failed': true,
            'error': 'Video generation completed but no video URL found',
          };
        }
      } 
      // Check if video generation failed
      else if (status == 'failed') {
        return {
          'completed': false,
          'failed': true,
          'error': 'Video generation failed on server',
        };
      } 
      // Still processing
      else {
        String message = 'Video generation in progress...';
        if (status == 'processing') {
          message = 'Processing video request...';
        } else if (status == 'generating') {
          message = 'Generating video content...';
        } else if (status == 'pending') {
          message = 'Video request queued for processing...';
        }

        return {
          'completed': false,
          'failed': false,
          'message': message,
        };
      }

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking video status: $e');
      }
      
      // Don't fail immediately on network errors - retry
      return {
        'completed': false,
        'failed': false,
        'error': e.toString(),
        'message': 'Temporary error checking status, retrying...',
      };
    }
  }

  /// Check for stalled video generation jobs and restart them
  Future<void> checkAndRestartStalledVideoJobs() async {
    try {
      if (kDebugMode) {
        print('🔍 Checking for stalled video generation jobs...');
      }

      final cutoffTime = DateTime.now().subtract(const Duration(minutes: 10));
      
      final stalledJobs = await _firestore
          .collection('GenSpace_jobs')
          .where('videoGenerationStatus', isEqualTo: 'processing')
          .where('videoUpdatedAt', isLessThan: Timestamp.fromDate(cutoffTime))
          .limit(10)
          .get();

      for (final doc in stalledJobs.docs) {
        final data = doc.data();
        final imageId = data['videoImageId'] as String?;
        
        if (imageId != null && imageId.isNotEmpty) {
          if (kDebugMode) {
            print('🔄 Restarting polling for stalled job: ${doc.id}');
          }
          
          _startVideoPolling(doc.id, imageId);
        } else {
          // No image ID, mark as failed
          await _updateVideoStatus(
            doc.id,
            'failed',
            'Video generation was stalled without image ID',
          );
        }
      }

      if (kDebugMode) {
        print('✅ Stalled video job check completed. Found ${stalledJobs.docs.length} stalled jobs.');
      }

    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error checking stalled video jobs: $e');
      }
    }
  }

  /// Cancel video generation for a specific job
  Future<void> cancelVideoGeneration(String jobId) async {
    try {
      await _updateVideoStatus(
        jobId,
        'cancelled',
        'Video generation was cancelled by user',
      );
      
      if (kDebugMode) {
        print('🚫 Video generation cancelled for job: $jobId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error cancelling video generation: $e');
      }
    }
  }

  /// Get video generation status for a specific job
  Future<Map<String, dynamic>?> getVideoStatus(String jobId) async {
    try {
      final doc = await _firestore
          .collection('GenSpace_jobs')
          .doc(jobId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      // Get video URLs from result.output_video_url array
      final result = data['result'] as Map<String, dynamic>?;
      final videoUrls = result?['output_video_url'] as List<dynamic>?;
      final videoUrlsList = videoUrls?.map((e) => e.toString()).toList() ?? [];
      
      return {
        'status': data['videoGenerationStatus'],
        'message': data['videoMessage'],
        'videoUrls': videoUrlsList, // Return as array
        'videoUrl': videoUrlsList.isNotEmpty ? videoUrlsList.last : null, // Latest video for backward compatibility
        'imageId': data['videoImageId'],
        'updatedAt': data['videoUpdatedAt'],
      };
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error getting video status: $e');
      }
      return null;
    }
  }

  /// Start background video processing with notifications
  static Future<void> startBackgroundVideoProcessing(String jobId) async {
    try {
      if (kDebugMode) print('🚀 Starting background video processing for job: $jobId');
      
      // Ensure service is initialized
      if (!_isBackgroundServiceInitialized) {
        if (kDebugMode) print('⚠️ Video service not initialized, initializing now...');
        await initializeBackgroundService();
      }
      
      // Initialize connection state for this job
      _jobConnectionStates[jobId] = VideoConnectionState();
      
      // Ensure notification channel exists
      if (Platform.isAndroid && !_notificationChannelCreated) {
        await _initializeSilentNotifications();
      }

      // Register periodic tasks only when starting actual work
      await _registerVideoPeriodicTasks();
      if (kDebugMode) print('✅ Video periodic tasks registered for active job');

      // Start monitoring when service is actually needed
      if (!_monitoringActive) {
        await _setupVideoServiceMonitoring();
        _monitoringActive = true;
        if (kDebugMode) print('✅ Video service monitoring activated');
      }

      // Start service if not running
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        try {
          await service.startService();
          if (kDebugMode) print('✅ Video background service started');
          await Future.delayed(Duration(milliseconds: 500));
        } catch (e) {
          if (kDebugMode) print('⚠️ Could not start video background service: $e');
        }
      }
      
      // Send job to background service
      service.invoke('process_video', {
        'jobId': jobId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Register WorkManager task as backup
      await Workmanager().registerOneOffTask(
        'video_process_$jobId',
        VideoBackgroundTasks.resumeVideoProcessing,
        inputData: {
          'jobId': jobId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'persistent': true,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: Duration(seconds: 10),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      if (kDebugMode) print('✅ Video background processing started for job: $jobId');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to start video background processing: $e');
    }
  }

  /// Register periodic background tasks for video processing
  static Future<void> _registerVideoPeriodicTasks() async {
    try {
      await Workmanager().cancelAll();

      // Check incomplete videos every 15 minutes
      await Workmanager().registerPeriodicTask(
        VideoBackgroundTasks.checkIncompleteVideos,
        VideoBackgroundTasks.checkIncompleteVideos,
        frequency: Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
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

      // Poll active videos every 15 minutes
      await Workmanager().registerPeriodicTask(
        VideoBackgroundTasks.pollVideos,
        VideoBackgroundTasks.pollVideos,
        frequency: Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
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

      if (kDebugMode) print('✅ Video periodic tasks registered successfully');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to register video periodic tasks: $e');
    }
  }

  /// Set up video service monitoring
  static Future<void> _setupVideoServiceMonitoring() async {
    try {
      // Set up quick health checks every 30 seconds when actively processing
      _quickCheckTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
        try {
          await _checkActiveVideoJobs();
        } catch (e) {
          if (kDebugMode) print('⚠️ Quick video health check failed: $e');
        }
      });

      // Set up comprehensive health checks every 2 minutes
      _healthCheckTimer = Timer.periodic(Duration(minutes: 2), (timer) async {
        try {
          await _performVideoHealthCheck();
        } catch (e) {
          if (kDebugMode) print('⚠️ Video health check failed: $e');
        }
      });

      if (kDebugMode) print('✅ Video service monitoring enabled');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to setup video service monitoring: $e');
    }
  }

  /// Check active video jobs
  static Future<void> _checkActiveVideoJobs() async {
    try {
      final activeJobs = await FirebaseFirestore.instance
          .collection('GenSpace_jobs')
          .where('videoGenerationStatus', isEqualTo: 'processing')
          .limit(10)
          .get();

      for (final doc in activeJobs.docs) {
        final data = doc.data();
        final imageId = data['videoImageId'] as String?;
        
        if (imageId != null && imageId.isNotEmpty) {
          final connectionState = _jobConnectionStates[doc.id] ?? VideoConnectionState();
          connectionState.pollAttempts++;
          _jobConnectionStates[doc.id] = connectionState;
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Error checking active video jobs: $e');
    }
  }

  /// Perform comprehensive video health check
  static Future<void> _performVideoHealthCheck() async {
    try {
      if (kDebugMode) print('🔍 Performing video service health check...');
      
      // Check stalled video jobs and restart them
      await BackgroundVideoService().checkAndRestartStalledVideoJobs();
      
      if (kDebugMode) print('✅ Video health check completed');
    } catch (e) {
      if (kDebugMode) print('❌ Video health check failed: $e');
    }
  }

  /// Stop video background service
  static Future<void> stopBackgroundVideoService() async {
    try {
      if (kDebugMode) print('🛑 Stopping video background service...');
      
      // Cancel all timers
      _healthCheckTimer?.cancel();
      _quickCheckTimer?.cancel();
      
      // Cancel WorkManager tasks
      await Workmanager().cancelAll();
      
      // Stop background service
      final service = FlutterBackgroundService();
      service.invoke('stop');
      
      // Clear connection states and active video generations
      _jobConnectionStates.clear();
      _activeVideoGenerations.clear();
      _monitoringActive = false;
      
      // IMMEDIATELY clear the persistent video background service notifications
      await NotificationService.cancelNotification(998); // Video service uses ID 998
      if (kDebugMode) print('🔔 Video background service notification cleared');
      
      if (kDebugMode) print('✅ Video background service stop completed');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to stop video service: $e');
      // Still try to clear notifications even if stopping failed
      try {
        await NotificationService.cancelNotification(998);
      } catch (notifError) {
        if (kDebugMode) print('⚠️ Failed to clear video notification: $notifError');
      }
    }
  }

  /// Show notification when video completes
  static Future<void> _showVideoCompletionNotification(String jobId, String? videoUrl) async {
    try {
      if (videoUrl != null && videoUrl.isNotEmpty) {
        await _notifications.show(
          jobId.hashCode,
          '🎬 Video Generation Complete!',
          'Your video has been generated successfully and is ready for export.',
          NotificationDetails(
            android: AndroidNotificationDetails(
              'video_user_notifications',
              'Video Generation Updates',
              channelDescription: 'Important notifications about your video generation',
              importance: Importance.high,
              priority: Priority.high,
              showWhen: true,
              when: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to show video completion notification: $e');
    }
  }

  /// Show battery optimization guide to user (call from UI)
  static Future<void> showBatteryOptimizationGuide(BuildContext context) async {
    try {
      await BatteryOptimizationHelper.ensureBatteryOptimizationSetup(context);
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to show video battery optimization guide: $e');
    }
  }
}

/// Video WorkManager callback dispatcher
@pragma('vm:entry-point')
void videoCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('🔄 [VideoWorkManager] Executing background task: $task');
      print('🔄 [VideoWorkManager] Input data: $inputData');
      
      await Firebase.initializeApp();
      print('✅ [VideoWorkManager] Firebase initialized');

      switch (task) {
        case VideoBackgroundTasks.checkIncompleteVideos:
          await _checkAndResumeIncompleteVideos();
          break;
          
        case VideoBackgroundTasks.pollVideos:
          await _pollActiveVideosWithConnectionRecovery();
          break;
          
        case VideoBackgroundTasks.resumeVideoProcessing:
          final jobId = inputData?['jobId'] as String?;
          if (jobId != null) {
            await _resumeVideoProcessingWithRecovery(jobId);
          }
          break;
      }

      print('✅ [VideoWorkManager] Task $task completed successfully');
      return Future.value(true);
    } catch (e) {
      print('❌ [VideoWorkManager] Background task error: $e');
      print('❌ [VideoWorkManager] Stack trace: ${StackTrace.current}');
      return Future.value(false);
    }
  });
}

/// Background video service entry point
@pragma('vm:entry-point')
void onVideoServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  print('🚀 [VideoBackgroundService] Background video service started');
  print('🚀 [VideoBackgroundService] Service type: ${service.runtimeType}');

  try {
    await Firebase.initializeApp();
  } catch (e) {
    if (kDebugMode) print('⚠️ Firebase init error in video service: $e');
  }

  final dio = _createVideoRobustDio(isBackgroundService: true);

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
          final activeVideos = await _getActiveVideoJobsCount();
          if (activeVideos > 0) {
            service.setForegroundNotificationInfo(
              title: "RatNawnAI Video",
              content: "Processing $activeVideos video${activeVideos > 1 ? 's' : ''}",
            );
          } else {
            service.setForegroundNotificationInfo(
              title: "RatNawnAI Video Background",
              content: "Processing videos in background",
            );
          }
        }
      } catch (e) {
        // Silent fail
      }
    });
  }

  // Listen for video processing requests
  service.on('process_video').listen((event) async {
    final jobId = event?['jobId'] as String?;
    if (jobId != null) {
      if (kDebugMode) print('📹 Processing video: $jobId');
      await _processVideoWithFullRecovery(jobId, dio);
    }
  });

  // Main video processing loop with connection monitoring
  Timer.periodic(Duration(seconds: 15), (timer) async {
    try {
      await _pollActiveVideosWithConnectionRecovery();
    } catch (e) {
      if (kDebugMode) print('⚠️ Video polling error: $e');
    }
  });

  // Stop handler
  service.on('stop').listen((event) async {
    print('🛑 [VideoBackgroundService] Stop signal received');
    await service.stopSelf();
  });
}

/// iOS background handler for video service
@pragma('vm:entry-point')
Future<bool> onVideoIosBackground(ServiceInstance service) async {
  print('🍎 [VideoBackgroundService] iOS background execution');
  
  try {
    await Firebase.initializeApp();
    await _pollActiveVideosWithConnectionRecovery();
    return true;
  } catch (e) {
    print('❌ [VideoBackgroundService] iOS background error: $e');
    return false;
  }
}

/// Helper functions for background video processing
Future<void> _checkAndResumeIncompleteVideos() async {
  try {
    print('🔍 [VideoWorkManager] Checking incomplete videos...');
    
    final incompleteVideos = await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .where('videoGenerationStatus', isEqualTo: 'processing')
        .limit(10)
        .get();

    for (final doc in incompleteVideos.docs) {
      final data = doc.data();
      final imageId = data['videoImageId'] as String?;
      
      if (imageId != null && imageId.isNotEmpty) {
        print('🔄 [VideoWorkManager] Resuming video processing: ${doc.id}');
        await _resumeVideoProcessingWithRecovery(doc.id);
      }
    }
    
    print('✅ [VideoWorkManager] Incomplete videos check completed');
  } catch (e) {
    print('❌ [VideoWorkManager] Error checking incomplete videos: $e');
  }
}

Future<void> _pollActiveVideosWithConnectionRecovery() async {
  try {
    print('🔄 [VideoWorkManager] Polling active videos...');
    
    final activeVideos = await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .where('videoGenerationStatus', isEqualTo: 'processing')
        .limit(5)
        .get();

    for (final doc in activeVideos.docs) {
      final data = doc.data();
      final imageId = data['videoImageId'] as String?;
      
      if (imageId != null && imageId.isNotEmpty) {
        await _checkVideoStatusInBackground(doc.id, imageId);
      }
    }
    
    print('✅ [VideoWorkManager] Active videos polling completed');
  } catch (e) {
    print('❌ [VideoWorkManager] Error polling active videos: $e');
  }
}

Future<void> _resumeVideoProcessingWithRecovery(String jobId) async {
  try {
    print('🔄 [VideoWorkManager] Resuming video processing: $jobId');
    
    final doc = await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .doc(jobId)
        .get();
    
    if (doc.exists) {
      final data = doc.data()!;
      final imageId = data['videoImageId'] as String?;
      final status = data['videoGenerationStatus'] as String?;
      
      if (status == 'processing' && imageId != null && imageId.isNotEmpty) {
        await _checkVideoStatusInBackground(jobId, imageId);
      }
    }
  } catch (e) {
    print('❌ [VideoWorkManager] Error resuming video processing: $e');
  }
}

Future<void> _processVideoWithFullRecovery(String jobId, Dio dio) async {
  try {
    print('📹 [VideoBackgroundService] Processing video with recovery: $jobId');
    
    final doc = await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .doc(jobId)
        .get();
    
    if (doc.exists) {
      final data = doc.data()!;
      final imageId = data['videoImageId'] as String?;
      
      if (imageId != null && imageId.isNotEmpty) {
        await _checkVideoStatusInBackground(jobId, imageId);
      }
    }
  } catch (e) {
    print('❌ [VideoBackgroundService] Error processing video: $e');
  }
}

Future<void> _checkVideoStatusInBackground(String jobId, String imageId) async {
  try {
    final dio = _createVideoRobustDio(isBackgroundService: true);
    
    final response = await dio.get(
      ApiConfig.fashionAIEndpoint,
      queryParameters: {'id': imageId},
    );

    final responseData = response.data as Map<String, dynamic>;
    final data = responseData['data'] as Map<String, dynamic>?;
    
    if (data != null) {
      final status = data['status'] as String?;
      final generatedVideos = data['generatedVideos'] as List<dynamic>?;

      if (status == 'completed' && generatedVideos != null && generatedVideos.isNotEmpty) {
        final firstVideo = generatedVideos.first as Map<String, dynamic>?;
        final videoUrl = firstVideo?['videoUrl'] as String?;
        
        if (videoUrl != null && videoUrl.isNotEmpty) {
          await _updateVideoStatusInBackground(jobId, 'completed', 'Video generation completed!', videoUrl: videoUrl);
          await BackgroundVideoService._showVideoCompletionNotification(jobId, videoUrl);
          
          // Stop background video service immediately after completion
          await BackgroundVideoService.stopBackgroundVideoService();
          
          if (kDebugMode) {
            print('🛑 Background video service stopped after completion in background worker');
          }
        }
      } else if (status == 'failed') {
        await _updateVideoStatusInBackground(jobId, 'failed', 'Video generation failed');
      }
    }
  } catch (e) {
    print('❌ Error checking video status in background: $e');
  }
}

Future<void> _updateVideoStatusInBackground(String jobId, String status, String message, {String? videoUrl}) async {
  try {
    final updateData = {
      'videoGenerationStatus': status,
      'videoMessage': message,
      'videoUpdatedAt': FieldValue.serverTimestamp(),
    };

    if (videoUrl != null) {
      updateData['result.output_video_url'] = FieldValue.arrayUnion([videoUrl]);
    }

    await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .doc(jobId)
        .update(updateData);
    
    // Handle video completion or failure - decrement counter and stop service if all videos done
    if ((status == 'completed' && videoUrl != null) || status == 'failed') {
      // Decrement active video generation counter for this job
      if (BackgroundVideoService._activeVideoGenerations.containsKey(jobId)) {
        BackgroundVideoService._activeVideoGenerations[jobId] = BackgroundVideoService._activeVideoGenerations[jobId]! - 1;
        
        if (kDebugMode) {
          final statusText = status == 'completed' ? 'completed' : 'failed';
          print('🎬 Video $statusText for job: $jobId (${BackgroundVideoService._activeVideoGenerations[jobId]} remaining) - Background');
        }
        
        // If no more active video generations for this job, check if we should stop the service
        if (BackgroundVideoService._activeVideoGenerations[jobId]! <= 0) {
          BackgroundVideoService._activeVideoGenerations.remove(jobId);
          
          // Check if there are any other jobs with active video generations
          final totalActiveVideos = BackgroundVideoService._activeVideoGenerations.values.fold<int>(0, (sum, count) => sum + count);
          
          if (totalActiveVideos == 0) {
            await BackgroundVideoService.stopBackgroundVideoService();
            
            if (kDebugMode) {
              print('🛑 Background video service stopped - all video generations completed/failed (Background)');
            }
          } else {
            if (kDebugMode) {
              print('🔄 Background video service continues - $totalActiveVideos videos still processing (Background)');
            }
          }
        }
      }
    }
  } catch (e) {
    print('❌ Error updating video status in background: $e');
  }
}

Future<int> _getActiveVideoJobsCount() async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('GenSpace_jobs')
        .where('videoGenerationStatus', isEqualTo: 'processing')
        .count()
        .get();
    return snapshot.count ?? 0;
  } catch (e) {
    return 0;
  }
}

Dio _createVideoRobustDio({bool isBackgroundService = false}) {
  final dio = Dio();
  
  dio.options = BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: Duration(minutes: 5),
    receiveTimeout: Duration(minutes: 10),
    sendTimeout: Duration(minutes: 5),
    headers: {
      'x-api-key': ApiConfig.apiKey,
      'Content-Type': 'application/json',
    },
  );

  if (isBackgroundService && kDebugMode) {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (object) => print('🎬 [VideoBackground] API: $object'),
    ));
  }

  return dio;
}
