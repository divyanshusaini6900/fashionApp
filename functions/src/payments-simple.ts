import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { initializeApp } from "firebase-admin/app";
import { defineSecret } from "firebase-functions/params";
import Razorpay from "razorpay";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";

// Initialize Firebase Admin
initializeApp();

const db = getFirestore();

// Define secrets for Firebase Functions v2
const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");
const razorpayWebhookSecret = defineSecret("RAZORPAY_WEBHOOK_SECRET");

// Create Payment Intent for Subscription
export const createPaymentIntent = onCall({
    enforceAppCheck: false, // Enable App Check for production security
    secrets: [razorpayKeyId, razorpayKeySecret]
}, async (request) => {
    try {
        const {
            planName,
            planType,
            amount,
            durationMonths,
            creditsPerMonth,
            billingPeriod,
            userId,
        } = request.data;

        // Validate user authentication
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated");
        }

        // Validate required fields
        if (!planName || !planType || !amount || !durationMonths || !creditsPerMonth || !billingPeriod || !userId) {
            throw new HttpsError("invalid-argument", "Missing required fields");
        }

        // Validate amount
        if (amount <= 0) {
            throw new HttpsError("invalid-argument", "Amount must be greater than 0");
        }

        // Initialize Razorpay with secrets
        const razorpay = new Razorpay({
            key_id: razorpayKeyId.value(),
            key_secret: razorpayKeySecret.value(),
        });

        // Create Razorpay order
        const order = await razorpay.orders.create({
            amount: Math.round(amount * 100), // Convert to paise
            currency: "INR",
            receipt: `ord_${Date.now().toString().slice(-8)}_${userId.slice(-8)}`,
            notes: {
                planName,
                planType,
                billingPeriod,
                durationMonths: durationMonths.toString(),
                creditsPerMonth: creditsPerMonth.toString(),
                userId,
                type: "subscription",
            },
        });

        // Save payment intent to Firestore
        await db.collection("payment_intents").doc(order.id).set({
            orderId: order.id,
            userId,
            type: "subscription",
            planName,
            planType,
            amount,
            durationMonths,
            creditsPerMonth,
            billingPeriod,
            status: "pending",
            createdAt: new Date(),
        });

        logger.info("Payment intent created", {
            orderId: order.id,
            userId,
            amount,
            planName,
        });

        return {
            orderId: order.id,
            amount: order.amount,
            currency: order.currency,
        };
    } catch (error) {
        logger.error("Error creating payment intent", error);
        throw new HttpsError("internal", "Failed to create payment intent");
    }
});

// Create Payment Intent for Pay As You Go Credits
export const createPayAsYouGoIntent = onCall({
    enforceAppCheck: false, // Temporarily disabled until Play Integrity is configured
    secrets: [razorpayKeyId, razorpayKeySecret]
}, async (request) => {
    try {
        const { credits, amount, userId } = request.data;

        // Validate user authentication
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated");
        }

        // Validate required fields
        if (!credits || !amount || !userId) {
            throw new HttpsError("invalid-argument", "Missing required fields");
        }

        // Validate amount and credits
        if (amount <= 0 || credits <= 0) {
            throw new HttpsError("invalid-argument", "Amount and credits must be greater than 0");
        }

        // Initialize Razorpay with secrets
        const razorpay = new Razorpay({
            key_id: razorpayKeyId.value(),
            key_secret: razorpayKeySecret.value(),
        });

        // Create Razorpay order
        const order = await razorpay.orders.create({
            amount: Math.round(amount * 100), // Convert to paise
            currency: "INR",
            receipt: `payg_${Date.now().toString().slice(-8)}_${userId.slice(-8)}`,
            notes: {
                credits: credits.toString(),
                userId,
                type: "pay_as_you_go",
            },
        });

        // Save payment intent to Firestore
        await db.collection("payment_intents").doc(order.id).set({
            orderId: order.id,
            userId,
            type: "pay_as_you_go",
            credits,
            amount,
            status: "pending",
            createdAt: new Date(),
        });

        logger.info("Pay As You Go intent created", {
            orderId: order.id,
            userId,
            amount,
            credits,
        });

        return {
            orderId: order.id,
            amount: order.amount,
            currency: order.currency,
        };
    } catch (error) {
        logger.error("Error creating Pay As You Go intent", error);
        throw new HttpsError("internal", "Failed to create payment intent");
    }
});

// Razorpay Webhook Handler
export const razorpayWebhook = onRequest({
    secrets: [razorpayWebhookSecret]
}, async (req, res) => {
    try {
        if (req.method !== "POST") {
            res.status(405).send("Method Not Allowed");
            return;
        }

        const signature = req.headers["x-razorpay-signature"] as string;
        const body = JSON.stringify(req.body);

        // Verify webhook signature
        const expectedSignature = crypto
            .createHmac("sha256", razorpayWebhookSecret.value())
            .update(body)
            .digest("hex");

        if (signature !== expectedSignature) {
            logger.error("Invalid webhook signature");
            res.status(400).send("Invalid signature");
            return;
        }

        const event = req.body;

        logger.info("Webhook received", { event: event.event });

        if (event.event === "payment.captured") {
            await handlePaymentSuccess(event.payload.payment.entity);
        } else if (event.event === "payment.failed") {
            await handlePaymentFailure(event.payload.payment.entity);
        } else if (event.event === "payment.authorized") {
            await handlePaymentAuthorized(event.payload.payment.entity);
        } else if (event.event === "order.paid") {
            await handleOrderPaid(event.payload.order.entity);
        } else if (event.event === "refund.processed") {
            await handleRefundProcessed(event.payload.refund.entity);
        }

        res.status(200).send("OK");
    } catch (error) {
        logger.error("Webhook error", error);
        res.status(500).send("Internal Server Error");
    }
});

// Handle successful payment
async function handlePaymentSuccess(payment: any) {
    try {
        const orderId = payment.order_id;

        // Get payment intent
        const paymentIntent = await db.collection("payment_intents").doc(orderId).get();
        if (!paymentIntent.exists) {
            logger.error("Payment intent not found", { orderId });
            return;
        }

        const paymentData = paymentIntent.data()!;

        // Update payment status
        const updateData: any = {
            status: "success",
            paymentId: payment.id,
            updatedAt: new Date(),
        };

        // Only add signature if it exists
        if (payment.signature) {
            updateData.signature = payment.signature;
        }

        await db.collection("payment_intents").doc(orderId).update(updateData);

        // Process subscription/credits based on payment type
        if (paymentData.type === "subscription") {
            await processSubscription(paymentData);
        } else if (paymentData.type === "pay_as_you_go") {
            await processPayAsYouGo(paymentData);
        }

        logger.info("Payment processed successfully", {
            orderId,
            paymentId: payment.id,
            type: paymentData.type,
        });
    } catch (error) {
        logger.error("Error processing successful payment", error);
    }
}

// Handle failed payment
async function handlePaymentFailure(payment: any) {
    try {
        const orderId = payment.order_id;

        // Update payment status
        await db.collection("payment_intents").doc(orderId).update({
            status: "failed",
            paymentId: payment.id,
            errorCode: payment.error_code,
            errorMessage: payment.error_description,
            updatedAt: new Date(),
        });

        logger.info("Payment failed", {
            orderId,
            paymentId: payment.id,
            errorCode: payment.error_code,
        });
    } catch (error) {
        logger.error("Error processing failed payment", error);
    }
}

// Handle payment authorized (before capture)
async function handlePaymentAuthorized(payment: any) {
    try {
        const orderId = payment.order_id;

        // Update payment status to authorized
        await db.collection("payment_intents").doc(orderId).update({
            status: "authorized",
            paymentId: payment.id,
            authorizedAt: new Date(),
            updatedAt: new Date(),
        });

        logger.info("Payment authorized", {
            orderId,
            paymentId: payment.id,
        });
    } catch (error) {
        logger.error("Error processing authorized payment", error);
    }
}

// Handle order paid
async function handleOrderPaid(order: any) {
    try {
        const orderId = order.id;

        // Update payment status to paid
        await db.collection("payment_intents").doc(orderId).update({
            status: "paid",
            orderPaidAt: new Date(),
            updatedAt: new Date(),
        });

        logger.info("Order paid", {
            orderId,
            amount: order.amount,
        });
    } catch (error) {
        logger.error("Error processing order paid", error);
    }
}

// Handle refund processed
async function handleRefundProcessed(refund: any) {
    try {
        const paymentId = refund.payment_id;

        // Find the payment intent by payment ID
        const paymentIntents = await db.collection("payment_intents")
            .where("paymentId", "==", paymentId)
            .get();

        if (paymentIntents.empty) {
            logger.error("Payment intent not found for refund", { paymentId });
            return;
        }

        const paymentIntent = paymentIntents.docs[0];
        const paymentData = paymentIntent.data();

        // Update payment status
        await paymentIntent.ref.update({
            status: "refunded",
            refundId: refund.id,
            refundAmount: refund.amount,
            refundedAt: new Date(),
            updatedAt: new Date(),
        });

        // If it was a subscription, deactivate it
        if (paymentData.type === "subscription") {
            await db.collection("users").doc(paymentData.userId).update({
                "subscription.isActive": false,
                "subscription.refundedAt": new Date(),
                lastUpdated: new Date(),
            });
        }

        // If it was pay-as-you-go, deduct credits
        if (paymentData.type === "pay_as_you_go") {
            await db.runTransaction(async (transaction) => {
                const userRef = db.collection("users").doc(paymentData.userId);
                const userDoc = await transaction.get(userRef);

                if (userDoc.exists) {
                    const currentCredits = userDoc.data()?.credits || 0;
                    const refundedCredits = Math.floor(refund.amount / 100 / 160); // Assuming ₹160 per credit

                    transaction.update(userRef, {
                        credits: Math.max(0, currentCredits - refundedCredits),
                        lastUpdated: new Date(),
                    });
                }
            });
        }

        logger.info("Refund processed", {
            refundId: refund.id,
            paymentId,
            amount: refund.amount,
            type: paymentData.type,
        });
    } catch (error) {
        logger.error("Error processing refund", error);
    }
}

// Process subscription payment with 20% bonus system
async function processSubscription(paymentData: any) {
    try {
        const userId = paymentData.userId;
        const planCredits = paymentData.creditsPerMonth;
        const durationMonths = paymentData.durationMonths;

        // Calculate total credits and bonus (20% bonus system)
        const totalPlanCredits = planCredits * durationMonths;
        const bonusCredits = Math.ceil(totalPlanCredits * 0.20); // 20% bonus, rounded up
        const totalCreditsWithBonus = totalPlanCredits + bonusCredits;
        const monthlyCredits = Math.ceil(totalCreditsWithBonus / durationMonths);

        // Calculate expiry date
        const now = new Date();
        const expiryDate = new Date(now.getFullYear(), now.getMonth() + durationMonths, now.getDate());

        // Update user subscription using transaction (ADDITIVE SYSTEM)
        await db.runTransaction(async (transaction) => {
            const userRef = db.collection("users").doc(userId);
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error("User document not found");
            }

            const userData = userDoc.data();
            const currentCredits = userData?.credits || 0;
            const existingSubscription = userData?.subscription;

            // Prepare new subscription data with bonus information
            const newSubscriptionData = {
                planName: paymentData.planName,
                planType: paymentData.planType,
                billingPeriod: paymentData.billingPeriod,
                creditsPerMonth: planCredits, // Max Credits Per Month
                totalCredits: totalPlanCredits,
                bonusCredits: bonusCredits,
                totalCreditsWithBonus: totalCreditsWithBonus,
                monthlyCredits: monthlyCredits,
                durationMonths: durationMonths,
                startDate: new Date(),
                expiryDate: expiryDate,
                isActive: true,
                lastPayment: new Date(),
            };

            // Handle multiple plans - ADDITIVE SYSTEM
            let finalSubscriptionData;

            if (existingSubscription && existingSubscription.isActive) {
                // User has existing active subscription - COMBINE PLANS
                const existingCredits = existingSubscription.totalCreditsWithBonus || 0;
                const existingDuration = existingSubscription.durationMonths || 0;

                // Calculate combined totals
                const combinedTotalCredits = (totalCreditsWithBonus || 0) + userData?.creditBalance || 0;

                // Calculate combined monthly credits (sum of individual monthly credits)
                const totalDuration = Math.max(existingDuration, durationMonths);
                const combinedMonthlyCredits = (combinedTotalCredits / totalDuration);

                // Use the longer expiry date
                const existingExpiry = existingSubscription.expiryDate ?
                    new Date(existingSubscription.expiryDate.seconds * 1000) : new Date();
                const finalExpiryDate = expiryDate > existingExpiry ? expiryDate : existingExpiry;

                finalSubscriptionData = {
                    ...existingSubscription,
                    planName: `${existingSubscription.planName} + ${paymentData.planName}`,
                    planType: "Combined Plan",
                    billingPeriod: "Combined",
                    creditsPerMonth: monthlyCredits, // latest plan credits per month
                    totalCredits: combinedTotalCredits,
                    bonusCredits: bonusCredits,
                    totalCreditsWithBonus: combinedTotalCredits,
                    monthlyCredits: combinedMonthlyCredits,
                    durationMonths: totalDuration,
                    expiryDate: finalExpiryDate,
                    isActive: true,
                    lastPayment: new Date(),
                    // Track individual plans
                    individualPlans: [
                        ...(existingSubscription.individualPlans || [existingSubscription]),
                        newSubscriptionData
                    ]
                };

                logger.info("Combining existing subscription with new plan", {
                    userId,
                    existingCredits,
                    newCredits: totalCreditsWithBonus,
                    combinedTotalCredits,
                    existingPlan: existingSubscription.planName,
                    newPlan: paymentData.planName
                });
            } else {
                // No existing subscription - CREATE NEW
                finalSubscriptionData = {
                    ...newSubscriptionData,
                    individualPlans: [newSubscriptionData]
                };

                logger.info("Creating new subscription", {
                    userId,
                    planName: paymentData.planName,
                    totalCreditsWithBonus
                });
            }

            // Simple monthly distribution tracking
            const monthlyDistribution = {
                monthlyCredits: finalSubscriptionData.monthlyCredits,
                lastDistributionDate: new Date(),
                distributionCount: 0,
            };

            // Initialize rollover tracking for new subscriptions (ultra simple)
            const rolloverData = {
                lastRolloverCredits: 0,
                lastRolloverDate: new Date(),
                lastRolloverTotalCredits: (currentCredits + totalCreditsWithBonus),
            };

            transaction.update(userRef, {
                subscription: {
                    ...finalSubscriptionData,
                    monthlyDistribution: monthlyDistribution,
                },
                credits: currentCredits + totalCreditsWithBonus, // Add only NEW plan credits with bonus
                creditBalance: currentCredits + totalCreditsWithBonus,
                rolloverData: rolloverData,
                lastUpdated: new Date(),
            });
        });

        logger.info("Subscription activated with 20% bonus", {
            userId,
            planName: paymentData.planName,
            totalPlanCredits,
            bonusCredits,
            totalCreditsWithBonus,
            monthlyCredits
        });
    } catch (error) {
        logger.error("Error processing subscription", error);
        throw error;
    }
}

// Process Pay As You Go payment
async function processPayAsYouGo(paymentData: any) {
    try {
        const userId = paymentData.userId;
        const purchasedCredits = paymentData.credits;

        // Update user credits using transaction
        await db.runTransaction(async (transaction) => {
            const userRef = db.collection("users").doc(userId);
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error("User document not found");
            }

            const currentCredits = userDoc.data()?.credits || 0;

            transaction.update(userRef, {
                credits: currentCredits + purchasedCredits,
                creditBalance: currentCredits + purchasedCredits,
                lastUpdated: new Date(),
            });
        });

        logger.info("Credits added", {
            userId,
            credits: purchasedCredits,
        });
    } catch (error) {
        logger.error("Error processing Pay As You Go payment", error);
        throw error;
    }
}

// Verify payment signature (for client-side verification)
export const verifyPayment = onCall({
    enforceAppCheck: false, // Temporarily disabled until Play Integrity is configured
    secrets: [razorpayKeyId, razorpayKeySecret]
}, async (request) => {
    try {
        const { paymentId, orderId, signature } = request.data;

        // Validate user authentication
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated");
        }

        // Validate required fields
        if (!paymentId || !orderId || !signature) {
            throw new HttpsError("invalid-argument", "Missing required fields");
        }

        // Verify signature
        const expectedSignature = crypto
            .createHmac("sha256", razorpayKeySecret.value())
            .update(`${orderId}|${paymentId}`)
            .digest("hex");

        const isValid = signature === expectedSignature;

        if (!isValid) {
            throw new HttpsError("invalid-argument", "Invalid payment signature");
        }

        // Initialize Razorpay with secrets
        const razorpay = new Razorpay({
            key_id: razorpayKeyId.value(),
            key_secret: razorpayKeySecret.value(),
        });

        // Get payment details from Razorpay
        const payment = await razorpay.payments.fetch(paymentId);

        return {
            isValid: true,
            payment: {
                id: payment.id,
                amount: payment.amount,
                currency: payment.currency,
                status: payment.status,
                orderId: payment.order_id,
            },
        };
    } catch (error) {
        logger.error("Error verifying payment", error);
        throw new HttpsError("internal", "Failed to verify payment");
    }
});