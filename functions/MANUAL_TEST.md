# Manual Testing Guide for 20% Bonus Credit System

## 🧪 Test Results Summary

### ✅ Core Logic Test (PASSED)

The core calculation logic has been tested and works correctly:

```
Quarterly Plan: 20 credits/month × 3 months = 60 total credits
Bonus: 60 × 0.20 = 12 extra credits
Total: 60 + 12 = 72 credits
Monthly: 72 ÷ 3 = 24 credits/month
```

### 📊 Test Cases Verified:

1. **Quarterly Plan**: 20×3 = 60 + 12 bonus = 72 total → 24/month ✅
2. **6-Month Plan**: 50×6 = 300 + 60 bonus = 360 total → 60/month ✅
3. **Yearly Plan**: 100×12 = 1200 + 240 bonus = 1440 total → 120/month ✅
4. **Monthly Plan**: 10×1 = 10 + 2 bonus = 12 total → 12/month ✅

## 🚀 How to Test the Firebase Function

### Option 1: Using Firebase Emulator

```bash
# Start the emulator
firebase emulators:start --only functions

# In another terminal, test the function
node test-firebase-function.js
```

### Option 2: Using curl

```bash
curl -X POST http://localhost:5001/your-project-id/us-central1/planPurchaseWebhook \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "test-user-123",
    "planName": "Quarterly Plan",
    "planType": "Monthly Plan",
    "billingPeriod": "Quarterly",
    "creditsPerMonth": 20,
    "durationMonths": 3
  }'
```

### Option 3: Deploy and Test

```bash
# Deploy the function
firebase deploy --only functions:planPurchaseWebhook

# Test with actual Firebase project
curl -X POST https://us-central1-your-project-id.cloudfunctions.net/planPurchaseWebhook \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "test-user-123",
    "planName": "Quarterly Plan",
    "planType": "Monthly Plan",
    "billingPeriod": "Quarterly",
    "creditsPerMonth": 20,
    "durationMonths": 3
  }'
```

## 📋 Expected Response

```json
{
  "success": true,
  "data": {
    "userId": "test-user-123",
    "planName": "Quarterly Plan",
    "totalCreditsWithBonus": 72,
    "bonusCredits": 12,
    "monthlyCredits": 24,
    "durationMonths": 3
  }
}
```

## 🔍 What to Verify

1. ✅ Bonus calculation: 20% of total plan credits
2. ✅ Monthly distribution: Total credits ÷ duration (rounded up)
3. ✅ User document updated with subscription data
4. ✅ Transaction logged in creditTransactions collection
5. ✅ System flags initialized for tracking

## 🎯 Integration Points

- ✅ Integrated with existing Razorpay webhook system
- ✅ Updates existing `processSubscription` function
- ✅ Maintains backward compatibility
- ✅ Adds comprehensive tracking data

## 📝 Next Steps

After successful testing:

1. Commit Feature #1: 20% Bonus Credit System
2. Move to Feature #2: Monthly Credit Allocation with Rollover
3. Implement scheduled cron jobs for monthly processing

## 🐛 Troubleshooting

- **Build errors**: Check TypeScript version compatibility
- **Connection refused**: Ensure Firebase emulator is running
- **Function not found**: Verify function is deployed correctly
- **Permission errors**: Check Firebase project permissions
