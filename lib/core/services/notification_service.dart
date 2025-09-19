import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
}
