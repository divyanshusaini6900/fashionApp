/**
 * Firebase Functions for TechRelieve Payment System
 * 
 * This file exports all payment-related functions including:
 * - createPaymentIntent: Creates Razorpay orders for subscriptions
 * - createPayAsYouGoIntent: Creates Razorpay orders for credit purchases
 * - razorpayWebhook: Handles Razorpay webhook events
 * - verifyPayment: Verifies payment signatures
 */

// Export payment functions
export {
    createPaymentIntent,
    createPayAsYouGoIntent,
    razorpayWebhook,
    verifyPayment,
} from "./payments-simple";

// Export AI generation webhook function
export {
    aiGenerationWebhook,
} from "./ai-generation-webhook";

// Export AI completion handler
export {
    aiCompletionHandler,
} from "./ai-completion-handler";

// Export AI generation initiator
export {
    aiGenerationInitiator,
} from "./ai-generation-initiator";

// Export credit usage analytics functions
export {
    getUserCreditUsageAnalytics,
    getAdminCreditUsageStats,
} from "./credit-usage-analytics";

// Export plan purchase functions
export {
    processPlanPurchase,
    planPurchaseWebhook,
} from "./plan-purchase";

// Export daily allocation functions
export {
    dailyCreditDistribution,
    emergencyCreditAudit,
} from "./monthly-allocation";
