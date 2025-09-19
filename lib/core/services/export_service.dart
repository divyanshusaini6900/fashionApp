// lib/core/services/export_service.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:gal/gal.dart';
import '../config/api_config.dart';

class exportService {
  static final Dio _dio = Dio();

  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      print('📱 Android SDK: ${androidInfo.version.sdkInt}');

      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ - request media permissions
        print('🔐 Requesting media permissions for Android 13+');
        final photosStatus = await Permission.photos.request();
        print('📸 Photos permission: $photosStatus');
        return photosStatus.isGranted;
      } else if (androidInfo.version.sdkInt >= 30) {
        // Android 11-12 - request storage permission
        print('🔐 Requesting storage permission for Android 11-12');
        final storageStatus = await Permission.storage.request();
        print('💾 Storage permission: $storageStatus');
        return storageStatus.isGranted;
      } else {
        // Android 10 and below - request storage permission
        print('🔐 Requesting storage permission for Android 10-');
        final storageStatus = await Permission.storage.request();
        print('💾 Storage permission: $storageStatus');
        return storageStatus.isGranted;
      }
    }
    return true; // iOS doesn't need special permissions
  }

  static Future<Directory?> getexportDirectory() async {
    if (Platform.isAndroid) {
      try {
        // Try public exports directory first
        final Directory publicexportsDir =
            Directory('/storage/emulated/0/export');
        if (await publicexportsDir.exists()) {
          print('✅ Using public exports directory: ${publicexportsDir.path}');
          return publicexportsDir;
        }

        // Alternative with 's'
        final Directory altexportsDir =
            Directory('/storage/emulated/0/exports');
        if (await altexportsDir.exists()) {
          print('✅ Using alternative exports directory: ${altexportsDir.path}');
          return altexportsDir;
        }

        // Fallback to app-specific directory
        final Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final appexportDir = Directory('${externalDir.path}/export');
          if (!await appexportDir.exists()) {
            await appexportDir.create(recursive: true);
          }
          print('⚠️ Using app-specific export directory: ${appexportDir.path}');
          return appexportDir;
        }
      } catch (e) {
        print('❌ Error accessing export directory: $e');
      }

      // Last resort
      return await getApplicationDocumentsDirectory();
    } else {
      // iOS
      return await getApplicationDocumentsDirectory();
    }
  }

  static Future<String> exportFile({
    required String url,
    required String fileName,
    required CancelToken? cancelToken,
    required Function(double) onProgress,
  }) async {
    // Get export directory
    final Directory? exportsDir = await getexportDirectory();
    if (exportsDir == null) {
      throw Exception('Could not access export directory');
    }

    final filePath = '${exportsDir.path}/$fileName';
    print('💾 exporting to: $filePath');

    // export file
    await _dio.download(
      url,
      filePath,
      cancelToken: cancelToken,
      options: Options(
        headers: {
          'Accept': '*/*',
          'User-Agent': 'RatNawnAI/1.0',
        },
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status! < 500,
      ),
      onReceiveProgress: (received, total) {
        if (total != -1) {
          final progress = received / total;
          onProgress(progress);
        }
      },
    );

    // Verify file
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File was not saved properly');
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      await file.delete();
      throw Exception('exported file is empty');
    }

    print('✅ File exported successfully. Size: $fileSize bytes');

    // Trigger media scan on Android
    if (Platform.isAndroid) {
      try {
        await Process.run('am', [
          'broadcast',
          '-a',
          'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
          '-d',
          'file://$filePath'
        ]);
        print('✅ Media scan triggered');
      } catch (e) {
        print('⚠️ Could not trigger media scan: $e');
      }
    }

    return filePath;
  }

  /// Export image to both export directory and photo gallery
  static Future<Map<String, dynamic>> exportImageWithGallery({
    required String url,
    required String fileName,
    required CancelToken? cancelToken,
    required Function(double) onProgress,
  }) async {
    bool exportSuccess = false;
    bool gallerySuccess = false;
    String exportPath = '';
    String errorMessage = '';

    // Download image bytes first
    final response = await _dio.get(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Accept': '*/*',
          'User-Agent': 'RatNawnAI/1.0',
        },
      ),
      onReceiveProgress: (received, total) {
        if (total != -1) {
          final progress = received / total;
          onProgress(progress);
        }
      },
    );

    // 1. Save to export directory
    try {
      final Directory? exportsDir = await getexportDirectory();
      if (exportsDir != null) {
        final filePath = '${exportsDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(response.data);

        // Verify file
        if (await file.exists() && await file.length() > 0) {
          exportPath = filePath;
          exportSuccess = true;
          print('✅ Image exported to: $filePath');

          // Trigger media scan on Android
          if (Platform.isAndroid) {
            try {
              await Process.run('am', [
                'broadcast',
                '-a',
                'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
                '-d',
                'file://$filePath'
              ]);
              print('✅ Media scan triggered');
            } catch (e) {
              print('⚠️ Could not trigger media scan: $e');
            }
          }
        }
      }
    } catch (e) {
      errorMessage += 'Export directory: ${e.toString()}\n';
    }

    // 2. Save to Photo Gallery using Gal library
    try {
      // Check if Gal has access (automatically handles permissions)
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }

      if (await Gal.hasAccess()) {
        await Gal.putImageBytes(
          response.data,
          name: fileName,
        );
        gallerySuccess = true;
        print('✅ Image saved to gallery');
      } else {
        errorMessage += 'Gallery: Permission denied\n';
      }
    } catch (e) {
      errorMessage += 'Gallery: ${e.toString()}\n';
    }

    return {
      'exportSuccess': exportSuccess,
      'gallerySuccess': gallerySuccess,
      'exportPath': exportPath,
      'errorMessage': errorMessage,
    };
  }

  static Future<String> exportVideo({
    required String url,
    required String fileName,
    required CancelToken? cancelToken,
    required Function(double) onProgress,
  }) async {
    // export to temp first
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = '${tempDir.path}/$fileName';

    await _dio.download(
      url,
      tempFilePath,
      cancelToken: cancelToken,
      options: Options(
        receiveTimeout: ApiConfig.exportReceiveTimeout,
        sendTimeout: ApiConfig.exportSendTimeout,
      ),
      onReceiveProgress: (received, total) {
        if (total != -1) {
          final progress = received / total;
          onProgress(progress);
        }
      },
    );

    // Save to gallery
    await Gal.putVideo(tempFilePath);
    print('✅ Video saved to gallery');

    // Clean up temp file
    await File(tempFilePath).delete();

    return 'Gallery';
  }
}
