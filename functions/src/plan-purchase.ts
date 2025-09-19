/**
 * Plan Purchase Processing with 20% Bonus Credit System
 * 
 * This function handles plan purchases and applies the 20% bonus credit system.
 * It integrates with the existing Razorpay webhook system.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { logger } from 'firebase-functions';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

/**
 * Process plan purchase with 20% bonus credits
 * This function is called from the Razorpay webhook
 */
export async function processPlanPurchase(paymentData: any) {
    try {
        const userId = paymentData.userId;
        const planCredits = paymentData.creditsPerMonth;
        const durationMonths = paymentData.durationMonths;
        const planName = paymentData.planName;
        const planType = paymentData.planType;
        const billingPeriod = paymentData.billingPeriod;

        logger.info('Processing plan purchase', {
            userId,
            planName,
            planCredits,
            durationMonths
        });

        // Calculate total credits and bonus
        const totalPlanCredits = planCredits * durationMonths;
        const bonusCredits = Math.ceil(totalPlanCredits * 0.20); // 20% bonus, rounded up
        const totalCreditsWithBonus = totalPlanCredits + bonusCredits;

        // Calculate monthly credits (rounded up)
        const monthlyCredits = Math.ceil(totalCreditsWithBonus / durationMonths);

        // Calculate expiry date
        const now = new Date();
        const expiryDate = new Date(now.getFullYear(), now.getMonth() + durationMonths, now.getDate());

        // Update user document with transaction
        await db.runTransaction(async (transaction) => {
            const userRef = db.collection('users').doc(userId);
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error('User document not found');
            }

            const currentData = userDoc.data();
            const currentCredits = currentData?.creditBalance || 0;

            // Prepare subscription data
            const subscriptionData = {
                planName: planName,
                planType: planType,
                billingPeriod: billingPeriod,
                creditsPerMonth: planCredits,
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

            // Prepare monthly credits tracking
            const monthlyCreditsData = {
                totalAllocated: totalCreditsWithBonus,
                monthlyAmount: monthlyCredits,
                remainingMonths: durationMonths,
                lastAllocationDate: new Date(),
                allocationHistory: []
            };

            // Prepare system flags
            const systemFlags = {
                lastMonthlyProcessed: new Date(),
                lastRolloverProcessed: new Date(),
                monthlyProcessingStatus: {} as Record<string, string>,
                rolloverProcessingStatus: {} as Record<string, string>,
                failedProcessing: []
            };

            // Initialize monthly processing status for all months
            for (let i = 0; i < durationMonths; i++) {
                const monthDate = new Date(now.getFullYear(), now.getMonth() + i, 1);
                const monthKey = monthDate.toISOString().substring(0, 7); // YYYY-MM format
                systemFlags.monthlyProcessingStatus[monthKey] = 'pending';
                systemFlags.rolloverProcessingStatus[monthKey] = 'pending';
            }

            // Update user document
            transaction.update(userRef, {
                subscription: subscriptionData,
                monthlyCredits: monthlyCreditsData,
                systemFlags: systemFlags,
                creditBalance: admin.firestore.FieldValue.increment(totalCreditsWithBonus),
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

            // Log the transaction
            await db.collection('creditTransactions').add({
                userId: userId,
                type: 'plan_purchase',
                planName: planName,
                planCredits: planCredits,
                durationMonths: durationMonths,
                totalPlanCredits: totalPlanCredits,
                bonusCredits: bonusCredits,
                totalCreditsWithBonus: totalCreditsWithBonus,
                monthlyCredits: monthlyCredits,
                balanceBefore: currentCredits,
                balanceAfter: currentCredits + totalCreditsWithBonus,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                reason: 'plan_purchase_with_bonus'
            });
        });

        logger.info('Plan purchase processed successfully', {
            userId,
            planName,
            totalCreditsWithBonus,
            bonusCredits,
            monthlyCredits
        });

        return {
            success: true,
            data: {
                userId,
                planName,
                totalCreditsWithBonus,
                bonusCredits,
                monthlyCredits,
                durationMonths
            }
        };

    } catch (error) {
        logger.error('Error processing plan purchase', error);
        throw error;
    }
}

/**
 * Firebase Function to handle plan purchase webhook
 * This can be called from the Razorpay webhook or directly
 */
export const planPurchaseWebhook = functions.https.onRequest(async (req, res) => {
    // Set CORS headers
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
        res.status(204).send('');
        return;
    }

    if (req.method !== 'POST') {
        res.status(405).send('Method not allowed');
        return;
    }

    try {
        const paymentData = req.body;

        // Validate required fields
        if (!paymentData.userId || !paymentData.creditsPerMonth || !paymentData.durationMonths) {
            res.status(400).send('Missing required fields');
            return;
        }

        const result = await processPlanPurchase(paymentData);

        res.status(200).json(result);
    } catch (error) {
        logger.error('Error in plan purchase webhook', error);
        res.status(500).json({
            success: false,
            error: error instanceof Error ? error.message : 'Unknown error'
        });
    }
});
