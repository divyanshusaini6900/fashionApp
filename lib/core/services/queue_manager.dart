import 'dart:async';
import 'dart:io';
import 'package:RatNawnAI_app/core/services/GenSpace_queue_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


/// Provider class for managing the GenSpace queue state in the UI
class QueueManagerProvider extends ChangeNotifier {
  final GenSpaceQueueService _queueService = GenSpaceQueueService();
  StreamSubscription? _queueSubscription;
  
  // Queue state
  Map<String, GenSpaceQueueItem> _allJobs = {};
  Map<String, dynamic> _queueStatus = {};
  bool _isInitialized = false;

  // Getters
  Map<String, GenSpaceQueueItem> get allJobs => _allJobs;
  Map<String, dynamic> get queueStatus => _queueStatus;
  bool get isInitialized => _isInitialized;
  
  List<GenSpaceQueueItem> get queuedJobs => _allJobs.values
      .where((job) => job.status == 'queued')
      .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
  List<GenSpaceQueueItem> get processingJobs => _allJobs.values
      .where((job) => job.status == 'processing')
      .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
  List<GenSpaceQueueItem> get completedJobs => _allJobs.values
      .where((job) => job.status == 'completed')
      .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
  List<GenSpaceQueueItem> get failedJobs => _allJobs.values
      .where((job) => job.status == 'failed')
      .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Initialize the queue manager
  void initialize() {
    if (_isInitialized) return;
    
    _queueService.initialize();
    
    // Listen to queue status changes
    _queueSubscription = _queueService.queueStatusStream.listen((jobs) {
      _allJobs = jobs;
      _queueStatus = _queueService.getQueueStatus();
      notifyListeners();
    });
    
    _isInitialized = true;
    if (kDebugMode) print('🎯 QueueManagerProvider initialized');
  }

  /// Queue a new GenSpace generation (fast, non-blocking)
  Future<String> queueGenSpace({
    required String text,
    required String username,
    required String product,
    required Map<String, dynamic> productImages,
    List<dynamic> additionalImages = const [],
    bool generateVideo = false,
    bool generateCsv = false,
    int imagesToGenerate = 1,
    double creditCost = 10.0,
    String? productType,
    String? gender,
    String? skuId,
    Map<String, List<int>>? backgroundArrays,
  }) async {
    try {
      // Convert dynamic maps to proper types
      final Map<String, File?> imageFiles = {};
      productImages.forEach((key, value) {
        if (value is File) {
          imageFiles[key] = value;
        } else {
          imageFiles[key] = null;
        }
      });

      final List<File> additionalFiles = additionalImages
          .whereType<File>()
          .toList();

      // Queue the job with all parameters including OpenAPI fields
      final documentId = await _queueService.queueGenSpaceGeneration(
        text: text,
        username: username,
        product: product,
        productImages: imageFiles,
        additionalImages: additionalFiles,
        generateVideo: generateVideo,
        generateCsv: generateCsv,
        imagesToGenerate: imagesToGenerate,
        creditCost: creditCost,
        productType: productType,
        gender: gender,
        skuId: skuId,
        backgroundArrays: backgroundArrays,
      );

      // Update local state immediately
      _queueStatus = _queueService.getQueueStatus();
      notifyListeners();

      if (kDebugMode) print('✅ Queued job $documentId');
      return documentId;
      
    } catch (e) {
      if (kDebugMode) print('❌ Failed to queue job: $e');
      rethrow;
    }
  }

  /// Cancel a job
  Future<bool> cancelJob(String jobId) async {
    try {
      final success = await _queueService.cancelJob(jobId);
      if (success) {
        _queueStatus = _queueService.getQueueStatus();
        notifyListeners();
      }
      return success;
    } catch (e) {
      if (kDebugMode) print('❌ Failed to cancel job: $e');
      return false;
    }
  }

  /// Clear completed jobs
  void clearCompletedJobs() {
    _queueService.clearCompletedJobs();
    _queueStatus = _queueService.getQueueStatus();
    notifyListeners();
  }

  /// Get job by ID
  GenSpaceQueueItem? getJob(String jobId) {
    return _allJobs[jobId];
  }

  /// Check if a job exists
  bool hasJob(String jobId) {
    return _allJobs.containsKey(jobId);
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    _queueService.dispose();
    super.dispose();
  }
}