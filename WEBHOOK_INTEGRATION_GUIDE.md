# Webhook Integration Guide

## Overview

Your app now has a new webhook-based AI generation system that provides:

- ✅ **Credit-aware generation** - Checks and deducts credits before API calls
- ✅ **Dynamic credit rates** - Reads rates from your `credits/creditUsage` document
- ✅ **Proper error handling** - Refunds credits on failure
- ✅ **Detailed tracking** - Tracks both estimated and actual credit usage

## Integration Steps

### 1. New Webhook Service

The new `WebhookAIService` class handles all webhook communication:

```dart
import 'package:your_app/core/services/webhook_ai_service.dart';

final webhookService = WebhookAIService();
```

### 2. Updated FashionAIService

Your existing `FashionAIService` now has a new method `generateWithWebhook()`:

```dart
// OLD WAY (Direct API)
final jobId = await fashionAI.generateFashionGenSpace(
  text: 'Product description',
  productImages: images,
  // ... other parameters
);

// NEW WAY (Webhook-based with credit management)
final jobId = await fashionAI.generateWithWebhook(
  text: 'Product description',
  productImages: images,
  imagesToGenerate: 3,
  generateVideo: true,
  generateCsv: true,
  productType: 'general',
  gender: 'unisex',
);
```

### 3. Credit System Integration

The webhook system automatically:

- ✅ Fetches credit rates from `credits/creditUsage` document
- ✅ Calculates total cost: `(images × image_rate) + (video × video_rate) + (csv × excel_rate)`
- ✅ Checks user balance before generation
- ✅ Deducts credits with `pending` status
- ✅ Marks as `completed` on success or `refunded` on failure

### 4. Testing the Integration

Use the test class to verify everything works:

```dart
import 'package:your_app/core/services/webhook_integration_test.dart';

// Test webhook generation
await WebhookIntegrationTest.testWebhookGeneration();

// Compare old vs new methods
await WebhookIntegrationTest.compareGenerationMethods();

// Test credit calculations
await WebhookIntegrationTest.testCreditCalculation();
```

## Key Benefits

### 1. **Credit Safety**

- Credits are checked and deducted **before** API calls
- No more failed generations due to insufficient credits
- Automatic refunds on failure

### 2. **Dynamic Rates**

- Update credit rates anytime by modifying `credits/creditUsage` document
- No code changes needed for rate updates
- Consistent rates across all generation types

### 3. **Better Tracking**

- Detailed breakdown of credit usage per feature
- Both estimated and actual usage tracking
- Analytics-ready data structure

### 4. **Error Recovery**

- Proper error handling and user notifications
- Automatic cleanup on failures
- Detailed error logging

## Migration Strategy

### Phase 1: Parallel Testing

- Keep both systems running
- Test webhook system with a subset of users
- Compare results and performance

### Phase 2: Gradual Migration

- Switch new users to webhook system
- Monitor credit deduction accuracy
- Verify analytics data

### Phase 3: Full Migration

- Switch all users to webhook system
- Remove old direct API calls
- Clean up unused code

## Configuration

### Credit Rates Document

Make sure your `credits/creditUsage` document has:

```json
{
  "image": 1.0,
  "video": 1.0,
  "excel": 0.5,
  "updatedAt": "timestamp"
}
```

### Firebase Functions

Ensure these functions are deployed:

- `aiGenerationInitiator`
- `aiCompletionHandler`
- `getUserCreditUsageAnalytics`
- `getAdminCreditUsageStats`

## Monitoring

### Analytics Functions

Use the new analytics functions to monitor:

- User credit usage patterns
- Generation success rates
- Credit consumption by feature

```dart
// Get user analytics
final analytics = await getUserCreditUsageAnalytics(userId);

// Get admin stats
final adminStats = await getAdminCreditUsageStats();
```

## Troubleshooting

### Common Issues

1. **Webhook not available**

   - Check Firebase Functions deployment
   - Verify function URLs are correct

2. **Credit calculation errors**

   - Verify `credits/creditUsage` document exists
   - Check document structure matches expected format

3. **Generation failures**
   - Check user authentication
   - Verify image uploads are working
   - Review Firebase Functions logs

### Debug Mode

Enable debug logging to see detailed information:

```dart
if (kDebugMode) {
  print('Webhook generation initiated...');
}
```

## Next Steps

1. **Test the integration** using the provided test classes
2. **Update your UI** to use the new `generateWithWebhook()` method
3. **Monitor the system** using the analytics functions
4. **Gradually migrate** users to the new system

The webhook system is now ready for production use! 🚀
