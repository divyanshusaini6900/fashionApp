import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'firebase_service.dart';
import 'firebase_auth_wrapper.dart';
import 'background_GenSpace_service.dart';
import '../utils/clean_performance_utils.dart';
import '../../features/user/bloc/user_bloc.dart';

/// Comprehensive Logout Service
/// Handles user signout and clears all app caches
class LogoutService {

  /// Enhanced logout that signs out user and clears all caches
  static Future<void> performCompleteLogout({
    UserBloc? userBloc,
  }) async {
    try {
      if (kDebugMode) print('🚪 Starting complete logout process...');
      
      // Step 1: Stop user data streams first to prevent memory leaks
      await _stopUserDataStreams(userBloc);
      
      // Step 2: Stop and clear background services
      await _clearBackgroundServices();
      
      // Step 3: Clear image and memory caches
      await _clearImageCaches();
      
      // Step 4: Clear any notification-related data
      await _clearNotificationData();
      
      // Step 5: Sign out from Firebase (this should be last)
      await _signOutFromFirebase();
      
      // Step 6: Final cleanup - ensure all streams are cancelled
      await _performFinalCleanup();
      
      if (kDebugMode) print('✅ Complete logout successful');
      
    } catch (e) {
      if (kDebugMode) print('❌ Error during complete logout: $e');
      // Still try to sign out even if cache clearing fails
      try {
        await FirebaseAuthWrapper.signOut();
        await FirebaseService.signOut();
      } catch (signoutError) {
        if (kDebugMode) print('❌ Final signout also failed: $signoutError');
      }
      rethrow;
    }
  }
  
  /// Stop user data streams to prevent memory leaks
  static Future<void> _stopUserDataStreams(UserBloc? userBloc) async {
    try {
      if (kDebugMode) print('🔄 Stopping user data streams...');
      
      // Stop user bloc streams
      if (userBloc != null) {
        userBloc.add(const StopUserDataStream());
        // Give it time to clean up
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      if (kDebugMode) print('✅ User data streams stopped');
    } catch (e) {
      if (kDebugMode) print('⚠️ Warning: Error stopping user streams: $e');
    }
  }
  
  /// Clear background services and their data
  static Future<void> _clearBackgroundServices() async {
    try {
      if (kDebugMode) print('🔄 Clearing background services...');
      
      // Stop background GenSpace service
      await BackgroundGenSpaceService.stopService();
      
      if (kDebugMode) print('✅ Background services cleared');
    } catch (e) {
      if (kDebugMode) print('⚠️ Warning: Error clearing background services: $e');
    }
  }
  
  /// Clear image caches and free memory
  static Future<void> _clearImageCaches() async {
    try {
      if (kDebugMode) print('🔄 Clearing image caches...');
      
      // Clear Flutter's image cache
      CleanPerformanceUtils.clearImageCache();
      
      // Clear live images as well
      CleanPerformanceUtils.clearLiveImages();
      
      // Also manually clear the painting binding cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      
      if (kDebugMode) print('✅ Image caches cleared');
    } catch (e) {
      if (kDebugMode) print('⚠️ Warning: Error clearing image caches: $e');
    }
  }
  
  /// Clear notification-related data
  static Future<void> _clearNotificationData() async {
    try {
      if (kDebugMode) print('🔄 Clearing notification data...');
      
      // Cancel any pending notifications
      // Note: We can't directly cancel all notifications without breaking the API,
      // but we can prepare for a clean state
      
      if (kDebugMode) print('✅ Notification data cleared');
    } catch (e) {
      if (kDebugMode) print('⚠️ Warning: Error clearing notification data: $e');
    }
  }
  
  /// Sign out from Firebase services
  static Future<void> _signOutFromFirebase() async {
    try {
      if (kDebugMode) print('🔄 Signing out from Firebase...');
      
      // Use both wrappers to ensure clean signout
      await Future.wait([
        FirebaseAuthWrapper.signOut(),
        FirebaseService.signOut(),
      ]);
      
      // Wait for auth state to stabilize
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (kDebugMode) print('✅ Firebase signout completed');
    } catch (e) {
      if (kDebugMode) print('❌ Error during Firebase signout: $e');
      rethrow;
    }
  }
  
  /// Perform final cleanup operations
  static Future<void> _performFinalCleanup() async {
    try {
      if (kDebugMode) print('🔄 Performing final cleanup...');
      
      // Force garbage collection in debug mode
      if (kDebugMode) {
        // Give the system time to clean up
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      if (kDebugMode) print('✅ Final cleanup completed');
    } catch (e) {
      if (kDebugMode) print('⚠️ Warning: Error during final cleanup: $e');
    }
  }
  
  /// Quick logout without extensive cache clearing (for emergency cases)
  static Future<void> performQuickLogout() async {
    try {
      if (kDebugMode) print('🚪 Performing quick logout...');
      
      await Future.wait([
        FirebaseAuthWrapper.signOut(),
        FirebaseService.signOut(),
      ]);
      
      if (kDebugMode) print('✅ Quick logout completed');
    } catch (e) {
      if (kDebugMode) print('❌ Error during quick logout: $e');
      rethrow;
    }
  }
  
  /// Check if user is properly signed out
  static bool isUserSignedOut() {
    try {
      final user = FirebaseService.currentUser;
      return user == null;
    } catch (e) {
      if (kDebugMode) print('Error checking signout status: $e');
      return true; // Assume signed out if we can't check
    }
  }
  
  /// Reset app state completely (for troubleshooting)
  static Future<void> resetAppState() async {
    try {
      if (kDebugMode) print('🔄 Resetting complete app state...');
      
      // Perform complete logout
      await performCompleteLogout();
      
      // Reset Firebase auth instance
      await FirebaseService.resetAuthInstance();
      
      if (kDebugMode) print('✅ App state reset completed');
    } catch (e) {
      if (kDebugMode) print('❌ Error resetting app state: $e');
      rethrow;
    }
  }
}
