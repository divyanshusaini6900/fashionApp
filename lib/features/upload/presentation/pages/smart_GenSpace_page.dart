import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/config/api_config.dart';
import '../../../navbar/safe_state_mixin.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/services/queue_manager.dart';
import '../../../../core/services/discount_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/background_GenSpace_service.dart';

import '../../../../core/utils/credit_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/loading_overlay.dart';

import 'dart:async';

class SmartGenSpacePage extends StatefulWidget {
  const SmartGenSpacePage({super.key});

  @override
  State<SmartGenSpacePage> createState() => _SmartGenSpacePageState();
}

class _SmartGenSpacePageState extends State<SmartGenSpacePage>
    with
        TickerProviderStateMixin,
        SafeStateMixin,
        AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _descriptionController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Dress type and gender selection
  String? _selectedDressType;
  String _selectedGender = 'Male';

  // Dropdown items for dress type
  final List<String> _dressTypes = ['Ethnic', 'Western'];

  // Image handling
  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, File?> _productImages = {
    'front_view': null,
    'side_view': null,
    'back_view': null,
    'detail_view': null,
  };
  final List<File> _additionalImages = [];

  // Excel generation toggle
  bool _generateCsv = true;
  // Images to generate dropdown
  int _imagesToGenerate = 1;

  // Background selections for each image (using image labels as keys)
  Map<String, String> _backgroundSelections = {};

  // Processing state
  bool _isProcessing = false;
  bool _showingLoadingMessage = false;

  // Job tracking for loading overlay
  String? _currentJobId;
  bool _showGenerationLoading = false;
  bool _successMessageShown = false;
  StreamSubscription? _queueStatusSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _jobDocSubscription;
  bool _hasListenerAttached = false;
  Timer? _loadingTimer;
  DiscountService? _discountService;

  // Pricing helpers using Firebase discount service
  PriceCalculation get _priceCalculation {
    final discountService = context.read<DiscountService>();
    return discountService.calculatePrice(
      imageCount: _imagesToGenerate,
      includeExcel: _generateCsv,
    );
  }

  double get _imageBasePrice => _priceCalculation.imageTotal;
  double get _imageDiscountPercent => _priceCalculation.imageDiscountPercent;
  double get _imageDiscountCredits => _priceCalculation.imageDiscountAmount;
  double get _addOnsPrice => _priceCalculation.excelPriceAfterDiscount;
  double get _creditCost => _priceCalculation.totalAfterDiscount;

  String _formatCredits(double credits) {
    return CreditFormatter.formatCredits(credits);
  }

  void _onDescriptionChanged() {
    if (mounted) {
      safeSetState(() {});
    }
  }

  void _onSelectionChanged() {
    if (mounted) {
      safeSetState(() {
        // Refresh the UI when dress type or gender changes
        // This could also trigger preview updates or validation
      });

      // Optional: Show feedback to user about their selection
      if (_selectedDressType != null && kDebugMode) {
        print('Selection updated: $_selectedDressType, $_selectedGender');
      }
    }
  }

  /// Get list of uploaded image types in order
  List<String> _getUploadedImageTypes() {
    List<String> uploadedTypes = [];
    
    // Add product images in order
    if (_productImages['front_view'] != null) uploadedTypes.add('Front View');
    if (_productImages['side_view'] != null) uploadedTypes.add('Side View');
    if (_productImages['back_view'] != null) uploadedTypes.add('Back View');
    if (_productImages['detail_view'] != null) uploadedTypes.add('Detail View');
    
    // Add additional images (use base type only)
    if (_additionalImages.isNotEmpty) {
      uploadedTypes.add('Additional View');
    }
    
    return uploadedTypes;
  }
  
  /// Generate image labels based on uploaded images and number to generate
  List<String> _generateImageLabels() {
    final uploadedTypes = _getUploadedImageTypes();
    
    if (uploadedTypes.isEmpty) {
      // If no images uploaded, show generic labels
      return List.generate(_imagesToGenerate, (index) => 'Image ${index + 1}');
    }
    
    List<String> labels = [];
    int currentIndex = 0;
    
    for (int i = 0; i < _imagesToGenerate; i++) {
      final imageType = uploadedTypes[currentIndex % uploadedTypes.length];
      final imageNumber = (currentIndex ~/ uploadedTypes.length) + 1;
      
      // All image types get "Image X" appended, including Additional View
      labels.add('$imageType Image $imageNumber');
      
      currentIndex++;
    }
    
    return labels;
  }

  /// Update background selections when number of images changes
  void _updateBackgroundSelections(int newImageCount) {
    final newLabels = _generateImageLabels();
    final Map<String, String> newSelections = {};
    
    // Keep existing selections for labels that still exist
    for (String label in newLabels) {
      newSelections[label] = _backgroundSelections[label] ?? 'White';
    }
    
    _backgroundSelections = newSelections;
    
    // Print background arrays to terminal
    _printBackgroundArrays();
  }

  /// Convert background selection to array
  /// OpenAPI expects [white, plain, random] order
  List<int> _getBackgroundArray(String background) {
    switch (background) {
      case 'White':
        return [1, 0, 0]; // White is first in OpenAPI
      case 'Plain':
        return [0, 1, 0]; // Plain is second in OpenAPI  
      case 'Random':
        return [0, 0, 1]; // Random is third in OpenAPI
      default:
        return [1, 0, 0]; // Default to White
    }
  }

  /// Extract view type from image label
  String _getViewType(String imageLabel) {
    // Remove "Image X" from the end to get the view type
    final parts = imageLabel.split(' ');
    if (parts.length >= 3 && parts[parts.length - 2] == 'Image') {
      // Join all parts except the last two ("Image" and number)
      return parts.sublist(0, parts.length - 2).join(' ');
    }
    return imageLabel; // Fallback
  }

  /// Group background selections by view type and create combined arrays
  Map<String, List<int>> _createBackgroundArraysByViewType() {
    Map<String, List<int>> viewTypeArrays = {};
    
    _backgroundSelections.forEach((imageLabel, background) {
      final viewType = _getViewType(imageLabel);
      final backgroundArray = _getBackgroundArray(background);
      
      if (viewTypeArrays.containsKey(viewType)) {
        // Add arrays element-wise
        for (int i = 0; i < 3; i++) {
          viewTypeArrays[viewType]![i] += backgroundArray[i];
        }
      } else {
        // Create new array for this view type
        viewTypeArrays[viewType] = List<int>.from(backgroundArray);
      }
    });
    
    return viewTypeArrays;
  }

  /// Get background arrays for GenSpace generation (only for specific views)
  Map<String, List<int>> getBackgroundArraysForGeneration() {
    final allArrays = _createBackgroundArraysByViewType();
    // Only return arrays for specific views, not generic "Image X"
    return Map<String, List<int>>.fromEntries(
      allArrays.entries.where((entry) => 
        !entry.key.startsWith('Image ') || entry.key.contains('View')
      )
    );
  }

  /// Print background arrays to terminal
  void _printBackgroundArrays() {
    if (_backgroundSelections.isEmpty) {
      print('🎨 No background selections yet');
      return;
    }
    
    // Check if we have actual specific views (not generic "Image X")
    final hasSpecificViews = _backgroundSelections.keys.any((label) => 
      !label.startsWith('Image ') || 
      label.contains('Front View') || 
      label.contains('Side View') || 
      label.contains('Back View') || 
      label.contains('Detail View') || 
      label.contains('Additional View')
    );
    
    if (!hasSpecificViews) {
      print('🎨 No specific views selected - arrays will be created only for uploaded specific views');
      return;
    }
    
    print('\n🎨 ===== BACKGROUND ARRAYS =====');
    
    // Print individual selections (only for specific views)
    print('\n📋 Individual Selections:');
    _backgroundSelections.forEach((imageLabel, background) {
      // Skip generic "Image X" labels
      if (!imageLabel.startsWith('Image ') || imageLabel.contains('View')) {
        final array = _getBackgroundArray(background);
        print('   $imageLabel -> $background -> $array');
      }
    });
    
    // Print combined arrays by view type (only for specific views)
    final viewTypeArrays = _createBackgroundArraysByViewType();
    final specificViewArrays = Map<String, List<int>>.fromEntries(
      viewTypeArrays.entries.where((entry) => 
        !entry.key.startsWith('Image ') || entry.key.contains('View')
      )
    );
    
    if (specificViewArrays.isNotEmpty) {
      print('\n🔗 Combined Arrays by View Type:');
      specificViewArrays.forEach((viewType, combinedArray) {
        print('   $viewType -> $combinedArray');
      });
    }
    
    print('🎨 ==============================\n');
  }

  /// Reset form to prepare for new GenSpace generation
  void _resetFormForNewGenSpace() {
    if (mounted) {
      safeSetState(() {
        // Reset form fields but keep user preferences
        _descriptionController.clear();
        _productImages.updateAll((key, value) => null);
        _additionalImages.clear();
        _backgroundSelections.clear();

        // Keep dress type, gender, and CSV settings as user preference
        // _selectedDressType = null; // Don't reset this
        // _selectedGender = 'Male'; // Don't reset this
        // _generateCsv = true; // Don't reset this

        // Reset processing states
        _isProcessing = false;
        _showingLoadingMessage = false;
        _showGenerationLoading = false;
        _successMessageShown = false;
        _currentJobId = null;
      });

      if (kDebugMode) print('Form reset for new GenSpace generation');
    }
  }

  @override
  void initState() {
    super.initState();

    _setupAnimations();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasListenerAttached) {
        _descriptionController.addListener(_onDescriptionChanged);
        _hasListenerAttached = true;

        _discountService = context.read<DiscountService>();
        _discountService?.addListener(_onDiscountDataChanged);
      }
    });
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: ApiConfig.longAnimation,
      vsync: this,
    );

    _slideController = AnimationController(
      duration: ApiConfig.extraLongAnimation,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  void _onDiscountDataChanged() {
    if (mounted) {
      safeSetState(() {});
    }
  }

  @override
  void dispose() {
    _discountService?.removeListener(_onDiscountDataChanged);
    _queueStatusSubscription?.cancel();
    _jobDocSubscription?.cancel();
    _loadingTimer?.cancel();

    if (_hasListenerAttached) {
      _descriptionController.removeListener(_onDescriptionChanged);
    }

    _descriptionController.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F1F1),
      body: LoadingOverlay(
        isLoading: _showingLoadingMessage || _showGenerationLoading,
        loadingMessage: _showGenerationLoading
            ? 'Please wait for the generate GenSpace...\nProcessing your images and generating content'
            : 'Starting generation...\nYour GenSpace will be processed automatically',
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _buildForm(),
            ),
            _buildBottomSection(),
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
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RatNawnAI Studio',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Short,Clear,Professional',
                  style: GoogleFonts.roboto(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dress Type Dropdown
            _buildDressTypeSection(),
            const SizedBox(height: 24),

            // Gender Selection
            _buildGenderSection(),
            const SizedBox(height: 24),

            // Product Images
            _buildProductImagesSection(),
            const SizedBox(height: 24),

            // Additional Images
            _buildAdditionalImagesSection(),
            const SizedBox(height: 24),

            // Images to Generate
            _buildImagesToGenerateSection(),
            const SizedBox(height: 24),

            // Select Background For Images
            _buildBackgroundSelectionSection(),
            const SizedBox(height: 24),

            // Product Description
            _buildProductDescriptionSection(),
            const SizedBox(height: 24),

            // Excel Report Toggle
            _buildExcelToggleSection(),
            const SizedBox(height: 24),
            // Price Breakdown
            _buildPriceBreakdown(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildDressTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0x331E1E1E),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3F000000),
                blurRadius: 4,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDressType,
              hint: Text(
                'Choose Dress Type',
                style: GoogleFonts.roboto(
                  color: const Color(0xFF1E1E1E),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
              icon: const Icon(Icons.keyboard_arrow_down),
              isExpanded: true,
              items: _dressTypes.map((String type) {
                return DropdownMenuItem<String>(
                  value: type,
                  child: Text(
                    type,
                    style: GoogleFonts.roboto(
                      color: const Color(0xFF1E1E1E),
                      fontSize: 16,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedDressType = newValue;
                });
                _onSelectionChanged();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Gender',
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E1E1E),
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildRadioOption('Male'),
            const SizedBox(width: 34),
            _buildRadioOption('Female'),
          ],
        ),
      ],
    );
  }

  Widget _buildRadioOption(String value) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedGender = value;
        });
        _onSelectionChanged();
      },
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Radio<String>(
            value: value,
            groupValue: _selectedGender,
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedGender = newValue;
                });
                _onSelectionChanged();
              }
            },
            activeColor: const Color(0xFF1B68C0),
          ),
          Text(
            value,
            style: GoogleFonts.roboto(
              color: Colors.black.withOpacity(0.87),
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Images',
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E1E1E),
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Upload clear images of your product from different angles',
          style: GoogleFonts.roboto(
            color: const Color(0xFF1E1E1E),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.14,
          ),
          itemCount: 4,
          itemBuilder: (context, index) {
            final keys = [
              'front_view',
              'side_view',
              'back_view',
              'detail_view'
            ];
            final labels = [
              'Front View',
              'Side View',
              'Back View',
              'Detail View'
            ];
            final key = keys[index];
            final label = labels[index];

            return _buildImageCard(
              label: label,
              imageFile: _productImages[key],
              onTap: () => _pickProductImage(key),
              onRemove: _productImages[key] != null
                  ? () => _removeProductImage(key)
                  : null,
            );
          },
        ),
      ],
    );
  }

  Widget _buildImageCard({
    required String label,
    File? imageFile,
    required VoidCallback onTap,
    VoidCallback? onRemove,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: imageFile != null
                ? const Color(0xFF1B68C0).withOpacity(0.5)
                : const Color(0x331E1E1E),
            width: imageFile != null ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3F000000),
              blurRadius: 4,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: imageFile != null
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      imageFile,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (onRemove != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: GoogleFonts.roboto(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B68C0).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate,
                      color: Color(0xFF1B68C0),
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: GoogleFonts.roboto(
                      color: const Color(0xFF1E1E1E),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAdditionalImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Additional Images',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF1E1E1E),
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add more product images (Optional)',
                    style: GoogleFonts.roboto(
                      color: const Color(0xFF1E1E1E),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _pickAdditionalImage,
              icon: const Icon(Icons.add_photo_alternate, size: 20),
              label: Text(
                'Add',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B68C0),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: _additionalImages.isEmpty ? 160 : null,
          padding: _additionalImages.isEmpty ? const EdgeInsets.all(16) : null,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0x331E1E1E),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3F000000),
                blurRadius: 4,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: _additionalImages.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 40,
                      color: const Color(0xFF1E1E1E).withOpacity(0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No additional images added',
                      style: GoogleFonts.roboto(
                        color: const Color(0xFF1E1E1E),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemCount: _additionalImages.length,
                  itemBuilder: (context, index) {
                    return _buildAdditionalImageItem(
                        _additionalImages[index], index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAdditionalImageItem(File imageFile, int index) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            imageFile,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeAdditionalImage(index),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.red,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagesToGenerateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Images To Generate',
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E1E1E),
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 124,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0x331E1E1E),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3F000000),
                blurRadius: 4,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _imagesToGenerate,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              isExpanded: true,
              items: List.generate(6, (index) => index + 1).map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text(
                    '$value image${value > 1 ? 's' : ''}',
                    style: GoogleFonts.roboto(
                      color: const Color(0xFF1E1E1E),
                      fontSize: 16,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (int? newValue) {
                if (newValue != null) {
                  setState(() {
                    _imagesToGenerate = newValue;
                    // Update background selections for the new number of images
                    _updateBackgroundSelections(newValue);
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundSelectionSection() {
    final imageLabels = _generateImageLabels();
    
    // Only show if there are uploaded images
    if (_getUploadedImageTypes().isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Background For Images',
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E1E1E),
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        // Generate background selection for each image label
        ...imageLabels.map((label) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildImageBackgroundOption(label),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildImageBackgroundOption(String imageLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          imageLabel,
          style: GoogleFonts.roboto(
            color: const Color(0xFF1E1E1E),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildBackgroundRadioOption(imageLabel, 'White'),
            const SizedBox(width: 24),
            _buildBackgroundRadioOption(imageLabel, 'Plain'),
            const SizedBox(width: 24),
            _buildBackgroundRadioOption(imageLabel, 'Random'),
          ],
        ),
      ],
    );
  }

  Widget _buildBackgroundRadioOption(String imageLabel, String value) {
    return InkWell(
      onTap: () {
        setState(() {
          _backgroundSelections[imageLabel] = value;
          // Print arrays when selection changes
          _printBackgroundArrays();
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<String>(
            value: value,
            groupValue: _backgroundSelections[imageLabel],
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _backgroundSelections[imageLabel] = newValue;
                  // Print arrays when selection changes
                  _printBackgroundArrays();
                });
              }
            },
            activeColor: const Color(0xFF1B68C0),
          ),
          Text(
            value,
            style: GoogleFonts.roboto(
              color: Colors.black.withOpacity(0.87),
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductDescriptionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Description',
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E1E1E),
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive height based on screen size
            final screenHeight = MediaQuery.of(context).size.height;

            // Responsive height calculation
            double containerHeight;
            if (screenHeight < 600) {
              // Small screens (phones in landscape)
              containerHeight = screenHeight * 0.25; // 25% of screen height
            } else if (screenHeight < 800) {
              // Medium screens (most phones)
              containerHeight = screenHeight * 0.22; // 22% of screen height
            } else {
              // Large screens (tablets, large phones)
              containerHeight = screenHeight * 0.18; // 18% of screen height
            }

            // Ensure minimum and maximum heights
            containerHeight = containerHeight.clamp(160.0, 300.0);

            return Container(
              width: double.infinity,
              height: containerHeight,
              padding:
                  EdgeInsets.all(ResponsiveUtils.isTablet(context) ? 20 : 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1F1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0x331E1E1E),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3F000000),
                    blurRadius: 4,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: TextFormField(
                controller: _descriptionController,
                maxLines: null,
                expands:
                    true, // âœ… This makes the field expand to fill container
                textAlignVertical:
                    TextAlignVertical.top, // âœ… Start text from top
                decoration: InputDecoration(
                  hintText: 'Describe your product here....',
                  hintStyle: GoogleFonts.roboto(
                    color: const Color(0xFF1E1E1E).withOpacity(0.6),
                    fontSize: ResponsiveUtils.isTablet(context) ? 18 : 16,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  focusedBorder:
                      InputBorder.none, // Removes blue border on focus
                  enabledBorder:
                      InputBorder.none, // Removes border when not focused
                  errorBorder:
                      InputBorder.none, // Removes border on error (optional)
                  focusedErrorBorder: InputBorder
                      .none, // Removes border on focused error (optional)
                  contentPadding: EdgeInsets.zero,
                  isDense: true, // Reduces default padding
                ),
                style: GoogleFonts.roboto(
                  color: const Color(0xFF1E1E1E),
                  fontSize: ResponsiveUtils.isTablet(context) ? 18 : 16,
                  fontWeight: FontWeight.w400,
                  height: 1.4, // âœ… Proper line height for readability
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a product description';
                  }
                  if (value.length < 3) {
                    return 'Description must be at least 50 characters';
                  }
                  return null;
                },
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Character: ${_descriptionController.text.length}/3 minimum',
          style: GoogleFonts.roboto(
            color: _descriptionController.text.length >= 3
                ? const Color(0xFF218838)
                : const Color(0xFF1E1E1E).withOpacity(0.6),
            fontSize: ResponsiveUtils.isTablet(context) ? 16 : 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceBreakdown() {
    final hasDiscount = _imageDiscountCredits > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0x331E1E1E),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3F000000),
            blurRadius: 4,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Price Breakdown',
                style: GoogleFonts.roboto(
                  color: const Color(0xFF1E1E1E),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B68C0).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_imagesToGenerate}x images',
                  style: GoogleFonts.roboto(
                    color: const Color(0xFF1B68C0),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPriceRow(
            icon: Icons.image_outlined,
            label: 'Images',
            value: '${_formatCredits(_imageBasePrice)} Credits',
            color: const Color(0xFF1E1E1E).withOpacity(0.6),
          ),
          if (hasDiscount) ...[
            const SizedBox(height: 8),
            _buildPriceRow(
              icon: Icons.local_offer_outlined,
              label: 'Discount (${(_imageDiscountPercent * 100).toInt()}%)',
              value: '-${_formatCredits(_imageDiscountCredits)}',
              color: const Color(0xFF218838),
            ),
          ],
          const SizedBox(height: 8),
          _buildPriceRow(
            icon: Icons.table_chart_outlined,
            label: 'Excel',
            value: _generateCsv ? '+${_formatCredits(_addOnsPrice)}' : '+0',
            color: const Color(0xFF1E1E1E).withOpacity(0.6),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0x661E1E1E)),
          const SizedBox(height: 12),
          _buildPriceRow(
            icon: Icons.payment_outlined,
            label: 'Total',
            value: '${_formatCredits(_creditCost)} Credits',
            color: const Color(0xFF1E1E1E),
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 24, color: color.withOpacity(0.8)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.roboto(
                color: color,
                fontSize: 16,
                fontWeight: isBold ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: GoogleFonts.roboto(
            color: color,
            fontSize: 16,
            fontWeight: isBold ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildExcelToggleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Excel Report (+${_formatCredits(_priceCalculation.excelPrice)} Credits)',
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E1E1E),
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose whether to generate an excel report for your GenSpace',
          style: GoogleFonts.roboto(
            color: const Color(0xFF1E1E1E),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _generateCsv
                  ? const Color(0xFF1B68C0).withOpacity(0.3)
                  : const Color(0x331E1E1E),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3F000000),
                blurRadius: 4,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: (_generateCsv
                              ? const Color(0xFF1B68C0)
                              : const Color(0xFF1E1E1E))
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.table_chart,
                      color: _generateCsv
                          ? const Color(0xFF1B68C0)
                          : const Color(0xFF1E1E1E),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generate Excel',
                        style: GoogleFonts.roboto(
                          color: const Color(0xFF1E1E1E),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _generateCsv ? 'Excel enabled' : 'Excel disabled',
                        style: GoogleFonts.roboto(
                          color: _generateCsv
                              ? const Color(0xFF1B68C0)
                              : const Color(0xFF1E1E1E).withOpacity(0.6),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: _generateCsv,
                onChanged: (value) {
                  setState(() {
                    _generateCsv = value;
                  });
                },
                activeColor: const Color(0xFF1B68C0),
                activeTrackColor: const Color(0xFF1B68C0).withOpacity(0.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSection() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(14),
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _processGenSpace,
            icon: _isProcessing
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.auto_awesome, size: 20),
            label: Text(
              _isProcessing
                  ? 'GENERATING...'
                  : 'Transform with AI (${_formatCredits(_creditCost)} CREDITS)',
              style: GoogleFonts.roboto(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B68C0),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }

  // Image picker methods
  Future<void> _pickProductImage(String imageType) async {
    try {
      final ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null && mounted) {
        safeSetState(() {
          _productImages[imageType] = File(image.path);
          // Update background selections when images change
          _updateBackgroundSelections(_imagesToGenerate);
        });
      }
    } catch (e) {
      _showMessage('Error selecting image: ${e.toString()}', isError: true);
    }
  }

  Future<void> _pickAdditionalImage() async {
    try {
      final ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null && mounted) {
        safeSetState(() {
          _additionalImages.add(File(image.path));
          // Update background selections when images change
          _updateBackgroundSelections(_imagesToGenerate);
        });
      }
    } catch (e) {
      _showMessage('Error selecting image: ${e.toString()}', isError: true);
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        'Select Image Source',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  Navigator.of(context).pop(ImageSource.camera),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F1F1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.grey.withOpacity(0.3)),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.camera_alt,
                                      size: 40,
                                      color: Color(0xFF1B68C0),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Camera',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.of(context)
                                  .pop(ImageSource.gallery),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F1F1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.grey.withOpacity(0.3)),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.photo_library,
                                      size: 40,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Gallery',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
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
      },
    );
  }

  void _removeProductImage(String imageType) {
    if (mounted) {
      safeSetState(() {
        _productImages[imageType] = null;
        // Update background selections when images change
        _updateBackgroundSelections(_imagesToGenerate);
      });
    }
  }

  void _removeAdditionalImage(int index) {
    if (mounted) {
      safeSetState(() {
        _additionalImages.removeAt(index);
        // Update background selections when images change
        _updateBackgroundSelections(_imagesToGenerate);
      });
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  String get _computedProductType {
    if (_selectedGender == 'Female' && _selectedDressType == 'Ethnic') {
      return 'kurti_lehenga';
    }
    return 'general';
  }

  // Process GenSpace method (keeping your existing logic)
  Future<void> _processGenSpace() async {
    if (!mounted) return;

    if (!_formKey.currentState!.validate()) {
      _showMessage('Please fill in all required fields', isError: true);
      return;
    }

    if (_selectedDressType == null || _selectedDressType!.isEmpty) {
      _showMessage('Please select a dress type', isError: true);
      return;
    }

    if (_productImages['front_view'] == null) {
      _showMessage('Please add at least a front view image', isError: true);
      return;
    }

    final requiredCredits = _creditCost;
    try {
      final hasEnoughCredits =
          await FirebaseService.hasEnoughCredits(requiredCredits);
      if (!hasEnoughCredits) {
        final currentBalance = await FirebaseService.getUsercreditBalance();
        _showInsufficientCreditsDialog(currentBalance, requiredCredits);
        return;
      }
    } catch (e) {
      _showMessage('Unable to check wallet balance. Please try again.',
          isError: true);
      return;
    }

    try {
      safeSetState(() {
        _isProcessing = true;
        _showingLoadingMessage = true;
        _showGenerationLoading = true;
        _successMessageShown = false;
      });

      // Print final background arrays before processing
      print('\n🚀 ===== FINAL BACKGROUND ARRAYS FOR GENERATION =====');
      _printBackgroundArrays();

      final queueManager =
          Provider.of<QueueManagerProvider>(context, listen: false);

      final jobIdFuture = queueManager.queueGenSpace(
        text: _descriptionController.text.trim(),
        username: FirebaseService.currentUser?.email ?? 'user',
        product: 'GenSpace',
        productImages: _productImages,
        additionalImages: _additionalImages,
        generateCsv: _generateCsv, // This passes the actual toggle value
        imagesToGenerate: _imagesToGenerate,
        creditCost: requiredCredits,
        // productType: _selectedDressType ?? 'general',
        productType: _computedProductType, // NEW
        gender: _selectedGender,
        backgroundArrays: getBackgroundArraysForGeneration(), // Pass background arrays
      );

      _startJobMonitoring(queueManager);

      jobIdFuture.then((id) async {
        _currentJobId = id;

        // Background service will be started automatically after image upload
        // This prevents timing issues with missing uploadedImageUrls
        if (kDebugMode) {
          print(
              'ðŸ“ Job $id created - background service will start after image upload');
        }
      }).catchError((error) {
        safeSetState(() {
          _showGenerationLoading = false;
          _currentJobId = null;
          _successMessageShown = false;
          _isProcessing = false;
          _showingLoadingMessage = false;
        });

        _showMessage('Error: ${error.toString()}', isError: true);
        _showGenerationFailedNotification();
      });

      safeSetState(() {
        _isProcessing = false;
        _showingLoadingMessage = false;
      });
    } catch (e) {
      _showMessage('Error: ${e.toString()}', isError: true);

      safeSetState(() {
        _showGenerationLoading = false;
        _currentJobId = null;
        _successMessageShown = false;
        _isProcessing = false;
        _showingLoadingMessage = false;
      });

      _showGenerationFailedNotification();
    }
  }

  void _startJobMonitoring(QueueManagerProvider queueManager) {
    _queueStatusSubscription?.cancel();
    _jobDocSubscription?.cancel();

    _queueStatusSubscription =
        Stream.periodic(const Duration(seconds: 2)).listen((_) async {
      if (_currentJobId == null || !mounted) return;

      try {
        final allJobs = queueManager.allJobs;
        final currentJob = allJobs.values.firstWhere(
          (job) => job.id == _currentJobId,
          orElse: () => throw StateError('Job not found'),
        );

        if (_jobDocSubscription == null && _currentJobId != null) {
          _jobDocSubscription = FirebaseFirestore.instance
              .collection('GenSpace_jobs')
              .doc(_currentJobId)
              .snapshots()
              .listen((snapshot) {
            if (!mounted) return;
            final data = snapshot.data();
            if (data != null &&
                data['conversionId'] != null &&
                data['conversionId'].toString().isNotEmpty) {
              safeSetState(() {
                _showGenerationLoading = false;
                _isProcessing = false;
                _showingLoadingMessage = false;
              });

              if (!_successMessageShown) {
                _successMessageShown = true;
                _showMessage(
                    'GenSpace submitted successfully!\nProcessing continues in background.');
              }

              _resetFormForNewGenSpace();

              _jobDocSubscription?.cancel();
              _jobDocSubscription = null;
            }
          });
        }

        if (currentJob.status == 'completed') {
          _onJobCompleted(true);
        } else if (currentJob.status == 'failed') {
          _onJobCompleted(false);
        }
      } catch (e) {
        _onJobCompleted(true);
      }
    });
  }

  void _onJobCompleted(bool success) async {
    _queueStatusSubscription?.cancel();
    _jobDocSubscription?.cancel();

    // Stop background service when job is completed (success or failure)
    // Always stop to ensure no persistent notifications
    try {
      await BackgroundGenSpaceService.stopService();
      if (kDebugMode) print('✅ Background service stopped after job completion (success: $success)');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to stop background service: $e');
    }

    safeSetState(() {
      _currentJobId = null;
      _successMessageShown = false;
    });

    if (success) {
      _showMessage(
          'GenSpace generated successfully!\nCheck the exports page for your results.');
    } else {
      _showMessage('GenSpace generation failed. Please try again.',
          isError: true);
      _showGenerationFailedNotification();
    }
  }

  Future<void> _showGenerationFailedNotification() async {
    try {
      await NotificationService.showNotification(
        title: 'Generate GenSpace Failed',
        body:
            'Your GenSpace generation was unsuccessful. Please try again or contact support if the issue persists.',
        id: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Failed to show notification: $e');
      }
    }
  }

  // Removed _clearForm() - replaced with _resetFormForNewGenSpace() which preserves user preferences

  void _showInsufficientCreditsDialog(
      double currentBalance, double requiredCredits) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 32,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Insufficient Credits',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(
                        text:
                            'Your wallet balance is low. Please add credits to your wallet.\n\n'),
                    const TextSpan(
                      text: 'Current Balance: ',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    TextSpan(
                      text:
                          '${currentBalance.toStringAsFixed(currentBalance % 1 == 0 ? 0 : 1)} Credits\n',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                    const TextSpan(
                      text: 'Required: ',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    TextSpan(
                      text:
                          '${requiredCredits.toStringAsFixed(requiredCredits % 1 == 0 ? 0 : 1)} Credits',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B68C0),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/pricing');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B68C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Add Credits',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
