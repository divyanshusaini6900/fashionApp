import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart'
    show Permission, PermissionActions, PermissionStatusGetters;
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/services/background_video_service.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../upload/models/processing_job_model.dart';
import '../../../upload/presentation/widgets/video_player_screen.dart';

class GenSpaceDetailsDialog extends StatelessWidget {
  final ProcessingJob job;

  const GenSpaceDetailsDialog({
    super.key,
    required this.job,
  });

  /// Extract input images from uploadedImageUrls array - fetch directly from Firebase
  Future<List<String>> _extractInputImages(ProcessingJob job) async {
    final List<String> inputImages = [];
    try {
      // Since uploadedImageUrls is not in the ProcessingJob model,
      // we need to fetch it directly from Firebase
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      // Get the document from Firebase using the job ID
      final docSnapshot =
          await firestore.collection('GenSpace_jobs').doc(job.id).get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        print('🔍 Firebase document data fetched for job: ${job.id}');

        // Get uploadedImageUrls from the Firebase document
        final uploadedUrls = data?['uploadedImageUrls'];

        if (uploadedUrls != null) {
          print(
              '✅ Found uploadedImageUrls in Firebase: ${uploadedUrls.runtimeType}');

          if (uploadedUrls is List) {
            for (var url in uploadedUrls) {
              if (url != null && url.toString().isNotEmpty) {
                inputImages.add(url.toString());
                print(
                    '  ✅ Added input image: ${url.toString().substring(0, min(50, url.toString().length))}...');
              }
            }
          }
        } else {
          print('❌ uploadedImageUrls not found in Firebase document');
        }
      } else {
        print('❌ Firebase document not found for job: ${job.id}');
      }

      print('📊 Extracted ${inputImages.length} input images from Firebase');
    } catch (e) {
      print('⚠️ Error extracting input images from Firebase: $e');
    }

    return inputImages;
  }

  Map<String, dynamic> _extractProductInfo(Map<String, dynamic> result) {
    // Navigate to the product_data based on your Firebase structure
    final metadata = result['metadata'] ?? {};
    final analysis = metadata['analysis'] ?? {};
    final productData = analysis['product_data'] ?? {};

    // Debug print to see what we're getting
    print('🔍 Metadata: $metadata');
    print('📊 Analysis: $analysis');
    print('📋 Product Data: $productData');

    // Extract the fields with exact names from your Firebase structure
    return {
      'description': metadata['Description'] ?? '', // Note: capital 'D'
      'key_features': metadata['keyFeatures'] ?? [],
      'search_keywords': metadata['searchKeywords'] ?? [],
      'gender': productData['Gender'] ?? '',
      'occasion': productData['Occasion'] ?? '',
      'sku_id': productData['skuId'] ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final result = job.result ?? {};

    // Check if video URLs exist - handle both String and Array formats for backward compatibility
    final videoData = result['output_video_url'];
    List<String> videoUrlsList = [];

    if (videoData is String && videoData.isNotEmpty) {
      // Handle legacy single video URL format
      videoUrlsList = [videoData];
    } else if (videoData is List<dynamic>) {
      // Handle new array format
      videoUrlsList = videoData
          .map((e) => e.toString())
          .where((url) => url.isNotEmpty)
          .toList();
    }

    final hasVideo = videoUrlsList.isNotEmpty;

    // Check if Excel was generated
    final bool excelGenerated = result['excel_export_url'] != null;

    // Get generated/output images
    final outputImages = _getAllImages(result);

    // Extract product information
    final productInfo = _extractProductInfo(result);

    // Debug print to see the structure
    print('🔍 Result structure: ${result.keys.toList()}');
    print('📊 Product info extracted: $productInfo');
    print('📊 Excel generated: $excelGenerated');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.inventory_2_rounded,
                      color: AppColors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product Details',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                        Text(
                          TimeFormatUtils.formatDetailedTimeAgo(job.createdAt),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: AppColors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.white,
                      ),
                      splashRadius: 20,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Input Images Section - Load asynchronously from Firebase
                    FutureBuilder<List<String>>(
                      future: _extractInputImages(job),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(
                                    AppColors.primaryBlue),
                              ),
                            ),
                          );
                        }

                        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                          final inputImages = snapshot.data!;
                          print(
                              '🎨 Building UI with ${inputImages.length} input images');
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle(
                                  'Input Images', Icons.image_rounded),
                              const SizedBox(height: 16),
                              _buildInputImageGallery(context, inputImages),
                              const SizedBox(height: 24),
                            ],
                          );
                        }

                        // If no input images found, don't show the section
                        return const SizedBox.shrink();
                      },
                    ),

                    // Generated Images Gallery
                    if (outputImages.isNotEmpty) ...[
                      _buildSectionTitle(
                          'Product Images', Icons.auto_awesome_rounded),
                      const SizedBox(height: 16),
                      _buildImageGallery(context, outputImages),
                      const SizedBox(height: 24),
                    ],

                    // Video Section
                    _buildVideoSectionHeader(context, hasVideo, videoUrlsList),
                    const SizedBox(height: 16),
                    _buildVideoSection(context, hasVideo, videoUrlsList),
                    const SizedBox(height: 24),

                    // Product Details - Modified to check for Excel generation
                    () {
                      // If Excel was not generated, show appropriate message
                      if (!excelGenerated) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle(
                                'Product Details', Icons.info_rounded),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.lightGrey.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 48,
                                      color: AppColors.grey,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Product details not available',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Excel generation was not requested for this GenSpace.\nProduct features and keywords are only available when Excel is generated.',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: AppColors.grey.withOpacity(0.8),
                                        height: 1.5,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      // If Excel was generated, show the product details
                      final description = productInfo['description'];
                      final keyFeatures = productInfo['key_features'];
                      final searchKeywords = productInfo['search_keywords'];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (description != null ||
                              keyFeatures != null ||
                              searchKeywords != null) ...[
                            // Description - Show even without Excel if available
                            if (description != null &&
                                description.toString().isNotEmpty) ...[
                              _buildSectionTitle(
                                  'Description', Icons.description_rounded),
                              const SizedBox(height: 12),
                              _buildInfoCard(description.toString()),
                              const SizedBox(height: 24),
                            ],

                            // Key Features - Only show if Excel was generated
                            if (keyFeatures != null &&
                                keyFeatures.toString().isNotEmpty) ...[
                              _buildSectionTitle(
                                  'Key Features', Icons.star_rounded),
                              const SizedBox(height: 12),
                              _buildKeyFeatures(keyFeatures),
                              const SizedBox(height: 24),
                            ],

                            // Search Keywords - Only show if Excel was generated
                            if (searchKeywords != null &&
                                searchKeywords.toString().isNotEmpty) ...[
                              _buildSectionTitle(
                                  'Search Keywords', Icons.tag_rounded),
                              const SizedBox(height: 12),
                              _buildKeywords(searchKeywords),
                            ],
                          ] else ...[
                            // If Excel was generated but no product details found
                            _buildSectionTitle(
                                'Product Details', Icons.info_rounded),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.lightGrey.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 48,
                                      color: AppColors.grey,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Product details processing',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Product description, features, and keywords are being generated',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: AppColors.grey.withOpacity(0.8),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    }(),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.lightGrey.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  if (result['excel_export_url'] != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final url = Uri.parse(result['excel_export_url']);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.download_rounded),
                        label: Text(
                          'export Excel',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (result['excel_export_url'] != null)
                    const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Close',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.primaryBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build gallery for input images with the same style as generated images
  Widget _buildInputImageGallery(BuildContext context, List<String> images) {
    print('🖼️ Building input gallery with ${images.length} images');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.lightGrey,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
            childAspectRatio: 1,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            print('Building input image tile $index: ${images[index]}');

            return GestureDetector(
              onTap: () {
                // Log input image details to terminal when clicked
                print('🖼️ INPUT IMAGE CLICKED:');
                print('   📍 Index: $index');
                print('   🔗 URL: ${images[index]}');
                print('   📊 Total Input Images: ${images.length}');
                print('   ─────────────────────────────────────');
                
                _showFullScreenImage(context, images[index], index, images);
              },
              child: Container(
                color: AppColors.lightGrey.withOpacity(0.1),
                child: Stack(
                  children: [
                    // Main image
                    CachedNetworkImage(
                      imageUrl: images[index],
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (context, url) => Container(
                        color: AppColors.lightGrey.withOpacity(0.3),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.primaryBlue),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.lightGrey.withOpacity(0.3),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_rounded,
                                color: AppColors.grey,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Image Error',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: AppColors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // export button positioned at top-right
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          onPressed: () =>
                              _exportImageStatic(context, images[index], index),
                          icon: const Icon(
                            Icons.download,
                            color: Colors.white,
                            size: 20,
                          ),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

List<String> _getAllImages(Map<String, dynamic> result) {
  // Using Set to automatically eliminate duplicates
  final uniqueImages = <String>{};

  print('🔍 Starting enhanced image collection...');

  // METHOD 1: Check metadata.generatedImages[] first (highest priority)
  final metadata = result['metadata'];
  bool method1Success = false;
  
  if (metadata != null && metadata is Map) {
    final generatedImages = metadata['generatedImages'];
    
    if (generatedImages != null && generatedImages is List && generatedImages.isNotEmpty) {
      print('🎯 METHOD 1: Processing metadata.generatedImages (${generatedImages.length} groups)');
      
      for (int i = 0; i < generatedImages.length; i++) {
        final group = generatedImages[i];
        
        if (group is Map) {
          // Extract imageId and imageSrc from the group
          final imageId = group['imageId']?.toString().trim() ?? '';
          final imageSrc = group['imageSrc']?.toString().trim() ?? '';
          
          print('📦 Group[$i] - imageId: $imageId');
          
          // Add main imageSrc if available
          if (imageSrc.isNotEmpty) {
            uniqueImages.add(imageSrc);
            method1Success = true;
            print('✅ Added main imageSrc from group[$i]: ${imageSrc.substring(0, min(50, imageSrc.length))}...');
          }
          
          // Process generatedRefImages array within this group
          final generatedRefImages = group['generatedRefImages'];
          if (generatedRefImages is List) {
            print('🔄 Processing ${generatedRefImages.length} generatedRefImages in group[$i]');
            
            for (int j = 0; j < generatedRefImages.length; j++) {
              final refImg = generatedRefImages[j];
              
              if (refImg is Map) {
                // Extract imageSrc from each reference image
                final refImageSrc = refImg['imageSrc']?.toString().trim() ?? '';
                final savedImageSrc = refImg['savedImageSrc']?.toString().trim() ?? '';
                
                // Prioritize savedImageSrc over imageSrc
                if (savedImageSrc.isNotEmpty) {
                  uniqueImages.add(savedImageSrc);
                  method1Success = true;
                  print('💾 Added savedImageSrc from group[$i][$j]: ${savedImageSrc.substring(0, min(50, savedImageSrc.length))}...');
                } else if (refImageSrc.isNotEmpty) {
                  uniqueImages.add(refImageSrc);
                  method1Success = true;
                  print('🖼️ Added imageSrc from group[$i][$j]: ${refImageSrc.substring(0, min(50, refImageSrc.length))}...');
                }
              }
            }
          }
        }
      }
      
      print('✅ METHOD 1 completed: Found ${uniqueImages.length} unique images');
    } else {
      print('⚠️ METHOD 1: metadata.generatedImages is null, empty, or not a List');
    }
  } else {
    print('⚠️ METHOD 1: metadata is null or not a Map');
  }

  // METHOD 2: Only try result.generatedImages[] if METHOD 1 failed to find any images
  if (!method1Success) {
    print('🔄 METHOD 2: METHOD 1 failed, trying result.generatedImages[]');
    
    final resultGeneratedImages = result['generatedImages'];
    if (resultGeneratedImages != null && resultGeneratedImages is List && resultGeneratedImages.isNotEmpty) {
      print('🎯 METHOD 2: Processing result.generatedImages (${resultGeneratedImages.length} groups)');
      
      for (int i = 0; i < resultGeneratedImages.length; i++) {
        final group = resultGeneratedImages[i];
        
        if (group is Map) {
          // Extract imageId and imageSrc from the group
          final imageId = group['imageId']?.toString().trim() ?? '';
          final imageSrc = group['imageSrc']?.toString().trim() ?? '';
          
          print('📦 Result Group[$i] - imageId: $imageId');
          
          // Add main imageSrc if available
          if (imageSrc.isNotEmpty) {
            uniqueImages.add(imageSrc);
            print('✅ Added main imageSrc from result group[$i]: ${imageSrc.substring(0, min(50, imageSrc.length))}...');
          }
          
          // Process generatedRefImages array within this group
          final generatedRefImages = group['generatedRefImages'];
          if (generatedRefImages is List) {
            print('🔄 Processing ${generatedRefImages.length} generatedRefImages in result group[$i]');
            
            for (int j = 0; j < generatedRefImages.length; j++) {
              final refImg = generatedRefImages[j];
              
              if (refImg is Map) {
                // Extract imageSrc from each reference image
                final refImageSrc = refImg['imageSrc']?.toString().trim() ?? '';
                final savedImageSrc = refImg['savedImageSrc']?.toString().trim() ?? '';
                
                // Prioritize savedImageSrc over imageSrc
                if (savedImageSrc.isNotEmpty) {
                  uniqueImages.add(savedImageSrc);
                  print('💾 Added savedImageSrc from result group[$i][$j]: ${savedImageSrc.substring(0, min(50, savedImageSrc.length))}...');
                } else if (refImageSrc.isNotEmpty) {
                  uniqueImages.add(refImageSrc);
                  print('🖼️ Added imageSrc from result group[$i][$j]: ${refImageSrc.substring(0, min(50, refImageSrc.length))}...');
                }
              }
            }
          }
        }
      }
      
      print('✅ METHOD 2 completed: Found ${uniqueImages.length} unique images');
    } else {
      print('⚠️ METHOD 2: result.generatedImages is null, empty, or not a List');
    }
  } else {
    print('✅ METHOD 1 was successful, skipping METHOD 2');
  }

  // METHOD 3: Always check upscaled images (highest quality) regardless of METHOD 1/2 results
  print('🔄 METHOD 3: Processing upscaled images...');
  final upscaledImageUrls = result['upscaledImages'];
  int upscaledCount = 0;
  
  if (upscaledImageUrls != null && upscaledImageUrls is List) {
    print('🔍 Processing upscaledImages array objects...');
    
    for (int i = 0; i < upscaledImageUrls.length; i++) {
      final item = upscaledImageUrls[i];
      if (item is Map) {
        final imageSrc = item['imageSrc']?.toString().trim() ?? '';
        if (imageSrc.isNotEmpty) {
          uniqueImages.add(imageSrc);
          upscaledCount++;
          print('✨ Processing upscaled imageSrc from [$i]: ${imageSrc.substring(0, min(50, imageSrc.length))}...');
        }
        
        // Also check for imageUrl field as fallback
        final imageUrl = item['imageUrl']?.toString().trim() ?? '';
        if (imageUrl.isNotEmpty) {
          uniqueImages.add(imageUrl);
          upscaledCount++;
          print('✨ Processing upscaled imageUrl from [$i]: ${imageUrl.substring(0, min(50, imageUrl.length))}...');
        }
      }
    }
    
    if (upscaledCount > 0) {
      print('📊 Successfully found ${upscaledCount} upscaled images');
    } else {
      print('❌ No upscaled images found');
    }
  }

  // METHOD 4: Check image_variations field (fallback for final images)
  print('🔄 METHOD 4: Processing image variations...');
  final imageVariations = result['image_variations'];
  if (imageVariations != null && imageVariations is List) {
    for (final variation in imageVariations) {
      if (variation is String && variation.toString().trim().isNotEmpty) {
        uniqueImages.add(variation.toString().trim());
        print('🎨 Processing image from image_variations');
      }
    }
    print('📊 Found ${imageVariations.length} image variations');
  }

  // METHOD 5: Navigate to metadata.geminiGeneratedImages[] (new Gemini AI generated images)
  print('🔄 METHOD 5: Processing metadata Gemini images...');
  if (metadata != null && metadata is Map) {
    final geminiGeneratedImages = metadata['geminiGeneratedImages'];
    if (geminiGeneratedImages != null && geminiGeneratedImages is List) {
      print('🤖 Found ${geminiGeneratedImages.length} Gemini image groups in metadata');

      for (int i = 0; i < geminiGeneratedImages.length; i++) {
        final gi = geminiGeneratedImages[i];

        if (gi is Map) {
          // Process imageSrc from Gemini results
          final imageSrc = gi['imageSrc']?.toString().trim() ?? '';
          if (imageSrc.isNotEmpty) {
            uniqueImages.add(imageSrc);
            print('🤖 Processing Gemini imageSrc from [$i]: ${imageSrc.substring(0, min(50, imageSrc.length))}...');
          }
        }
      }
    }
  }

  // METHOD 6: Check root-level geminiGeneratedImages
  print('🔄 METHOD 6: Processing root-level Gemini images...');
  final geminiGeneratedImages2 = result['geminiGeneratedImages'];
  if (geminiGeneratedImages2 != null && geminiGeneratedImages2 is List) {
    for (int i = 0; i < geminiGeneratedImages2.length; i++) {
      final gi = geminiGeneratedImages2[i];
      if (gi is Map) {
        final imageSrc = gi['imageSrc']?.toString().trim() ?? '';
        if (imageSrc.isNotEmpty) {
          uniqueImages.add(imageSrc);
          print('🤖 Processing root Gemini imageSrc from [$i]: ${imageSrc.substring(0, min(50, imageSrc.length))}...');
        }
      }
    }
  }

  // Convert Set to List for return
  final imagesList = uniqueImages.toList();

  print('📊 FINAL RESULT: Returning ${imagesList.length} unique images total');
  print('📋 All images found:');
  for (int i = 0; i < imagesList.length; i++) {
    print('  ${i + 1}. ${imagesList[i].substring(0, min(60, imagesList[i].length))}...');
  }

  return imagesList;
}

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.darkGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildImageGallery(BuildContext context, List<String> images) {
    print('🖼️ Building gallery with ${images.length} images');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.lightGrey,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
            childAspectRatio: 1,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            print('Building image tile $index: ${images[index]}');

            return GestureDetector(
              onTap: () {
                // Log generated image details to terminal when clicked
                print('🎨 GENERATED IMAGE CLICKED:');
                print('   📍 Index: $index');
                print('   🔗 URL: ${images[index]}');
                print('   📊 Total Generated Images: ${images.length}');
                print('   ─────────────────────────────────────');
                
                _showFullScreenImage(context, images[index], index, images);
              },
              child: Container(
                color: AppColors.lightGrey.withOpacity(0.1),
                child: Stack(
                  children: [
                    // Main image
                    CachedNetworkImage(
                      imageUrl: images[index],
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (context, url) => Container(
                        color: AppColors.lightGrey.withOpacity(0.3),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.primaryBlue),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.lightGrey.withOpacity(0.3),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_rounded,
                                color: AppColors.grey,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Image Error',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: AppColors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // export button positioned at top-right
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          onPressed: () =>
                              _exportImageStatic(context, images[index], index),
                          icon: const Icon(
                            Icons.download,
                            color: Colors.white,
                            size: 20,
                          ),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoSectionHeader(
      BuildContext context, bool hasVideo, List<String> videoUrls) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryBlue.withOpacity(0.1),
              AppColors.primaryBlue.withOpacity(0.1),
            ],
          ),
          border: Border.all(
            color: AppColors.primaryBlue.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Section title with icon
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.videocam_rounded,
                      size: 20,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // Add Expanded to prevent overflow
                    child: Text(
                      'Generate Video',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkGrey,
                      ),
                      overflow: TextOverflow.ellipsis, // Handle text overflow
                    ),
                  ),
                ],
              ),
            ),

            // Generate video button with credit cost (always show)
            const SizedBox(width: 16),

            ElevatedButton(
              onPressed: () => _generateVideo(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.all(10),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size(48, 48), // Ensures good touch target
              ),
              child: Icon(
                Icons.smart_display_outlined,
                size: 25,
                color: AppColors.primaryBlue,
              ),
            ),
          ],
        ));
  }

  void _generateVideo(BuildContext context) {
    // Show image selection dialog
    _showImageSelectionDialog(context);
  }

  void _showImageSelectionDialog(BuildContext context) {
    // Get generated images for selection
    final result = job.result ?? {};
    final outputImages = _getAllImages(result);

    if (outputImages.isEmpty) {
      // Show error if no images available
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No generated images available for video creation',
                  style: GoogleFonts.poppins(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return VideoImageSelectionDialog(
          images: outputImages,
          onImagesSelected: (selectedImageUrls) {
            // Close the dialog
            Navigator.of(dialogContext).pop();

            // Start multiple video generations in parallel
            _startMultipleVideoGeneration(context, selectedImageUrls);
          },
          onCancel: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

// Helper method to find imageId for a given image URL
  String? _findImageIdForUrl(String imageUrl) {
    try {
      final result = job.result ?? {};

      final metadata = result['metadata'];
      if (metadata != null && metadata is Map) {
        final generatedImages = metadata['generatedImages'];

        String? imageIdOutside; // 👈 यह बाहर declare किया गया है

        if (generatedImages != null && generatedImages is List) {
          for (final gi in generatedImages) {
            if (gi is Map) {
              final imageId = gi['imageId']?.toString().trim();

              if (imageId != null && imageId.isNotEmpty) {
                imageIdOutside = imageId; // 👈 loop के अंदर value save कर ली
              }

              final imageSrc = gi['imageSrc']?.toString().trim() ?? '';
              if (imageSrc == imageUrl &&
                  imageId != null &&
                  imageId.isNotEmpty) {
                return imageId;
              }
            }
          }
        }

        if (imageIdOutside != null) {
          print("✅ Outside access: $imageIdOutside");
          return imageIdOutside;
        }
      }
    } catch (e) {
      print("⚠️ Error: $e");
    }

    return null;
  }

  void _startMultipleVideoGeneration(
      BuildContext context, List<String> selectedImageUrls) async {
    try {
      // 1. Get video credit cost from Firebase
      final creditUsageDoc = await FirebaseFirestore.instance
          .collection('credits')
          .doc('creditUsage')
          .get();

      double videoCreditCost = 1.0; // Default
      if (creditUsageDoc.exists) {
        final data = creditUsageDoc.data() as Map<String, dynamic>;
        videoCreditCost = (data['video'] ?? 1.0).toDouble();
      }

      // 2. Calculate total cost
      final totalCreditCost = selectedImageUrls.length * videoCreditCost;

      if (kDebugMode) {
        print(
            '💰 Video generation cost: ${selectedImageUrls.length} videos × $videoCreditCost credits = $totalCreditCost total credits');
      }

      // 3. Check if user has enough credits
      try {
        final hasEnoughCredits =
            await FirebaseService.hasEnoughCredits(totalCreditCost);
        if (!hasEnoughCredits) {
          final currentBalance = await FirebaseService.getUsercreditBalance();

          // Show insufficient credits dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Insufficient credits! You have ${currentBalance.toStringAsFixed(1)} credits but need ${totalCreditCost.toStringAsFixed(1)} credits.',
                      style: GoogleFonts.poppins(
                        color: AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Unable to check credit balance. Please try again.',
                    style: GoogleFonts.poppins(
                      color: AppColors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // 4. Start background video service
      try {
        await BackgroundVideoService.initializeBackgroundService();
        await BackgroundVideoService.startBackgroundVideoProcessing(job.id);

        if (kDebugMode) {
          print(
              '🚀 Background video service started for multiple video generation (${selectedImageUrls.length} videos) for job: ${job.id}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Failed to start background video service: $e');
        }
      }

      // 5. Show initial progress snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Starting ${selectedImageUrls.length} video generations (${totalCreditCost.toStringAsFixed(1)} credits)...',
                  style: GoogleFonts.poppins(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryBlue,
          duration: const Duration(seconds: 3),
        ),
      );

      // 6. Start video generation for each selected image in parallel
      final List<Future<void>> videoGenerationFutures = [];

      for (int i = 0; i < selectedImageUrls.length; i++) {
        final imageUrl = selectedImageUrls[i];
        final videoFuture = _generateSingleVideo(
            context, imageUrl, i + 1, selectedImageUrls.length);
        videoGenerationFutures.add(videoFuture);
      }

      // 7. Wait for all video generations to complete (or fail)
      await Future.wait(videoGenerationFutures, eagerError: false);

      if (kDebugMode) {
        print(
            '✅ All ${selectedImageUrls.length} video generations have been initiated');
      }

      // 8. Deduct credits after successful video generation requests
      try {
        await FirebaseService.deductCredits(totalCreditCost,
            reason: 'video_generation');
        if (kDebugMode) {
          print(
              '💳 Successfully deducted $totalCreditCost credits for ${selectedImageUrls.length} video generations');
        }

        // Show success message with credit deduction info
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${selectedImageUrls.length} video generations started! ${totalCreditCost.toStringAsFixed(1)} credits deducted.',
                    style: GoogleFonts.poppins(
                      color: AppColors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          print('❌ Failed to deduct credits: $e');
        }
        // Note: Video generation has already started, so we just warn about credit deduction failure
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning_amber, color: AppColors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Video generation started but credit deduction failed. Please contact support.',
                    style: GoogleFonts.poppins(
                      color: AppColors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // 9. Start listening to video generation progress
      _listenToVideoProgress(context);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error starting multiple video generation: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to start video generation: ${e.toString()}',
                  style: GoogleFonts.poppins(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _generateSingleVideo(BuildContext context,
      String selectedImageUrl, int videoNumber, int totalVideos) async {
    try {
      // Extract imageId from refImg for the selected image URL
      final imageId = _findImageIdForUrl(selectedImageUrl);

      if (kDebugMode) {
        print(
            '🎬 Starting video generation $videoNumber/$totalVideos for image: ${selectedImageUrl.substring(0, 50)}...');
      }

      // Start background video generation
      final videoService = BackgroundVideoService();

      // Call the video generation service with the extracted imageId
      await videoService.startVideoGeneration(
        jobId: job.id,
        selectedImageUrl: selectedImageUrl,
        imageId: imageId,
      );

      if (kDebugMode) {
        print(
            '✅ Video generation $videoNumber/$totalVideos initiated successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error generating video $videoNumber/$totalVideos: $e');
      }

      // Show error for this specific video
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber, color: AppColors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Video $videoNumber/$totalVideos failed to start: ${e.toString()}',
                  style: GoogleFonts.poppins(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _listenToVideoProgress(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    StreamSubscription? subscription;

    subscription = firestore
        .collection('GenSpace_jobs')
        .doc(job.id)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final videoStatus = data['videoGenerationStatus'] as String?;
      final videoMessage = data['videoMessage'] as String?;
      // Get video URLs - handle both String and Array formats for backward compatibility
      final result = data['result'] as Map<String, dynamic>?;
      final videoData = result?['output_video_url'];
      List<String> videoUrlsList = [];

      if (videoData is String && videoData.isNotEmpty) {
        // Handle legacy single video URL format
        videoUrlsList = [videoData];
      } else if (videoData is List<dynamic>) {
        // Handle new array format
        videoUrlsList = videoData
            .map((e) => e.toString())
            .where((url) => url.isNotEmpty)
            .toList();
      }

      final videoUrl = videoUrlsList.isNotEmpty
          ? videoUrlsList.last
          : null; // Get latest video

      if (videoStatus == 'completed' && videoUrl != null) {
        // Video generation completed
        subscription?.cancel();

        // Stop background video service immediately
        try {
          await BackgroundVideoService.stopBackgroundVideoService();
          if (kDebugMode) {
            print(
                '🛑 Background video service stopped from UI after completion');
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Failed to stop background video service from UI: $e');
          }
        }

        // Update the local job object if needed
        if (job.result != null) {
          job.result!['output_video_url'] = videoUrlsList; // Store as array
        }

        // Show success notification
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.video_library, color: AppColors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Video generation completed! Refresh to see your video.',
                    style: GoogleFonts.poppins(
                      color: AppColors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'View',
              textColor: AppColors.white,
              onPressed: () async {
                // Open video URL
                final url = Uri.parse(videoUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        );
      } else if (videoStatus == 'failed') {
        // Video generation failed
        subscription?.cancel();

        // Stop background video service immediately
        try {
          await BackgroundVideoService.stopBackgroundVideoService();
          if (kDebugMode) {
            print('🛑 Background video service stopped from UI after failure');
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Failed to stop background video service from UI: $e');
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    videoMessage ?? 'Video generation failed',
                    style: GoogleFonts.poppins(
                      color: AppColors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }

      // You can also show progress updates if needed
      if (videoStatus == 'processing' && videoMessage != null) {
        if (kDebugMode) print('📊 Video progress: $videoMessage');
      }
    });

    // Cancel subscription when dialog is closed or after timeout
    Future.delayed(Duration(minutes: 10), () {
      subscription?.cancel();
    });
  }

  Widget _buildVideoSection(
      BuildContext context, bool hasVideo, List<String> videoUrls) {
    if (!hasVideo || videoUrls.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.lightGrey.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.lightGrey,
            width: 1,
          ),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.videocam_off_rounded,
                size: 48,
                color: AppColors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                'Video not generated',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No video was generated for this GenSpace',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.grey.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // return Column(
    //   children: videoUrls.asMap().entries.map((entry) {
    //     final index = entry.key;
    //     final videoUrl = entry.value;
    //     final isFirst = index == 0;
    //
    //     return Container(
    //       margin: isFirst ? EdgeInsets.zero : const EdgeInsets.only(top: 12),
    //       decoration: BoxDecoration(
    //         gradient: LinearGradient(
    //           begin: Alignment.topLeft,
    //           end: Alignment.bottomRight,
    //           colors: [
    //             AppColors.primaryBlue.withOpacity(0.1),
    //             AppColors.primaryBlue.withOpacity(0.1),
    //           ],
    //         ),
    //         borderRadius: BorderRadius.circular(16),
    //         border: Border.all(
    //           color: AppColors.primaryBlue.withOpacity(0.3),
    //           width: 1,
    //         ),
    //       ),
    //       child: Material(
    //         color: Colors.transparent,
    //         child: Padding(
    //           padding: const EdgeInsets.all(20),
    //           child: Row(
    //             children: [
    //               // Left side - Video Generated text
    //               Text(
    //                 videoUrls.length > 1
    //                     ? 'Video  ${index + 1} of ${videoUrls.length}'
    //                     : 'Video ',
    //                 style: GoogleFonts.poppins(
    //                   fontSize: 16,
    //                   fontWeight: FontWeight.w600,
    //                   color: AppColors.darkGrey,
    //                 ),
    //               ),
    //               const Spacer(),
    //               // Right side - Row with 2 columns (View and Download)
    //               Row(
    //                 children: [
    //                   // Column 1: Play icon with "View" text
    //                   InkWell(
    //                     onTap: () async {
    //                       final url = Uri.parse(videoUrl);
    //                       if (await canLaunchUrl(url)) {
    //                         await launchUrl(url, mode: LaunchMode.externalApplication);
    //                       }
    //                     },
    //                     borderRadius: BorderRadius.circular(12),
    //                     child: Column(
    //                       children: [
    //                         Container(
    //                           padding: const EdgeInsets.all(16),
    //                           decoration: BoxDecoration(
    //                             color: AppColors.white,
    //                             borderRadius: BorderRadius.circular(12),
    //                             boxShadow: [
    //                               BoxShadow(
    //                                 color: AppColors.primaryBlue.withOpacity(0.2),
    //                                 blurRadius: 8,
    //                                 offset: const Offset(0, 4),
    //                               ),
    //                             ],
    //                           ),
    //                           child: Icon(
    //                             Icons.play_arrow_rounded,
    //                             color: AppColors.primaryBlue,
    //                             size: 32,
    //                           ),
    //                         ),
    //                         const SizedBox(height: 8),
    //                         Text(
    //                           'View',
    //                           style: GoogleFonts.poppins(
    //                             fontSize: 12,
    //                             fontWeight: FontWeight.w500,
    //                             color: AppColors.darkGrey,
    //                           ),
    //                         ),
    //                       ],
    //                     ),
    //                   ),
    //                   const SizedBox(width: 20),
    //                   // Column 2: Download icon with "Download" text
    //                   InkWell(
    //                     onTap: () => _exportVideo(context, videoUrl, index),
    //                     borderRadius: BorderRadius.circular(12),
    //                     child: Column(
    //                       children: [
    //                         Container(
    //                           padding: const EdgeInsets.all(16),
    //                           decoration: BoxDecoration(
    //                             color: AppColors.white,
    //                             borderRadius: BorderRadius.circular(12),
    //                             boxShadow: [
    //                               BoxShadow(
    //                                 color: AppColors.primaryBlue.withOpacity(0.2),
    //                                 blurRadius: 8,
    //                                 offset: const Offset(0, 4),
    //                               ),
    //                             ],
    //                           ),
    //                           child: Icon(
    //                             Icons.download_rounded,
    //                             color: AppColors.primaryBlue,
    //                             size: 32,
    //                           ),
    //                         ),
    //                         const SizedBox(height: 8),
    //                         Text(
    //                           'Download',
    //                           style: GoogleFonts.poppins(
    //                             fontSize: 12,
    //                             fontWeight: FontWeight.w500,
    //                             color: AppColors.darkGrey,
    //                           ),
    //                         ),
    //                       ],
    //                     ),
    //                   ),
    //                 ],
    //               ),
    //             ],
    //           ),
    //         ),
    //       ),
    //     );
    //   }).toList(),
    // );

    return Column(
      children: videoUrls.asMap().entries.map((entry) {
        final index = entry.key;
        final videoUrl = entry.value;
        final isFirst = index == 0;

        return Container(
          margin: isFirst ? EdgeInsets.zero : const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryBlue.withOpacity(0.1),
                AppColors.primaryBlue.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primaryBlue.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Left side - Video Generated text
                  Text(
                    videoUrls.length > 1
                        ? 'Video ${index + 1} of ${videoUrls.length}'
                        : 'Video ',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkGrey,
                    ),
                  ),
                  const Spacer(),
                  // Right side - Row with 2 columns (View and Download)
                  Row(
                    children: [
                      // Column 1: Play icon with "View" text
                      InkWell(
                        onTap: () {
                          // Navigate to in-app video player
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VideoPlayerScreen(
                                videoUrl: videoUrl,
                                title: videoUrls.length > 1
                                    ? 'Video ${index + 1} of ${videoUrls.length}'
                                    : 'Video',
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        AppColors.primaryBlue.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: AppColors.primaryBlue,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'View',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.darkGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Column 2: Download icon with "Download" text
                      InkWell(
                        onTap: () => _exportVideo(context, videoUrl, index),
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        AppColors.primaryBlue.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.download_rounded,
                                color: AppColors.primaryBlue,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Download',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.darkGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// export video method
  Future<void> _exportVideo(
      BuildContext context, String videoUrl, int index) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'exporting video...',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // export the video
      final dio = Dio();
      final response = await dio.get(
        videoUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200) {
        final bytes = Uint8List.fromList(response.data);

        // Save to temporary file first
        final tempDir = await getTemporaryDirectory();
        final tempFilePath =
            '${tempDir.path}/fashion_video_${DateTime.now().millisecondsSinceEpoch}_${index + 1}.mp4';
        final tempFile = File(tempFilePath);
        await tempFile.writeAsBytes(bytes);

        // Save to gallery
        await Gal.putVideo(tempFilePath);

        // Clean up temporary file
        await tempFile.delete();

        // Close loading dialog
        Navigator.of(context).pop();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.video_library, color: AppColors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Video exported successfully!',
                    style: GoogleFonts.poppins(
                      color: AppColors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        throw Exception('Failed to export video');
      }
    } catch (e) {
      // Close loading dialog if open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to export video: ${e.toString()}',
                  style: GoogleFonts.poppins(
                    color: AppColors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildInfoCard(String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.lightGrey,
          width: 1,
        ),
      ),
      child: Text(
        content,
        style: GoogleFonts.poppins(
          fontSize: 14,
          height: 1.6,
          color: AppColors.darkGrey,
        ),
      ),
    );
  }

  Widget _buildKeyFeatures(dynamic features) {
    List<String> featureList = [];

    if (features is List) {
      featureList = features.map((e) => e.toString()).toList();
    } else if (features is String) {
      featureList = features.split(',').map((e) => e.trim()).toList();
    }

    return Column(
      children: featureList.map((feature) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  feature,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.darkGrey,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeywords(dynamic keywords) {
    List<String> keywordList = [];

    if (keywords is List) {
      keywordList = keywords.map((e) => e.toString()).toList();
    } else if (keywords is String) {
      keywordList = keywords.split(',').map((e) => e.trim()).toList();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keywordList.map((keyword) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryBlue.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Text(
            keyword,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.primaryBlue,
            ),
          ),
        );
      }).toList(),
    );
  }

// Permission helper
  static Future<bool> _requestPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
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
    } else {
      // iOS - request photos permission
      print('🔐 Requesting photos permission for iOS');
      final photosStatus = await Permission.photos.request();
      print('📸 Photos permission: $photosStatus');
      return photosStatus.isGranted;
    }
  }

// Option 2: Save directly to Downloads folder AND Photo Gallery
  static Future<void> _exportImageToDownloads(
      BuildContext context, String imageUrl, int index) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Saving image...',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Request permission
      bool hasPermission = await _requestPermission();
      if (!hasPermission) {
        Navigator.of(context).pop();
        _showErrorMessageStatic(context,
            'Storage permission is required. Please grant permission in Settings to save images.');
        return;
      }

      // Download image bytes first
      final dio = Dio();
      final response = await dio.get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final fileName =
          'GenSpace_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      bool downloadsSuccess = false;
      bool gallerySuccess = false;
      String errorMessage = '';

      // 1. Save to Downloads folder
      try {
        Directory? directory;
        if (Platform.isAndroid) {
          // Try to access Downloads folder first
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            // Fallback to external storage
            directory = await getExternalStorageDirectory();
            if (directory != null) {
              directory = Directory('${directory.path}/Download');
              await directory.create(recursive: true);
            }
          }

          // If still no access, try app's external directory
          if (directory == null || !await directory.exists()) {
            directory = await getExternalStorageDirectory();
            if (directory != null) {
              directory = Directory('${directory.path}/RatNawnAI_Downloads');
              await directory.create(recursive: true);
            }
          }
        } else {
          // iOS - use documents directory
          directory = await getApplicationDocumentsDirectory();
        }

        if (directory != null) {
          final filePath = '${directory.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(response.data);
          downloadsSuccess = true;
          print('✅ Image saved to: $filePath');
        }
      } catch (e) {
        errorMessage += 'Downloads folder: ${e.toString()}\n';
        print('❌ Downloads save failed: $e');
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
        } else {
          errorMessage += 'Gallery: Permission denied\n';
        }
      } catch (e) {
        errorMessage += 'Gallery: ${e.toString()}\n';
      }

      Navigator.of(context).pop();

      // Show success dialog with both locations
      String successMessage = '';
      String downloadsLocation = '';

      if (downloadsSuccess && gallerySuccess) {
        successMessage =
            'Image saved successfully to Downloads folder and Photo Gallery!';
        downloadsLocation = 'Downloads folder';
      } else if (downloadsSuccess) {
        successMessage = 'Image saved to app folder. Gallery save failed.';
        downloadsLocation = 'App Downloads folder';
      } else if (gallerySuccess) {
        successMessage = 'Image saved to Photo Gallery. Downloads save failed.';
      } else {
        Navigator.of(context).pop(); // Close any remaining dialogs
        _showErrorMessageStatic(context, 'Failed to save image: $errorMessage');
        return;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Image Saved',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(successMessage, style: GoogleFonts.poppins()),
              SizedBox(height: 12),
              if (downloadsSuccess) ...[
                Row(
                  children: [
                    Icon(Icons.folder, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Text(downloadsLocation,
                        style: GoogleFonts.poppins(fontSize: 14)),
                  ],
                ),
                SizedBox(height: 8),
              ],
              if (gallerySuccess) ...[
                Row(
                  children: [
                    Icon(Icons.photo_library, color: Colors.green, size: 16),
                    SizedBox(width: 8),
                    Text('Photo Gallery',
                        style: GoogleFonts.poppins(fontSize: 14)),
                  ],
                ),
                SizedBox(height: 8),
              ],
              Text('File: $fileName', style: GoogleFonts.poppins(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      _showErrorMessageStatic(context, 'Error saving image: ${e.toString()}');
    }
  }

  //
  // static Future<void> _exportImageWithGallerySaver(BuildContext context, String imageUrl, int index) async {
  //   try {
  //     // Show loading indicator
  //     showDialog(
  //       context: context,
  //       barrierDismissible: false,
  //       builder: (context) => Center(
  //         child: Container(
  //           padding: const EdgeInsets.all(20),
  //           decoration: BoxDecoration(
  //             color: Colors.white,
  //             borderRadius: BorderRadius.circular(12),
  //           ),
  //           child: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               const CircularProgressIndicator(),
  //               const SizedBox(height: 16),
  //               Text(
  //                 'Saving image...',
  //                 style: GoogleFonts.poppins(
  //                   fontSize: 16,
  //                   fontWeight: FontWeight.w500,
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),
  //     );
  //
  //     // Request storage permission
  //     if (Platform.isAndroid) {
  //       var status = await Permission.storage.status;
  //       if (!status.isGranted) {
  //         status = await Permission.storage.request();
  //         if (!status.isGranted) {
  //           Navigator.of(context).pop();
  //           _showErrorMessageStatic(context, 'Storage permission is required');
  //           return;
  //         }
  //       }
  //     }
  //
  //     // Download the image
  //     final dio = Dio();
  //     final response = await dio.get(
  //       imageUrl,
  //       options: Options(responseType: ResponseType.bytes),
  //     );
  //
  //     // Save to gallery using image_gallery_saver
  //     final result = await ImageGallerySaver.saveImage(
  //       Uint8List.fromList(response.data),
  //       name: 'GenSpace_image_${DateTime.now().millisecondsSinceEpoch}',
  //       isReturnImagePathOfIOS: true,
  //     );
  //
  //     Navigator.of(context).pop();
  //
  //     if (result['isSuccess'] == true) {
  //       _showSuccessMessageStatic(context, 'Image saved to gallery successfully!');
  //     } else {
  //       _showErrorMessageStatic(context, 'Failed to save image to gallery');
  //     }
  //
  //   } catch (e) {
  //     Navigator.of(context).pop();
  //     _showErrorMessageStatic(context, 'Error saving image: ${e.toString()}');
  //   }
  // }

  static Future<void> _exportImageStatic(
      BuildContext context, String imageUrl, int index) async {
    // Use our new dual-save function that saves to both Downloads and Gallery
    await _exportImageToDownloads(context, imageUrl, index);
  }

  static void _showErrorMessageStatic(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl,
      int currentIndex, List<String> allImages) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.9),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullScreenImageViewer(
            imageUrl: imageUrl,
            currentIndex: currentIndex,
            allImages: allImages,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }
}

// Video Image Selection Dialog
class VideoImageSelectionDialog extends StatefulWidget {
  final List<String> images;
  final Function(List<String>) onImagesSelected;
  final VoidCallback onCancel;

  const VideoImageSelectionDialog({
    super.key,
    required this.images,
    required this.onImagesSelected,
    required this.onCancel,
  });

  @override
  State<VideoImageSelectionDialog> createState() =>
      _VideoImageSelectionDialogState();
}

class _VideoImageSelectionDialogState extends State<VideoImageSelectionDialog> {
  List<String> selectedImageUrls = [];

  /// Fetch video credit usage from Firebase credits collection
  Stream<double> get _videoCreditUsageStream {
    return FirebaseFirestore.instance
        .collection('credits')
        .doc('creditUsage')
        .snapshots()
        .map<double>((doc) {
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return (data['video'] ?? 1.0).toDouble();
      } else {
        return 1.0; // Default video credit cost
      }
    }).handleError((error) {
      if (kDebugMode) print('Error fetching video credit usage: $error');
      return Stream.value(1.0); // Return default stream on error
    });
  }

  /// Format credits for display
  String _formatCredits(double credits) {
    if (credits == credits.toInt()) {
      return credits.toInt().toString();
    } else {
      return credits.toStringAsFixed(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.video_library_rounded,
                      color: AppColors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Images for Videos',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                        Text(
                          'Choose multiple images to generate videos in parallel',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: AppColors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Instruction text with credit cost
                    StreamBuilder<double>(
                      stream: _videoCreditUsageStream,
                      builder: (context, snapshot) {
                        final videoCreditCost = snapshot.data ?? 1.0;
                        final totalCost =
                            selectedImageUrls.length * videoCreditCost;

                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primaryBlue.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: AppColors.primaryBlue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Select multiple images to generate videos in parallel. Tap images to select/deselect.',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: AppColors.primaryBlue,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Credit cost display
                            if (selectedImageUrls.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.credit_card,
                                      color: Colors.green.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        '${selectedImageUrls.length} video${selectedImageUrls.length > 1 ? 's' : ''} × ${_formatCredits(videoCreditCost)} credit${videoCreditCost > 1 ? 's' : ''} = ${_formatCredits(totalCost)} total credit${totalCost > 1 ? 's' : ''}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Images grid
                    Flexible(
                      child: GridView.builder(
                        shrinkWrap: true,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1,
                        ),
                        itemCount: widget.images.length,
                        itemBuilder: (context, index) {
                          final imageUrl = widget.images[index];
                          final isSelected =
                              selectedImageUrls.contains(imageUrl);

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  selectedImageUrls.remove(imageUrl);
                                } else {
                                  selectedImageUrls.add(imageUrl);
                                }
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primaryBlue
                                      : AppColors.lightGrey,
                                  width: isSelected ? 3 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppColors.primaryBlue
                                              .withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Stack(
                                children: [
                                  // Image
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit
                                          .contain, // Changed from BoxFit.cover
                                      width: double.infinity,
                                      height: double.infinity,
                                      placeholder: (context, url) => Container(
                                        color: AppColors.lightGrey
                                            .withOpacity(0.3),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation(
                                                AppColors.primaryBlue),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        color: AppColors.lightGrey
                                            .withOpacity(0.3),
                                        child: Center(
                                          child: Icon(
                                            Icons.broken_image_rounded,
                                            color: AppColors.grey,
                                            size: 32,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Selection indicator
                                  if (isSelected)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryBlue,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.check,
                                          color: AppColors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),

                                  // Overlay for better selection visibility
                                  if (isSelected)
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(11),
                                        color: AppColors.primaryBlue
                                            .withOpacity(0.2),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.lightGrey.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.primaryBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: StreamBuilder<double>(
                      stream: _videoCreditUsageStream,
                      builder: (context, snapshot) {
                        final videoCreditCost = snapshot.data ?? 1.0;
                        final totalCost =
                            selectedImageUrls.length * videoCreditCost;

                        return ElevatedButton(
                          onPressed: selectedImageUrls.isNotEmpty
                              // ? () => widget.onImagesSelected(selectedImageUrls)
                              ? _startVideoGeneration
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor:
                                AppColors.grey.withOpacity(0.3),
                          ),
                          child: Text(
                            selectedImageUrls.isEmpty
                                ? 'Select Images'
                                : selectedImageUrls.length == 1
                                    ? 'Generate 1 Video '
                                    : 'Generate ${selectedImageUrls.length} Videos',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startVideoGeneration() {
    // 1. Show loading dialog immediately
    showDialog(
      context: context,
      barrierDismissible: true, // User can dismiss by tapping outside
      builder: (context) => Dialog(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating Videos...'),
              Text('Please wait...'),
            ],
          ),
        ),
      ),
    );

    // 2. Close the image selection dialog
    Navigator.pop(context);

    // 3. Start the actual video generation
    widget.onImagesSelected(selectedImageUrls);
  }
}

// Full Screen Image Viewer
class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final int currentIndex;
  final List<String> allImages;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.currentIndex,
    required this.allImages,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Image Viewer
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              // Log full-screen image details when swiping between images
              print('📱 FULL-SCREEN IMAGE CHANGED:');
              print('   📍 New Index: $index');
              print('   🔗 URL: ${widget.allImages[index]}');
              print('   📊 Total Images: ${widget.allImages.length}');
              print('   ─────────────────────────────────────');
              
              setState(() {
                _currentIndex = index;
              });
            },
            itemCount: widget.allImages.length,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.allImages[index],
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(AppColors.white),
                      ),
                    ),
                    errorWidget: (context, url, error) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image_rounded,
                            color: AppColors.white,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: GoogleFonts.poppins(
                              color: AppColors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: AppColors.white,
                              size: 24,
                            ),
                          ),
                          splashRadius: 24,
                        ),
                      ),
                      const Spacer(),
                      // export button
                      Material(
                        color: Colors.transparent,
                        child: IconButton(
                          onPressed: () =>
                              GenSpaceDetailsDialog._exportImageStatic(
                                  context,
                                  widget.allImages[_currentIndex],
                                  _currentIndex),
                          // onPressed: () => GenSpaceDetailsDialog._exportImageWithGallerySaver(context, widget.allImages[_currentIndex], _currentIndex),
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.download,
                              color: AppColors.white,
                              size: 24,
                            ),
                          ),
                          splashRadius: 24,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.allImages.length}',
                          style: GoogleFonts.poppins(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Page Indicators
          if (widget.allImages.length > 1)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.allImages.length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? AppColors.white
                          : AppColors.white.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
