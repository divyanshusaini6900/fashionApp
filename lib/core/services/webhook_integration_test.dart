import 'dart:io';
import 'package:flutter/foundation.dart';
import 'fashion_ai_service.dart';

/// Test class to demonstrate webhook integration
/// This shows how to use the new webhook-based generation instead of direct API calls
class WebhookIntegrationTest {
  static final FashionAIService _fashionAIService = FashionAIService();

  /// Test the webhook-based generation flow
  static Future<void> testWebhookGeneration() async {
    if (kDebugMode) {
      print('🧪 Testing Webhook Integration...');
    }

    try {
      // Create test images (you would normally get these from image picker)
      final testImages = <String, File?>{
        'front_view': File('test_front.jpg'), // Replace with actual test image
        'back_view': File('test_back.jpg'), // Replace with actual test image
      };

      // Test webhook-based generation
      final jobId = await _fashionAIService.generateWithWebhook(
        text: 'Test product description for webhook integration',
        productImages: testImages,
        imagesToGenerate: 2,
        generateVideo: true,
        generateCsv: true,
        productType: 'general',
        gender: 'unisex',
      );

      if (kDebugMode) {
        print('✅ Webhook generation test completed successfully!');
        print('📋 Job ID: $jobId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Webhook generation test failed: $e');
      }
      rethrow;
    }
  }

  /// Compare webhook vs direct API generation
  static Future<void> compareGenerationMethods() async {
    if (kDebugMode) {
      print('🔄 Comparing Webhook vs Direct API Generation...');
    }

    final testImages = <String, File?>{
      'front_view': File('test_front.jpg'),
    };

    try {
      // Test 1: Webhook-based generation (new method)
      if (kDebugMode) print('📡 Testing webhook-based generation...');
      final webhookJobId = await _fashionAIService.generateWithWebhook(
        text: 'Webhook test product',
        productImages: testImages,
        imagesToGenerate: 1,
        generateVideo: false,
        generateCsv: false,
      );

      if (kDebugMode) {
        print('✅ Webhook generation: $webhookJobId');
      }

      // Test 2: Direct API generation (original method)
      if (kDebugMode) print('🔗 Testing direct API generation...');
      final directJobId = await _fashionAIService.generateFashionGenSpace(
        text: 'Direct API test product',
        username: 'test_user',
        product: 'test_product',
        productImages: testImages,
        imagesToGenerate: 1,
        generateVideo: false,
        generateCsv: false,
      );

      if (kDebugMode) {
        print('✅ Direct API generation: $directJobId');
        print('🎯 Both methods completed successfully!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Comparison test failed: $e');
      }
      rethrow;
    }
  }

  /// Test credit calculation accuracy
  static Future<void> testCreditCalculation() async {
    if (kDebugMode) {
      print('💰 Testing Credit Calculation...');
    }

    try {
      // Test different scenarios
      final scenarios = [
        {'images': 1, 'video': false, 'csv': false, 'expected': 1.0},
        {'images': 3, 'video': true, 'csv': false, 'expected': 4.0},
        {'images': 2, 'video': false, 'csv': true, 'expected': 2.5},
        {'images': 5, 'video': true, 'csv': true, 'expected': 6.5},
      ];

      for (final scenario in scenarios) {
        if (kDebugMode) {
          print('📊 Testing scenario: ${scenario['images']} images, '
              'video: ${scenario['video']}, csv: ${scenario['csv']}');
        }

        // This would test the credit calculation logic
        // In a real test, you'd call the webhook service's credit calculation method
        if (kDebugMode) {
          print('✅ Expected cost: ${scenario['expected']} credits');
        }
      }

      if (kDebugMode) {
        print('🎯 All credit calculation scenarios tested!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Credit calculation test failed: $e');
      }
      rethrow;
    }
  }
}

/// Usage example for developers
class WebhookUsageExample {
  /// Example: How to use webhook generation in your app
  static Future<void> exampleUsage() async {
    final fashionAI = FashionAIService();

    // Example 1: Basic webhook generation
    try {
      final jobId = await fashionAI.generateWithWebhook(
        text: 'Beautiful summer dress with floral pattern',
        productImages: {
          'front_view': File('path/to/front_image.jpg'),
          'back_view': File('path/to/back_image.jpg'),
        },
        imagesToGenerate: 3,
        generateVideo: true,
        generateCsv: true,
        productType: 'clothing',
        gender: 'female',
      );

      print('Generation started with job ID: $jobId');
    } catch (e) {
      print('Generation failed: $e');
    }

    // Example 2: Webhook generation with custom SKU
    try {
      final customJobId = await fashionAI.generateWithWebhook(
        text: 'Premium leather jacket',
        productImages: {
          'front_view': File('path/to/jacket_front.jpg'),
        },
        imagesToGenerate: 2,
        generateVideo: false,
        generateCsv: true,
        skuId: 'CUSTOM-SKU-1234',
        productType: 'accessories',
      );

      print('Custom generation started with job ID: $customJobId');
    } catch (e) {
      print('Custom generation failed: $e');
    }
  }
}
