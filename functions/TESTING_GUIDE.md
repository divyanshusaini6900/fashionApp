# Webhook-Based Credit Flow Testing Guide

## 🧪 Testing Overview

This guide helps you test the complete webhook-based credit flow with detailed usage tracking.

## 📋 Prerequisites

1. **Firebase Functions Deployed**: All webhook functions must be deployed
2. **Environment Variables Set**:
   - `AI_GENERATION_WEBHOOK_SECRET`
   - `AI_COMPLETION_WEBHOOK_SECRET`
   - `FASHION_AI_API_KEY`
   - `FASHION_AI_BASE_URL`
3. **Test Data**: Use the setup script to create test data

## 🚀 Step-by-Step Testing

### Step 1: Deploy Firebase Functions

```bash
# Build the functions
npm run build

# Deploy all functions
firebase deploy --only functions

# Or deploy specific functions
firebase deploy --only functions:aiGenerationInitiator
firebase deploy --only functions:aiCompletionHandler
firebase deploy --only functions:getUserCreditUsageAnalytics
firebase deploy --only functions:getAdminCreditUsageStats
```

### Step 2: Set Environment Secrets

```bash
# Set webhook secrets
firebase functions:secrets:set AI_GENERATION_WEBHOOK_SECRET
firebase functions:secrets:set AI_COMPLETION_WEBHOOK_SECRET

# Set API credentials
firebase functions:secrets:set FASHION_AI_API_KEY
firebase functions:secrets:set FASHION_AI_BASE_URL
```

### Step 3: Setup Test Data

```bash
# Install dependencies
npm install axios firebase-admin

# Setup test data
node setup-test-data.js
```

### Step 4: Test Individual Components

#### Test 1: AI Generation Initiator

```bash
# Test the initiator webhook
node test-webhook-flow.js initiator
```

**Expected Response**:

```json
{
  "success": true,
  "message": "Generation initiated successfully",
  "conversionId": "conv_abc123",
  "creditsDeducted": 10,
  "newBalance": 90
}
```

**Check Firestore**:

- `users` collection: User's credit balance should be reduced
- `creditTransactions` collection: New transaction with `status: "pending"`
- `GenSpace_jobs` collection: Job status should be "processing"

#### Test 2: AI Completion Handler

```bash
# Test the completion webhook
node test-webhook-flow.js completion
```

**Expected Response**:

```json
{
  "success": true,
  "message": "OK"
}
```

**Check Firestore**:

- `creditTransactions` collection: Transaction status should be "completed"
- `GenSpace_jobs` collection: Job status should be "completed"
- `notifications` collection: New notification should be created

#### Test 3: User Analytics

```bash
# Test user credit usage analytics
node test-webhook-flow.js user-analytics
```

**Expected Response**:

```json
{
  "success": true,
  "data": {
    "userId": "test_user_123",
    "summary": {
      "totalCreditsUsed": 10,
      "totalJobs": 1,
      "totalImages": 3,
      "totalVideos": 1,
      "totalExcels": 0
    },
    "breakdown": {
      "images": {
        "totalCredits": 3,
        "totalGenerated": 3,
        "averagePerJob": 3
      },
      "video": {
        "totalCredits": 5,
        "totalGenerated": 1,
        "averagePerJob": 5
      },
      "excel": {
        "totalCredits": 0,
        "totalGenerated": 0,
        "averagePerJob": 0
      }
    }
  }
}
```

#### Test 4: Admin Statistics

```bash
# Test admin credit usage statistics
node test-webhook-flow.js admin-stats
```

**Expected Response**:

```json
{
  "success": true,
  "data": {
    "summary": {
      "totalCreditsUsed": 10,
      "totalJobs": 1,
      "uniqueUsers": 1,
      "averageCreditsPerJob": 10,
      "averageCreditsPerUser": 10
    },
    "featureStats": {
      "images": {
        "totalCredits": 3,
        "totalGenerated": 3,
        "jobs": 1
      },
      "video": {
        "totalCredits": 5,
        "totalGenerated": 1,
        "jobs": 1
      },
      "excel": {
        "totalCredits": 0,
        "totalGenerated": 0,
        "jobs": 0
      }
    }
  }
}
```

#### Test 5: Failed Generation

```bash
# Test failed generation handling
node test-webhook-flow.js failed
```

**Expected Response**:

```json
{
  "success": true,
  "message": "OK"
}
```

**Check Firestore**:

- `creditTransactions` collection: Original transaction should be "refunded"
- New refund transaction should be created
- `GenSpace_jobs` collection: Job status should be "failed"

### Step 5: Run Complete Test Suite

```bash
# Run all tests
node test-webhook-flow.js
```

## 🔍 Manual Testing with Postman/curl

### Test Generation Initiator

```bash
curl -X POST https://us-central1-techrelieve-90c12.cloudfunctions.net/aiGenerationInitiator \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Signature: your-signature" \
  -d '{
    "jobId": "test_job_123",
    "userId": "test_user_123",
    "requestData": {
      "generateVideo": true,
      "generateCsv": true,
      "imagesToGenerate": 3,
      "text": "Test product description"
    },
    "uploadedImageUrls": ["https://example.com/test-image.jpg"],
    "creditCost": 10
  }'
```

### Test Completion Handler

```bash
curl -X POST https://us-central1-techrelieve-90c12.cloudfunctions.net/aiCompletionHandler \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Signature: your-signature" \
  -d '{
    "jobId": "test_job_123",
    "conversionId": "conv_abc123",
    "status": "completed",
    "generatedImages": [
      {"imageSrc": "https://example.com/generated-1.jpg"},
      {"imageSrc": "https://example.com/generated-2.jpg"},
      {"imageSrc": "https://example.com/generated-3.jpg"}
    ],
    "generatedVideos": [
      {"videoUrl": "https://example.com/generated-video.mp4"}
    ],
    "csv": null,
    "description": "Generated test product description"
  }'
```

## 📊 Testing Credit Flow Scenarios

### Scenario 1: Successful Generation

1. User has 100 credits
2. Requests: 3 images + 1 video + 1 Excel (10 credits)
3. AI generates: 3 images + 1 video + 0 Excel (8 credits)
4. **Result**: User charged 10 credits, 8 actually used

### Scenario 2: Insufficient Credits

1. User has 5 credits
2. Requests: 3 images + 1 video + 1 Excel (10 credits)
3. **Result**: Job fails immediately, no credits deducted

### Scenario 3: Partial Generation Failure

1. User has 100 credits
2. Requests: 3 images + 1 video + 1 Excel (10 credits)
3. AI generates: 3 images + 0 video + 1 Excel (5 credits)
4. **Result**: User charged 10 credits, 5 actually used

### Scenario 4: Complete Generation Failure

1. User has 100 credits
2. Requests: 3 images + 1 video + 1 Excel (10 credits)
3. AI fails completely
4. **Result**: User refunded 10 credits

## 🐛 Troubleshooting

### Common Issues

1. **Signature Verification Failed**

   - Check webhook secrets are set correctly
   - Verify signature generation in test script

2. **User Not Found**

   - Ensure test user exists in Firestore
   - Check user ID matches in test data

3. **Insufficient Credits**

   - Verify user has enough credits for test
   - Check credit cost calculation

4. **Job Not Found**
   - Ensure job document exists in Firestore
   - Check job ID matches in requests

### Debug Commands

```bash
# Check function logs
firebase functions:log --only aiGenerationInitiator
firebase functions:log --only aiCompletionHandler

# Check Firestore data
# Use Firebase Console or Firestore emulator
```

## 🧹 Cleanup

```bash
# Clean up test data
node setup-test-data.js cleanup
```

## ✅ Success Criteria

- [ ] Generation initiator deducts credits and creates pending transaction
- [ ] Completion handler updates transaction to completed
- [ ] Failed generation refunds credits
- [ ] Analytics functions return correct data
- [ ] Backward compatibility with legacy transactions
- [ ] All webhook security validations pass
- [ ] Notifications are created for users

## 📈 Performance Testing

For production testing, consider:

1. **Load Testing**: Test with multiple concurrent requests
2. **Error Handling**: Test with invalid data, network failures
3. **Security Testing**: Test with invalid signatures, malformed payloads
4. **Data Consistency**: Verify credit balances remain consistent under load

## 🔐 Security Testing

1. **Signature Validation**: Test with invalid signatures
2. **Payload Validation**: Test with malformed data
3. **Rate Limiting**: Test with rapid requests
4. **Input Sanitization**: Test with malicious input

---

**Note**: The test scripts are already configured with your Firebase Functions URL: `https://us-central1-techrelieve-90c12.cloudfunctions.net`
