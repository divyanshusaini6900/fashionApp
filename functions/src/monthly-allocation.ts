import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { getFirestore } from "firebase-admin/firestore";

// Use existing Firebase Admin instance
const db = getFirestore();

/**
 * Monthly Credit Distribution System
 * 
 * This function runs monthly to distribute credits to users with active subscriptions.
 * It calculates monthly credits based on their plan and distributes them accordingly.
 */

interface MonthlyAllocation {
    totalCredits: number;
    monthlyCredits: number;
    durationMonths: number;
    distributedMonths: number[];
    nextDistributionDate: Date;
    isActive: boolean;
    distributionStatus: {
        lastDistributionDate: Date | null;
        distributionCompleted: boolean;
        distributionFailed: boolean;
        failureReason: string | null;
        retryCount: number;
    };
}

interface UserSubscription {
    isActive: boolean;
    totalCreditsWithBonus: number;
    durationMonths: number;
    startDate: Date;
    expiryDate: Date;
    monthlyCredits?: number;
    monthlyAllocation?: MonthlyAllocation; // Keep for backward compatibility
    monthlyDistribution?: {
        monthlyCredits: number;
        lastDistributionDate: Date;
        distributionCount: number;
    };
}

// Removed old shouldCalculateRollover function - now using shouldCalculateUnusedCredits

export const dailyCreditDistribution = onSchedule({
    schedule: "0 0 * * *", // Run every day at midnight
    timeZone: "Asia/Kolkata",
    memory: "1GiB",
    timeoutSeconds: 540,
}, async (event) => {
    logger.info("Starting daily credit distribution and rollover process (rollover only happens every 30 days)");

    try {
        const currentDate = new Date();

        // Get all users with active subscriptions
        const usersSnapshot = await db.collection("users")
            .where("subscription.isActive", "==", true)
            .get();

        logger.info(`Found ${usersSnapshot.size} users with active subscriptions`);

        let processedUsers = 0;
        let distributedCredits = 0;
        let rolloverCredits = 0;

        for (const userDoc of usersSnapshot.docs) {
            try {
                const userId = userDoc.id;
                const userData = userDoc.data();
                const subscription = userData.subscription as UserSubscription;

                if (!subscription || !subscription.isActive) {
                    continue;
                }

                // Check if subscription is still valid
                const expiryDate = new Date(subscription.expiryDate);
                if (expiryDate < currentDate) {
                    logger.info(`Subscription expired for user ${userId}, skipping`);
                    continue;
                }

                // Get monthly distribution info
                let monthlyDistribution = subscription.monthlyDistribution;
                if (!monthlyDistribution) {
                    // For new users, set lastDistributionDate to current date to prevent immediate distribution
                    monthlyDistribution = {
                        monthlyCredits: subscription.monthlyCredits || 0,
                        lastDistributionDate: currentDate, // Use current date, not start date
                        distributionCount: 0,
                    };
                    logger.info(`Created monthly distribution for user ${userId}: ${monthlyDistribution.monthlyCredits} credits/month, lastDistributionDate set to current date`);
                }

                // Check if it's time to distribute credits (simple 30-day check)
                const shouldDistribute = shouldDistributeCredits(monthlyDistribution, currentDate, subscription);

                // DEBUG: Log distribution check for each user
                const lastDistDate = new Date(monthlyDistribution.lastDistributionDate);
                const daysSince = Math.floor((currentDate.getTime() - lastDistDate.getTime()) / (1000 * 60 * 60 * 24));
                logger.info(`User ${userId}: Last distribution ${lastDistDate.toISOString()}, days since: ${daysSince}, should distribute: ${shouldDistribute}`);
                logger.info(`User ${userId}: Subscription start: ${new Date(subscription.startDate).toISOString()}, expiry: ${new Date(subscription.expiryDate).toISOString()}`);

                if (shouldDistribute) {
                    try {
                        // Distribute monthly credits AND rollover credits at the same time
                        const result = await distributeMonthlyAndRolloverCredits(userId, userData, monthlyDistribution, currentDate);
                        distributedCredits += result.monthlyCredits;
                        rolloverCredits += result.rolloverCredits;
                        logger.info(`Successfully distributed ${result.monthlyCredits} monthly + ${result.rolloverCredits} rollover credits to user ${userId}`);
                    } catch (error) {
                        logger.error(`Failed to distribute credits to user ${userId}:`, error);
                    }
                }


                // Check for expired rollover credits (daily check)
                // await expireOldRolloverCredits(userId, userData, currentDate);

                processedUsers++;

            } catch (error) {
                logger.error(`Error processing user ${userDoc.id}:`, error);
                // Continue with next user
            }
        }

        logger.info(`Daily processing completed: ${processedUsers} users processed, ${distributedCredits} credits distributed, ${rolloverCredits} rollover credits applied`);

        // Update system flags
        await updateSystemFlags(currentDate, processedUsers, distributedCredits, rolloverCredits);

    } catch (error) {
        logger.error("Error in daily credit distribution:", error);
        throw error;
    }
});


// Old complex function removed - using simplified version below

/**
 * Distribute monthly credits AND rollover credits at the same time (fixed)
 * Rollover only happens every 30 days and only for valid subscriptions
 */
async function distributeMonthlyAndRolloverCredits(
    userId: string,
    userData: any,
    monthlyDistribution: any,
    currentDate: Date
): Promise<{ monthlyCredits: number; rolloverCredits: number }> {
    const userRef = db.collection("users").doc(userId);
    let monthlyCreditsAdded = 0;
    let rolloverCreditsAdded = 0;

    await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
            throw new Error(`User document not found: ${userId}`);
        }

        const currentUserData = userDoc.data();
        const monthlyCredits = currentUserData?.subscription?.monthlyCredits || 0;
        const currentCredits = currentUserData?.credits || 0;
        const currentRolloverData = currentUserData?.rolloverData || {};

        // 1. Calculate rollover credits from last month's unused credits
        const lastRolloverCredits = currentRolloverData.lastRolloverCredits || 0;

        // Calculate unused credits from last month: (total credits after last distribution) - (last rollover credits)
        const lastMonthUnused = Math.max(0, currentCredits - lastRolloverCredits);
        const rolloverAmount = Math.ceil(lastMonthUnused * 0.5); // 50% rollover, rounded up

        logger.info(`User ${userId}: Current credits: ${currentCredits}, last rollover: ${lastRolloverCredits}, unused: ${lastMonthUnused}, rollover: ${rolloverAmount}`);


        // 2. Calculate total credits to add (monthly + rollover)
        const totalCreditsToAdd = monthlyCredits + rolloverAmount;

        // 3. Update user credits and creditBalance
        transaction.update(userRef, {
            credits: totalCreditsToAdd,
            creditBalance: totalCreditsToAdd,
            lastUpdated: new Date(),
        });

        // 4. Update rollover tracking - ultra simple
        transaction.update(userRef, {
            rolloverData: {
                lastRolloverCredits: rolloverAmount,
                lastRolloverDate: currentDate,
                lastRolloverTotalCredits: totalCreditsToAdd,
            },
        });

        // 5. Update monthly distribution tracking
        transaction.update(userRef, {
            "subscription.monthlyDistribution": {
                ...monthlyDistribution,
                lastDistributionDate: currentDate,
                distributionCount: monthlyDistribution.distributionCount + 1,
            },
        });

        monthlyCreditsAdded = monthlyCredits;
        rolloverCreditsAdded = rolloverAmount;

        logger.info(`Distributed to user ${userId}: ${monthlyCredits} monthly + ${rolloverAmount} rollover = ${totalCreditsToAdd} total credits`);
    });

    return { monthlyCredits: monthlyCreditsAdded, rolloverCredits: rolloverCreditsAdded };
}


/**
 * Expire old rollover credits after 30 days
 */
// async function expireOldRolloverCredits(
//     userId: string,
//     userData: any,
//     currentDate: Date
// ): Promise<number> {
//     const rolloverData = userData.rolloverData;
//     if (!rolloverData || !rolloverData.lastRolloverDate) return 0;

//     const rolloverDate = new Date(rolloverData.lastRolloverDate.seconds * 1000);
//     const daysSinceRollover = Math.floor((currentDate.getTime() - rolloverDate.getTime()) / (1000 * 60 * 60 * 24));

//     // If rollover credits are older than 30 days, expire them
//     if (daysSinceRollover > 30 && rolloverData.rolloverCredits > 0) {
//         const userRef = db.collection("users").doc(userId);
//         const expiredCredits = rolloverData.rolloverCredits;

//         await db.runTransaction(async (transaction) => {
//             const userDoc = await transaction.get(userRef);
//             if (!userDoc.exists) return;

//             const userData = userDoc.data();
//             const currentCredits = userData?.credits || 0;
//             const currentRolloverData = userData?.rolloverData || {};

//             // Remove expired rollover credits
//             transaction.update(userRef, {
//                 credits: Math.max(0, currentCredits - expiredCredits),
//                 rolloverData: {
//                     ...currentRolloverData,
//                     rolloverCredits: 0, // Reset rollover credits
//                     expiredCredits: expiredCredits,
//                     expirationDate: currentDate,
//                     // Keep rollover history for audit
//                     rolloverHistory: [
//                         ...(currentRolloverData.rolloverHistory || []),
//                         {
//                             type: 'expired',
//                             amount: expiredCredits,
//                             date: currentDate,
//                             daysSinceRollover: daysSinceRollover
//                         }
//                     ].slice(-5), // Keep only last 5 entries
//                 },
//                 lastUpdated: new Date(),
//             });
//         });

//         logger.info(`Expired ${expiredCredits} rollover credits for user ${userId} (${daysSinceRollover} days old)`);
//         return expiredCredits;
//     }

//     return 0;
// }

/**
 * Update system flags for monitoring
 */
async function updateSystemFlags(
    currentDate: Date,
    processedUsers: number,
    distributedCredits: number,
    rolloverCredits: number
): Promise<void> {
    const systemRef = db.collection("system").doc("dailyDistribution");

    await systemRef.set({
        lastRun: currentDate,
        processedUsers,
        distributedCredits,
        rolloverCredits,
        status: "completed",
        nextRun: new Date(currentDate.getTime() + 24 * 60 * 60 * 1000), // Next day
        distributionFailures: await getDistributionFailures(), // Track failures
    }, { merge: true });
}

/**
 * Get count of distribution failures for monitoring
 */
async function getDistributionFailures(): Promise<number> {
    const usersSnapshot = await db.collection("users")
        .where("subscription.monthlyAllocation.distributionStatus.distributionFailed", "==", true)
        .get();

    return usersSnapshot.size;
}

// Old complex function removed - using simplified version below

// Removed unused function: distributeMissedCredits

/**
 * EMERGENCY CHECK: Run a comprehensive audit of all users
 * This function can be called manually to ensure no user has missed credits
 */
export const emergencyCreditAudit = onCall({
    enforceAppCheck: false, // Temporarily disabled until Play Integrity is configured
}, async (request: any) => {
    try {
        logger.info("Starting emergency credit audit");

        const usersSnapshot = await db.collection("users")
            .where("subscription.isActive", "==", true)
            .get();

        let auditedUsers = 0;
        let fixedUsers = 0;
        let totalCreditsDistributed = 0;

        for (const userDoc of usersSnapshot.docs) {
            try {
                const userId = userDoc.id;
                const userData = userDoc.data();
                const subscription = userData.subscription;

                if (!subscription || !subscription.isActive) continue;

                const monthlyAllocation = subscription.monthlyAllocation;
                if (!monthlyAllocation) continue;

                const currentDate = new Date();
                const planStartDate = new Date(subscription.startDate);
                const monthsSinceStart = Math.floor(
                    (currentDate.getTime() - planStartDate.getTime()) / (1000 * 60 * 60 * 24 * 30)
                );

                const expectedDistributions = Math.min(monthsSinceStart + 1, monthlyAllocation.durationMonths);
                const actualDistributions = monthlyAllocation.distributedMonths.length;

                if (actualDistributions < expectedDistributions) {
                    const missingDistributions = expectedDistributions - actualDistributions;
                    logger.warn(`User ${userId} is missing ${missingDistributions} distributions - manual intervention required`);
                    // Note: distributeMissedCredits function removed as part of simplification
                    // Manual intervention required for missed distributions
                }

                auditedUsers++;
            } catch (error) {
                logger.error(`Error auditing user ${userDoc.id}:`, error);
            }
        }

        logger.info(`Emergency audit completed: ${auditedUsers} users audited, ${fixedUsers} users fixed, ${totalCreditsDistributed} credits distributed`);

        return {
            success: true,
            auditedUsers,
            fixedUsers,
            totalCreditsDistributed,
        };
    } catch (error) {
        logger.error("Error in emergency credit audit:", error);
        throw error;
    }
});

/**
 * Simple check if distribution should happen (30 days since last distribution)
 * This controls BOTH monthly credit distribution AND rollover calculation
 * Rollover only happens when this function returns true (every 30 days)
 */
function shouldDistributeCredits(
    monthlyDistribution: any,
    currentDate: Date,
    subscription: any
): boolean {
    const lastDistributionDate = new Date(monthlyDistribution.lastDistributionDate);
    const daysSinceLastDistribution = Math.floor(
        (currentDate.getTime() - lastDistributionDate.getTime()) / (1000 * 60 * 60 * 24)
    );

    // Distribute every 30 days
    if (daysSinceLastDistribution < 30) {
        return false;
    }

    // Check if subscription is still active
    const expiryDate = new Date(subscription.expiryDate);
    if (expiryDate < currentDate) {
        logger.info(`Subscription expired, skipping distribution`);
        return false;
    }

    // Check if we haven't exceeded the subscription duration
    const startDate = new Date(subscription.startDate);
    const monthsSinceStart = Math.floor(
        (currentDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24 * 30)
    );

    if (monthsSinceStart >= subscription.durationMonths) {
        logger.info(`Subscription duration exceeded (${monthsSinceStart}/${subscription.durationMonths}), skipping`);
        return false;
    }

    return true;
}