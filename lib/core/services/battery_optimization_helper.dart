import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Helper class to manage battery optimization settings for better background service reliability
class BatteryOptimizationHelper {
  static const platform = MethodChannel('com.ratnawnai.battery_optimization');

  /// Check if the app is whitelisted from battery optimization
  static Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final bool isWhitelisted = await platform.invokeMethod('isBatteryOptimizationDisabled');
      return isWhitelisted;
    } catch (e) {
      print('Error checking battery optimization: $e');
      return false;
    }
  }

  /// Request to disable battery optimization for the app
  static Future<bool> requestDisableBatteryOptimization() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final bool result = await platform.invokeMethod('requestDisableBatteryOptimization');
      return result;
    } catch (e) {
      print('Error requesting battery optimization disable: $e');
      return false;
    }
  }

  /// Get device manufacturer for specific instructions
  static Future<String> getDeviceManufacturer() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.manufacturer.toLowerCase();
      }
    } catch (e) {
      print('Error getting device manufacturer: $e');
    }
    return 'unknown';
  }

  /// Show battery optimization guidance dialog
  static Future<void> showBatteryOptimizationGuide(BuildContext context) async {
    final manufacturer = await getDeviceManufacturer();
    final isOptimized = await isBatteryOptimizationDisabled();
    
    if (isOptimized) {
      // Already optimized, show success message
      _showSuccessDialog(context);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.battery_alert, color: Colors.orange),
            SizedBox(width: 8),
            Text('Background Service Setup'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To ensure your GenSpaces process reliably in the background, please configure your device settings:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: 16),
              _buildManufacturerSpecificInstructions(context, manufacturer),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Why is this needed?',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Android aggressively manages battery by stopping background apps. These settings ensure your GenSpaces continue processing even when the app is not visible.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await requestDisableBatteryOptimization();
              _showManualInstructions(context, manufacturer);
            },
            child: Text('Configure Now'),
          ),
        ],
      ),
    );
  }

  /// Build manufacturer-specific instructions
  static Widget _buildManufacturerSpecificInstructions(BuildContext context, String manufacturer) {
    String instructions = '';
    String brand = '';

    switch (manufacturer) {
      case 'samsung':
        brand = 'Samsung';
        instructions = '''
1. Open Settings → Device Care → Battery
2. Tap "More battery settings"
3. Find "RatNawnAI" in the app list
4. Set to "Unrestricted"
5. Also disable "Adaptive Battery" or add app to exceptions
        ''';
        break;

      case 'xiaomi':
      case 'redmi':
        brand = 'Xiaomi/Redmi';
        instructions = '''
1. Open Security app → Battery → Power
2. Find "RatNawnAI" and set to "No restrictions"
3. Settings → Apps → Manage apps → RatNawnAI
4. Enable "Autostart" and "Background activity"
5. Disable MIUI Optimization in Developer options
        ''';
        break;

      case 'oppo':
        brand = 'OPPO';
        instructions = '''
1. Settings → Battery → Power Saving Mode (turn off)
2. Settings → Apps → App Management → RatNawnAI
3. Enable "Allow background activity"
4. Battery Optimization → RatNawnAI → Don't optimize
5. Startup Manager → Enable RatNawnAI
        ''';
        break;

      case 'vivo':
        brand = 'Vivo';
        instructions = '''
1. Settings → Battery → Background App Refresh
2. Find RatNawnAI and enable
3. Settings → More Settings → Applications
4. RatNawnAI → Permissions → Enable "Auto-start"
5. Battery optimization → RatNawnAI → Don't optimize
        ''';
        break;

      case 'huawei':
      case 'honor':
        brand = 'Huawei/Honor';
        instructions = '''
1. Phone Manager → Protected apps → Enable RatNawnAI
2. Settings → Apps → RatNawnAI → Battery
3. Set to "Allow background activity"
4. Battery → More battery settings → Sleep
5. Add RatNawnAI to exceptions
        ''';
        break;

      case 'oneplus':
        brand = 'OnePlus';
        instructions = '''
1. Settings → Battery → Battery optimization
2. Find RatNawnAI → Don't optimize
3. Settings → Apps → RatNawnAI → Battery
4. Enable "Background activity"
5. Advanced → Recent app management → Normal clear
        ''';
        break;

      default:
        brand = 'Generic Android';
        instructions = '''
1. Settings → Apps → RatNawnAI → Battery
2. Set to "Unrestricted" or "No optimization"
3. Settings → Battery → Battery optimization
4. Find RatNawnAI and select "Don't optimize"
5. Ensure "Background app refresh" is enabled
        ''';
    }

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$brand Device Settings:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: 8),
          Text(
            instructions,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// Show success dialog
  static void _showSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('All Set!'),
          ],
        ),
        content: Text(
          'Your device is already configured for reliable background processing. Your GenSpaces will continue processing even when the app is not visible.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Great!'),
          ),
        ],
      ),
    );
  }

  /// Show manual instructions for further configuration
  static void _showManualInstructions(BuildContext context, String manufacturer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Additional Configuration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'For best results, please also configure these device-specific settings:',
              ),
              SizedBox(height: 16),
              _buildManufacturerSpecificInstructions(context, manufacturer),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '⚠️ These steps may vary slightly based on your device\'s Android version. Look for similar options if the exact names don\'t match.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it!'),
          ),
        ],
      ),
    );
  }

  /// Check and guide user through battery optimization setup
  static Future<void> ensureBatteryOptimizationSetup(BuildContext context) async {
    try {
      final isOptimized = await isBatteryOptimizationDisabled();
      
      if (!isOptimized) {
        // Show guidance and request permission
        await showBatteryOptimizationGuide(context);
      }
    } catch (e) {
      print('Error in battery optimization setup: $e');
    }
  }
}
