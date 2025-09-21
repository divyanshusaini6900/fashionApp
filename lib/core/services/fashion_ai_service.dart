import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'firebase_service.dart';
import 'package:RatNawnAI_app/core/config/api_config.dart';
import 'notification_service.dart';
import 'webhook_ai_service.dart';

class FashionAIService {
  static final FashionAIService _instance = FashionAIService._internal();
  factory FashionAIService() => _instance;
  FashionAIService._internal();

  final Dio _dio = Dio();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Connection state tracking
  static final Map<String, ConnectionState> _activeConnections = {};

  void initialize() {
    _dio.options.baseUrl = ApiConfig.baseUrl; // Uses new URL
    _dio.options.connectTimeout = ApiConfig.connectTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
    _dio.options.sendTimeout = ApiConfig.sendTimeout;

    // Set default headers including API key for authentication
    _dio.options.headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'x-api-key': ApiConfig.apiKey,
      'User-Agent': 'RatNawnAI-App',
    };

    if (ApiConfig.enableDebugLogs) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: true,
        error: true,
      ));
    }
  }

  /// Generate a random SKU ID for GenSpace documents
  String _generateSkuId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();

    // Generate format: SKU-XXXX-XXXX
    String sku = 'SKU-';

    // First segment: 4 characters
    for (int i = 0; i < 4; i++) {
      sku += chars[random.nextInt(chars.length)];
    }

    sku += '-';

    // Second segment: 4 characters
    for (int i = 0; i < 4; i++) {
      sku += chars[random.nextInt(chars.length)];
    }

    return sku;
  }

  /// ORIGINAL METHOD - Generate fashion GenSpace (preserved for backward compatibility)
  Future<String> generateFashionGenSpace({
    required String text,
    required String username,
    required String product,
    required Map<String, File?> productImages,
    List<File> additionalImages = const [],
    bool generateVideo = false,
    bool generateCsv = false,
    int imagesToGenerate = 1,
    double? creditCost,
    String? skuId,
    String? productType,
    String? gender,
  }) async {
    // Wait for Firebase Auth to be ready
    await FirebaseAuth.instance.authStateChanges().first;

    final currentUser = FirebaseService.currentUser;
    if (currentUser == null) {
      // Try one more time after a short delay
      await Future.delayed(ApiConfig.retryDelay);
      final retryUser = FirebaseService.currentUser;
      if (retryUser == null) {
        throw FashionAIException(
            'User not authenticated. Please login and try again.');
      }
    }

    // Use SKU ID if provided, otherwise generate a random SKU ID
    final documentId = skuId ?? _generateSkuId();
    final jobDoc = _firestore.collection('GenSpace_jobs').doc(documentId);

    await jobDoc.set({
      'skuId': documentId,
      'userId': currentUser?.uid ?? FirebaseService.currentUser!.uid,
      'status': 'processing',
      'progress': 0.0,
      'message': 'Uploading images and starting AI generation...',
      'createdAt': FieldValue.serverTimestamp(),
      'requestData': {
        'text': text,
        'username': username,
        'product': product,
        'generateVideo': generateVideo,
        'generateCsv': generateCsv,
        'imagesToGenerate': imagesToGenerate,
        'productType': productType,
        'gender': gender,
      },
    });

    final uploadedImages = <String, XFile>{};
    for (final entry in productImages.entries) {
      if (entry.value != null) {
        uploadedImages[entry.key] = XFile(entry.value!.path);
      }
    }

    if (!uploadedImages.containsKey('front_view') &&
        !uploadedImages.containsKey('frontside')) {
      throw FashionAIException('Front view image is required');
    }

    await _updateJobProgress(
        documentId, 0.2, 'Images prepared, calling AI service...');

    try {
      // Use the new OpenAPI integration with generateCsv parameter
      final result = await generateWithOpenApiFromFirebase(
        text: text,
        productImages: productImages,
        additionalImages: additionalImages,
        numberOfOutputs: imagesToGenerate,
        isVideo: generateVideo,
        generateCsv: generateCsv, // Pass the actual value
        jobDocumentId: documentId,
        productType: productType,
        gender: gender,
        creditCost: creditCost, // Pass creditCost for immediate deduction
      );

      await _updateJobProgress(
          documentId, 0.8, 'AI generation complete, saving results...');
      await _saveGenerationResults(documentId, result);

      // Credits are now deducted immediately after receiving conversionId
      // No need to deduct credits here

      await _updateJobProgress(
          documentId, 1.0, 'GenSpace generated successfully!',
          isComplete: true);

      // Notify user that GenSpace generation has completed successfully (non-blocking)
      NotificationService.showNotification(
        title: 'GenSpace Generation Complete!',
        body:
            'Your product GenSpace has been generated successfully. Check your exports.',
      ).catchError((error) {
        if (kDebugMode) print('⚠️ Notification error: $error');
      });

      // IMMEDIATELY clear background service notification after showing success notification
      NotificationService.clearBackgroundServiceNotifications().catchError((error) {
        if (kDebugMode) print('⚠️ Error clearing background notifications: $error');
      });

      return documentId;
    } catch (e) {
      await _updateJobProgress(documentId, 0.0, 'Error: ${e.toString()}',
          isFailed: true);

      // Notify user that GenSpace generation has failed (non-blocking)
      NotificationService.showNotification(
        title: 'GenSpace Generation Failed',
        body: 'Failed to generate your product GenSpace. Please try again.',
      ).catchError((error) {
        if (kDebugMode) print('⚠️ Notification error: $error');
      });

      throw FashionAIException('Generation failed: ${e.toString()}');
    }
  }

  /// BULLETPROOF implementation with 100% reliability and internet recovery
  Future<FashionGenerationResponse> generateWithOpenApiFromFirebase({
    required String text,
    required Map<String, File?> productImages,
    List<File> additionalImages = const [],
    int numberOfOutputs = 1,
    bool isVideo = false,
    bool generateCsv = false, // ✅ Ensure default is false
    String? jobDocumentId,
    String? productType,
    String? gender,
    double? creditCost,
  }) async {
    // Initialize connection state for this job
    final connectionState =
        ConnectionState(jobId: jobDocumentId ?? _generateSkuId());
    if (jobDocumentId != null) {
      _activeConnections[jobDocumentId] = connectionState;
    }

    try {
      // 1. ENSURE USER AUTHENTICATION
      await FirebaseAuth.instance.authStateChanges().first;
      final currentUser = FirebaseService.currentUser;
      if (currentUser == null) {
        throw FashionAIException(
            'User not authenticated. Please login and try again.');
      }

      // 2. PREPARE IMAGES
      final uploadFiles =
          await _prepareImageFiles(productImages, additionalImages);
      if (uploadFiles.isEmpty) {
        throw FashionAIException('No valid images to process');
      }

      // 3. CHECK FOR EXISTING JOB (Recovery scenario)
      String? existingConversionId;
      Map<String, dynamic>? existingJobData;

      if (jobDocumentId != null && jobDocumentId.isNotEmpty) {
        existingJobData = await _checkExistingJob(jobDocumentId);
        existingConversionId = existingJobData?['conversionId'] as String?;

        if (existingConversionId != null && existingConversionId.isNotEmpty) {
          if (kDebugMode) {
            print(
                '🔄 RECOVERY MODE: Found existing conversion ID: $existingConversionId');
          }
          connectionState.conversionId = existingConversionId;

          // Check if job is already completed
          if (existingJobData?['status'] == 'completed') {
            if (kDebugMode) {
              print('✅ Job already completed, returning existing results');
            }
            return _buildResponseFromExistingData(existingJobData!);
          }
        }
      }

      // 4. UPLOAD IMAGES (if not already done)
      List<String>? uploadedUrls =
          existingJobData?['uploadedImageUrls']?.cast<String>();
      if (uploadedUrls == null || uploadedUrls.isEmpty) {
        uploadedUrls = await _uploadImagesWithRetry(
            uploadFiles, jobDocumentId, connectionState);
      } else {
        if (kDebugMode) {
          print(
              '✅ Using existing uploaded images: ${uploadedUrls.length} images');
        }
      }

      // 5. BUILD API REQUEST
      final inputImages = _buildInputImages(uploadedUrls, uploadFiles);

      // 6. TRIGGER CONVERSION (if not already done)
      String conversionId = existingConversionId ?? '';
      if (conversionId.isEmpty) {
        conversionId = await _triggerConversionWithRetry(
          inputImages: inputImages,
          text: text,
          numberOfOutputs: numberOfOutputs,
          isVideo: isVideo,
          generateCsv: generateCsv, // ✅ Pass the actual value
          jobDocumentId: jobDocumentId,
          connectionState: connectionState,
          productType: productType,
          gender: gender,
          creditCost: creditCost,
        );
      }

      connectionState.conversionId = conversionId;

      // 7. POLL FOR COMPLETION (with generateCsv setting)
      final completedData = await _pollUntilComplete(
        conversionId: conversionId,
        jobDocumentId: jobDocumentId,
        connectionState: connectionState,
        generateCsv: generateCsv, // Pass the actual setting
      );

      // 8. PROCESS AND SAVE RESULTS
      final response = await _processAndSaveResults(
        completedData: completedData,
        conversionId: conversionId,
        jobDocumentId: jobDocumentId,
        connectionState: connectionState,
        includeExcel: generateCsv, // Pass to processing
      );

      // 9. MARK AS COMPLETE
      if (jobDocumentId != null) {
        await _markJobComplete(jobDocumentId, response, connectionState);
      }

      return response;
    } catch (e) {
      // Handle failure - but ONLY if backend explicitly failed
      if (e.toString().contains('Backend processing failed')) {
        if (jobDocumentId != null) {
          await _markJobFailed(jobDocumentId, e.toString(), connectionState);
        }
        rethrow;
      }

      // For any other error, keep retrying
      if (kDebugMode) print('⚠️ Error occurred but will retry: $e');

      // If we have a job ID, update status but don't mark as failed
      if (jobDocumentId != null) {
        try {
          await _firestore
              .collection('GenSpace_jobs')
              .doc(jobDocumentId)
              .update({
            'lastError': e.toString(),
            'errorTime': FieldValue.serverTimestamp(),
            'message': 'Encountered error, retrying...',
            'isRetrying': true,
          });
        } catch (_) {}
      }

      // Retry after delay
      await Future.delayed(Duration(seconds: 5));

      // Recursive retry
      return generateWithOpenApiFromFirebase(
        text: text,
        productImages: productImages,
        additionalImages: additionalImages,
        numberOfOutputs: numberOfOutputs,
        isVideo: isVideo,
        generateCsv: generateCsv,
        jobDocumentId: jobDocumentId,
        productType: productType,
        gender: gender,
      );
    } finally {
      // Clean up connection state
      if (jobDocumentId != null) {
        _activeConnections.remove(jobDocumentId);
      }
    }
  }

  // Helper methods for bulletproof implementation
  Future<Map<String, dynamic>?> _checkExistingJob(String jobId) async {
    try {
      final doc = await _firestore.collection('GenSpace_jobs').doc(jobId).get();
      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Could not check existing job: $e');
    }
    return null;
  }

  Future<List<ImageFile>> _prepareImageFiles(
    Map<String, File?> productImages,
    List<File> additionalImages,
  ) async {
    final files = <ImageFile>[];

    final orderedKeys = ['front_view', 'back_view', 'side_view', 'detail_view'];
    for (final key in orderedKeys) {
      final file = productImages[key];
      if (file != null && await file.exists()) {
        files.add(ImageFile(file: XFile(file.path), type: key));
      }
    }

    for (int i = 0; i < additionalImages.length; i++) {
      final file = additionalImages[i];
      if (await file.exists()) {
        files.add(ImageFile(file: XFile(file.path), type: 'additional_$i'));
      }
    }

    return files;
  }

  Future<List<String>> _uploadImagesWithRetry(
    List<ImageFile> files,
    String? jobDocumentId,
    ConnectionState connectionState,
  ) async {
    int retries = 0;
    const maxRetries = 10;

    while (retries < maxRetries) {
      try {
        if (kDebugMode) {
          print('📤 Uploading ${files.length} images (attempt ${retries + 1})');
        }

        if (!(await _hasInternetConnection())) {
          await _waitForConnection(jobDocumentId, connectionState);
        }

        final urls = await FirebaseService.uploadImages(
            files.map((f) => f.file).toList());

        if (jobDocumentId != null) {
          await _firestore
              .collection('GenSpace_jobs')
              .doc(jobDocumentId)
              .update({
            'uploadedImageUrls': urls,
            'uploadCompleted': true,
            'uploadTime': FieldValue.serverTimestamp(),
          });
        }

        if (kDebugMode) print('✅ Uploaded ${urls.length} images successfully');
        return urls;
      } catch (e) {
        retries++;
        connectionState.uploadRetries = retries;

        if (kDebugMode) print('⚠️ Upload failed (attempt $retries): $e');

        if (retries >= maxRetries) {
          throw FashionAIException(
              'Failed to upload images after $maxRetries attempts');
        }

        await Future.delayed(Duration(seconds: 2 * retries));
      }
    }

    throw FashionAIException('Failed to upload images');
  }

  Future<String> _triggerConversionWithRetry({
    required List<Map<String, String>> inputImages,
    required String text,
    required int numberOfOutputs,
    required bool isVideo,
    bool generateCsv = false, // Add generateCsv parameter
    String? jobDocumentId,
    required ConnectionState connectionState,
    String? productType,
    String? gender,
    double? creditCost, // Add creditCost parameter
  }) async {
    int retries = 0;
    const maxRetries = 100;

    while (retries < maxRetries) {
      try {
        if (kDebugMode) {
          print(
              '🚀 POST Triggering conversion (attempt ${retries + 1}) - generateCsv: $generateCsv');
        }
        if (!(await _hasInternetConnection())) {
          await _waitForConnection(jobDocumentId, connectionState);
        }

        // Use the correct endpoint from OpenAPI spec
        final response = await _dio.post(
          ApiConfig.fashionAIEndpoint, // '/ratnawnai/fashionai'
          data: {
            'inputImages': inputImages,
            'text': text,
            'numberOfOutputs': numberOfOutputs,
            'isVideo': isVideo,
            'generateCsv': generateCsv, // Include generateCsv in POST body
            'upscale': true, // Add this as per OpenAPI spec
            if (productType != null && productType.isNotEmpty)
              'productType': productType,
            if (gender != null && gender.isNotEmpty)
              'gender': gender == 'Male' ? 'man' : 'woman',
          },
          options: Options(
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'x-api-key': ApiConfig.apiKey,
            },
            validateStatus: (status) => status! < 500,
            receiveTimeout: Duration(seconds: 60),
            sendTimeout: Duration(seconds: 60),
          ),
        );

        if (kDebugMode) {
          print('📡 API Response Status: ${response.statusCode}');
          print('📡 API Response Headers: ${response.headers}');
          print('📡 API Response Data: ${response.data}');
        }

        if (response.statusCode == 200 && response.data != null) {
          final conversionId = response.data['id']?.toString() ?? '';

          if (conversionId.isNotEmpty) {
            if (kDebugMode) print('✅ Conversion started: $conversionId');

            if (jobDocumentId != null) {
              await _firestore
                  .collection('GenSpace_jobs')
                  .doc(jobDocumentId)
                  .update({
                'conversionId': conversionId,
                'conversionStarted': FieldValue.serverTimestamp(),
                'progress': 0.3,
                'message': 'AI processing started...',
              });
            }

            // NO IMMEDIATE CREDIT DEDUCTION - Credits will be deducted via webhook after completion
            if (creditCost != null && creditCost > 0) {
              if (kDebugMode) {
                print(
                    '💳 Credits will be deducted after completion via webhook: $creditCost (conversionId: $conversionId)');
              }

              // Update job to indicate credits will be deducted after completion
              if (jobDocumentId != null) {
                await _firestore
                    .collection('GenSpace_jobs')
                    .doc(jobDocumentId)
                    .update({
                  'creditsPending': true,
                  'creditsAmount': creditCost,
                  'creditsDeductionMethod': 'webhook_after_completion',
                  'message':
                      'AI processing started. Credits will be deducted after completion...',
                });
              }
            }

            return conversionId;
          }
        } else if (response.statusCode == 403) {
          if (kDebugMode) {
            print('🚫 403 Forbidden Error - API Key or permissions issue');
            print('Response data: ${response.data}');
            print('Response headers: ${response.headers}');
          }
          throw Exception(
              'API access denied (403). Please check your API key and permissions.');
        }

        throw Exception('Invalid response from API');
      } catch (e) {
        retries++;
        connectionState.triggerRetries = retries;

        if (kDebugMode) print('⚠️ Trigger failed (attempt $retries): $e');

        if (jobDocumentId != null) {
          try {
            await _firestore
                .collection('GenSpace_jobs')
                .doc(jobDocumentId)
                .update({
              'triggerRetries': retries,
              'lastTriggerError': e.toString(),
              'message': 'Retrying API connection... (attempt $retries)',
            });
          } catch (_) {}
        }

        await Future.delayed(Duration(seconds: min(retries * 2, 30)));
      }
    }

    throw FashionAIException(
        'Failed to trigger conversion after $maxRetries attempts');
  }

  Future<Map<String, dynamic>> _pollUntilComplete({
    required String conversionId,
    String? jobDocumentId,
    required ConnectionState connectionState,
    bool generateCsv = true, // Add this parameter
  }) async {
    int pollAttempt = 0;
    int consecutiveErrors = 0;

    // Get the generateCsv setting from the job document if available
    bool shouldGenerateCsv = generateCsv;
    if (jobDocumentId != null) {
      try {
        final jobDoc = await _firestore
            .collection('GenSpace_jobs')
            .doc(jobDocumentId)
            .get();
        if (jobDoc.exists) {
          final requestData =
              jobDoc.data()?['requestData'] as Map<String, dynamic>?;
          shouldGenerateCsv = requestData?['generateCsv'] ?? false;
          if (kDebugMode) {
            print(
                '📊 Retrieved Excel generation setting from job: $shouldGenerateCsv');
          }
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ Could not fetch job settings: $e');
      }
    }

    // INFINITE LOOP - will never give up
    while (true) {
      pollAttempt++;
      connectionState.pollAttempts = pollAttempt;

      final delay = _getPollingDelay(pollAttempt, consecutiveErrors > 0);
      await Future.delayed(delay);

      try {
        if (kDebugMode) {
          print(
              '🔄 GET Poll #$pollAttempt for $conversionId - generateCsv: $shouldGenerateCsv');
        }

        if (!(await _hasInternetConnection())) {
          consecutiveErrors = 0;
          await _waitForConnection(jobDocumentId, connectionState);
          continue;
        }

        // Use GET endpoint with query parameters as per OpenAPI spec
        final response = await _dio.get(
          ApiConfig.fashionAIEndpoint, // '/ratnawnai/fashionai'
          queryParameters: {
            'id': conversionId,
            'generateCsv':
                shouldGenerateCsv, // Use the actual setting instead of hardcoded true
          },
          options: Options(
            headers: {
              'Accept': 'application/json',
              'x-api-key': ApiConfig.apiKey,
            },
            validateStatus: (status) => status! < 500,
            receiveTimeout: Duration(seconds: 30),
          ),
        );

        if (response.statusCode == 200 && response.data is Map) {
          final responseData = response.data as Map<String, dynamic>;
          final data = responseData['data'] as Map<String, dynamic>?;

          if (data != null) {
            connectionState.lastKnownData = data;
          }

          final status = data?['status']?.toString();
          if (kDebugMode) print('📊 Status: $status');

          consecutiveErrors = 0;

          if (jobDocumentId != null) {
            _updatePollingProgress(jobDocumentId, pollAttempt, status);
          }

          if (status == 'completed') {
            if (kDebugMode) print('🎉 Completed after $pollAttempt polls');
            return data!;
          } else if (status == 'failed') {
            if (kDebugMode) print('❌ Backend returned failed status');

            if (jobDocumentId != null) {
              await _firestore
                  .collection('GenSpace_jobs')
                  .doc(jobDocumentId)
                  .update({
                'backendFailure': true,
                'failureData': data,
                'message': 'Backend processing failed',
              });
            }

            throw FashionAIException('Backend processing failed');
          }
        }
      } catch (e) {
        consecutiveErrors++;
        connectionState.consecutiveErrors = consecutiveErrors;

        if (kDebugMode) print('⚠️ Poll error #$consecutiveErrors: $e');

        if (e.toString().contains('Backend processing failed')) {
          rethrow;
        }

        if (jobDocumentId != null) {
          try {
            await _firestore
                .collection('GenSpace_jobs')
                .doc(jobDocumentId)
                .update({
              'lastPollError': e.toString(),
              'consecutiveErrors': consecutiveErrors,
              'message':
                  'Retrying... (poll #$pollAttempt, errors: $consecutiveErrors)',
            });
          } catch (_) {}
        }
      }

      if (pollAttempt % 30 == 0) {
        if (kDebugMode) print('⏳ Still polling after $pollAttempt attempts');

        if (jobDocumentId != null) {
          try {
            await _firestore
                .collection('GenSpace_jobs')
                .doc(jobDocumentId)
                .update({
              'isLongRunning': true,
              'pollAttempts': pollAttempt,
              'message':
                  'Processing is taking longer than usual. Still working...',
            });
          } catch (_) {}
        }
      }
    }
  }

  Future<FashionGenerationResponse> _processAndSaveResults({
    required Map<String, dynamic> completedData,
    required String conversionId,
    String? jobDocumentId,
    required ConnectionState connectionState,
    bool includeExcel = true, // Add this parameter
  }) async {
    final data =
        completedData['data'] as Map<String, dynamic>? ?? completedData;
    final generatedImages = (data['generatedImages'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final generatedVideos = (data['generatedVideos'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    if (kDebugMode) {
      print(
          '📦 Processing ${generatedImages.length} images, ${generatedVideos.length} videos');
    }

    // Extract image URLs directly (no export needed for background service)
    final imageUrls = generatedImages
        .map((e) => e['imageSrc']?.toString())
        .whereType<String>()
        .toList();

    final videoUrls = generatedVideos
        .map((e) => e['videoUrl']?.toString())
        .whereType<String>()
        .toList();

    // Only include CSV URL if Excel generation was requested
    final csvUrl = includeExcel ? data['csv']?.toString() : null;

    // final description = data['description']?.toString();
    // final keyFeatures = (data['keyFeatures'] as List<dynamic>? ?? [])
    //     .map((e) => e.toString())
    //     .toList();
    // final searchKeywords = (data['searchKeywords'] as List<dynamic>? ?? [])
    //     .map((e) => e.toString())
    //     .toList();

    final metadata = {
      'originalImageCount': generatedImages.length,
      'pollAttempts': connectionState.pollAttempts,
      'connectionRetries': connectionState.connectionRetries,
      'processingComplete': true,
      'excelGenerated': includeExcel,
      ...completedData,
    };

    if (kDebugMode) {
      print('📊 Excel generation requested: $includeExcel');
      print('📊 CSV URL: ${csvUrl != null ? 'Available' : 'Not generated'}');
    }

    return FashionGenerationResponse(
      requestId: conversionId,
      outputImageUrl: null,
      imageVariations: imageUrls,
      outputVideoUrl: videoUrls.isNotEmpty ? videoUrls.first : null,
      excelReportUrl: csvUrl, // Will be null if Excel was not requested
      metadata: metadata,
    );
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();

      if (result.contains(ConnectivityResult.none)) {
        return false;
      }

      try {
        final testDio = Dio();
        testDio.options.connectTimeout = Duration(seconds: 3);
        testDio.options.receiveTimeout = Duration(seconds: 3);
        await testDio.get('https://www.google.com');
        return true;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<void> _waitForConnection(
    String? jobDocumentId,
    ConnectionState connectionState,
  ) async {
    if (kDebugMode) print('🌐 Waiting for internet connection...');

    connectionState.isWaitingForConnection = true;
    int checks = 0;

    if (jobDocumentId != null) {
      try {
        await _firestore.collection('GenSpace_jobs').doc(jobDocumentId).update({
          'connectionLost': true,
          'connectionLostTime': FieldValue.serverTimestamp(),
          'message': 'Internet connection lost. Waiting to reconnect...',
        });
      } catch (_) {}
    }

    while (true) {
      checks++;
      connectionState.connectionRetries = checks;

      if (await _hasInternetConnection()) {
        if (kDebugMode) print('✅ Connection restored after $checks checks');

        connectionState.isWaitingForConnection = false;

        if (jobDocumentId != null) {
          try {
            await _firestore
                .collection('GenSpace_jobs')
                .doc(jobDocumentId)
                .update({
              'connectionLost': false,
              'connectionRestoredTime': FieldValue.serverTimestamp(),
              'connectionChecks': checks,
              'message': 'Connection restored. Resuming...',
            });
          } catch (_) {}
        }

        break;
      }

      if (kDebugMode) print('📡 No connection. Check #$checks');

      if (checks % 10 == 0 && jobDocumentId != null) {
        try {
          await _firestore
              .collection('GenSpace_jobs')
              .doc(jobDocumentId)
              .update({
            'connectionChecks': checks,
            'message': 'Waiting for connection... (checked $checks times)',
          });
        } catch (_) {}
      }

      await Future.delayed(Duration(seconds: 2));
    }
  }

  Duration _getPollingDelay(int attempt, bool hasErrors) {
    if (hasErrors) return Duration(seconds: 5);
    if (attempt < 10) return Duration(seconds: 2);
    if (attempt < 30) return Duration(seconds: 3);
    if (attempt < 60) return Duration(seconds: 5);
    if (attempt < 120) return Duration(seconds: 10);
    return Duration(seconds: 15);
  }

  Future<void> _updatePollingProgress(
      String jobId, int pollAttempt, String? status) async {
    try {
      final progress = min(0.3 + (pollAttempt * 0.005), 0.95);
      final message = _getProgressMessage(pollAttempt, status);

      await _firestore.collection('GenSpace_jobs').doc(jobId).update({
        'progress': progress,
        'message': message,
        'lastPollingAttempt': pollAttempt,
        'lastPollingStatus': status,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to update progress: $e');
    }
  }

  String _getProgressMessage(int pollAttempt, String? status) {
    if (status == 'processing') {
      if (pollAttempt < 10) return 'AI is analyzing your images...';
      if (pollAttempt < 30) return 'Generating product variations...';
      if (pollAttempt < 60) return 'Creating optimized content...';
      if (pollAttempt < 90) return 'Finalizing your GenSpace...';
      return 'Almost done, please wait...';
    }
    return 'Processing... (attempt $pollAttempt)';
  }

  Future<void> _markJobComplete(
    String jobId,
    FashionGenerationResponse response,
    ConnectionState connectionState,
  ) async {
    try {
      await _firestore.collection('GenSpace_jobs').doc(jobId).update({
        'status': 'completed',
        'progress': 1.0,
        'message': 'GenSpace generated successfully!',
        'completedAt': FieldValue.serverTimestamp(),
        'result': {
          'excel_export_url': response.excelReportUrl,
          'image_variations': response.imageVariations,
          'output_video_url': response.outputVideoUrl,
          'request_id': response.requestId,
          'metadata': response.metadata,
          'products_processed': 1,
          'success_count': 1,
        },
        'statistics': {
          'totalPollAttempts': connectionState.pollAttempts,
          'totalConnectionRetries': connectionState.connectionRetries,
          'uploadRetries': connectionState.uploadRetries,
          'triggerRetries': connectionState.triggerRetries,
        },
      });

      if (kDebugMode) print('✅ Job marked as complete');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to mark job complete: $e');
    }
  }

  Future<void> _markJobFailed(
    String jobId,
    String error,
    ConnectionState connectionState,
  ) async {
    try {
      await _firestore.collection('GenSpace_jobs').doc(jobId).update({
        'status': 'failed',
        'progress': 0.0,
        'message': 'Generation failed: $error',
        'failedAt': FieldValue.serverTimestamp(),
        'errorMessage': error,
        'statistics': {
          'totalPollAttempts': connectionState.pollAttempts,
          'totalConnectionRetries': connectionState.connectionRetries,
          'uploadRetries': connectionState.uploadRetries,
          'triggerRetries': connectionState.triggerRetries,
        },
        'lastKnownData': connectionState.lastKnownData,
      });

      if (kDebugMode) print('❌ Job marked as failed');
    } catch (e) {
      if (kDebugMode) print('⚠️ Failed to mark job as failed: $e');
    }
  }

  FashionGenerationResponse _buildResponseFromExistingData(
      Map<String, dynamic> jobData) {
    final result = jobData['result'] as Map<String, dynamic>? ?? {};

    return FashionGenerationResponse(
      requestId: result['request_id'] ?? '',
      outputImageUrl: null,
      imageVariations: List<String>.from(result['image_variations'] ?? []),
      outputVideoUrl: result['output_video_url'],
      excelReportUrl: result['excel_export_url'],
      metadata: result['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  List<Map<String, String>> _buildInputImages(
    List<String> urls,
    List<ImageFile> files,
  ) {
    final inputImages = <Map<String, String>>[];
    final viewMap = {
      'front_view': 'front',
      'back_view': 'back',
      'side_view': 'side',
      'detail_view': 'detail',
    };

    for (int i = 0; i < urls.length && i < files.length; i++) {
      final type = files[i].type;
      final view =
          viewMap[type] ?? (type.startsWith('additional') ? 'detail' : 'front');

      inputImages.add({
        'url': urls[i],
        'view': view,
      });
    }

    return inputImages;
  }

  Future<void> _updateJobProgress(
    String jobId,
    double progress,
    String message, {
    bool isComplete = false,
    bool isFailed = false,
    Map<String, dynamic>? result,
  }) async {
    final updateData = {
      'progress': progress,
      'message': message,
      'status': isFailed ? 'failed' : (isComplete ? 'completed' : 'processing'),
    };

    if (result != null) {
      updateData['result'] = result;
    }
    if (isComplete || isFailed) {
      updateData['completedAt'] = FieldValue.serverTimestamp();
    }

    await _firestore.collection('GenSpace_jobs').doc(jobId).update(updateData);
  }

  Future<void> _saveGenerationResults(
      String jobId, FashionGenerationResponse result) async {
    final currentUser = FirebaseService.currentUser;
    if (currentUser == null) return;

    final resultData = {
      'excel_export_url': result.excelReportUrl,
      'image_variations': result.imageVariations,
      'output_video_url': result.outputVideoUrl != null
          ? [result.outputVideoUrl]
          : [], // Save as array
      'request_id': result.requestId,
      'metadata': result.metadata,
      'products_processed': 1,
      'success_count': 1,
    };

    await _firestore.collection('GenSpace_jobs').doc(jobId).update({
      'result': resultData,
    });
  }

  /// Generate video from image (new endpoint)
  Future<String> generateVideoFromImageWithId({
    required String imageUrl,
    required String imageId,
    String? existingConversionId,
    int maxRetries = 3,
  }) async {
    int attempt = 0;

    while (attempt < maxRetries) {
      attempt++;

      try {
        if (kDebugMode) {
          print('🎬 Video generation attempt $attempt/$maxRetries');
          print('📸 Image URL: $imageUrl');
          print('🔑 Image ID: $imageId');
          if (existingConversionId != null) {
            print('🔗 Using existing conversion ID: $existingConversionId');
          }
        }

        // Prepare request body according to OpenAPI spec
        final requestBody = {
          'imageUrl': imageUrl,
          'id': imageId, // Send imageId as id field instead of conversionId
        };

        // Note: existingConversionId is used for tracking purposes but not sent in request
        if (kDebugMode) {
          print('📦 Request body: $requestBody');
          print('🔗 Conversion ID (for tracking): $existingConversionId');
        }

        // Call the video generation endpoint
        final response = await _dio.post(
          ApiConfig.fashionAIVideoEndpoint,
          data: requestBody,
          options: Options(
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'x-api-key': ApiConfig.apiKey,
            },
            validateStatus: (status) {
              return status != null &&
                  (status < 500 ||
                      status == 502 ||
                      status == 503 ||
                      status == 504);
            },
            receiveTimeout: Duration(seconds: 30),
            sendTimeout: Duration(seconds: 30),
          ),
        );

        if (kDebugMode) {
          print('📡 Response status: ${response.statusCode}');
          print('📡 Response data: ${response.data}');
        }

        // Handle 502/503/504 Gateway errors with retry
        if (response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          if (attempt < maxRetries) {
            final waitTime = Duration(seconds: attempt * 2);
            await Future.delayed(waitTime);
            continue;
          } else {
            throw FashionAIException(
                'Video generation service is temporarily unavailable. Please try again in a few minutes.');
          }
        }

        if (response.statusCode == 200 && response.data != null) {
          final returnedId =
              response.data['id']?.toString() ?? existingConversionId ?? '';

          if (returnedId.isNotEmpty) {
            if (kDebugMode) {
              print('✅ Video generation started with ID: $returnedId');
            }
            return returnedId;
          } else {
            throw Exception('No conversion ID returned from video API');
          }
        } else {
          throw Exception(
              'Failed to generate video: Status ${response.statusCode}');
        }
      } on DioException catch (e) {
        if (kDebugMode) {
          print(
              '❌ Video generation API error (attempt $attempt): ${e.message}');
        }

        if (attempt < maxRetries) {
          final waitTime = Duration(seconds: attempt * 2);
          await Future.delayed(waitTime);
          continue;
        }

        throw FashionAIException('Failed to generate video: ${e.message}');
      }
    }

    throw FashionAIException(
        'Failed to generate video after $maxRetries attempts');
  }

  /// export Excel file (preserved)
  Future<String> exportExcelFile({
    required String url,
    required String fileName,
    Function(double)? onProgress,
  }) async {
    final Directory exportsDir = Platform.isAndroid
        ? Directory('/storage/emulated/0/export')
        : await getApplicationDocumentsDirectory();

    // if (exportsDir == null) {
    //   throw FashionAIException('Could not access exports directory');
    // }

    final String filePath = '${exportsDir.path}/$fileName';

    await _dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          final progress = received / total;
          onProgress?.call(progress);
        }
      },
    );

    return filePath;
  }

  /// Check API health
  Future<bool> checkApiHealth() async {
    try {
      if (kDebugMode) print('🔗 Checking API health at: ${ApiConfig.baseUrl}');

      final healthDio = Dio();
      healthDio.options.baseUrl = ApiConfig.baseUrl;
      healthDio.options.connectTimeout = ApiConfig.healthCheckTimeout;
      healthDio.options.receiveTimeout = ApiConfig.healthCheckTimeout;
      healthDio.options.sendTimeout = ApiConfig.healthCheckTimeout;

      final response = await healthDio.get('/',
          options: Options(
            receiveTimeout: ApiConfig.healthCheckTimeout,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'RatNawnAI-App',
              'x-api-key': ApiConfig.apiKey,
            },
            validateStatus: (status) {
              return status != null && status < 500;
            },
          ));

      final isHealthy = response.statusCode == 200;
      if (kDebugMode) {
        print(
            '🥼 API health check result: $isHealthy (status: ${response.statusCode})');
        print('🌐 Response headers: ${response.headers}');
      }
      return isHealthy;
    } catch (e) {
      if (kDebugMode) {
        print('❌ API health check failed: $e');
        if (e is DioException) {
          print('🔍 DioException type: ${e.type}');
          print('🔍 DioException message: ${e.message}');
          print('🔍 Request options: ${e.requestOptions.uri}');
          if (e.response != null) {
            print('🔍 Response status: ${e.response!.statusCode}');
            print('🔍 Response data: ${e.response!.data}');
            print('🔍 Response headers: ${e.response!.headers}');
          }
        }
      }
      return false;
    }
  }

  /// Test network connectivity
  Future<bool> testNetworkConnectivity() async {
    try {
      if (kDebugMode) print('🌐 Testing basic network connectivity...');

      final testDio = Dio();
      testDio.options.connectTimeout = const Duration(seconds: 5);
      testDio.options.receiveTimeout = const Duration(seconds: 5);

      final response = await testDio
          .get('https://dns.google.com/resolve?name=google.com&type=A');
      final isConnected = response.statusCode == 200;

      if (kDebugMode) print('🌐 Network connectivity test: $isConnected');
      return isConnected;
    } catch (e) {
      if (kDebugMode) print('❌ Network connectivity test failed: $e');
      return false;
    }
  }

  /// NEW WEBHOOK-BASED GENERATION METHOD
  /// This method uses our new credit-aware webhook system instead of direct API calls
  Future<String> generateWithWebhook({
    required String text,
    required Map<String, File?> productImages,
    Map<String, File?>? additionalImages,
    required int imagesToGenerate,
    required bool generateVideo,
    required bool generateCsv,
    String? skuId,
    String? username,
    String? product,
    String? productType,
    String? gender,
    Map<String, List<int>>? backgroundArrays,
  }) async {
    // Wait for Firebase Auth to be ready
    await FirebaseAuth.instance.authStateChanges().first;

    final currentUser = FirebaseService.currentUser;
    if (currentUser == null) {
      // Try one more time after a short delay
      await Future.delayed(ApiConfig.retryDelay);
      final retryUser = FirebaseService.currentUser;
      if (retryUser == null) {
        throw FashionAIException(
            'User not authenticated. Please login and try again.');
      }
    }

    // Use SKU ID if provided, otherwise generate a random SKU ID
    final documentId = skuId ?? _generateSkuId();
    final jobDoc = _firestore.collection('GenSpace_jobs').doc(documentId);

    await jobDoc.set({
      'skuId': documentId,
      'userId': currentUser?.uid ?? FirebaseService.currentUser!.uid,
      'status': 'processing',
      'progress': 0.0,
      'message': 'Starting webhook-based AI generation...',
      'createdAt': FieldValue.serverTimestamp(),
      'requestData': {
        'text': text,
        'username': username,
        'product': product,
        'generateVideo': generateVideo,
        'generateCsv': generateCsv,
        'imagesToGenerate': imagesToGenerate,
        'productType': productType,
        'gender': gender,
      },
    });

    if (!productImages.containsKey('front_view') &&
        !productImages.containsKey('frontside')) {
      throw FashionAIException('Front view image is required');
    }

    await _updateJobProgress(
        documentId, 0.1, 'Initializing webhook-based generation...');

    try {
      // Initialize webhook service
      final webhookService = WebhookAIService();

      // Check if webhook system is available
      final isWebhookAvailable =
          await webhookService.isWebhookSystemAvailable();
      if (!isWebhookAvailable) {
        throw FashionAIException(
            'Webhook system is not available. Please try again later.');
      }

      await _updateJobProgress(
          documentId, 0.2, 'Initiating generation through webhook...');

      // Initiate generation through webhook
      final initiationResult = await webhookService.initiateGeneration(
        jobId: documentId,
        text: text,
        productImages: productImages,
        additionalImages: additionalImages,
        imagesToGenerate: imagesToGenerate,
        generateVideo: generateVideo,
        generateCsv: generateCsv,
        productType: productType,
        gender: gender,
        backgroundArrays: backgroundArrays,
      );

      if (!initiationResult['success']) {
        throw FashionAIException(
            'Failed to initiate generation: ${initiationResult['error']}');
      }

      final conversionId = initiationResult['conversionId'] as String;
      
      // Safe numeric casting to prevent null subtype errors
      final creditsDeducted = (initiationResult['creditsDeducted'] as num?)?.toDouble() ?? 0.0;
      final newBalance = (initiationResult['newBalance'] as num?)?.toDouble() ?? 0.0;
      
      if (kDebugMode) {
        print('🔍 Initiation result keys: ${initiationResult.keys}');
        print('🔍 Credits deducted: $creditsDeducted');
        print('🔍 New balance: $newBalance');
      }

      // Get the uploaded image URLs from the webhook service response
      final uploadedImageUrls = <String>[];
      if (initiationResult.containsKey('uploadedImageUrls')) {
        final urls = initiationResult['uploadedImageUrls'];
        if (urls is List) {
          uploadedImageUrls.addAll(urls.map((e) => e.toString()));
        }
      }

      // Update job with conversion ID
      await jobDoc.update({
        'conversionId': conversionId,
        'creditsDeducted': creditsDeducted,
        'newBalance': newBalance,
        'message': 'Generation initiated, waiting for completion...',
        'progress': 0.3,
        'uploadedImageUrls': uploadedImageUrls, // ✅ Save uploaded image URLs
      });

      if (kDebugMode) {
        print('✅ Webhook generation initiated successfully');
        print('🆔 Conversion ID: $conversionId');
        print('💰 Credits deducted: $creditsDeducted');
        print('💳 New balance: $newBalance');
      }

      await _updateJobProgress(
          documentId, 0.4, 'Generation in progress, monitoring status...');

      // Wait for completion
      final completionResult = await webhookService.waitForCompletion(
        jobId: documentId,
        conversionId: conversionId,
        timeout: const Duration(minutes: 15), // Extended timeout for webhook
      );

      if (completionResult['status'] == 'failed') {
        throw FashionAIException(
            'Generation failed: ${completionResult['error']}');
      }

      await _updateJobProgress(
          documentId, 0.8, 'Generation complete, processing results...');

      // Get the final results
      final results = await webhookService.getGenerationResults(documentId);

      await _updateJobProgress(
          documentId, 1.0, 'Webhook generation completed successfully!',
          isComplete: true);

      // Notify user that GenSpace generation has completed successfully (non-blocking)
      NotificationService.showNotification(
        title: 'GenSpace Generation Complete!',
        body:
            'Your product GenSpace has been generated successfully using the new webhook system. Check your exports.',
      ).catchError((error) {
        if (kDebugMode) print('⚠️ Notification error: $error');
      });

      // IMMEDIATELY clear background service notification after showing success notification
      NotificationService.clearBackgroundServiceNotifications().catchError((error) {
        if (kDebugMode) print('⚠️ Error clearing background notifications: $error');
      });

      if (kDebugMode) {
        print('✅ Webhook-based generation completed successfully');
        print('📊 Results: ${results.keys.join(', ')}');
      }

      return documentId;
    } catch (e) {
      await _updateJobProgress(documentId, 0.0, 'Error: ${e.toString()}',
          isFailed: true);

      // Notify user that GenSpace generation has failed (non-blocking)
      NotificationService.showNotification(
        title: 'GenSpace Generation Failed',
        body:
            'Failed to generate your product GenSpace using webhook system. Please try again.',
      ).catchError((error) {
        if (kDebugMode) print('⚠️ Notification error: $error');
      });

      throw FashionAIException('Webhook generation failed: ${e.toString()}');
    }
  }
}

// Helper classes
class ConnectionState {
  final String jobId;
  String? conversionId;
  Map<String, dynamic>? lastKnownData;
  int pollAttempts = 0;
  int connectionRetries = 0;
  int uploadRetries = 0;
  int triggerRetries = 0;
  int consecutiveErrors = 0;
  bool isWaitingForConnection = false;

  ConnectionState({required this.jobId});
}

class ImageFile {
  final XFile file;
  final String type;

  ImageFile({required this.file, required this.type});
}

class FashionGenerationResponse {
  final String requestId;
  final String? outputImageUrl;
  final List<String> imageVariations;
  final String? outputVideoUrl;
  final String? excelReportUrl;
  final Map<String, dynamic>? metadata;

  FashionGenerationResponse({
    required this.requestId,
    this.outputImageUrl,
    this.imageVariations = const [],
    this.outputVideoUrl,
    this.excelReportUrl,
    this.metadata,
  });

  factory FashionGenerationResponse.fromJson(Map<String, dynamic> json) {
    return FashionGenerationResponse(
      requestId: json['request_id'] ?? '',
      outputImageUrl: null,
      imageVariations: List<String>.from(json['image_variations'] ?? []),
      outputVideoUrl: json['output_video_url'],
      excelReportUrl: json['excel_report_url'],
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'request_id': requestId,
      'image_variations': imageVariations,
      'output_video_url': outputVideoUrl,
      'excel_report_url': excelReportUrl,
      'metadata': metadata,
    };
  }
}

class FashionAIException implements Exception {
  final String message;
  FashionAIException(this.message);
  @override
  String toString() => 'FashionAIException: $message';
}
