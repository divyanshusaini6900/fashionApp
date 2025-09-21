import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fashion_ai_service.dart';
import 'firebase_service.dart';
import 'notification_service.dart';
import 'background_GenSpace_service.dart';

/// Queue item representing a GenSpace generation request
class GenSpaceQueueItem {
  final String id;
  final String? skuId;
  final String text;
  final String username;
  final String product;
  final Map<String, File?> productImages;
  final List<File> additionalImages;
  final bool generateVideo;
  final bool generateCsv;
  final int imagesToGenerate;
  final double creditCost;
  final String userId;
  final DateTime createdAt;
  final String? productType;
  final String? gender;
  final Map<String, List<int>>? backgroundArrays;
  // Queue management - use string status
  String status;
  String? errorMessage;
  double progress;
  String progressMessage;
  GenSpaceQueueItem({
    required this.id,
    this.skuId,
    required this.text,
    required this.username,
    required this.product,
    required this.productImages,
    required this.additionalImages,
    required this.generateVideo,
    required this.generateCsv,
    required this.imagesToGenerate,
    required this.creditCost,
    required this.userId,
    required this.createdAt,
    this.productType,
    this.gender,
    this.backgroundArrays,
    this.status = 'queued',
    this.errorMessage,
    this.progress = 0.0,
    this.progressMessage = 'Queued for processing',
  });
  Map<String, dynamic> toFirestore() {
    return {
      'skuId': id,
      'userId': userId,
      'status': status,
      'progress': progress,
      'message': progressMessage,
      'createdAt': Timestamp.fromDate(createdAt),
      'requestData': {
        'text': text,
        'username': username,
        'product': product,
        'generateVideo': generateVideo,
        'generateCsv': generateCsv, // ✅ Ensure this is saved
        'imagesToGenerate': imagesToGenerate,
        'creditCost': creditCost,
        'productType': productType,
        'gender': gender,
      },
      'errorMessage': errorMessage,
    };
  }
}

/// High-performance queue service for handling multiple GenSpace generations
class GenSpaceQueueService {
  static final GenSpaceQueueService _instance =
      GenSpaceQueueService._internal();
  factory GenSpaceQueueService() => _instance;
  GenSpaceQueueService._internal();

  // Queue management
  final Queue<GenSpaceQueueItem> _queue = Queue<GenSpaceQueueItem>();
  final Map<String, GenSpaceQueueItem> _activeJobs = {};
  final Map<String, StreamSubscription> _jobSubscriptions = {};
  // Configuration - UNLIMITED PARALLEL PROCESSING
  static const int maxConcurrentJobs = -1;
  static const int maxQueueSize = -1;
  static const Duration queueCheckInterval = Duration(milliseconds: 100);

  // State
  bool _isInitialized = false;
  Timer? _queueProcessor;
  final StreamController<Map<String, GenSpaceQueueItem>>
      _queueStatusController =
      StreamController<Map<String, GenSpaceQueueItem>>.broadcast();

  // Services
  final FashionAIService _fashionAIService = FashionAIService();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generate a random SKU ID for GenSpace documents
  String _generateSkuId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();

    String sku = 'SKU-';

    for (int i = 0; i < 4; i++) {
      sku += chars[random.nextInt(chars.length)];
    }

    sku += '-';

    for (int i = 0; i < 4; i++) {
      sku += chars[random.nextInt(chars.length)];
    }

    return sku;
  }

  /// Initialize the queue service
  void initialize() {
    if (_isInitialized) return;

    _fashionAIService.initialize();
    _startQueueProcessor();
    _isInitialized = true;

    if (kDebugMode) print('🚀 GenSpaceQueueService initialized');
  }

  /// Add a GenSpace generation request to the queue
  Future<String> queueGenSpaceGeneration({
    required String text,
    required String username,
    required String product,
    required Map<String, File?> productImages,
    List<File> additionalImages = const [],
    bool generateVideo = false,
    bool generateCsv = false,
    int imagesToGenerate = 1,
    double creditCost = 10.0,
    String? productType,
    String? gender,
    String? skuId,
    Map<String, List<int>>? backgroundArrays,
  }) async {
    // Quick validation
    final currentUser = FirebaseService.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    // Check credit balance quickly
    final hasEnoughCredits = await FirebaseService.hasEnoughCredits(creditCost);
    if (!hasEnoughCredits) {
      final currentBalance = await FirebaseService.getUsercreditBalance();
      throw Exception(
          'Insufficient Credits. Required: $creditCost, Available: $currentBalance');
    }

    // Create queue item - use SKU ID as document ID if provided, otherwise generate random SKU
    final documentId = skuId ?? _generateSkuId();

    if (kDebugMode) {
      print('📝 Creating queue item with generateCsv: $generateCsv');
    }

    final queueItem = GenSpaceQueueItem(
      id: documentId,
      skuId: documentId,
      text: text,
      username: username,
      product: product,
      productImages: Map.from(productImages),
      additionalImages: List.from(additionalImages),
      generateVideo: generateVideo,
      generateCsv: generateCsv, // ✅ Store the actual toggle value
      imagesToGenerate: imagesToGenerate,
      creditCost: creditCost,
      userId: currentUser.uid,
      createdAt: DateTime.now(),
      productType: productType,
      gender: gender,
      backgroundArrays: backgroundArrays,
    );

    // Add to queue immediately
    _queue.add(queueItem);

    // Save initial job status to Firestore (non-blocking)
    _saveJobStatusToFirestore(queueItem).catchError((error) {
      if (kDebugMode)
        print('⚠️ Warning: Failed to save initial job status: $error');
    });

    // START BACKGROUND PROCESSING for webhook jobs (as fallback)
    try {
      await BackgroundGenSpaceService.startBackgroundProcessing(documentId);
      if (kDebugMode)
        print(
            '✅ Background processing enabled for webhook job $documentId (fallback polling)');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to start background processing: $e');
      // Continue anyway - foreground processing will still work
    }

    // Notify queue status change
    _notifyQueueStatusChange();

    if (kDebugMode)
      print('📋 Added job $documentId to queue with generateCsv: $generateCsv');

    return documentId;
  }

  /// Start the queue processor
  void _startQueueProcessor() {
    _queueProcessor = Timer.periodic(queueCheckInterval, (timer) {
      _processQueue();
    });
  }

  /// Process the queue
  void _processQueue() {
    // Remove completed jobs from active jobs
    _activeJobs.removeWhere((id, job) =>
        job.status == 'completed' ||
        job.status == 'failed' ||
        job.status == 'cancelled');

    // Start ALL queued jobs immediately
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _activeJobs[job.id] = job;
      // Process ALL jobs in parallel
      _processJobParallel(job).catchError((error) {
        if (kDebugMode) print('❌ Error processing job ${job.id}: $error');
        job.status = 'failed';
        job.errorMessage = error.toString();
        _updateJobInFirestore(job);
      });
    }

    // Notify status change
    _notifyQueueStatusChange();
  }

  /// Process a single job with full parallelization and continuous monitoring
  Future<void> _processJobParallel(GenSpaceQueueItem job) async {
    Timer? progressTimer;
    StreamSubscription? firestoreSubscription;
    try {
      // Update status to processing
      job.status = 'processing';
      job.progress = 0.1;
      job.progressMessage = 'Starting generation...';
      await _updateJobInFirestore(job);

      if (kDebugMode) {
        print('🔄 Processing job ${job.id}');
        print(
            '📊 Job settings - generateCsv: ${job.generateCsv}, generateVideo: ${job.generateVideo}');
      }

      // Start real-time Firestore listener for this specific job
      firestoreSubscription = _firestore
          .collection('GenSpace_jobs')
          .doc(job.id)
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists) return;

        final data = snapshot.data();
        if (data != null) {
          // Update local job state from Firestore
          final firestoreProgress =
              (data['progress'] as num?)?.toDouble() ?? job.progress;
          final firestoreMessage =
              data['message'] as String? ?? job.progressMessage;
          final firestoreStatus = data['status'] as String? ?? job.status;

          // Only update if there's a change
          if (job.progress != firestoreProgress ||
              job.progressMessage != firestoreMessage ||
              job.status != firestoreStatus) {
            job.progress = firestoreProgress;
            job.progressMessage = firestoreMessage;
            job.status = firestoreStatus;

            // Notify UI of changes
            _notifyQueueStatusChange();

            if (kDebugMode) {
              print(
                  '📊 Job ${job.id} progress updated: ${(firestoreProgress * 100).toInt()}% - $firestoreMessage');
            }
          }

          // Check if job completed or failed
          if (firestoreStatus == 'completed' || firestoreStatus == 'failed') {
            if (kDebugMode)
              print('🏁 Job ${job.id} finished with status: $firestoreStatus');
            progressTimer?.cancel();
            firestoreSubscription?.cancel();
          }
        }
      });

      // Start a progress monitoring timer
      progressTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
        try {
          // Check job document for updates
          final doc =
              await _firestore.collection('GenSpace_jobs').doc(job.id).get();
          if (!doc.exists) {
            timer.cancel();
            return;
          }

          final data = doc.data()!;
          final currentStatus = data['status'] as String? ?? '';

          // If job is completed or failed, stop monitoring
          if (currentStatus == 'completed' || currentStatus == 'failed') {
            timer.cancel();
            job.status = currentStatus;
            _notifyQueueStatusChange();
            return;
          }
          // Check if conversionId exists
          final conversionId = data['conversionId'] as String?;
          if (conversionId != null && conversionId.isNotEmpty) {
            // We have a conversion ID, job is properly processing
            if (job.progress < 0.3) {
              job.progress = 0.3;
              job.progressMessage = 'AI processing started...';
              await _updateJobInFirestore(job);
            }
          }

          // Check polling attempts to show more accurate progress
          final pollingAttempts =
              (data['lastPollingAttempt'] as num?)?.toInt() ?? 0;
          if (pollingAttempts > 0) {
            // Calculate progress based on polling attempts
            double estimatedProgress = 0.3 + (pollingAttempts * 0.01);
            if (estimatedProgress > 0.95) estimatedProgress = 0.95;
            if (estimatedProgress > job.progress) {
              job.progress = estimatedProgress;
              job.progressMessage =
                  data['message'] as String? ?? 'Processing with AI...';
              _notifyQueueStatusChange();
            }
          }
        } catch (e) {
          if (kDebugMode)
            print('⚠️ Error monitoring progress for job ${job.id}: $e');
        }
      });

      // Convert additional images to the expected format
      final Map<String, File?> additionalImagesMap = {};
      for (int i = 0; i < job.additionalImages.length; i++) {
        additionalImagesMap['additional_$i'] = job.additionalImages[i];
      }

      // Call the NEW WEBHOOK-BASED Fashion AI service
      await _fashionAIService.generateWithWebhook(
        text: job.text,
        productImages: job.productImages,
        additionalImages: additionalImagesMap,
        imagesToGenerate: job.imagesToGenerate,
        generateVideo: job.generateVideo,
        generateCsv: job.generateCsv,
        skuId: job.id,
        username: job.username,
        product: job.product,
        productType: job.productType,
        gender: job.gender,
        backgroundArrays: job.backgroundArrays,
      );

      // Cancel monitoring timers
      progressTimer.cancel();
      firestoreSubscription.cancel();

      // Results will be saved via webhook callback
      // No need to save results here for webhook-based processing

      // Mark as completed
      job.status = 'completed';
      job.progress = 1.0;
      job.progressMessage = 'GenSpace generated successfully!';
      await _updateJobInFirestore(job);

      if (kDebugMode) print('✅ Job ${job.id} completed successfully');

      // Send notification
      NotificationService.showNotification(
        title: 'GenSpace Generation Complete!',
        body: 'Your product GenSpace has been generated successfully.',
      ).catchError((error) {
        if (kDebugMode) print('⚠️ Notification error: $error');
      });

      // IMMEDIATELY clear background service notification after showing success notification
      NotificationService.clearBackgroundServiceNotifications().catchError((error) {
        if (kDebugMode) print('⚠️ Error clearing background notifications: $error');
      });

      // Check if there are other processing jobs after completion
      await _checkAndStopBackgroundServiceIfNoJobs();
    } catch (e) {
      // Cancel timers on error
      progressTimer?.cancel();
      firestoreSubscription?.cancel();

      // Only mark as failed if it's a real error
      if (!e.toString().contains('timeout') &&
          !e.toString().contains('Timeout')) {
        job.status = 'failed';
        job.errorMessage = e.toString();
        job.progressMessage = 'Generation failed: ${e.toString()}';

        await _updateJobInFirestore(job);

        if (kDebugMode) print('❌ Job ${job.id} failed: $e');

        // Send failure notification
        NotificationService.showNotification(
          title: 'GenSpace Generation Failed',
          body: 'Failed to generate GenSpace. Please try again.',
        ).catchError((error) {
          if (kDebugMode) print('⚠️ Notification error: $error');
        });
        // Check if there are other processing jobs after failure
        await _checkAndStopBackgroundServiceIfNoJobs();
      } else {
        // For timeouts, keep retrying
        if (kDebugMode)
          print('⏱️ Job ${job.id} timeout, continuing to poll...');
        job.progressMessage =
            'Processing is taking longer than usual. Please wait...';
        await _updateJobInFirestore(job);

        // Retry the job
        Future.delayed(Duration(seconds: 5), () {
          _processJobParallel(job);
        });
      }
    }
  }

  /// Save job status to Firestore
  Future<void> _saveJobStatusToFirestore(GenSpaceQueueItem job) async {
    try {
      final firestoreData = job.toFirestore();

      if (kDebugMode) {
        final requestData =
            firestoreData['requestData'] as Map<String, dynamic>;
        print(
            '💾 Saving job to Firestore with generateCsv: ${requestData['generateCsv']}');
      }

      await _firestore
          .collection('GenSpace_jobs')
          .doc(job.id)
          .set(firestoreData);
    } catch (e) {
      if (kDebugMode) print('❌ Failed to save job status: $e');
    }
  }

  /// Update job in Firestore with retry logic
  Future<void> _updateJobInFirestore(GenSpaceQueueItem job) async {
    int retryCount = 0;
    const maxRetries = 3;
    while (retryCount < maxRetries) {
      try {
        await _firestore.collection('GenSpace_jobs').doc(job.id).update({
          'status': job.status,
          'progress': job.progress,
          'message': job.progressMessage,
          'errorMessage': job.errorMessage,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        return; // Success
      } catch (e) {
        retryCount++;
        if (kDebugMode)
          print(
              '⚠️ Failed to update job status (attempt $retryCount/$maxRetries): $e');

        if (retryCount >= maxRetries) {
          if (kDebugMode)
            print('❌ Failed to update job status after $maxRetries attempts');
        } else {
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }
    }
  }

  /// Notify queue status change to listeners
  void _notifyQueueStatusChange() {
    final allJobs = <String, GenSpaceQueueItem>{};

    allJobs.addAll(_activeJobs);

    for (final job in _queue) {
      allJobs[job.id] = job;
    }

    _queueStatusController.add(allJobs);
  }

  /// Get current queue status
  Map<String, dynamic> getQueueStatus() {
    return {
      'queueLength': _queue.length,
      'activeJobs': _activeJobs.length,
      'totalJobs': _queue.length + _activeJobs.length,
      'maxConcurrent': -1,
      'isProcessing': _activeJobs.isNotEmpty || _queue.isNotEmpty,
      'parallelMode': true,
      'unlimitedProcessing': true,
    };
  }

  /// Stream of queue status changes
  Stream<Map<String, GenSpaceQueueItem>> get queueStatusStream =>
      _queueStatusController.stream;

  /// Cancel a job
  Future<bool> cancelJob(String jobId) async {
    // Remove from queue if not started
    final queuedJob = _queue.cast<GenSpaceQueueItem?>().firstWhere(
          (job) => job?.id == jobId,
          orElse: () => null,
        );

    if (queuedJob != null) {
      _queue.remove(queuedJob);
      queuedJob.status = 'cancelled';
      await _updateJobInFirestore(queuedJob);
      _notifyQueueStatusChange();
      return true;
    }

    // Check if job is active
    final activeJob = _activeJobs[jobId];
    if (activeJob != null && activeJob.status == 'processing') {
      activeJob.status = 'cancelled';
      await _updateJobInFirestore(activeJob);
      _notifyQueueStatusChange();
      return true;
    }
    return false;
  }

  /// Clear completed and failed jobs
  void clearCompletedJobs() {
    _activeJobs.removeWhere(
        (id, job) => job.status == 'completed' || job.status == 'failed');
    _notifyQueueStatusChange();
  }

  /// Check if there are no active jobs and stop background service if needed
  Future<void> _checkAndStopBackgroundServiceIfNoJobs() async {
    try {
      if (kDebugMode) print('🔍 Checking for other active jobs...');
      final activeJobs = await _firestore
          .collection('GenSpace_jobs')
          .where('status', isEqualTo: 'processing')
          .get();

      if (kDebugMode) print('📊 Found ${activeJobs.docs.length} active jobs');

      if (activeJobs.docs.isEmpty) {
        // No more active jobs, stop the background service
        if (kDebugMode)
          print('🛑 Stopping background service - no more active jobs');
        await BackgroundGenSpaceService.stopService();
        if (kDebugMode) print('✅ Background GenSpace service stopped');
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
      if (kDebugMode) print('❌ Error checking active jobs: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    _queueProcessor?.cancel();
    _queueStatusController.close();
    _jobSubscriptions.values.forEach((sub) => sub.cancel());
    _jobSubscriptions.clear();
    _isInitialized = false;
  }
}
