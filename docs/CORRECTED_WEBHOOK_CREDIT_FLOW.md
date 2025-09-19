# Corrected Webhook-Based Credit Flow Implementation

## Problem Identified

The initial webhook implementation had a critical flaw:

- **Issue**: Credits were not checked before calling the AI generation API
- **Risk**: Users could initiate generation without sufficient credits, wasting API resources
- **Consequence**: API processing would occur even if user couldn't afford the generation

## Corrected Flow

### New Proper Credit Flow:

```
1. User initiates generation request
2. Call Generation Initiator Webhook
3. Check user credit balance
4. If insufficient credits → Reject request immediately
5. If sufficient credits → Deduct credits and mark as PENDING
6. Call AI generation API
7. If API call fails → Refund credits
8. If API call succeeds → Wait for completion webhook
9. On completion → Update transaction status to COMPLETED
10. On failure → Refund credits and update status to REFUNDED
```

## Implementation Details

### 1. Generation Initiator Webhook (`aiGenerationInitiator`)

**Purpose**: Validates credits and initiates generation before calling AI API

**Flow**:

1. **Credit Validation**: Check if user has sufficient credits
2. **Credit Deduction**: Deduct credits and mark transaction as `PENDING`
3. **API Call**: Call AI generation API with completion webhook
4. **Error Handling**: Refund credits if API call fails

**Key Features**:

- ✅ **Pre-validation**: Credits checked before API call
- ✅ **Pending Status**: Credits deducted but marked as pending
- ✅ **Immediate Refund**: Credits refunded if API call fails
- ✅ **Detailed Logging**: Complete transaction history

### 2. Completion Handler (`aiCompletionHandler`)

**Purpose**: Handles completion events and updates transaction status

**Flow**:

1. **Check Pending Transaction**: Look for existing pending credit transaction
2. **Update Status**: Change from `PENDING` to `COMPLETED` or `REFUNDED`
3. **Save Results**: Store generation results in Firestore
4. **Send Notifications**: Notify user of completion/failure

**Key Features**:

- ✅ **Status Updates**: Proper transaction status management
- ✅ **Refund Logic**: Automatic refunds for failed generations
- ✅ **Result Storage**: Complete generation results saved
- ✅ **User Notifications**: Real-time completion notifications

### 3. Credit Transaction States

```
PENDING → COMPLETED (successful generation)
PENDING → REFUNDED (failed generation)
```

**Transaction Fields**:

- `status`: "pending" | "completed" | "refunded"
- `operationType`: "pending_deduction" | "failed_job_refund"
- `actualResults`: What was actually generated
- `completionDetails`: Webhook processing details

## Database Schema Updates

### GenSpace_jobs Collection

```javascript
{
  // Existing fields...
  status: "pending" | "processing" | "completed" | "failed",
  creditsDeducted: true,
  creditsDeductedAt: timestamp,
  creditsAmount: number,
  creditBalanceAfter: number,
  pendingAt: timestamp,
  creditsRefunded: boolean,
  creditsRefundedAt: timestamp,
  creditsRefundAmount: number,
  failureReason: string,
  creditCheckFailed: boolean,
  requiredCredits: number,
  availableCredits: number
}
```

### creditTransactions Collection

```javascript
{
  userId: string,
  type: "deduction" | "refund",
  amount: number,
  balanceBefore: number,
  balanceAfter: number,
  timestamp: timestamp,
  reason: string,
  operationType: "pending_deduction" | "failed_job_refund",
  jobId: string,
  status: "pending" | "completed" | "refunded",
  requestData: object,
  actualResults: object,
  completionDetails: object,
  refundReason: string
}
```

## API Integration

### Generation Initiator Request

```json
POST /aiGenerationInitiator
{
  "jobId": "SKU-ABCD-1234",
  "userId": "user123",
  "requestData": {
    "text": "product description",
    "imagesToGenerate": 3,
    "generateVideo": true,
    "generateCsv": true,
    "productType": "clothing",
    "gender": "Male"
  },
  "uploadedImageUrls": ["https://..."],
  "creditCost": 5.5
}
```

### Generation Initiator Response

```json
{
  "success": true,
  "message": "Generation initiated successfully",
  "conversionId": "conv_12345",
  "creditsDeducted": 5.5,
  "newBalance": 94.5
}
```

### Completion Webhook Payload

```json
{
  "status": "completed",
  "jobId": "SKU-ABCD-1234",
  "conversionId": "conv_12345",
  "generatedImages": [...],
  "generatedVideos": [...],
  "csv": "https://...",
  "description": "...",
  "keyFeatures": [...],
  "searchKeywords": [...]
}
```

## Error Handling

### Insufficient Credits

```json
{
  "success": false,
  "error": "insufficient_credits",
  "message": "Insufficient credits. Required: 5.5, Available: 2.0",
  "requiredCredits": 5.5,
  "availableCredits": 2.0
}
```

### API Call Failure

```json
{
  "success": false,
  "error": "api_call_failed",
  "message": "AI generation API unavailable",
  "creditsRefunded": true
}
```

### Generation Failure

- Credits automatically refunded
- Transaction status updated to "refunded"
- User notified of failure and refund

## Security Features

### Webhook Signature Verification

- HMAC-SHA256 signature validation
- Prevents unauthorized webhook calls
- Comprehensive security logging

### Payload Validation

- Required field validation
- Data type checking
- Input sanitization

### Transaction Integrity

- Atomic credit operations
- Rollback on failures
- Complete audit trail

## Benefits of Corrected Flow

### For Users

- ✅ **No Wasted Credits**: Credits only charged for successful generations
- ✅ **Immediate Feedback**: Know immediately if insufficient credits
- ✅ **Automatic Refunds**: Failed generations automatically refunded
- ✅ **Transparent Billing**: Clear transaction history

### For System

- ✅ **Resource Protection**: No API calls without sufficient credits
- ✅ **Cost Control**: Prevents unnecessary API usage
- ✅ **Reliability**: Proper error handling and recovery
- ✅ **Auditability**: Complete transaction logging

### For Business

- ✅ **Revenue Protection**: No lost revenue from failed generations
- ✅ **User Trust**: Transparent and fair credit system
- ✅ **Operational Efficiency**: Reduced support tickets
- ✅ **Scalability**: Proper resource management

## Deployment Checklist

### Firebase Functions

- [ ] Deploy `aiGenerationInitiator`
- [ ] Deploy `aiCompletionHandler`
- [ ] Set webhook secrets
- [ ] Configure API endpoints

### Flutter App

- [ ] Update webhook service
- [ ] Test credit validation
- [ ] Verify refund flow
- [ ] Test error handling

### AI Generation Service

- [ ] Configure completion webhook URL
- [ ] Test webhook callbacks
- [ ] Verify signature generation
- [ ] Test error scenarios

## Testing Scenarios

### 1. Sufficient Credits

- User has enough credits
- Generation succeeds
- Credits deducted and marked completed

### 2. Insufficient Credits

- User lacks credits
- Request rejected immediately
- No API call made

### 3. API Failure

- Credits deducted
- API call fails
- Credits automatically refunded

### 4. Generation Failure

- Credits deducted
- API call succeeds
- Generation fails
- Credits automatically refunded

### 5. Generation Success

- Credits deducted
- API call succeeds
- Generation completes
- Transaction marked as completed

## Conclusion

The corrected webhook-based credit flow ensures:

- **Credit validation before API calls**
- **Proper transaction state management**
- **Automatic refunds for failures**
- **Complete audit trail**
- **Enhanced user experience**

This implementation provides a robust, fair, and transparent credit system that protects both users and the business while ensuring reliable AI generation services.
