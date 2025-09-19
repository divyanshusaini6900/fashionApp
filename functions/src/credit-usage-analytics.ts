import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { getFirestore } from "firebase-admin/firestore";

const db = getFirestore();

/**
 * Get user credit usage analytics
 */
export const getUserCreditUsageAnalytics = onRequest(
    { cors: true },
    async (req, res) => {
        try {
            const { userId } = req.query;

            if (!userId) {
                res.status(400).json({
                    success: false,
                    error: "userId is required"
                });
                return;
            }

            // Get all credit transactions for the user (including pending ones for debugging)
            // Simple query - get user's deduction transactions
            const query = db.collection("creditTransactions")
                .where("userId", "==", userId)
                .where("type", "==", "deduction");

            const snapshot = await query.get();
            const allTransactions = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data()
            })) as any[];

            // For now, include ALL transactions (both new and legacy)
            // TODO: Later we can filter to only show new system transactions
            const transactions = allTransactions;

            // Debug logging
            console.log(`Found ${allTransactions.length} transactions for user ${userId}`);
            allTransactions.forEach((tx, index) => {
                console.log(`Transaction ${index + 1}:`, {
                    id: tx.id,
                    status: tx.status,
                    type: tx.type,
                    amount: tx.amount,
                    hasBreakdown: !!tx.creditUsageBreakdown,
                    hasActualUsage: !!tx.actualCreditUsage,
                    reason: tx.reason
                });
            });

            // Calculate simple usage totals
            const analytics = calculateSimpleCreditUsage(transactions);

            res.json({
                success: true,
                data: {
                    userId,
                    summary: analytics.summary,
                    breakdown: analytics.breakdown
                }
            });

        } catch (error) {
            logger.error("Error getting credit usage analytics", error);
            res.status(500).json({
                success: false,
                error: "Failed to get credit usage analytics"
            });
        }
    }
);

/**
 * Get admin credit usage statistics
 */
export const getAdminCreditUsageStats = onRequest(
    { cors: true },
    async (req, res) => {
        try {
            const { startDate, endDate, groupBy = "day" } = req.query;

            // Get all completed credit transactions with new breakdown system
            let query = db.collection("creditTransactions")
                .where("status", "==", "completed")
                .where("type", "==", "deduction")
                .where("creditUsageBreakdown", "!=", null);

            // Apply date filters if provided
            if (startDate) {
                query = query.where("timestamp", ">=", new Date(startDate as string));
            }
            if (endDate) {
                query = query.where("timestamp", "<=", new Date(endDate as string));
            }

            const snapshot = await query.get();
            const transactions = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data()
            })) as any[];

            // Calculate admin stats
            const stats = calculateAdminCreditStats(transactions, groupBy as string);

            res.json({
                success: true,
                data: {
                    period: {
                        startDate: startDate || null,
                        endDate: endDate || null,
                        groupBy
                    },
                    summary: stats.summary,
                    breakdown: stats.breakdown,
                    timeline: stats.timeline,
                    userStats: stats.userStats
                }
            });

        } catch (error) {
            logger.error("Error getting admin credit usage stats", error);
            res.status(500).json({
                success: false,
                error: "Failed to get admin credit usage stats"
            });
        }
    }
);

/**
 * Simple credit usage calculation for wallet page
 */
function calculateSimpleCreditUsage(transactions: any[]) {
    let totalCreditsUsed = 0;
    let totalImagesGenerated = 0;
    let totalVideosGenerated = 0;
    let totalExcelsGenerated = 0;

    transactions.forEach(transaction => {
        // Add to total credits used
        totalCreditsUsed += transaction.amount || 0;

        // Count actual usage from the breakdown
        const breakdown = transaction.creditUsageBreakdown;
        const actualUsage = transaction.actualCreditUsage;

        if (breakdown) {
            // New system - use breakdown data (estimated)
            if (breakdown.image) {
                totalImagesGenerated += breakdown.image.requested || 0;
            }
            if (breakdown.video) {
                totalVideosGenerated += breakdown.video.requested || 0;
            }
            if (breakdown.excel) {
                totalExcelsGenerated += breakdown.excel.requested || 0;
            }
        } else if (actualUsage) {
            // New system - use actual usage data
            if (actualUsage.image) {
                totalImagesGenerated += actualUsage.image.generated || 0;
            }
            if (actualUsage.video) {
                totalVideosGenerated += actualUsage.video.generated || 0;
            }
            if (actualUsage.excel) {
                totalExcelsGenerated += actualUsage.excel.generated || 0;
            }
        } else {
            // Legacy system - estimate based on amount and reason
            const amount = transaction.amount || 0;
            const reason = transaction.reason || '';
            const operationType = transaction.operationType || '';

            if (operationType === 'image_generation' || reason === 'image_generation' || reason === 'GenSpace_generation') {
                totalImagesGenerated += Math.round(amount / 1.0); // 1 credit per image
            } else if (operationType === 'video_generation' || reason === 'video_generation') {
                totalVideosGenerated += Math.round(amount / 1.0); // 1 credit per video
            } else if (operationType === 'excel_generation' || reason === 'excel_generation') {
                totalExcelsGenerated += Math.round(amount / 0.5); // 0.5 credits per excel
            }
        }
    });

    return {
        summary: {
            totalCreditsUsed,
            totalTransactions: transactions.length
        },
        breakdown: {
            image: {
                totalGenerated: totalImagesGenerated,
                totalCredits: totalImagesGenerated * 1.0 // Assuming 1 credit per image
            },
            video: {
                totalGenerated: totalVideosGenerated,
                totalCredits: totalVideosGenerated * 1.0 // Assuming 1 credit per video
            },
            excel: {
                totalGenerated: totalExcelsGenerated,
                totalCredits: totalExcelsGenerated * 0.5 // Assuming 0.5 credits per excel
            }
        }
    };
}

/**
 * Calculate admin-level credit usage statistics
 */
function calculateAdminCreditStats(transactions: any[], groupBy: string) {
    const totalCreditsUsed = transactions.reduce((sum, t) => sum + t.amount, 0);
    const totalJobs = transactions.length;
    const uniqueUsers = new Set(transactions.map(t => t.userId)).size;

    const featureStats = {
        image: { totalCredits: 0, totalGenerated: 0, jobs: 0 },
        video: { totalCredits: 0, totalGenerated: 0, jobs: 0 },
        excel: { totalCredits: 0, totalGenerated: 0, jobs: 0 },
    };

    const userStats: any = {};
    const timeline: any = {};

    transactions.forEach(transaction => {
        // Handle Firestore Timestamp objects properly
        let date: Date;
        if (transaction.timestamp && typeof transaction.timestamp.toDate === 'function') {
            // Firestore Timestamp object
            date = transaction.timestamp.toDate();
        } else if (transaction.timestamp) {
            // Regular Date or timestamp
            date = new Date(transaction.timestamp);
        } else {
            // Skip transactions without timestamp
            return;
        }

        // Validate the date
        if (isNaN(date.getTime())) {
            console.warn('Invalid timestamp in transaction:', transaction.id, transaction.timestamp);
            return;
        }

        const dateKey = getDateKey(date, groupBy);

        // User stats
        if (!userStats[transaction.userId]) {
            userStats[transaction.userId] = {
                totalCredits: 0,
                totalJobs: 0,
                image: 0,
                videos: 0,
                excels: 0,
            };
        }

        userStats[transaction.userId].totalCredits += transaction.amount || 0;
        userStats[transaction.userId].totalJobs += 1;

        // Timeline stats
        if (!timeline[dateKey]) {
            timeline[dateKey] = {
                date: dateKey,
                totalCredits: 0,
                totalJobs: 0,
                uniqueUsers: new Set(),
                images: 0,
                videos: 0,
                excels: 0,
            };
        }

        timeline[dateKey].totalCredits += transaction.amount || 0;
        timeline[dateKey].totalJobs += 1;
        timeline[dateKey].uniqueUsers.add(transaction.userId);

        // Process credit breakdown
        const usage = transaction.actualCreditUsage || transaction.creditUsageBreakdown;

        if (usage) {
            if (usage.image) {
                const imageCount = usage.image.generated || usage.image.requested || 0;
                featureStats.image.totalGenerated += imageCount;
                featureStats.image.jobs += 1;
                userStats[transaction.userId].image += imageCount;
                timeline[dateKey].images += imageCount;
            }

            if (usage.video) {
                const videoCount = usage.video.generated || usage.video.requested || 0;
                featureStats.video.totalGenerated += videoCount;
                featureStats.video.jobs += 1;
                userStats[transaction.userId].videos += videoCount;
                timeline[dateKey].videos += videoCount;
            }

            if (usage.excel) {
                const excelCount = usage.excel.generated || usage.excel.requested || 0;
                featureStats.excel.totalGenerated += excelCount;
                featureStats.excel.jobs += 1;
                userStats[transaction.userId].excels += excelCount;
                timeline[dateKey].excels += excelCount;
            }
        }
    });

    // Convert timeline to array and calculate unique users per period
    const timelineArray = Object.values(timeline).map((entry: any) => ({
        ...entry,
        uniqueUsers: entry.uniqueUsers.size
    }));

    return {
        summary: {
            totalCreditsUsed,
            totalJobs,
            uniqueUsers,
            averageCreditsPerJob: totalJobs > 0 ? totalCreditsUsed / totalJobs : 0
        },
        breakdown: featureStats,
        timeline: timelineArray,
        userStats: Object.values(userStats)
    };
}

/**
 * Get date key for grouping
 */
function getDateKey(date: Date, groupBy: string): string {
    switch (groupBy) {
        case "hour":
            return date.toISOString().slice(0, 13) + ":00:00.000Z";
        case "day":
            return date.toISOString().slice(0, 10);
        case "week":
            const weekStart = new Date(date);
            weekStart.setDate(date.getDate() - date.getDay());
            return weekStart.toISOString().slice(0, 10);
        case "month":
            return date.toISOString().slice(0, 7);
        case "year":
            return date.toISOString().slice(0, 4);
        default:
            return date.toISOString().slice(0, 10);
    }
}