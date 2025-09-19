import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/utils/responsive_utils.dart';

class exportVideoCard extends StatelessWidget {
  final exportableVideo video;
  final double? progress;
  final VoidCallback onexport;
  final VoidCallback onCancel;

  const exportVideoCard({
    super.key,
    required this.video,
    this.progress,
    required this.onexport,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isexporting = progress != null;
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with thumbnail and info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 80,
                    height: 60,
                    child: video.thumbnailUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: video.thumbnailUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.lightGrey,
                              child: const Icon(
                                Icons.video_file_rounded,
                                color: AppColors.grey,
                                size: 24,
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.lightGrey,
                              child: const Icon(
                                Icons.video_file_rounded,
                                color: AppColors.grey,
                                size: 24,
                              ),
                            ),
                          )
                        : Container(
                            color: AppColors.lightGrey,
                            child: const Icon(
                              Icons.video_file_rounded,
                              color: AppColors.grey,
                              size: 24,
                            ),
                          ),
                  ),
                ),

                const SizedBox(width: 16),

                // Video info
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkGrey,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                 
                    const SizedBox(height: 8),
                
                  ],
                ),
              ],
            ),
          ),

          // Progress bar (if exporting)
          if (isexporting) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'exporting...',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      Text(
                        '${(progress! * 100).toInt()}%',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.lightGrey,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: isexporting
                  ? OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded),
                      label: Text(
                        'Cancel export',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: onexport,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        'export Video',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryAccent,
                        foregroundColor: AppColors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return TimeFormatUtils.formatTimeAgo(date);
  }
}