# Credit Usage Tracking System

## Overview

The credit usage tracking system provides detailed analytics and reporting for how users consume credits across different AI generation features (images, videos, Excel reports). This system tracks both estimated and actual credit usage, providing comprehensive insights for users and administrators.

## Collections and Fields

### 1. `creditTransactions` Collection (Enhanced)

**Purpose**: Track all credit transactions with detailed usage breakdown

**Enhanced Fields**:

```typescript
{
  // Core transaction fields
  id: string,                     // Transaction ID
  userId: string,                 // User ID
  type: string,                   // "deduction" | "addition" | "refund"
  amount: number,                 // Total credit amount
  balanceBefore: number,          // Balance before transaction
  balanceAfter: number,           // Balance after transaction
  timestamp: Date,                // Transaction timestamp
  status: string,                 // "pending" | "completed" | "refunded"
  jobId?: string,                 // Associated job ID
  reason: string,                 // Transaction reason
  operationType: string,          // Operation type

  // Request data
  requestData: {
    generateVideo: boolean,
    generateCsv: boolean,
    imagesToGenerate: number,
  },

  // ESTIMATED credit usage breakdown (set during deduction)
  creditUsageBreakdown: {
    images: {
      requested: number,          // Number of images requested
      creditsPerImage: number,    // Credits per image (e.g., 1)
      totalCredits: number,       // Total credits for images
    },
    video: {
      requested: number,          // Number of videos requested (0 or 1)
      creditsPerVideo: number,    // Credits per video (e.g., 5)
      totalCredits: number,       // Total credits for video
    },
    excel: {
      requested: number,          // Number of Excel files requested (0 or 1)
      creditsPerExcel: number,    // Credits per Excel (e.g., 2)
      totalCredits: number,       // Total credits for Excel
    },
    totalEstimatedCredits: number, // Total estimated credits
  },

  // ACTUAL credit usage breakdown (set on completion)
  actualCreditUsage?: {
    images: {
      generated: number,          // Actual images generated
      creditsPerImage: number,    // Credits per image
      totalCredits: number,       // Actual credits used for images
    },
    video: {
      generated: number,          // Actual videos generated (0 or 1)
      creditsPerVideo: number,    // Credits per video
      totalCredits: number,       // Actual credits used for video
    },
    excel: {
      generated: number,          // Actual Excel files generated (0 or 1)
      creditsPerExcel: number,    // Credits per Excel
      totalCredits: number,       // Actual credits used for Excel
    },
    totalActualCredits: number,   // Total actual credits used
  },

  // Completion details
  completedAt?: Date,             // When transaction completed
  actualResults?: {
    imageCount: number,
    hasVideo: boolean,
    hasExcel: boolean,
  },
  completionDetails?: {
    processedAt: Date,
    webhookProcessed: boolean,
  },

  // Refund details
  refundedAt?: Date,              // When transaction was refunded
  refundReason?: string,          // Reason for refund
}
```

## Credit Pricing Structure

### Current Pricing (Configurable)

- **Images**: 1 credit per image
- **Videos**: 5 credits per video
- **Excel Reports**: 2 credits per Excel file

### Pricing Configuration

The pricing can be easily modified in the following locations:

- `functions/src/ai-generation-initiator.ts` - Lines 268, 273, 278
- `functions/src/ai-completion-handler.ts` - Lines 616, 617, 618

## Analytics and Reporting

### 1. User Credit Usage Analytics

**Endpoint**: `getUserCreditUsageAnalytics`

**Query Parameters**:

- `userId` (required): User ID to analyze
- `startDate` (optional): Start date for analysis
- `endDate` (optional): End date for analysis
- `groupBy` (optional): Grouping period ("hour", "day", "week", "month", "year")

**Response Structure**:

```typescript
{
  success: true,
  data: {
    userId: string,
    period: {
      startDate: string | null,
      endDate: string | null,
      groupBy: string
    },
    summary: {
      totalCreditsUsed: number,
      totalJobs: number,
      totalImages: number,
      totalVideos: number,
      totalExcels: number,
      averageCreditsPerJob: number,
      mostUsedFeature: string
    },
    breakdown: {
      images: {
        totalCredits: number,
        totalGenerated: number,
        averagePerJob: number
      },
      video: {
        totalCredits: number,
        totalGenerated: number,
        averagePerJob: number
      },
      excel: {
        totalCredits: number,
        totalGenerated: number,
        averagePerJob: number
      }
    },
    timeline: Array<{
      date: string,
      totalCredits: number,
      jobs: number,
      images: number,
      videos: number,
      excels: number
    }>,
    trends: {
      creditsTrend: "increasing" | "decreasing" | "stable",
      jobsTrend: "increasing" | "decreasing" | "stable",
      creditsChangePercent: number,
      jobsChangePercent: number
    }
  }
}
```

### 2. Admin Credit Usage Statistics

**Endpoint**: `getAdminCreditUsageStats`

**Query Parameters**:

- `startDate` (optional): Start date for analysis
- `endDate` (optional): End date for analysis
- `groupBy` (optional): Grouping period

**Response Structure**:

```typescript
{
  success: true,
  data: {
    period: {
      startDate: string | null,
      endDate: string | null,
      groupBy: string
    },
    summary: {
      totalCreditsUsed: number,
      totalJobs: number,
      uniqueUsers: number,
      averageCreditsPerJob: number,
      averageCreditsPerUser: number
    },
    featureStats: {
      images: {
        totalCredits: number,
        totalGenerated: number,
        jobs: number
      },
      video: {
        totalCredits: number,
        totalGenerated: number,
        jobs: number
      },
      excel: {
        totalCredits: number,
        totalGenerated: number,
        jobs: number
      }
    },
    topUsers: Array<{
      userId: string,
      totalCredits: number,
      totalJobs: number,
      images: number,
      videos: number,
      excels: number
    }>,
    timeline: Array<{
      date: string,
      totalCredits: number,
      jobs: number,
      uniqueUsers: number
    }>,
    trends: {
      creditsTrend: "increasing" | "decreasing" | "stable",
      jobsTrend: "increasing" | "decreasing" | "stable",
      creditsChangePercent: number,
      jobsChangePercent: number
    }
  }
}
```

## Usage Examples

### 1. Get User's Credit Usage for Last 30 Days

```javascript
const response = await fetch(
  `https://your-region-your-project.cloudfunctions.net/getUserCreditUsageAnalytics?userId=user123&startDate=2024-01-01&endDate=2024-01-31&groupBy=day`
);
const analytics = await response.json();
```

### 2. Get Admin Stats for Current Month

```javascript
const response = await fetch(
  `https://your-region-your-project.cloudfunctions.net/getAdminCreditUsageStats?startDate=2024-01-01&endDate=2024-01-31&groupBy=day`
);
const stats = await response.json();
```

## Credit Flow with Usage Tracking

### 1. Initial Request (ai-generation-initiator.ts)

```typescript
// When user initiates generation
const creditUsageBreakdown = {
  images: {
    requested: 5,
    creditsPerImage: 1,
    totalCredits: 5,
  },
  video: {
    requested: 1,
    creditsPerVideo: 5,
    totalCredits: 5,
  },
  excel: {
    requested: 1,
    creditsPerExcel: 2,
    totalCredits: 2,
  },
  totalEstimatedCredits: 12,
};

// Credits deducted with PENDING status
// creditUsageBreakdown stored in creditTransactions
```

### 2. Completion (ai-completion-handler.ts)

```typescript
// When generation completes successfully
const actualCreditUsage = {
  images: {
    generated: 5, // Actually generated 5 images
    creditsPerImage: 1,
    totalCredits: 5,
  },
  video: {
    generated: 1, // Actually generated 1 video
    creditsPerVideo: 5,
    totalCredits: 5,
  },
  excel: {
    generated: 0, // Excel generation failed
    creditsPerExcel: 2,
    totalCredits: 0,
  },
  totalActualCredits: 10, // Only 10 credits actually used
};

// Transaction status updated to COMPLETED
// actualCreditUsage stored in creditTransactions
```

## Benefits

### For Users

- **Transparency**: See exactly how credits are used
- **Usage History**: Track spending patterns over time
- **Feature Insights**: Understand which features consume most credits
- **Budget Planning**: Make informed decisions about credit purchases

### For Administrators

- **Revenue Analytics**: Track credit consumption trends
- **Feature Popularity**: Identify most/least used features
- **User Behavior**: Understand usage patterns
- **Pricing Optimization**: Data-driven pricing decisions
- **Resource Planning**: Plan infrastructure based on usage

### For Business Intelligence

- **Usage Forecasting**: Predict future credit consumption
- **Feature ROI**: Measure feature adoption and value
- **User Segmentation**: Identify power users vs casual users
- **Churn Analysis**: Correlate usage patterns with user retention

## Implementation Notes

1. **Pricing Flexibility**: Credit costs are easily configurable in the code
2. **Audit Trail**: Complete history of all credit transactions
3. **Real-time Analytics**: Live data available through Firebase Functions
4. **Scalable**: Designed to handle high-volume usage tracking
5. **Secure**: All analytics respect user privacy and data security

## Future Enhancements

1. **Credit Packages**: Track usage by different credit packages
2. **Seasonal Analytics**: Identify usage patterns by season/time
3. **Predictive Analytics**: ML-based usage forecasting
4. **Usage Alerts**: Notify users when approaching credit limits
5. **Credit Optimization**: Suggest optimal credit usage strategies
