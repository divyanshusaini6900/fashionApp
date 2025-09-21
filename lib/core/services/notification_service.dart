import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationPlugin = FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    try {
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestAlertPermission: true,
      );
      
      const InitializationSettings initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final result = await _notificationPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      _isInitialized = result ?? false;
      
      if (kDebugMode) {
        print('📱 Notification service initialized: $_isInitialized');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize notification service: $e');
      }
      _isInitialized = false;
    }
  }
  
  static void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('📱 Notification tapped: ${response.payload}');
    }
    // Handle notification tap - you can add navigation logic here
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    int id = 0,
  }) async {
    try {
      // Skip if not initialized to avoid blocking the main flow
      if (!_isInitialized) {
        if (kDebugMode) {
          print('⚠️ Notification service not initialized, skipping notification');
        }
        return;
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'GenSpace_channel',
        'GenSpace Notifications',
        channelDescription: 'Notifications for GenSpace generation updates',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationPlugin.show(
        id,
        title,
        body,
        platformDetails,
      );
      
      if (kDebugMode) {
        print('📱 Notification shown: $title - $body');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to show notification: $e');
      }
      // Don't throw - notifications are non-critical
    }
  }

  static Future<void> requestPermissions() async {
    try {
      if (_notificationPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>() != null) {
        await _notificationPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      
      if (_notificationPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>() != null) {
        await _notificationPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to request notification permissions: $e');
      }
    }
  }

  /// Cancel a specific notification by ID
  static Future<void> cancelNotification(int id) async {
    try {
      if (!_isInitialized) {
        if (kDebugMode) {
          print('⚠️ Notification service not initialized, skipping cancel');
        }
        return;
      }

      await _notificationPlugin.cancel(id);
      
      if (kDebugMode) {
        print('✅ Cancelled notification with ID: $id');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to cancel notification: $e');
      }
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      if (!_isInitialized) {
        if (kDebugMode) {
          print('⚠️ Notification service not initialized, skipping cancel all');
        }
        return;
      }

      await _notificationPlugin.cancelAll();
      
      if (kDebugMode) {
        print('✅ Cancelled all notifications');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to cancel all notifications: $e');
      }
    }
  }

  /// Clear background service notifications (both GenSpace and Video)
  static Future<void> clearBackgroundServiceNotifications() async {
    try {
      if (!_isInitialized) {
        if (kDebugMode) {
          print('⚠️ Notification service not initialized, attempting to initialize...');
        }
        await initialize(); // Try to initialize if not already done
        if (!_isInitialized) {
          print('❌ Could not initialize notification service for clearing');
          return;
        }
      }

      // Cancel the GenSpace background service notification (ID 999)
      await _notificationPlugin.cancel(999);
      
      // Cancel the Video background service notification (ID 998)  
      await _notificationPlugin.cancel(998);
      
      // Also try to cancel any foreground service notifications that might be stuck
      for (int i = 995; i <= 1005; i++) {
        try {
          await _notificationPlugin.cancel(i);
        } catch (e) {
          // Silent fail for each individual notification
        }
      }
      
      if (kDebugMode) {
        print('✅ Cleared background service notifications (GenSpace: 999, Video: 998, Range: 995-1005)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to clear background service notifications: $e');
      }
    }
  }
}
