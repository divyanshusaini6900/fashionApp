import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/fashion_ai_service.dart';
import '../../../core/config/api_config.dart';

// Events
abstract class exportEvent extends Equatable {
  const exportEvent();

  @override
  List<Object> get props => [];
}

class LoadexportableVideos extends exportEvent {
  const LoadexportableVideos();
}

class exportVideo extends exportEvent {
  final exportableVideo video;

  const exportVideo({required this.video});

  @override
  List<Object> get props => [video];
}

class DeleteexportedVideo extends exportEvent {
  final String videoId;

  const DeleteexportedVideo({required this.videoId});

  @override
  List<Object> get props => [videoId];
}

class Cancelexport extends exportEvent {
  final String videoId;

  const Cancelexport({required this.videoId});

  @override
  List<Object> get props => [videoId];
}

class RefreshexportableVideos extends exportEvent {
  const RefreshexportableVideos();
}

class exportExcelFile extends exportEvent {
  final String url;
  final String fileName;

  const exportExcelFile({
    required this.url,
    required this.fileName,
  });

  @override
  List<Object> get props => [url, fileName];
}

// States
abstract class exportState extends Equatable {
  const exportState();

  @override
  List<Object> get props => [];
}

class exportInitial extends exportState {
  const exportInitial();
}

class exportLoading extends exportState {
  const exportLoading();
}

class exportLoaded extends exportState {
  final List<exportableVideo> videos;
  final Map<String, double> exportProgress;

  const exportLoaded({
    required this.videos,
    this.exportProgress = const {},
  });

  @override
  List<Object> get props => [videos, exportProgress];

  exportLoaded copyWith({
    List<exportableVideo>? videos,
    Map<String, double>? exportProgress,
  }) {
    return exportLoaded(
      videos: videos ?? this.videos,
      exportProgress: exportProgress ?? this.exportProgress,
    );
  }
}

class exportError extends exportState {
  final String message;

  const exportError({required this.message});

  @override
  List<Object> get props => [message];
}

class exportSuccess extends exportState {
  final String fileName;
  final String filePath;

  const exportSuccess({
    required this.fileName,
    required this.filePath,
  });

  @override
  List<Object> get props => [fileName, filePath];
}

class ExcelexportInProgress extends exportState {
  final double progress;
  final String fileName;

  const ExcelexportInProgress({
    required this.progress,
    required this.fileName,
  });

  @override
  List<Object> get props => [progress, fileName];
}

class ExcelexportSuccess extends exportState {
  final String fileName;
  final String filePath;

  const ExcelexportSuccess({
    required this.fileName,
    required this.filePath,
  });

  @override
  List<Object> get props => [fileName, filePath];
}

// BLoC
class exportBloc extends Bloc<exportEvent, exportState> {
  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};
  final FashionAIService _fashionAIService = FashionAIService();

  exportBloc() : super(const exportInitial()) {
    on<LoadexportableVideos>(_onLoadexportableVideos);
    on<RefreshexportableVideos>(_onRefreshexportableVideos);
    on<exportVideo>(_onexportVideo);
    on<Cancelexport>(_onCancelexport);
    on<exportExcelFile>(_onexportExcelFile);
    
    // Initialize the FashionAI service
    _fashionAIService.initialize();
  }

  Future<void> _onLoadexportableVideos(
    LoadexportableVideos event,
    Emitter<exportState> emit,
  ) async {
    emit(const exportLoading());
    try {
      final videos = await FirebaseService.getexportableVideos();
      emit(exportLoaded(videos: videos));

    } catch (e) {
      emit(exportError(message: e.toString()));
    }
  }

  Future<void> _onRefreshexportableVideos(
    RefreshexportableVideos event,
    Emitter<exportState> emit,
  ) async {
    try {
      final videos = await FirebaseService.getexportableVideos();
      if (state is exportLoaded) {
        final currentState = state as exportLoaded;
        emit(currentState.copyWith(videos: videos));
      } else {
        emit(exportLoaded(videos: videos));
      }
    } catch (e) {
      emit(exportError(message: e.toString()));
    }
  }

  Future<void> _onexportVideo(
    exportVideo event,
    Emitter<exportState> emit,
  ) async {
    if (state is! exportLoaded) return;
    final currentState = state as exportLoaded;
    final video = event.video;

    try {
      print('🚀 Starting export for: ${video.title}');
      
      // Request storage permission
      await _requestStoragePermission();
      
      // Create file name
      final fileName = '${video.title.replaceAll(RegExp(r'[^\w\s-]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      // Get temporary export path
      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/$fileName';

      // Create cancel token
      final cancelToken = CancelToken();
      _cancelTokens[video.id] = cancelToken;

      print('📥 Starting export from: ${video.videoUrl}');
      
      // export to temporary location first
      await _dio.download(
        video.videoUrl,
        tempFilePath,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: ApiConfig.exportReceiveTimeout,
          sendTimeout: ApiConfig.exportSendTimeout,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            final updatedProgress = Map<String, double>.from(currentState.exportProgress);
            updatedProgress[video.id] = progress;
            print('📊 export progress: ${(progress * 100).toStringAsFixed(1)}%');
            emit(currentState.copyWith(exportProgress: updatedProgress));
          }
        },
      );

      // Save to gallery using Gal
      await Gal.putVideo(tempFilePath);
      print('✅ Video saved to gallery successfully');
      
      // Clean up temporary file
      await File(tempFilePath).delete();
      
      // Remove cancel token and progress tracking
      _cancelTokens.remove(video.id);
      final updatedProgress = Map<String, double>.from(currentState.exportProgress);
      updatedProgress.remove(video.id);
      
      emit(currentState.copyWith(exportProgress: updatedProgress));
      

      
      emit(exportSuccess(fileName: fileName, filePath: 'Gallery'));

    } catch (e) {
      _cancelTokens.remove(video.id);
      final updatedProgress = Map<String, double>.from(currentState.exportProgress);
      updatedProgress.remove(video.id);
      emit(currentState.copyWith(exportProgress: updatedProgress));
      
      if (e is DioException && e.type == DioExceptionType.cancel) {
        print('🚫 export was cancelled');
        return;
      }
      
      print('❌ export failed: $e');
      emit(exportError(message: 'export failed: ${e.toString()}'));
    }
  }

  void _onCancelexport(
    Cancelexport event,
    Emitter<exportState> emit,
  ) {
    final cancelToken = _cancelTokens[event.videoId];
    if (cancelToken != null) {
      cancelToken.cancel();
      _cancelTokens.remove(event.videoId);
      if (state is exportLoaded) {
        final currentState = state as exportLoaded;
        final updatedProgress = Map<String, double>.from(currentState.exportProgress);
        updatedProgress.remove(event.videoId);
        emit(currentState.copyWith(exportProgress: updatedProgress));
      }
    }
  }

  Future<void> _onexportExcelFile(
    exportExcelFile event,
    Emitter<exportState> emit,
  ) async {
    try {
      print('📥 Starting Excel file export: ${event.fileName}');
      
      // Request storage permission
      await _requestStoragePermission();
      
      emit(ExcelexportInProgress(progress: 0.0, fileName: event.fileName));

      // export the Excel file
      final filePath = await _fashionAIService.exportExcelFile(
        url: event.url,
        fileName: event.fileName,
        onProgress: (progress) {
          emit(ExcelexportInProgress(progress: progress, fileName: event.fileName));
        },
      );

      emit(ExcelexportSuccess(fileName: event.fileName, filePath: filePath));



    } catch (e) {
      print('❌ Excel export failed: $e');
      emit(exportError(message: 'Excel export failed: ${e.toString()}'));
      

    }
  }

  Future<void> _requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        print('📱 Storage permission status: $status');
        
        if (status.isDenied || status.isPermanentlyDenied) {
          print('⚠️ Storage permission denied');
          await Permission.photos.request();
        }
      }
      print('✅ Storage access configured');
    } catch (e) {
      print('⚠️ Permission request failed: $e');
    }
  }
}
