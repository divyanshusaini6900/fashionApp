import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to fetch and manage discount percentages from Firebase
class DiscountService extends ChangeNotifier {
  static final DiscountService _instance = DiscountService._internal();
  factory DiscountService() => _instance;
  DiscountService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _discountSubscription;
  StreamSubscription? _creditPricingSubscription;
  
  // Discount data from Firebase
  Map<String, int> _imageDiscounts = {};
  Map<String, int> _videoDiscounts = {};
  Map<String, int> _excelDiscounts = {};
  
  // Credit pricing data from Firebase creditUsage document
  Map<String, dynamic> _creditPricing = {};
  
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;

  // Getters
  Map<String, int> get imageDiscounts => _imageDiscounts;
  Map<String, int> get videoDiscounts => _videoDiscounts;
  Map<String, int> get excelDiscounts => _excelDiscounts;
  Map<String, dynamic> get creditPricing => _creditPricing;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Initialize the discount service and start listening to Firebase
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

             // Start listening to discount changes in real-time
       _discountSubscription = _firestore
           .collection('discount')
           .snapshots()
           .listen(_onDiscountDataChanged, onError: _onDiscountError);

       // Start listening to credit pricing changes in real-time
       _creditPricingSubscription = _firestore
           .collection('credits')
           .doc('creditUsage')
           .snapshots()
           .listen(_onCreditPricingChanged, onError: _onCreditPricingError);

       _isInitialized = true;
      if (kDebugMode) print('✅ DiscountService initialized');
      
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) print('❌ DiscountService initialization failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Handle discount data changes from Firebase
  void _onDiscountDataChanged(QuerySnapshot snapshot) {
    try {
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        switch (doc.id) {
          case 'image':
            _imageDiscounts = _parseDiscountData(data);
            break;
          case 'video':
            _videoDiscounts = _parseDiscountData(data);
            break;
          case 'excel':
            _excelDiscounts = _parseDiscountData(data);
            break;
        }
      }
      
      _error = null;
      notifyListeners();
      
      if (kDebugMode) {
        print('✅ Discount data updated:');
        print('   Image discounts: $_imageDiscounts');
        print('   Video discounts: $_videoDiscounts');
        print('   Excel discounts: $_excelDiscounts');
      }
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) print('❌ Error parsing discount data: $e');
      notifyListeners();
    }
  }

  /// Parse discount data from Firebase document
  Map<String, int> _parseDiscountData(Map<String, dynamic> data) {
    final Map<String, int> discounts = {};
    
    data.forEach((key, value) {
      if (value is int) {
        discounts[key] = value;
      } else if (value is double) {
        discounts[key] = value.toInt();
      } else if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          discounts[key] = parsed;
        }
      }
    });
    
    return discounts;
  }

     /// Handle Firebase errors
   void _onDiscountError(dynamic error) {
     _error = error.toString();
     if (kDebugMode) print('❌ Discount service Firebase error: $error');
     notifyListeners();
   }

   /// Handle credit pricing data changes from Firebase
   void _onCreditPricingChanged(DocumentSnapshot snapshot) {
     try {
       if (snapshot.exists && snapshot.data() != null) {
         _creditPricing = snapshot.data() as Map<String, dynamic>;
         
         if (kDebugMode) {
           print('✅ Credit pricing updated: $_creditPricing');
         }
         
         _error = null;
         notifyListeners();
       }
     } catch (e) {
       _error = e.toString();
       if (kDebugMode) print('❌ Error parsing credit pricing data: $e');
       notifyListeners();
     }
   }

   /// Handle Firebase credit pricing errors
   void _onCreditPricingError(dynamic error) {
     _error = error.toString();
     if (kDebugMode) print('❌ Credit pricing service Firebase error: $error');
     notifyListeners();
   }

  /// Get image discount percentage for specific quantity
  double getImageDiscountPercent(int imageCount) {
    final key = '${imageCount}image';
    final discountValue = _imageDiscounts[key] ?? 0;
    return discountValue / 100.0; // Convert to percentage (20 -> 0.20)
  }

  /// Get video discount percentage
  double getVideoDiscountPercent() {
    // Assuming video discount is stored with a specific key
    final discountValue = _videoDiscounts['video'] ?? _videoDiscounts['1video'] ?? 0;
    return discountValue / 100.0;
  }

     /// Get Excel discount percentage
   double getExcelDiscountPercent() {
     // Assuming Excel discount is stored with a specific key
     final discountValue = _excelDiscounts['excel'] ?? _excelDiscounts['1excel'] ?? 0;
     return discountValue / 100.0;
   }

   /// Get credit pricing from Firebase creditUsage document (supports decimal values)
   double getImageCreditPrice() {
     final dynamic imagePrice = _creditPricing['image'];
     if (imagePrice is double) return imagePrice;
     if (imagePrice is int) return imagePrice.toDouble();
     if (imagePrice is String) return double.tryParse(imagePrice) ?? 1.0;
     return 1.0; // Default fallback
   }



   double getExcelCreditPrice() {
     final dynamic excelPrice = _creditPricing['excel'];
     if (excelPrice is double) return excelPrice;
     if (excelPrice is int) return excelPrice.toDouble();
     if (excelPrice is String) return double.tryParse(excelPrice) ?? 0.5;
     return 0.5; // Default fallback
   }

     /// Calculate complete pricing with Firebase discounts
   PriceCalculation calculatePrice({
     required int imageCount,
     required bool includeExcel,
   }) {
     // Get base prices from Firebase creditUsage document
     final double imageBasePrice = getImageCreditPrice(); // per image
     final double excelBasePrice = getExcelCreditPrice();

    // Calculate image pricing
    final double totalImageBasePrice = imageCount * imageBasePrice;
    final double imageDiscountPercent = getImageDiscountPercent(imageCount);
    final double imageDiscountAmount = totalImageBasePrice * imageDiscountPercent;
    final double imagePriceAfterDiscount = totalImageBasePrice - imageDiscountAmount;

    // Calculate Excel pricing
    final double excelDiscountPercent = includeExcel ? getExcelDiscountPercent() : 0.0;
    final double excelDiscountAmount = includeExcel ? (excelBasePrice * excelDiscountPercent) : 0.0;
    final double excelPriceAfterDiscount = includeExcel ? (excelBasePrice - excelDiscountAmount) : 0.0;

    // Calculate totals
    final double totalBeforeDiscount = totalImageBasePrice + 
        (includeExcel ? excelBasePrice : 0.0);
    final double totalDiscountAmount = imageDiscountAmount + excelDiscountAmount;
    final double totalAfterDiscount = imagePriceAfterDiscount + excelPriceAfterDiscount;

    return PriceCalculation(
      imageCount: imageCount,
      imageBasePrice: imageBasePrice,
      imageTotal: totalImageBasePrice,
      imageDiscountPercent: imageDiscountPercent,
      imageDiscountAmount: imageDiscountAmount,
      imagePriceAfterDiscount: imagePriceAfterDiscount,
      
      videoPrice: 0.0,
      videoDiscountPercent: 0.0,
      videoDiscountAmount: 0.0,
      videoPriceAfterDiscount: 0.0,
      
      excelPrice: excelBasePrice,
      excelDiscountPercent: excelDiscountPercent,
      excelDiscountAmount: excelDiscountAmount,
      excelPriceAfterDiscount: excelPriceAfterDiscount,
      
      totalBeforeDiscount: totalBeforeDiscount,
      totalDiscountAmount: totalDiscountAmount,
      totalAfterDiscount: totalAfterDiscount,
    );
  }

     /// Dispose the service
   void dispose() {
     _discountSubscription?.cancel();
     _creditPricingSubscription?.cancel();
     _discountSubscription = null;
     _creditPricingSubscription = null;
     _isInitialized = false;
     super.dispose();
   }
}

/// Price calculation result with all discount details (supports decimal values)
class PriceCalculation {
  final int imageCount;
  final double imageBasePrice;
  final double imageTotal;
  final double imageDiscountPercent;
  final double imageDiscountAmount;
  final double imagePriceAfterDiscount;
  
  final double videoPrice;
  final double videoDiscountPercent;
  final double videoDiscountAmount;
  final double videoPriceAfterDiscount;
  
  final double excelPrice;
  final double excelDiscountPercent;
  final double excelDiscountAmount;
  final double excelPriceAfterDiscount;
  
  final double totalBeforeDiscount;
  final double totalDiscountAmount;
  final double totalAfterDiscount;

  const PriceCalculation({
    required this.imageCount,
    required this.imageBasePrice,
    required this.imageTotal,
    required this.imageDiscountPercent,
    required this.imageDiscountAmount,
    required this.imagePriceAfterDiscount,
    required this.videoPrice,
    required this.videoDiscountPercent,
    required this.videoDiscountAmount,
    required this.videoPriceAfterDiscount,
    required this.excelPrice,
    required this.excelDiscountPercent,
    required this.excelDiscountAmount,
    required this.excelPriceAfterDiscount,
    required this.totalBeforeDiscount,
    required this.totalDiscountAmount,
    required this.totalAfterDiscount,
  });

  // Convenience getters
  bool get hasImageDiscount => imageDiscountPercent > 0;
  bool get hasVideoDiscount => videoDiscountPercent > 0;
  bool get hasExcelDiscount => excelDiscountPercent > 0;
  bool get hasAnyDiscount => hasImageDiscount || hasVideoDiscount || hasExcelDiscount;
}
