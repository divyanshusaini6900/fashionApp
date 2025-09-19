import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/fashion_ai_service.dart';

// Events
abstract class UploadEvent extends Equatable {
  const UploadEvent();

  @override
  List<Object> get props => [];
}

class SelectImages extends UploadEvent {
  const SelectImages();
}

class RemoveImage extends UploadEvent {
  final int index;

  const RemoveImage({required this.index});

  @override
  List<Object> get props => [index];
}

class ClearImages extends UploadEvent {
  const ClearImages();
}

class UploadImages extends UploadEvent {
  const UploadImages();
}

class ResetUpload extends UploadEvent {
  const ResetUpload();
}

class GenerateFashionReport extends UploadEvent {
  final String text;
  final String username;
  final String product;

  const GenerateFashionReport({
    required this.text,
    required this.username,
    required this.product,
  });

  @override
  List<Object> get props => [text, username, product];
}

// States
abstract class UploadState extends Equatable {
  const UploadState();

  @override
  List<Object> get props => [];
}

class UploadInitial extends UploadState {
  const UploadInitial();
}

class ImagesSelected extends UploadState {
  final List<XFile> images;

  const ImagesSelected({required this.images});

  @override
  List<Object> get props => [images];
}

class UploadInProgress extends UploadState {
  final List<XFile> images;
  final double progress;
  final int currentIndex;

  const UploadInProgress({
    required this.images,
    required this.progress,
    required this.currentIndex,
  });

  @override
  List<Object> get props => [images, progress, currentIndex];
}

class UploadSuccess extends UploadState {
  final List<String> imageUrls;
  final int imageCount;

  const UploadSuccess({
    required this.imageUrls,
    required this.imageCount,
  });

  @override
  List<Object> get props => [imageUrls, imageCount];
}

class UploadError extends UploadState {
  final String message;

  const UploadError({required this.message});

  @override
  List<Object> get props => [message];
}

// InsufficientCredits state removed
// Credit validation now handled at feature level (GenSpace/video generation)

class FashionGenerationInProgress extends UploadState {
  final String message;

  const FashionGenerationInProgress({required this.message});

  @override
  List<Object> get props => [message];
}

class FashionGenerationSuccess extends UploadState {
  final FashionGenerationResponse response;

  const FashionGenerationSuccess({required this.response});

  @override
  List<Object> get props => [response];
}

class FashionGenerationError extends UploadState {
  final String message;

  const FashionGenerationError({required this.message});

  @override
  List<Object> get props => [message];
}

// BLoC
class UploadBloc extends Bloc<UploadEvent, UploadState> {
  final ImagePicker _imagePicker = ImagePicker();
  final FashionAIService _fashionAIService = FashionAIService();

  UploadBloc() : super(const UploadInitial()) {
    on<SelectImages>(_onSelectImages);
    on<RemoveImage>(_onRemoveImage);
    on<ClearImages>(_onClearImages);
    on<UploadImages>(_onUploadImages);
    on<ResetUpload>(_onResetUpload);
    on<GenerateFashionReport>(_onGenerateFashionReport);
    // Initialize the FashionAI service
    _fashionAIService.initialize();
  }

  Future<void> _onSelectImages(
    SelectImages event,
    Emitter<UploadState> emit,
  ) async {
    try {
      final List<XFile> selectedImages = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (selectedImages.isNotEmpty) {
        // Limit to 50 images
        final List<XFile> limitedImages = selectedImages.take(50).toList();
        // If current state has images, add to existing list
        List<XFile> allImages = [];
        if (state is ImagesSelected) {
          allImages = List.from((state as ImagesSelected).images);
        }

        allImages.addAll(limitedImages);

        // Limit total images to 50
        if (allImages.length > 50) {
          allImages = allImages.take(50).toList();
        }

        emit(ImagesSelected(images: allImages));
      }
    } catch (e) {
      emit(UploadError(message: 'Error selecting images: ${e.toString()}'));
    }
  }

  void _onRemoveImage(
    RemoveImage event,
    Emitter<UploadState> emit,
  ) {
    if (state is ImagesSelected) {
      final currentImages = (state as ImagesSelected).images;
      if (event.index >= 0 && event.index < currentImages.length) {
        final updatedImages = List<XFile>.from(currentImages);
        updatedImages.removeAt(event.index);
        if (updatedImages.isEmpty) {
          emit(const UploadInitial());
        } else {
          emit(ImagesSelected(images: updatedImages));
        }
      }
    }
  }

  void _onClearImages(
    ClearImages event,
    Emitter<UploadState> emit,
  ) {
    emit(const UploadInitial());
  }

  Future<void> _onUploadImages(
    UploadImages event,
    Emitter<UploadState> emit,
  ) async {
    if (state is! ImagesSelected) return;

    final images = (state as ImagesSelected).images;
    if (images.isEmpty) return;

    try {
      if (kDebugMode)
        print('🚀 Starting upload process for ${images.length} images');

      // Check Firebase Auth first
      if (FirebaseService.currentUser == null) {
        throw 'Please login first to upload images';
      }

      if (kDebugMode)
        print('✅ User authenticated: ${FirebaseService.currentUser!.email}');

      // Note: Image upload no longer requires credit validation
      // Credits are only checked during GenSpace/video generation
      if (kDebugMode)
        print('📸 Starting image upload without credit validation');

      emit(UploadInProgress(
        images: images,
        progress: 0.0,
        currentIndex: 0,
      ));

      // Upload ALL images in parallel - no sequential processing
      if (kDebugMode)
        print('🚀 Starting PARALLEL upload for ${images.length} images');

      emit(UploadInProgress(
        images: images,
        progress: 0.1,
        currentIndex: 0,
      ));

      // Create parallel upload futures for ALL images simultaneously
      final List<Future<String>> uploadFutures =
          images.asMap().entries.map((entry) {
        final index = entry.key;
        final image = entry.value;

        return FirebaseService.uploadImages([image]).then((urls) {
          if (kDebugMode) print('✅ Image ${index + 1} uploaded in parallel');
          return urls.first;
        }).catchError((error) {
          if (kDebugMode) print('❌ Error uploading image ${index + 1}: $error');
          throw 'Error uploading image ${index + 1}: ${error.toString()}';
        });
      }).toList();

      // Start progress polling in parallel
      Timer.periodic(Duration(milliseconds: 200), (timer) {
        if (timer.tick * 0.05 < 0.9) {
          emit(UploadInProgress(
            images: images,
            progress: timer.tick * 0.05,
            currentIndex: (timer.tick * 0.05 * images.length).round(),
          ));
        } else {
          timer.cancel();
        }
      });

      // Wait for ALL uploads to complete in parallel
      final List<String> uploadedUrls = await Future.wait(uploadFutures);

      // Note: Image upload no longer deducts credits directly
      // Credits are only deducted during GenSpace/video generation
      if (kDebugMode)
        print(
            '✅ ${images.length} images uploaded successfully without credit deduction');

      // Final progress update
      emit(UploadInProgress(
        images: images,
        progress: 1.0,
        currentIndex: images.length,
      ));

      if (kDebugMode) print('🎉 Upload process completed successfully!');

      emit(UploadSuccess(
        imageUrls: uploadedUrls,
        imageCount: uploadedUrls.length,
      ));
    } catch (e) {
      if (kDebugMode) print('❌ Upload process failed: $e');

      emit(UploadError(message: e.toString()));
    }
  }

  void _onResetUpload(
    ResetUpload event,
    Emitter<UploadState> emit,
  ) {
    emit(const UploadInitial());
  }

  Future<void> _onGenerateFashionReport(
    GenerateFashionReport event,
    Emitter<UploadState> emit,
  ) async {
    if (state is! ImagesSelected) {
      emit(const FashionGenerationError(message: 'Please select images first'));
      return;
    }

    final images = (state as ImagesSelected).images;
    if (images.isEmpty) {
      emit(const FashionGenerationError(message: 'No images selected'));
      return;
    }

    try {
      emit(const FashionGenerationInProgress(
          message: 'Connecting to Fashion AI API...'));

      // Check API health first
      final isApiHealthy = await _fashionAIService.checkApiHealth();
      if (!isApiHealthy) {
        emit(const FashionGenerationError(
            message:
                'Fashion AI API is not available. Please make sure the server is running.'));
        return;
      }

      emit(const FashionGenerationInProgress(
          message: 'Generating fashion report...'));

      // Map images to the expected format for OpenAPI
      final productImages = <String, File?>{};

      // Always include front view (required)
      productImages['front_view'] = File(images[0].path);

      // Add other views if available
      if (images.length > 1) {
        productImages['back_view'] = File(images[1].path);
      }
      if (images.length > 2) {
        productImages['side_view'] = File(images[2].path);
      }
      if (images.length > 3) {
        productImages['detail_view'] = File(images[3].path);
      }

      if (kDebugMode)
        print('🚀 Sending ${images.length} images to Fashion AI API (OpenAPI)');

      // Call the NEW WEBHOOK-BASED Fashion AI method
      final jobId = await _fashionAIService.generateWithWebhook(
        text: event.text,
        productImages: productImages,
        imagesToGenerate: 1,
        generateVideo: false,
        generateCsv: true,
        username: 'user',
        product: 'Fashion Report',
      );

      if (kDebugMode) print('✅ Webhook-based generation completed');
      if (kDebugMode) print('Job ID: $jobId');

      // For webhook-based generation, we need to create a mock response
      // since the actual results are stored in Firestore
      final mockResponse = FashionGenerationResponse(
        requestId: jobId,
        imageVariations: [],
        excelReportUrl: 'Generated via webhook - check Firestore for results',
      );

      emit(FashionGenerationSuccess(response: mockResponse));
    } catch (e) {
      if (kDebugMode) print('❌ Fashion AI generation failed: $e');

      emit(FashionGenerationError(message: e.toString()));
    }
  }
}
