# Webhook-Based Credit Flow Implementation

## Overview

This document describes the implementation of the new webhook-based credit usage flow for AI generation services. The new flow ensures that credits are only deducted after successful completion of AI generation tasks, providing better user experience and preventing credit loss on failed generations.

## Architecture Changes

### Previous Flow (Immediate Credit Deduction)

```
1. User initiates generation
2. Credits deducted immediately after receiving conversionId
3. Background service polls for completion
4. Results saved when complete
```

**Issues:**

- Credits deducted before knowing if generation will succeed
- If API fails, credits are already gone
- No real-time completion handling

### New Flow (Webhook-Based Credit Deduction)

```
1. User initiates generation
2. AI generation API called with webhook callback URL
3. No immediate credit deduction
4. AI service processes generation
5. AI service calls webhook with completion data
6. Webhook deducts credits and saves results
7. User receives real-time notification
```

**Benefits:**

- Credits only deducted after successful completion
- Real-time completion notifications
- Better error handling and recovery
- Improved user experience

## Implementation Details

### 1. Firebase Functions

#### `aiGenerationWebhook` (`functions/src/ai-generation-webhook.ts`)

- Handles webhook events from AI generation service
- Processes completion, failure, and progress events
- Deducts credits only after successful completion
- Saves results to Firestore
- Sends user notifications

#### `aiCompletionHandler` (`functions/src/ai-completion-handler.ts`)

- Alternative endpoint for AI service completion calls
- Handles direct completion notifications
- Calculates actual credit cost based on generated content
- Provides detailed credit breakdown

#### `webhook-security.ts`

- Security utilities for webhook verification
- Signature validation using HMAC-SHA256
- Payload validation and sanitization
- Security event logging

### 2. Flutter Services

#### `WebhookAIService` (`lib/core/services/webhook_ai_service.dart`)

- New service for webhook-based AI generation
- Calls AI generation API with webhook callback URL
- No immediate credit deduction
- Handles webhook URL generation

#### Updated `FashionAIService`

- Removed immediate credit deduction
- Credits marked as pending until webhook completion
- Updated logging and status messages

#### Updated `BackgroundGenSpaceService`

- Added webhook-based processing support
- New method `startWebhookBasedProcessing()`
- Handles webhook-enabled jobs differently

### 3. Credit Calculation

Credits are now calculated based on actual generated content:

```typescript
function calculateActualCreditCost(
  requestData: any,
  actualResults: any
): number {
  let totalCost = 0;

  // Cost for actually generated images
  const actualImageCount = actualResults.generatedImages?.length || 0;
  totalCost += actualImageCount * 1.0; // 1 credit per image

  // Video generation cost (only if video was actually generated)
  if (actualResults.hasVideo) {
    totalCost += 2.0; // 2 credits for video
  }

  // Excel generation cost (only if Excel was actually generated)
  if (actualResults.hasExcel) {
    totalCost += 0.5; // 0.5 credits for Excel
  }

  return totalCost;
}
```

### 4. Security Implementation

#### Webhook Signature Verification

```typescript
const expectedSignature = crypto
  .createHmac("sha256", webhookSecret.value())
  .update(body)
  .digest("hex");

const isValid = crypto.timingSafeEqual(
  Buffer.from(signature, "hex"),
  Buffer.from(expectedSignature, "hex")
);
```

#### Payload Validation

- Validates required fields (jobId, event, status)
- Sanitizes input data to prevent injection attacks
- Logs security events for monitoring

## API Integration

### AI Generation API Call

The AI generation API is called with a webhook callback URL:

```json
{
    "inputImages": [...],
    "text": "product description",
    "numberOfOutputs": 3,
    "isVideo": true,
    "generateCsv": true,
    "webhookUrl": "https://your-project.cloudfunctions.net/aiCompletionHandler",
    "webhookEvents": ["generation.completed", "generation.failed", "generation.progress"]
}
```

### Webhook Payload Structure

#### Completion Event

```json
{
  "status": "completed",
  "jobId": "SKU-ABCD-1234",
  "conversionId": "conv_12345",
  "generatedImages": [{ "imageSrc": "https://...", "type": "generated" }],
  "generatedVideos": [{ "videoUrl": "https://...", "type": "generated" }],
  "csv": "https://...",
  "description": "Generated product description",
  "keyFeatures": ["feature1", "feature2"],
  "searchKeywords": ["keyword1", "keyword2"]
}
```

#### Failure Event

```json
{
  "status": "failed",
  "jobId": "SKU-ABCD-1234",
  "conversionId": "conv_12345",
  "reason": "Insufficient image quality",
  "error": "Detailed error message"
}
```

## Database Schema Changes

### GenSpace_jobs Collection

New fields added:

- `webhookEnabled`: boolean - indicates if webhook is enabled
- `webhookUrl`: string - webhook callback URL
- `creditsPending`: boolean - credits are pending deduction
- `creditsDeductionMethod`: string - method used for credit deduction
- `completedViaWebhook`: boolean - completed via webhook
- `actualCreditCost`: number - actual credits deducted
- `creditsDeductedAt`: timestamp - when credits were deducted

### creditTransactions Collection

Enhanced with:

- `operationType`: "webhook_deduction"
- `jobId`: reference to the job
- `actualResults`: what was actually generated
- `creditBreakdown`: detailed cost breakdown

## Deployment Steps

### 1. Deploy Firebase Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

### 2. Set Environment Secrets

```bash
firebase functions:secrets:set AI_GENERATION_WEBHOOK_SECRET
firebase functions:secrets:set AI_COMPLETION_WEBHOOK_SECRET
firebase functions:secrets:set FASHION_AI_API_KEY
firebase functions:secrets:set FASHION_AI_BASE_URL
```

### 3. Update AI Generation Service

Configure the AI generation service to call the webhook endpoints:

- `https://your-project.cloudfunctions.net/aiGenerationWebhook`
- `https://your-project.cloudfunctions.net/aiCompletionHandler`

### 4. Update Flutter App

- Deploy updated Flutter services
- Test webhook-based generation flow
- Verify credit deduction timing

## Testing

### 1. Unit Tests

- Test webhook signature verification
- Test credit calculation logic
- Test payload validation

### 2. Integration Tests

- Test complete webhook flow
- Test credit deduction timing
- Test error handling scenarios

### 3. End-to-End Tests

- Test user-initiated generation
- Verify webhook completion
- Confirm credit deduction
- Check user notifications

## Monitoring and Logging

### Security Events

- Webhook signature verification failures
- Invalid payload attempts
- Unauthorized access attempts

### Business Events

- Credit deduction events
- Generation completion events
- User notification events

### Performance Metrics

- Webhook response times
- Credit deduction processing time
- Generation completion rates

## Rollback Plan

If issues arise with the webhook flow:

1. **Immediate Rollback**: Revert to immediate credit deduction
2. **Gradual Migration**: Use feature flags to control webhook usage
3. **Data Recovery**: Ensure credit transactions are properly logged

## Future Enhancements

1. **Retry Logic**: Implement webhook retry mechanisms
2. **Rate Limiting**: Add rate limiting for webhook endpoints
3. **Analytics**: Enhanced analytics for webhook performance
4. **Multi-Provider**: Support for multiple AI generation providers

## Conclusion

The webhook-based credit flow provides a more reliable and user-friendly approach to credit management. By only deducting credits after successful completion, users are protected from losing credits on failed generations, while the real-time webhook notifications provide immediate feedback on generation status.

The implementation includes comprehensive security measures, detailed logging, and proper error handling to ensure a robust and reliable system.
