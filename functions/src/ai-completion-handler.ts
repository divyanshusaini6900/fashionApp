import { onRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {
    // verifyCompletionSignature, // Temporarily disabled for testing
    validateCompletionPayload,
    sanitizeWebhookData,
    logSecurityEvent
} from "./webhook-security";

const db = getFirestore();

// Define secrets for webhook security
const webhookSecret = defineSecret("AI_COMPLETION_WEBHOOK_SECRET");

/**
 * AI Completion Handler
 * 
 * This endpoint is called by the AI generation service when generation is complete.
 * It handles:
 * 1. Verifying the completion request
 * 2. Calculating and deducting credits
 * 3. Saving results to Firestore
 * 4. Sending notifications to users
 * 
 * This is the endpoint that the AI generation API will call with completion data.
 */
export const aiCompletionHandler = onRequest({
    secrets: [webhookSecret],
    timeoutSeconds: 60,
    memory: "512MiB"
}, async (req, res) => {
    try {
        // Only accept POST requests
        if (req.method !== "POST") {
            logger.warn("Completion handler called with non-POST method", { method: req.method });
            res.status(405).send("Method Not Allowed");
            return;
        }

        // TODO: Temporarily disable signature verification for testing
        // Verify completion signature using security utilities
        // const signatureValidation = verifyCompletionSignature(
        //     { headers: req.headers, body: req.body },
        //     webhookSecret.value()
        // );

        // if (!signatureValidation.isValid) {
        //     logSecurityEvent("completion_signature_verification_failed", {
        //         error: signatureValidation.error,
        //         details: signatureValidation.details
        //     }, "error");
        //     res.status(401).send(`Unauthorized - ${signatureValidation.error}`);
        //     return;
        // }

        // Validate completion payload structure
        const payloadValidation = validateCompletionPayload(req.body);
        if (!payloadValidation.isValid) {
            logSecurityEvent("completion_payload_validation_failed", {
                error: payloadValidation.error,
                details: payloadValidation.details
            }, "warn");
            res.status(400).send(`Bad Request - ${payloadValidation.error}`);
            return;
        }

        // Sanitize completion data
        const completionData = sanitizeWebhookData(req.body);
        logger.info("AI completion received", {
            jobId: completionData.jobId,
            status: completionData.status
        });

        // Handle completion based on status
        if (completionData.status === "completed") {
            logger.info("Processing successful completion", { jobId: completionData.jobId });
            await handleSuccessfulCompletion(completionData);
            logger.info("Successfully processed completion", { jobId: completionData.jobId });
        } else if (completionData.status === "failed") {
            logger.info("Processing failed completion", { jobId: completionData.jobId });
            await handleFailedCompletion(completionData);
            logger.info("Successfully processed failure", { jobId: completionData.jobId });
        } else {
            logger.warn("Unknown completion status", { status: completionData.status });
            res.status(400).send("Invalid completion status");
            return;
        }

        res.status(200).send("OK");
    } catch (error) {
        logger.error("Completion handler error", error);
        res.status(500).send("Internal Server Error");
    }
});

/**
 * Handle successful generation completion
 */
async function handleSuccessfulCompletion(completionData: any) {
    try {
        const {
            jobId,
            conversionId,
            metadata,
            generatedImages,
            generatedVideos,
            csv,
            description,
            keyFeatures,
            searchKeywords
        } = completionData;

        logger.info("Processing successful completion", { jobId, conversionId });

        // Get job details from Firestore
        const jobDoc = await db.collection("GenSpace_jobs").doc(jobId).get();
        if (!jobDoc.exists) {
            logger.error("Job not found", { jobId });
            return;
        }

        const jobData = jobDoc.data()!;
        const userId = jobData.userId;
        const requestData = jobData.requestData;

        // Check if credits were already deducted (pending status)
        logger.info("Looking for pending credit transaction", { jobId });
        const existingTransaction = await findPendingCreditTransaction(jobId);
        logger.info("Found pending transaction", {
            jobId,
            found: !!existingTransaction,
            transactionId: existingTransaction?.id
        });
        let creditCost = 0;

        if (existingTransaction) {
            // Credits already deducted, just update the transaction status
            await updatePendingTransactionToCompleted(existingTransaction, {
                imageCount: generatedImages?.length || 0,
                hasVideo: generatedVideos?.length > 0,
                hasExcel: !!csv
            });

            // Calculate actual credit cost for logging
            creditCost = calculateActualCreditCost(requestData, {
                generatedImages,
                generatedVideos,
                csv
            });

            logger.info("Updated existing pending transaction to completed", {
                jobId,
                transactionId: existingTransaction.id,
                actualResults: {
                    imageCount: generatedImages?.length || 0,
                    hasVideo: generatedVideos?.length > 0,
                    hasExcel: !!csv
                }
            });
        } else {
            // Fallback: Calculate and deduct credits (for backward compatibility)
            creditCost = calculateActualCreditCost(requestData, {
                generatedImages,
                generatedVideos,
                csv
            });

            logger.info("No pending transaction found, deducting credits", {
                jobId,
                creditCost,
                actualResults: {
                    imageCount: generatedImages?.length || 0,
                    hasVideo: generatedVideos?.length > 0,
                    hasExcel: !!csv
                }
            });

            await deductCreditsFromUser(userId, creditCost, jobId, requestData, {
                imageCount: generatedImages?.length || 0,
                hasVideo: generatedVideos?.length > 0,
                hasExcel: !!csv
            });
        }

        // Save results to Firestore
        await saveGenerationResults(jobId, {
            generatedImages,
            generatedVideos,
            csv,
            description,
            keyFeatures,
            searchKeywords,
            conversionId
        }, metadata);

        // Update job status to completed
        await db.collection("GenSpace_jobs").doc(jobId).update({
            status: "completed",
            progress: 1.0,
            message: "Generation completed successfully!",
            completedAt: new Date(),
            completedViaWebhook: true,
            actualCreditCost: creditCost,
            creditsDeductedAt: new Date(),
            conversionId: conversionId,
        });

        // Send completion notification
        await sendCompletionNotification(userId, jobId, {
            imageCount: generatedImages?.length || 0,
            hasVideo: generatedVideos?.length > 0,
            hasExcel: !!csv
        });

        logger.info("Successful completion processed", {
            jobId,
            userId,
            creditCost
        });

    } catch (error) {
        logger.error("Error handling successful completion", error);
        throw error;
    }
}

/**
 * Handle failed generation
 */
async function handleFailedCompletion(completionData: any) {
    try {
        const { jobId, conversionId, error, reason } = completionData;

        logger.info("Processing failed completion", { jobId, conversionId, reason });

        // Get job data
        const jobDoc = await db.collection("GenSpace_jobs").doc(jobId).get();
        if (!jobDoc.exists) {
            logger.error("Job not found for failed completion", { jobId });
            return;
        }

        const jobData = jobDoc.data()!;
        const userId = jobData.userId;

        // Check if credits were already deducted and need refund
        const pendingTransaction = await findPendingCreditTransaction(jobId);

        if (pendingTransaction) {
            // Refund the deducted credits
            await refundCreditsForFailedJob(userId, (pendingTransaction as any).amount, jobId, reason);

            logger.info("Credits refunded for failed job", {
                jobId,
                userId,
                refundAmount: pendingTransaction.amount,
                reason
            });
        }

        // Update job status to failed
        await db.collection("GenSpace_jobs").doc(jobId).update({
            status: "failed",
            progress: 0.0,
            message: `Generation failed: ${reason}. ${pendingTransaction ? 'Credits refunded.' : ''}`,
            failedAt: new Date(),
            failureReason: reason,
            failureError: error,
            failedViaWebhook: true,
            conversionId: conversionId,
            creditsRefunded: !!pendingTransaction,
            creditsRefundedAt: pendingTransaction ? new Date() : null,
            creditsRefundAmount: pendingTransaction?.amount || 0,
        });

        // Send failure notification
        await sendFailureNotification(userId, jobId, reason);

        logger.info("Failed completion processed", { jobId, reason, creditsRefunded: !!pendingTransaction });

    } catch (error) {
        logger.error("Error handling failed completion", error);
        throw error;
    }
}

/**
 * Calculate actual credit cost based on what was generated
 */
function calculateActualCreditCost(requestData: any, actualResults: any): number {
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

/**
 * Deduct credits from user account
 */
async function deductCreditsFromUser(
    userId: string,
    amount: number,
    jobId: string,
    requestData: any,
    actualResults: any
) {
    try {
        const userRef = db.collection("users").doc(userId);

        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error("User document not found");
            }

            const currentBalance = userDoc.data()?.creditBalance || 0;

            if (currentBalance < amount) {
                throw new Error(`Insufficient credits. Required: ${amount}, Available: ${currentBalance}`);
            }

            const newBalance = currentBalance - amount;

            // Update user balance
            transaction.update(userRef, {
                creditBalance: newBalance,
                lastUpdated: new Date(),
            });

            // Log credit transaction with detailed breakdown
            transaction.set(db.collection("creditTransactions").doc(), {
                userId: userId,
                type: "deduction",
                amount: amount,
                balanceBefore: currentBalance,
                balanceAfter: newBalance,
                timestamp: new Date(),
                reason: "AI_generation_completion",
                operationType: "webhook_deduction",
                jobId: jobId,
                requestData: {
                    generateVideo: requestData.generateVideo,
                    generateCsv: requestData.generateCsv,
                    imagesToGenerate: requestData.imagesToGenerate,
                },
                actualResults: {
                    imageCount: actualResults.imageCount,
                    hasVideo: actualResults.hasVideo,
                    hasExcel: actualResults.hasExcel,
                },
                creditBreakdown: {
                    image: actualResults.imageCount * 1.0,
                    video: actualResults.hasVideo ? 2.0 : 0,
                    excel: actualResults.hasExcel ? 0.5 : 0,
                }
            });
        });

        logger.info("Credits deducted successfully", {
            userId,
            amount,
            jobId,
            actualResults
        });

    } catch (error) {
        logger.error("Error deducting credits", error);
        throw error;
    }
}

/**
 * Save generation results to Firestore
 */
async function saveGenerationResults(jobId: string, results: any, metadata: any) {
    try {
        const resultData = {
            image_variations: results.generatedImages?.map((img: any) => img.imageSrc) || [],
            output_video_url: results.generatedVideos?.[0]?.videoUrl || null,
            excel_export_url: results.csv || null,
            description: results.description,
            key_features: results.keyFeatures,
            search_keywords: results.searchKeywords,
            request_id: results.conversionId || jobId,
            metadata: {
                ...metadata,
                webhookProcessed: true,
                processedAt: new Date(),
            },
            products_processed: 1,
            success_count: 1,
        };

        await db.collection("GenSpace_jobs").doc(jobId).update({
            result: resultData,
        });

        logger.info("Generation results saved", { jobId });

    } catch (error) {
        logger.error("Error saving generation results", error);
        throw error;
    }
}

/**
 * Send completion notification to user
 */
async function sendCompletionNotification(userId: string, jobId: string, results: any) {
    try {
        // Create notification document for the app to pick up
        await db.collection("notifications").add({
            userId: userId,
            type: "generation_completed",
            title: "GenSpace Generation Complete!",
            body: `Your product GenSpace has been generated successfully! ${results.imageCount} images${results.hasVideo ? ', 1 video' : ''}${results.hasExcel ? ', Excel report' : ''} created.`,
            data: {
                jobId: jobId,
                imageCount: results.imageCount,
                hasVideo: results.hasVideo,
                hasExcel: results.hasExcel,
            },
            read: false,
            createdAt: new Date(),
        });

        logger.info("Completion notification sent", { userId, jobId, results });

    } catch (error) {
        logger.error("Error sending completion notification", error);
        // Don't throw - notification failure shouldn't break the flow
    }
}

/**
 * Send failure notification to user
 */
async function sendFailureNotification(userId: string, jobId: string, reason: string) {
    try {
        await db.collection("notifications").add({
            userId: userId,
            type: "generation_failed",
            title: "GenSpace Generation Failed",
            body: `Failed to generate your product GenSpace: ${reason}`,
            data: {
                jobId: jobId,
                reason: reason,
            },
            read: false,
            createdAt: new Date(),
        });

        logger.info("Failure notification sent", { userId, jobId, reason });

    } catch (error) {
        logger.error("Error sending failure notification", error);
        // Don't throw - notification failure shouldn't break the flow
    }
}

/**
 * Find pending credit transaction for a job
 */
async function findPendingCreditTransaction(jobId: string) {
    try {
        logger.info("Searching for pending credit transaction", { jobId });

        // First try to find with new fields
        let transactions = await db.collection("creditTransactions")
            .where("jobId", "==", jobId)
            .where("status", "==", "pending")
            .where("operationType", "==", "pending_deduction")
            .limit(1)
            .get();

        logger.info("New format query results", {
            jobId,
            count: transactions.size,
            docs: transactions.docs.map(doc => ({ id: doc.id, data: doc.data() }))
        });

        // If not found, try legacy format (missing status/operationType fields)
        if (transactions.empty) {
            logger.info("Trying legacy format query", { jobId });
            transactions = await db.collection("creditTransactions")
                .where("jobId", "==", jobId)
                .where("type", "==", "deduction")
                .limit(1)
                .get();

            logger.info("Legacy format query results", {
                jobId,
                count: transactions.size,
                docs: transactions.docs.map(doc => ({ id: doc.id, data: doc.data() }))
            });
        }

        if (transactions.empty) {
            return null;
        }

        const doc = transactions.docs[0];
        const data = doc.data();

        // Ensure required fields exist with defaults
        return {
            id: doc.id,
            amount: data.amount || 0,
            status: data.status || "completed", // Default to completed for legacy
            operationType: data.operationType || "legacy_deduction",
            jobId: data.jobId || jobId,
            userId: data.userId,
            ...data
        };
    } catch (error) {
        logger.error("Error finding pending credit transaction", error);
        return null;
    }
}

/**
 * Update pending transaction to completed status
 */
async function updatePendingTransactionToCompleted(
    transaction: any,
    actualResults: any
) {
    try {
        // Calculate actual credit usage based on results
        const actualCreditUsage = await calculateActualCreditUsage(actualResults);

        // Build update object with fallbacks for missing fields
        const updateData: any = {
            status: "completed",
            completedAt: new Date(),
            actualResults: {
                imageCount: actualResults.imageCount,
                hasVideo: actualResults.hasVideo,
                hasExcel: actualResults.hasExcel,
            },
            // Record actual credit usage breakdown with rates from collection
            actualCreditUsage: actualCreditUsage,
            completionDetails: {
                processedAt: new Date(),
                webhookProcessed: true,
            }
        };

        // Add missing fields for legacy transactions
        if (!transaction.operationType) {
            updateData.operationType = "legacy_deduction";
        }

        if (!transaction.requestData) {
            updateData.requestData = {
                generateVideo: false,
                generateCsv: false,
                imagesToGenerate: 1,
            };
        }

        if (!transaction.creditUsageBreakdown) {
            updateData.creditUsageBreakdown = {
                image: {
                    requested: 1,
                    creditsPerImage: 1,
                    totalCredits: transaction.amount || 1,
                },
                video: {
                    requested: 0,
                    creditsPerVideo: 5,
                    totalCredits: 0,
                },
                excel: {
                    requested: 0,
                    creditsPerExcel: 2,
                    totalCredits: 0,
                },
                totalEstimatedCredits: transaction.amount || 1,
            };
        }

        await db.collection("creditTransactions").doc(transaction.id).update(updateData);

        logger.info("Updated pending transaction to completed", {
            transactionId: transaction.id,
            actualResults,
            isLegacyTransaction: !transaction.operationType
        });

    } catch (error) {
        logger.error("Error updating pending transaction", error);
        throw error;
    }
}

/**
 * Refund credits for failed job
 */
async function refundCreditsForFailedJob(
    userId: string,
    amount: number,
    jobId: string,
    reason: string
) {
    try {
        const userRef = db.collection("users").doc(userId);

        await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                throw new Error("User document not found");
            }

            const currentBalance = userDoc.data()?.creditBalance || 0;
            const newBalance = currentBalance + amount;

            // Update user balance
            transaction.update(userRef, {
                creditBalance: newBalance,
                lastUpdated: new Date(),
            });

            // Log refund transaction
            transaction.set(db.collection("creditTransactions").doc(), {
                userId: userId,
                type: "refund",
                amount: amount,
                balanceBefore: currentBalance,
                balanceAfter: newBalance,
                timestamp: new Date(),
                reason: "AI_generation_failed",
                operationType: "failed_job_refund",
                jobId: jobId,
                failureReason: reason,
                status: "completed",
            });

            // Update the original pending transaction to refunded
            const pendingTransaction = await findPendingCreditTransaction(jobId);
            if (pendingTransaction) {
                transaction.update(db.collection("creditTransactions").doc(pendingTransaction.id), {
                    status: "refunded",
                    refundedAt: new Date(),
                    refundReason: reason,
                });
            }
        });

        logger.info("Credits refunded for failed job", {
            userId,
            jobId,
            amount,
            reason
        });

    } catch (error) {
        logger.error("Error refunding credits for failed job", error);
        throw error;
    }
}

/**
 * Calculate actual credit usage based on generation results
 */
async function calculateActualCreditUsage(actualResults: any) {
    try {
        // Fetch actual credit rates from collection
        const creditsDoc = await db.collection("credits").doc("creditUsage").get();
        const creditRates = creditsDoc.exists ? creditsDoc.data() : {
            image: 1,
            video: 1,
            excel: 0.5
        };

        // Ensure creditRates is not undefined
        if (!creditRates) {
            throw new Error("Failed to fetch credit rates");
        }

        // Use the image rate from the document
        const imageRate = creditRates.image;

        const imageCredits = actualResults.imageCount * imageRate;
        const videoCredits = actualResults.hasVideo ? creditRates.video : 0;
        const excelCredits = actualResults.hasExcel ? creditRates.excel : 0;

        return {
            image: {
                generated: actualResults.imageCount,
                creditsPerImage: imageRate,
                totalCredits: imageCredits,
            },
            video: {
                generated: actualResults.hasVideo ? 1 : 0,
                creditsPerVideo: creditRates.video,
                totalCredits: videoCredits,
            },
            excel: {
                generated: actualResults.hasExcel ? 1 : 0,
                creditsPerExcel: creditRates.excel,
                totalCredits: excelCredits,
            },
            totalCredits: imageCredits + videoCredits + excelCredits,
        };
    } catch (error) {
        logger.error("Error fetching credit rates for actual usage calculation", error);
        // Fallback to default rates
        const imageCredits = actualResults.imageCount * 1;
        const videoCredits = actualResults.hasVideo ? 1 : 0;
        const excelCredits = actualResults.hasExcel ? 0.5 : 0;

        return {
            image: {
                generated: actualResults.imageCount,
                creditsPerImage: 1,
                totalCredits: imageCredits,
            },
            video: {
                generated: actualResults.hasVideo ? 1 : 0,
                creditsPerVideo: 1,
                totalCredits: videoCredits,
            },
            excel: {
                generated: actualResults.hasExcel ? 1 : 0,
                creditsPerExcel: 0.5,
                totalCredits: excelCredits,
            },
            totalCredits: imageCredits + videoCredits + excelCredits,
        };
    }
}
