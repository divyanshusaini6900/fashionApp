import 'package:flutter/foundation.dart';

class ApiConfig {
  // Updated Backend base URL from OpenAPI specification
  static const String baseUrl = 'https://0nzcsn5vl9.execute-api.us-east-1.amazonaws.com/prod';
  
  // API key for authentication (x-api-key header)
  static const String apiKey = '88e80caba75e73c4734f95635f406431f4f7159bff0fd427cf2f1c565e84335a';
  
  // API endpoints from OpenAPI spec
  static const String indexStockEndpoint = '/index/stock';
  static const String indexTypesEndpoint = '/index/types';
  static const String indexSearchEndpoint = '/index/search';
  static const String fashionAIEndpoint = '/ratnawnai/fashionai';
  static const String fashionAIVideoEndpoint = '/ratnawnai/fashionai/video';
  
  // Network Timeouts - Extended for long-running AI operations
  static const Duration connectTimeout = Duration(minutes: 10);
  static const Duration receiveTimeout = Duration(minutes: 10);
  static const Duration sendTimeout = Duration(minutes: 10);
  
  // Quick operation timeouts
  static const Duration healthCheckTimeout = Duration(seconds: 10);
  static const Duration authTimeout = Duration(seconds: 15);
  static const Duration firestoreTimeout = Duration(seconds: 30);
  
  // Polling configuration for AI status checks
  static const Duration initialPollInterval = Duration(seconds: 2);
  static const Duration standardPollInterval = Duration(seconds: 3);
  static const Duration extendedPollInterval = Duration(seconds: 5);
  static const Duration longRunningPollInterval = Duration(seconds: 10);
  static const int fastPollAttempts = 10;
  static const int standardPollAttempts = 30;
  static const int extendedPollAttempts = 60;
  
  // export timeouts
  static const Duration exportConnectTimeout = Duration(seconds: 30);
  static const Duration exportReceiveTimeout = Duration(hours: 1);
  static const Duration exportSendTimeout = Duration(seconds: 60);
  
  // UI Animation timeouts
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 500);
  static const Duration longAnimation = Duration(milliseconds: 800);
  static const Duration extraLongAnimation = Duration(milliseconds: 1200);
  
  // Retry and delay timeouts
  static const Duration retryDelay = Duration(milliseconds: 500);
  static const Duration longRetryDelay = Duration(seconds: 2);
  static const Duration serviceInitDelay = Duration(milliseconds: 100);
  static const Duration errorRetryDelay = Duration(seconds: 5);
  
  // Queue configuration
  static const Duration queueCheckInterval = Duration(milliseconds: 500);
  static const int maxConsecutiveErrors = 10;
  
  // Progress update intervals
  static const Duration progressUpdateInterval = Duration(seconds: 2);
  
  // Debug mode
  static const bool enableDebugLogs = kDebugMode;
  
  // Get dynamic polling interval based on attempt number
  static Duration getDynamicPollInterval(int attemptNumber) {
    if (attemptNumber <= fastPollAttempts) {
      return initialPollInterval;
    } else if (attemptNumber <= standardPollAttempts) {
      return standardPollInterval;
    } else if (attemptNumber <= extendedPollAttempts) {
      return extendedPollInterval;
    } else {
      return longRunningPollInterval;
    }
  }
  
  // Calculate estimated progress based on polling attempts
  static double getEstimatedProgress(int pollingAttempts) {
    if (pollingAttempts < 5) return 0.3;
    if (pollingAttempts < 10) return 0.4;
    if (pollingAttempts < 20) return 0.5;
    if (pollingAttempts < 30) return 0.6;
    if (pollingAttempts < 40) return 0.7;
    if (pollingAttempts < 50) return 0.8;
    if (pollingAttempts < 60) return 0.85;
    if (pollingAttempts < 80) return 0.9;
    return 0.95;
  }
  
  // Get progress message based on polling attempts
  static String getProgressMessage(int pollingAttempts) {
    if (pollingAttempts < 5) return 'Initializing AI processing...';
    if (pollingAttempts < 10) return 'Analyzing images...';
    if (pollingAttempts < 20) return 'Generating product variations...';
    if (pollingAttempts < 30) return 'Creating content...';
    if (pollingAttempts < 40) return 'Optimizing results...';
    if (pollingAttempts < 50) return 'Finalizing generation...';
    if (pollingAttempts < 70) return 'Almost complete, please wait...';
    if (pollingAttempts < 100) return 'Processing is taking longer than usual. Please wait...';
    return 'Still processing... This may take a few more minutes.';
  }
}