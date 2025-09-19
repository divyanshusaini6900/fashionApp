import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  final String planName;
  final String planType;
  final String billingPeriod;
  final int creditsPerMonth;
  final int monthlyCredits;
  final DateTime startDate;
  final DateTime expiryDate;
  final bool isActive;
  final DateTime? lastPayment;
  final double creditRate;
  final double monthlyPrice;
  final List<Map<String, dynamic>>? individualPlans;

  const SubscriptionModel({
    required this.planName,
    required this.planType,
    required this.billingPeriod,
    required this.creditsPerMonth,
    required this.monthlyCredits,
    required this.startDate,
    required this.expiryDate,
    required this.isActive,
    this.lastPayment,
    required this.creditRate,
    required this.monthlyPrice,
    this.individualPlans,
  });

  factory SubscriptionModel.fromFirestore(Map<String, dynamic> data) {
    return SubscriptionModel(
      planName: data['planName'] ?? 'No Plan',
      planType: data['planType'] ?? 'Monthly Plan',
      billingPeriod: data['billingPeriod'] ?? 'Monthly',
      creditsPerMonth: data['creditsPerMonth'] ?? 0,
      monthlyCredits: data['monthlyCredits'] ?? 0,
      startDate: data['startDate'] != null
          ? (data['startDate'] as Timestamp).toDate()
          : DateTime.now(),
      expiryDate: data['expiryDate'] != null
          ? (data['expiryDate'] as Timestamp).toDate()
          : DateTime.now().add(const Duration(days: 30)),
      isActive: data['isActive'] ?? false,
      lastPayment: data['lastPayment'] != null
          ? (data['lastPayment'] as Timestamp).toDate()
          : null,
      creditRate: (data['creditRate'] ?? 165.0)
          .toDouble(), // Will be updated by fromFirestoreWithPricing
      monthlyPrice: (data['monthlyPrice'] ?? 8250.0)
          .toDouble(), // Will be updated by fromFirestoreWithPricing
      individualPlans: data['individualPlans'] != null
          ? List<Map<String, dynamic>>.from(data['individualPlans'])
          : null,
    );
  }

  // Async factory method to fetch pricing data from Firestore
  static Future<SubscriptionModel> fromFirestoreWithPricing(
      Map<String, dynamic> data) async {
    final planName = data['planName'];

    print('🚀 fromFirestoreWithPricing called for plan: $planName');
    print('📊 Existing creditRate in data: ${data['creditRate']}');
    print('📊 Existing monthlyPrice in data: ${data['monthlyPrice']}');

    // Fetch pricing data from Firestore
    final creditRate = data['creditRate'] != null
        ? (data['creditRate'] as num).toDouble()
        : await _getDefaultCreditRate(planName);

    final monthlyPrice = data['monthlyPrice'] != null
        ? (data['monthlyPrice'] as num).toDouble()
        : await _getDefaultMonthlyPrice(planName);

    print('💰 Final creditRate: $creditRate');
    print('💰 Final monthlyPrice: $monthlyPrice');

    return SubscriptionModel(
      planName: data['planName'] ?? 'No Plan',
      planType: data['planType'] ?? 'Monthly Plan',
      billingPeriod: data['billingPeriod'] ?? 'Monthly',
      creditsPerMonth: data['creditsPerMonth'] ?? 0,
      monthlyCredits: data['monthlyCredits'] ?? 0,
      startDate: data['startDate'] != null
          ? (data['startDate'] as Timestamp).toDate()
          : DateTime.now(),
      expiryDate: data['expiryDate'] != null
          ? (data['expiryDate'] as Timestamp).toDate()
          : DateTime.now().add(const Duration(days: 30)),
      isActive: data['isActive'] ?? false,
      lastPayment: data['lastPayment'] != null
          ? (data['lastPayment'] as Timestamp).toDate()
          : null,
      creditRate: creditRate,
      monthlyPrice: monthlyPrice,
      individualPlans: data['individualPlans'] != null
          ? List<Map<String, dynamic>>.from(data['individualPlans'])
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'planName': planName,
      'planType': planType,
      'billingPeriod': billingPeriod,
      'creditsPerMonth': creditsPerMonth,
      'monthlyCredits': monthlyCredits,
      'startDate': Timestamp.fromDate(startDate),
      'expiryDate': Timestamp.fromDate(expiryDate),
      'isActive': isActive,
      'lastPayment':
          lastPayment != null ? Timestamp.fromDate(lastPayment!) : null,
      'creditRate': creditRate,
      'monthlyPrice': monthlyPrice,
      'individualPlans': individualPlans,
    };
  }

  SubscriptionModel copyWith({
    String? planName,
    String? planType,
    String? billingPeriod,
    int? creditsPerMonth,
    int? monthlyCredits,
    DateTime? startDate,
    DateTime? expiryDate,
    bool? isActive,
    DateTime? lastPayment,
    double? creditRate,
    double? monthlyPrice,
    List<Map<String, dynamic>>? individualPlans,
  }) {
    return SubscriptionModel(
      planName: planName ?? this.planName,
      planType: planType ?? this.planType,
      billingPeriod: billingPeriod ?? this.billingPeriod,
      creditsPerMonth: creditsPerMonth ?? this.creditsPerMonth,
      monthlyCredits: monthlyCredits ?? this.monthlyCredits,
      startDate: startDate ?? this.startDate,
      expiryDate: expiryDate ?? this.expiryDate,
      isActive: isActive ?? this.isActive,
      lastPayment: lastPayment ?? this.lastPayment,
      creditRate: creditRate ?? this.creditRate,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      individualPlans: individualPlans ?? this.individualPlans,
    );
  }

  // Helper method to get the latest plan name (for UI display)
  String get displayPlanName {
    if (individualPlans != null && individualPlans!.isNotEmpty) {
      // Return the name of the latest plan (last in the array)
      final latestPlan = individualPlans!.last;
      return latestPlan['planName'] ?? planName;
    }
    return planName;
  }

  // Helper method to get default credit rate based on plan name from Firestore
  static Future<double> _getDefaultCreditRate(String? planName) async {
    if (planName == null) return 165.0;

    print('🔍 Fetching credit rate for plan: $planName');

    try {
      final firestore = FirebaseFirestore.instance;
      final querySnapshot = await firestore.collection('pricing_plans').get();

      print('📊 Found ${querySnapshot.docs.length} pricing plan documents');

      // Iterate through all documents to find matching planName
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        print(
            '📋 Checking document: ${doc.id} with planName: ${data['name']}');
        if (data['name'] == planName) {
          final creditRate = (data['creditRate'] ?? 165.0).toDouble();
          print('✅ Found matching plan! Credit rate: $creditRate');
          return creditRate;
        }
      }

      print('❌ No matching plan found for: $planName');
    } catch (e) {
      print('❌ Error fetching credit rate for $planName: $e');
    }

    return 165.0; // Default fallback
  }

  // Helper method to get default monthly price based on plan name from Firestore
  static Future<double> _getDefaultMonthlyPrice(String? planName) async {
    if (planName == null) return 8250.0;

    print('🔍 Fetching monthly price for plan: $planName');

    try {
      final firestore = FirebaseFirestore.instance;
      final querySnapshot = await firestore.collection('pricing_plans').get();

      print('📊 Found ${querySnapshot.docs.length} pricing plan documents');

      // Iterate through all documents to find matching planName
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        print(
            '📋 Checking document: ${doc.id} with planName: ${data['name']}');
        if (data['name'] == planName) {
          final monthlyPrice = (data['monthlyPrice'] ?? 8250.0).toDouble();
          print('✅ Found matching plan! Monthly price: $monthlyPrice');
          return monthlyPrice;
        }
      }

      print('❌ No matching plan found for: $planName');
    } catch (e) {
      print('❌ Error fetching monthly price for $planName: $e');
    }

    return 8250.0; // Default fallback
  }
}

class CreditUsageModel {
  final int imagesUsed;
  final int videosUsed;
  final int excelUsed;
  final double imageRate;
  final double videoRate;
  final double excelRate;

  const CreditUsageModel({
    required this.imagesUsed,
    required this.videosUsed,
    required this.excelUsed,
    required this.imageRate,
    required this.videoRate,
    required this.excelRate,
  });

  factory CreditUsageModel.fromFirestore(Map<String, dynamic> data) {
    return CreditUsageModel(
      imagesUsed: data['imagesUsed'] ?? 0,
      videosUsed: data['videosUsed'] ?? 0,
      excelUsed: data['excelUsed'] ?? 0,
      imageRate: (data['imageRate'] ?? 1.0).toDouble(),
      videoRate: (data['videoRate'] ?? 1.0).toDouble(),
      excelRate: (data['excelRate'] ?? 0.5).toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'imagesUsed': imagesUsed,
      'videosUsed': videosUsed,
      'excelUsed': excelUsed,
      'imageRate': imageRate,
      'videoRate': videoRate,
      'excelRate': excelRate,
    };
  }
}

class RolloverModel {
  final int lastMonthUnused;
  final double rolloverPercentage;
  final int rolledCredits;
  final int lastRolloverCredits;

  const RolloverModel({
    required this.lastMonthUnused,
    required this.rolloverPercentage,
    required this.rolledCredits,
    required this.lastRolloverCredits,
  });

  factory RolloverModel.fromFirestore(Map<String, dynamic> data) {
    return RolloverModel(
      lastMonthUnused: data['lastMonthUnused'] ?? 0,
      rolloverPercentage: (data['rolloverPercentage'] ?? 50.0).toDouble(),
      rolledCredits: data['rolledCredits'] ?? 0,
      lastRolloverCredits: data['lastRolloverCredits'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'lastMonthUnused': lastMonthUnused,
      'rolloverPercentage': rolloverPercentage,
      'rolledCredits': rolledCredits,
      'lastRolloverCredits': lastRolloverCredits,
    };
  }
}

class WalletDataModel {
  final double creditBalance;
  final SubscriptionModel? subscription;
  final CreditUsageModel creditUsage;
  final RolloverModel rolloverData;

  const WalletDataModel({
    required this.creditBalance,
    this.subscription,
    required this.creditUsage,
    required this.rolloverData,
  });

  factory WalletDataModel.fromFirestore(Map<String, dynamic> data) {
    return WalletDataModel(
      creditBalance: (data['creditBalance'] ?? 0.0).toDouble(),
      subscription: data['subscription'] != null
          ? SubscriptionModel.fromFirestore(data['subscription'])
          : null,
      creditUsage: data['creditUsage'] != null
          ? CreditUsageModel.fromFirestore(data['creditUsage'])
          : const CreditUsageModel(
              imagesUsed: 0,
              videosUsed: 0,
              excelUsed: 0,
              imageRate: 1.0,
              videoRate: 1.0,
              excelRate: 0.5,
            ),
      rolloverData: data['rolloverData'] != null
          ? RolloverModel.fromFirestore(data['rolloverData'])
          : const RolloverModel(
              lastMonthUnused: 0,
              rolloverPercentage: 50.0,
              rolledCredits: 0,
              lastRolloverCredits: 0,
            ),
    );
  }

  // Async factory method to fetch subscription with pricing data from Firestore
  static Future<WalletDataModel> fromFirestoreWithPricing(
      Map<String, dynamic> data) async {
    print('🏦 WalletDataModel.fromFirestoreWithPricing called');
    print('📋 Subscription data exists: ${data['subscription'] != null}');

    SubscriptionModel? subscription;
    if (data['subscription'] != null) {
      subscription = await SubscriptionModel.fromFirestoreWithPricing(
          data['subscription']);
    }

    return WalletDataModel(
      creditBalance: (data['creditBalance'] ?? 0.0).toDouble(),
      subscription: subscription,
      creditUsage: data['creditUsage'] != null
          ? CreditUsageModel.fromFirestore(data['creditUsage'])
          : const CreditUsageModel(
              imagesUsed: 0,
              videosUsed: 0,
              excelUsed: 0,
              imageRate: 1.0,
              videoRate: 1.0,
              excelRate: 0.5,
            ),
      rolloverData: data['rolloverData'] != null
          ? RolloverModel.fromFirestore(data['rolloverData'])
          : const RolloverModel(
              lastMonthUnused: 0,
              rolloverPercentage: 50.0,
              rolledCredits: 0,
              lastRolloverCredits: 0,
            ),
    );
  }

  // Factory method to create from dynamic usage data
  factory WalletDataModel.fromDynamicUsage({
    required double creditBalance,
    required Map<String, dynamic> dynamicUsage,
    SubscriptionModel? subscription,
    RolloverModel? rolloverData,
  }) {
    return WalletDataModel(
      creditBalance: creditBalance,
      subscription: subscription,
      creditUsage: CreditUsageModel(
        imagesUsed: dynamicUsage['imagesUsed'] ?? 0,
        videosUsed: dynamicUsage['videosUsed'] ?? 0,
        excelUsed: dynamicUsage['excelUsed'] ?? 0,
        imageRate: (dynamicUsage['imageRate'] ?? 1.0).toDouble(),
        videoRate: (dynamicUsage['videoRate'] ?? 1.0).toDouble(),
        excelRate: (dynamicUsage['excelRate'] ?? 0.5).toDouble(),
      ),
      rolloverData: rolloverData ??
          const RolloverModel(
            lastMonthUnused: 0,
            rolloverPercentage: 50.0,
            rolledCredits: 0,
            lastRolloverCredits: 0,
          ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'creditBalance': creditBalance,
      'subscription': subscription?.toFirestore(),
      'creditUsage': creditUsage.toFirestore(),
      'rolloverData': rolloverData.toFirestore(),
    };
  }
}
