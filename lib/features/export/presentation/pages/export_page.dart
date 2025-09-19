import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:RatNawnAI_app/core/services/GenSpaceService.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:async';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/export_service.dart';
import '../../../../core/config/api_config.dart';
import '../../../upload/models/processing_job_model.dart';
import '../widgets/GenSpace_result_card.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  // export management
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, double> _exportProgress = {};
  bool _hasInitialized = false;

  // Selection mode variables
  Set<String> _selectedJobs = {};
  bool _isSelectionMode = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();

    // Delay loading to avoid build conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasInitialized) {
        _loadGenSpaceResults();
        _hasInitialized = true;
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: ApiConfig.longAnimation,
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
  }

  void _loadGenSpaceResults() {
    if (!mounted) return;

    Future.microtask(() {
      if (mounted) {
        final GenSpaceServices =
            Provider.of<GenSpaceService>(context, listen: false);
        // Use the updated getUserJobs which now includes real-time updates
        GenSpaceServices.getUserJobs();
      }
    });
  }

  @override
  void dispose() {
    // Cancel all active exports
    _cancelTokens.values.forEach((token) => token.cancel());
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _exportGenSpace(ProcessingJob job) async {
    try {
      print('🔄 Starting export for job: ${job.id}');

      // Check if job has result with export URL
      if (job.result == null || job.result!['excel_export_url'] == null) {
        _showMessage('No export URL available for this job', isError: true);
        return;
      }

      final exportUrl = job.result!['excel_export_url'] as String;
      print('📥 export URL: $exportUrl');

      // Show export dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              'export Options',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading:
                      Icon(Icons.open_in_browser, color: AppColors.primaryBlue),
                  title: Text('Open in Browser', style: GoogleFonts.poppins()),
                  subtitle: Text('View/export using browser',
                      style: Theme.of(context).textTheme.bodySmall),
                  onTap: () {
                    Navigator.pop(context);
                    _openInBrowser(exportUrl);
                  },
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.download, color: AppColors.primaryBlue),
                  title: Text('export to Device', style: GoogleFonts.poppins()),
                  subtitle: Text('Save to exports folder',
                      style: Theme.of(context).textTheme.bodySmall),
                  onTap: () {
                    Navigator.pop(context);
                    _exportToDevice(exportUrl, job.id);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: GoogleFonts.poppins()),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('❌ export error: $e');
      _showMessage('export failed: ${e.toString()}', isError: true);
    }
  }

  Future<void> _openInBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _showMessage('Opening in browser...');
      } else {
        _showMessage('Could not open URL', isError: true);
      }
    } catch (e) {
      _showMessage('Error opening URL: ${e.toString()}', isError: true);
    }
  }

  Future<void> _exportToDevice(String url, String jobId) async {
    try {
      // Request storage permission
      final hasPermission = await exportService.requestStoragePermission();
      if (!hasPermission) {
        _showMessage('Storage permission is required to export files',
            isError: true);
        return;
      }

      // Create filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'RatNawnAI_GenSpace_${jobId.substring(jobId.length.clamp(0, 8))}_$timestamp.xlsx';

      // Create cancel token
      final cancelToken = CancelToken();
      _cancelTokens[jobId] = cancelToken;

      // Update UI to show export started
      setState(() {
        _exportProgress[jobId] = 0.0;
      });

      // export file
      final filePath = await exportService.exportFile(
        url: url,
        fileName: fileName,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _exportProgress[jobId] = progress;
            });
          }
        },
      );

      // Clean up
      _cancelTokens.remove(jobId);
      if (mounted) {
        setState(() {
          _exportProgress.remove(jobId);
        });
      }

      // Show success dialog
      _showexportSuccessDialog(fileName, filePath);
    } catch (e) {
      // Clean up on error
      _cancelTokens.remove(jobId);
      if (mounted) {
        setState(() {
          _exportProgress.remove(jobId);
        });
      }

      if (e is DioException && e.type == DioExceptionType.cancel) {
        _showMessage('export cancelled');
        return;
      }

      print('❌ export failed: $e');

      String errorMessage = 'export failed: ';
      if (e.toString().contains('403')) {
        errorMessage += 'Access denied. The export link may have expired.';
      } else if (e.toString().contains('404')) {
        errorMessage += 'File not found on server.';
      } else if (e.toString().contains('SocketException')) {
        errorMessage += 'Network error. Please check your connection.';
      } else {
        errorMessage += e.toString();
      }

      _showMessage(errorMessage, isError: true);
    }
  }

  void _cancelexport(String jobId) {
    final cancelToken = _cancelTokens[jobId];
    if (cancelToken != null) {
      cancelToken.cancel();
      _cancelTokens.remove(jobId);
      setState(() {
        _exportProgress.remove(jobId);
      });
      _showMessage('export cancelled');
    }
  }

  void _showexportSuccessDialog(String fileName, String filePath) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              SizedBox(width: 8),
              Text('export Complete',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File saved successfully!', style: GoogleFonts.poppins()),
              SizedBox(height: 16),
              Text('Filename:',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              SelectableText(fileName,
                  style: Theme.of(context).textTheme.bodySmall),
              SizedBox(height: 8),
              Text('Location:',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.lightGrey.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (Platform.isAndroid) ...[
                      Text(
                        'Internal Storage > export',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Open your file manager app and look in the exports folder',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.grey),
                      ),
                    ] else ...[
                      Text(
                        'Files app > On My iPhone > RatNawnAI',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: GoogleFonts.poppins()),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: Duration(
            seconds: isError
                ? 4
                : 2), // Keep custom logic for different message types
      ),
    );
  }

  void _toggleJobSelection(String jobId) {
    setState(() {
      if (_selectedJobs.contains(jobId)) {
        _selectedJobs.remove(jobId);
        if (_selectedJobs.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedJobs.add(jobId);
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _batchDeleteJobs() async {
    if (_selectedJobs.isEmpty) return;

    final count = _selectedJobs.length;
    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Multiple GenSpaces',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete $count GenSpace${count > 1 ? 's' : ''}? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: Text('Delete All', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppColors.primaryBlue),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Deleting GenSpaces...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      try {
        final GenSpaceServices =
            Provider.of<GenSpaceService>(context, listen: false);

        // Delete all selected jobs
        for (final jobId in _selectedJobs) {
          await GenSpaceServices.deleteJob(jobId);
        }

        // Clear selection
        setState(() {
          _selectedJobs.clear();
          _isSelectionMode = false;
        });
        // Close progress dialog
        Navigator.pop(context);

        _showMessage(
            '$count GenSpace${count > 1 ? 's' : ''} deleted successfully');

        // Refresh the list - real-time updates will handle this automatically
      } catch (e) {
        Navigator.pop(context);
        _showMessage('Failed to delete some GenSpaces: ${e.toString()}',
            isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Scaffold(
      backgroundColor: AppColors.lightGrey.withOpacity(0.3),
      appBar: AppBar(
        title: Row(
          children: [
            // App Icon/Logo Container
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.inventory_rounded,
                color: AppColors.primaryBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Title
            Expanded(
              child: Text(
                'RatNawnAI Results',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkGrey,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border(
              bottom: BorderSide(
                color: AppColors.lightGrey.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
        ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              onPressed: _batchDeleteJobs,
              icon: Icon(Icons.delete_sweep, color: AppColors.error),
              tooltip: 'Delete selected',
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedJobs.clear();
                  _isSelectionMode = false;
                });
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: AppColors.grey),
              ),
            ),
          ] else ...[
            IconButton(
              onPressed: () {
                Future.microtask(() {
                  if (mounted) {
                    final GenSpaceServices =
                    Provider.of<GenSpaceService>(context, listen: false);
                    // Force refresh to get latest data
                    GenSpaceServices.refreshJobs();
                  }
                });
              },
              icon: Icon(
                Icons.refresh_rounded,
                color: AppColors.primaryBlue,
              ),
              tooltip: 'Refresh results',
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: _buildGenSpaceResults(),
          );
        },
      ),
    );
  }

  Widget _buildGenSpaceResults() {
    return Consumer<GenSpaceService>(
      builder: (context, GenSpaceService, child) {
        if (GenSpaceService.isLoading) {
          return _buildLoadingState();
        } else if (GenSpaceService.jobs.isEmpty) {
          return _buildEmptyState();
        } else {
          return _buildResultsList(GenSpaceService.jobs);
        }
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.inventory_rounded,
                size: 60,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No GenSpaces Yet',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.darkGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create your first smart GenSpace to see\nprocessed results here',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.grey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/upload');
              },
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                'Create GenSpace',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 25),
      decoration: const BoxDecoration(
        color: Color(0xFF1B68C0),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(35),
          bottomRight: Radius.circular(35),
        ),
      ),
      child: Row(children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'RatNawnAI Results',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        )
      ]),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation(AppColors.primaryBlue),
      ),
    );
  }

  Widget _buildResultsList(List<ProcessingJob> jobs) {
    return RefreshIndicator(
      onRefresh: () async {
        final GenSpaceServices =
            Provider.of<GenSpaceService>(context, listen: false);
        // Use force refresh method for pull-to-refresh
        await GenSpaceServices.refreshJobs();
      },
      color: AppColors.primaryBlue,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: jobs.length,
        itemBuilder: (context, index) {
          final job = jobs[index];
          final isSelected = _selectedJobs.contains(job.id);
          final exportProgress = _exportProgress[job.id];
          final isexporting = exportProgress != null;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GestureDetector(
              onLongPress: () => _toggleJobSelection(job.id),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: isSelected
                      ? Border.all(color: AppColors.primaryBlue, width: 2)
                      : null,
                ),
                child: Stack(
                  children: [
                    GenSpaceResultCard(
                      job: job,
                      onexport: job.isCompleted && !isexporting
                          ? () => _exportGenSpace(job)
                          : null,
                      onDelete: () => _deleteJob(job),
                    ),

                    // export progress overlay
                    if (isexporting)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    value: exportProgress,
                                    valueColor: AlwaysStoppedAnimation(
                                        AppColors.primaryBlue),
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'exporting... ${(exportProgress * 100).toInt()}%',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () => _cancelexport(job.id),
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.poppins(
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _deleteJob(ProcessingJob job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete GenSpace',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.darkGrey,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this GenSpace result? This action cannot be undone.',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.grey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performDelete(job);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _performDelete(ProcessingJob job) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppColors.primaryBlue),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Deleting GenSpace...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      final GenSpaceServices =
          Provider.of<GenSpaceService>(context, listen: false);
      await GenSpaceServices.deleteJob(job.id);

      Navigator.pop(context);

      _showMessage('GenSpace deleted successfully');

      // Real-time listener will handle the update automatically
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      _showMessage('Failed to delete GenSpace: ${e.toString()}', isError: true);
    }
  }
}
