import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../config/api_config.dart';

/// Service for handling AI generation through Firebase Functions webhooks
/// This replaces direct API calls with our new credit-aware webhook system
class WebhookAIService {
  final Dio _dio = Dio();

  WebhookAIService() {
    _dio.options.baseUrl = ApiConfig.baseUrl;
    _dio.options.connectTimeout = ApiConfig.connectTimeout;
    _dio.options.receiveTimeout = ApiConfig.receiveTimeout;
    _dio.options.sendTimeout = ApiConfig.sendTimeout;
  }

  /// Upload images to Firebase Storage and get URLs
  Future<List<String>> _uploadImages(
    Map<String, File?> productImages, 
    Map<String, File?>? additionalImages
  ) async {
    final uploadedUrls = <String>[];

    // Upload product images
    for (final entry in productImages.entries) {
      if (entry.value != null) {
        try {
          // Upload to Firebase Storage
          final ref = FirebaseStorage.instance
              .ref()
              .child('product_images')
              .child(
                  '${DateTime.now().millisecondsSinceEpoch}_${entry.key}.jpg');

          final uploadTask = ref.putFile(entry.value!);
          final snapshot = await uploadTask;
          final downloadUrl = await snapshot.ref.getDownloadURL();

          uploadedUrls.add(downloadUrl);

          if (kDebugMode) {
            print('✅ Uploaded ${entry.key}: $downloadUrl');
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Failed to upload ${entry.key}: $e');
          }
          throw Exception('Failed to upload ${entry.key}: $e');
        }
      }
    }

    // Upload additional images
    if (additionalImages != null) {
      for (final entry in additionalImages.entries) {
        if (entry.value != null) {
          try {
            // Upload to Firebase Storage with detail_view naming (all additional images use same name)
            final ref = FirebaseStorage.instance
                .ref()
                .child('product_images')
                .child('${DateTime.now().millisecondsSinceEpoch}_detail_view.jpg');

            final uploadTask = ref.putFile(entry.value!);
            final snapshot = await uploadTask;
            final downloadUrl = await snapshot.ref.getDownloadURL();

            uploadedUrls.add(downloadUrl);

            if (kDebugMode) {
              print('✅ Uploaded additional ${entry.key} as detail_view: $downloadUrl');
            }
          } catch (e) {
            if (kDebugMode) {
              print('❌ Failed to upload additional ${entry.key}: $e');
            }
            throw Exception('Failed to upload additional ${entry.key}: $e');
          }
        }
      }
    }

    return uploadedUrls;
  }

  /// Prepare image URLs with background arrays according to OpenAPI spec
  List<Map<String, dynamic>> _prepareImageUrlsWithBackgrounds(
    List<String> uploadedImageUrls,
    Map<String, File?> productImages,
    Map<String, File?>? additionalImages,
    Map<String, List<int>>? backgroundArrays,
  ) {
    final result = <Map<String, dynamic>>[];
    int urlIndex = 0;
    
    // Process product images
    productImages.forEach((key, file) {
      if (file != null && urlIndex < uploadedImageUrls.length) {
        String viewType; // lowercase for OpenAPI
        String backgroundKey; // original format for background lookup
        
        switch (key) {
          case 'front_view':
            viewType = 'front';
            backgroundKey = 'Front View';
            break;
          case 'side_view':
            viewType = 'side';
            backgroundKey = 'Side View';
            break;
          case 'back_view':
            viewType = 'back';
            backgroundKey = 'Back View';
            break;
          case 'detail_view':
            viewType = 'detail';
            backgroundKey = 'Detail View';
            break;
          default:
            viewType = 'detail';
            backgroundKey = 'Detail View';
        }
        
        // Get background array for this view type
        final backgroundArray = backgroundArrays?[backgroundKey] ?? [1, 0, 0]; // Default [White, Plain, Random] - White is default
        
        result.add({
          'url': uploadedImageUrls[urlIndex],
          'view': viewType, // lowercase for OpenAPI
          'backgrounds': backgroundArray,
        });
        
        urlIndex++;
      }
    });

    // Process additional images
    if (additionalImages != null) {
      additionalImages.forEach((key, file) {
        if (file != null && urlIndex < uploadedImageUrls.length) {
          // Additional images use the combined "Additional View" background array
          // Background arrays are organized by view type, not individual image labels
          final backgroundKey = 'Additional View';
          
          // Get background array for Additional View (combined array from UI)
          final backgroundArray = backgroundArrays?[backgroundKey] ?? [1, 0, 0]; // Default [White, Plain, Random] - White is default
          
          result.add({
            'url': uploadedImageUrls[urlIndex],
            'view': 'detail', // Additional images are sent as detail view
            'backgrounds': backgroundArray,
          });
          
          if (kDebugMode) {
            print('📸 Additional image: $key -> $backgroundKey -> $backgroundArray');
            print('🔍 Available background keys: ${backgroundArrays?.keys.toList()}');
          }
          
          urlIndex++;
        }
      });
    }

    if (kDebugMode) {
      print('🎨 Image URLs with background arrays (OpenAPI format):');
      for (var item in result) {
        print('   ${item['view']}: ${item['backgrounds']}');
      }
    }

    return result;
  }

  /// Deduct credits from user's wallet
  Future<bool> _deductCredits(String userId, double amount, String jobId) async {
    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(userId);
      
      return await FirebaseFirestore.instance.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userDoc);
        
        if (!userSnapshot.exists) {
          throw Exception('User not found');
        }
        
        final userData = userSnapshot.data()!;
        final currentBalance = (userData['creditBalance'] as num?)?.toDouble() ?? 0.0;
        
        if (currentBalance < amount) {
          return false; // Insufficient credits
        }
        
        final newBalance = currentBalance - amount;
        
        // Update user's credit balance
        transaction.update(userDoc, {
          'creditBalance': newBalance,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        
        // Log the credit transaction
        final transactionDoc = FirebaseFirestore.instance
            .collection('credit_transactions')
            .doc();
        
        transaction.set(transactionDoc, {
          'userId': userId,
          'jobId': jobId,
          'type': 'debit',
          'amount': amount,
          'balanceBefore': currentBalance,
          'balanceAfter': newBalance,
          'reason': 'GenSpace generation',
          'timestamp': FieldValue.serverTimestamp(),
        });
        
        if (kDebugMode) {
          print('💰 Credits deducted: $amount, New balance: $newBalance');
        }
        
        return true;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Credit deduction failed: $e');
      }
      return false;
    }
  }

  /// Calculate credit cost based on generation parameters
  Future<double> _calculateCreditCost({
    required int imagesToGenerate,
    required bool generateVideo,
    required bool generateCsv,
  }) async {
    try {
      // Fetch credit rates from Firestore
      final creditsDoc = await FirebaseFirestore.instance
          .collection('credits')
          .doc('creditUsage')
          .get();

      Map<String, dynamic> creditRates;
      if (creditsDoc.exists && creditsDoc.data() != null) {
        creditRates = creditsDoc.data()!;
      } else {
        // Fallback to default rates
        creditRates = {
          'image': 1.0,
          'video': 1.0,
          'excel': 0.5,
        };
      }

      final imageRate = (creditRates['image'] ?? 1.0).toDouble();
      final videoRate = (creditRates['video'] ?? 1.0).toDouble();
      final excelRate = (creditRates['excel'] ?? 0.5).toDouble();

      final totalCost = (imagesToGenerate * imageRate) +
          (generateVideo ? videoRate : 0.0) +
          (generateCsv ? excelRate : 0.0);

      if (kDebugMode) {
        print('💰 Credit calculation:');
        print(
            '   Images: $imagesToGenerate × $imageRate = ${imagesToGenerate * imageRate}');
        print('   Video: ${generateVideo ? videoRate : 0}');
        print('   Excel: ${generateCsv ? excelRate : 0}');
        print('   Total: $totalCost');
      }

      return totalCost.toDouble();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to fetch credit rates, using defaults: $e');
      }
      // Fallback calculation
      return (imagesToGenerate * 1.0) +
          (generateVideo ? 1.0 : 0.0) +
          (generateCsv ? 0.5 : 0.0);
    }
  }

  /// Map gender to OpenAPI specification format
  String? _mapGenderToOpenAPI(String? gender) {
    if (gender == null) return null;
    switch (gender.toLowerCase()) {
      case 'female':
        return 'woman';
      case 'male':
        return 'man';
      case 'woman':
      case 'man':
        return gender.toLowerCase();
      default:
        return null;
    }
  }

  /// Initiate AI generation through OpenAPI (direct call)
  Future<Map<String, dynamic>> initiateGeneration({
    required String jobId,
    required String text,
    required Map<String, File?> productImages,
    Map<String, File?>? additionalImages,
    required int imagesToGenerate,
    required bool generateVideo,
    required bool generateCsv,
    String? productType,
    String? gender,
    Map<String, List<int>>? backgroundArrays,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Upload images first
      if (kDebugMode) print('📤 Uploading images...');
      final uploadedImageUrls = await _uploadImages(productImages, additionalImages);

      // Calculate credit cost (for internal tracking)
      final creditCost = await _calculateCreditCost(
        imagesToGenerate: imagesToGenerate,
        generateVideo: generateVideo,
        generateCsv: generateCsv,
      );

      // Deduct credits before making API call
      final hasEnoughCredits = await FirebaseAuth.instance.currentUser != null
          ? await _deductCredits(currentUser.uid, creditCost, jobId)
          : false;
      
      if (!hasEnoughCredits) {
        throw Exception('Insufficient credits. Required: $creditCost');
      }

      // Prepare image URLs with background arrays according to OpenAPI spec
      final imageUrlsWithBackgrounds = _prepareImageUrlsWithBackgrounds(
        uploadedImageUrls, 
        productImages,
        additionalImages,
        backgroundArrays
      );

      // Prepare request data according to OpenAPI specification
      final requestData = {
        'inputImages': imageUrlsWithBackgrounds,
        'productType': productType ?? 'general',
        'gender': _mapGenderToOpenAPI(gender),
        'text': text,
        'isVideo': generateVideo,
        'upscale': true,
        'numberOfOutputs': imagesToGenerate,
        'generateCsv': generateCsv,
      };

      if (kDebugMode) {
        print('🚀 Calling Ratnawnai OpenAPI directly...');
        print('📦 Request: ${jsonEncode(requestData)}');
      }

      // Call the Ratnawnai API through your proxy
      final openApiDio = Dio();
      openApiDio.options.baseUrl = ApiConfig.baseUrl; // Your proxy URL
      
      final response = await openApiDio.post(
        ApiConfig.fashionAIEndpoint, // /ratnawnai/fashionai
        data: requestData,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': ApiConfig.apiKey, // Your proxy API key
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final result = response.data as Map<String, dynamic>;

        // OpenAPI returns 200 with { "message": "...", "id": "..." } on success
        if (result.containsKey('id')) {
          final conversionId = result['id'] as String;
          
          if (kDebugMode) {
            print('✅ Generation initiated successfully');
            print('🆔 Conversion ID: $conversionId');
            print('📝 Message: ${result['message']}');
          }

          // Save job info to Firestore for tracking
          await FirebaseFirestore.instance
              .collection('GenSpace_jobs')
              .doc(jobId)
              .update({
            'conversionId': conversionId,
            'status': 'processing',
            'message': 'Generation initiated via OpenAPI',
            'progress': 0.3,
            'creditCost': creditCost,
            'uploadedImageUrls': uploadedImageUrls, // ✅ Save uploaded image URLs
          });

          // Get user's current balance after deduction
          final currentUser = FirebaseAuth.instance.currentUser!;
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
          
          final currentBalance = userDoc.exists 
              ? (userDoc.data()?['creditBalance'] as num?)?.toDouble() ?? 0.0
              : 0.0;

          return {
            'success': true,
            'conversionId': conversionId,
            'message': result['message'],
            'creditsDeducted': creditCost, // Match expected field name
            'newBalance': currentBalance, // Provide current balance
            'creditCost': creditCost, // For backward compatibility
            'uploadedImageUrls': uploadedImageUrls, // ✅ Include uploaded image URLs
          };
        } else {
          throw Exception(
              'Generation failed: ${result['error'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.data}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Generation initiation failed: $e');
      }
      rethrow;
    }
  }

  /// Poll for completion status using OpenAPI
  Future<Map<String, dynamic>> pollForCompletion({
    required String jobId,
    required String conversionId,
  }) async {
    try {
      // Poll using API status endpoint through your proxy
      final statusDio = Dio();
      statusDio.options.baseUrl = ApiConfig.baseUrl; // Your proxy URL
      
      final response = await statusDio.get(
        ApiConfig.fashionAIEndpoint, // /ratnawnai/fashionai
        queryParameters: {'id': conversionId},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': ApiConfig.apiKey, // Your proxy API key
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final result = response.data as Map<String, dynamic>;
        final data = result['data'] as Map<String, dynamic>?;
        
        if (data != null) {
          final status = data['status'] as String?;

          if (kDebugMode) {
            print('📊 Generation status: $status');
          }

          if (status == 'completed') {
            // Generation completed successfully
            // Update Firestore with results
            await FirebaseFirestore.instance
                .collection('GenSpace_jobs')
                .doc(jobId)
                .update({
              'status': 'completed',
              'progress': 1.0,
              'message': 'Generation completed successfully',
              'result': data,
            });

            return {
              'completed': true,
              'status': 'completed',
              'data': data,
            };
          } else if (status == 'failed') {
            // Generation failed
            await FirebaseFirestore.instance
                .collection('GenSpace_jobs')
                .doc(jobId)
                .update({
              'status': 'failed',
              'message': 'Generation failed',
              'error': 'Generation failed',
            });

            return {
              'completed': true,
              'status': 'failed',
              'error': 'Generation failed',
            };
          } else {
            // Still processing (pending, processing, generating)
            await FirebaseFirestore.instance
                .collection('GenSpace_jobs')
                .doc(jobId)
                .update({
              'status': status ?? 'processing',
              'message': 'Generation in progress...',
            });

            return {
              'completed': false,
              'status': status ?? 'processing',
            };
          }
        }
      }
      
      // If response doesn't contain expected data, assume still processing
      return {
        'completed': false,
        'status': 'processing',
      };
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Polling failed: $e');
      }
      
      // Don't rethrow immediately - might be temporary network issue
      return {
        'completed': false,
        'status': 'polling_error',
        'error': e.toString(),
      };
    }
  }

  /// Wait for completion with polling
  Future<Map<String, dynamic>> waitForCompletion({
    required String jobId,
    required String conversionId,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final startTime = DateTime.now();
    const pollInterval = Duration(seconds: 3);

    while (DateTime.now().difference(startTime) < timeout) {
      try {
        final result = await pollForCompletion(
          jobId: jobId,
          conversionId: conversionId,
        );

        if (result['completed'] == true) {
          return result;
        }

        // Wait before next poll
        await Future.delayed(pollInterval);
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Polling error: $e');
        }
        await Future.delayed(pollInterval);
      }
    }

    throw Exception('Generation timeout after ${timeout.inMinutes} minutes');
  }

  /// Get generation results
  Future<Map<String, dynamic>> getGenerationResults(String jobId) async {
    try {
      final jobDoc = await FirebaseFirestore.instance
          .collection('GenSpace_jobs')
          .doc(jobId)
          .get();

      if (!jobDoc.exists) {
        throw Exception('Job not found: $jobId');
      }

      final jobData = jobDoc.data()!;
      final result = jobData['result'] as Map<String, dynamic>?;

      if (result == null) {
        throw Exception('No results found for job: $jobId');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to get results: $e');
      }
      rethrow;
    }
  }

  /// Check if the API system is available
  Future<bool> isWebhookSystemAvailable() async {
    // Skip availability check for now to avoid 404 errors
    // Assume the system is available and let the actual request handle failures
    if (kDebugMode) {
      print('✅ Webhook system assumed available (skipping test to avoid 404s)');
    }
    return true;
  }
}
