import { onRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {
    verifyWebhookSignature,
    validateWebhookPayload,
    sanitizeWebhookData,
    logSecurityEvent
} from "./webhook-security";

const db = getFirestore();

// Define secrets for webhook security
const webhookSecret = defineSecret("AI_GENERATION_WEBHOOK_SECRET");
const apiKey = defineSecret("FASHION_AI_API_KEY");
const baseUrl = defineSecret("FASHION_AI_BASE_URL");

/**
 * AI Generation Webhook Handler
 * 
 * This webhook receives completion events from the AI generation service
 * and handles credit deduction, result saving, and user notifications.
 * 
 * Flow:
 * 1. Receive webhook with generation completion data
 * 2. Verify webhook signature for security
 * 3. Extract job details and results
 * 4. Deduct credits from user account
 * 5. Save results to Firestore
 * 6. Send completion notification to user
 */
export const aiGenerationWebhook = onRequest({
    secrets: [webhookSecret, apiKey, baseUrl],
    timeoutSeconds: 60,
    memory: "512MiB"
}, async (req, res) => {
    try {
        // Only accept POST requests
        if (req.method !== "POST") {
            logger.warn("Webhook called with non-POST method", { method: req.method });
            res.status(405).send("Method Not Allowed");
            return;
        }

        // Verify webhook signature using security utilities
        const signatureValidation = verifyWebhookSignature(
            { headers: req.headers, body: req.body },
            webhookSecret.value()
        );

        if (!signatureValidation.isValid) {
            logSecurityEvent("webhook_signature_verification_failed", {
                error: signatureValidation.error,
                details: signatureValidation.details
            }, "error");
            res.status(401).send(`Unauthorized - ${signatureValidation.error}`);
            return;
        }

        // Validate webhook payload structure
        const payloadValidation = validateWebhookPayload(req.body);
        if (!payloadValidation.isValid) {
            logSecurityEvent("webhook_payload_validation_failed", {
                error: payloadValidation.error,
                details: payloadValidation.details
            }, "warn");
            res.status(400).send(`Bad Request - ${payloadValidation.error}`);
            return;
        }

        // Sanitize webhook data
        const webhookData = sanitizeWebhookData(req.body);
        logger.info("AI Generation webhook received", {
            event: webhookData.event,
            jobId: webhookData.jobId
        });

        // Handle different webhook events
        switch (webhookData.event) {
            case "generation.completed":
                await handleGenerationCompleted(webhookData);
                break;
            case "generation.failed":
                await handleGenerationFailed(webhookData);
                break;
            case "generation.progress":
                await handleGenerationProgress(webhookData);
                break;
            default:
                logger.warn("Unknown webhook event", { event: webhookData.event });
        }

        res.status(200).send("OK");
    } catch (error) {
        logger.error("Webhook processing error", error);
        res.status(500).send("Internal Server Error");
    }
});

/**
 * Handle successful generation completion
 */
async function handleGenerationCompleted(webhookData: any) {
    try {
        const { jobId, results, metadata } = webhookData;

        logger.info("Processing completed generation", { jobId });

        // Get job details from Firestore
        const jobDoc = await db.collection("GenSpace_jobs").doc(jobId).get();
        if (!jobDoc.exists) {
            logger.error("Job not found", { jobId });
            return;
        }

        const jobData = jobDoc.data()!;
        const userId = jobData.userId;
        const requestData = jobData.requestData;

        // Calculate credit cost based on generation type
        const creditCost = calculateCreditCost(requestData, results);

        logger.info("Calculated credit cost", {
            jobId,
            creditCost,
            requestData: {
                generateVideo: requestData.generateVideo,
                generateCsv: requestData.generateCsv,
                imagesToGenerate: requestData.imagesToGenerate
            }
        });

        // Deduct credits from user account
        await deductCreditsFromUser(userId, creditCost, jobId, requestData);

        // Save results to Firestore
        await saveGenerationResults(jobId, results, metadata);

        // Update job status to completed
        await db.collection("GenSpace_jobs").doc(jobId).update({
            status: "completed",
            progress: 1.0,
            message: "Generation completed successfully!",
            completedAt: new Date(),
            completedViaWebhook: true,
            creditCost: creditCost,
            creditsDeductedAt: new Date(),
        });

        // Send completion notification
        await sendCompletionNotification(userId, jobId, results);

        logger.info("Generation completion processed successfully", {
            jobId,
            userId,
            creditCost
        });

    } catch (error) {
        logger.error("Error handling generation completion", error);
        throw error;
    }
}

/**
 * Handle generation failure
 */
async function handleGenerationFailed(webhookData: any) {
    try {
        const { jobId, error, reason } = webhookData;

        logger.info("Processing failed generation", { jobId, reason });

        // Update job status to failed
        await db.collection("GenSpace_jobs").doc(jobId).update({
            status: "failed",
            progress: 0.0,
            message: `Generation failed: ${reason}`,
            failedAt: new Date(),
            failureReason: reason,
            failureError: error,
            failedViaWebhook: true,
        });

        // Send failure notification
        const jobDoc = await db.collection("GenSpace_jobs").doc(jobId).get();
        if (jobDoc.exists) {
            const jobData = jobDoc.data()!;
            await sendFailureNotification(jobData.userId, jobId, reason);
        }

        logger.info("Generation failure processed", { jobId, reason });

    } catch (error) {
        logger.error("Error handling generation failure", error);
        throw error;
    }
}

/**
 * Handle generation progress updates
 */
async function handleGenerationProgress(webhookData: any) {
    try {
        const { jobId, progress, message } = webhookData;

        // Update job progress
        await db.collection("GenSpace_jobs").doc(jobId).update({
            progress: progress,
            message: message,
            lastProgressUpdate: new Date(),
            progressViaWebhook: true,
        });

        logger.info("Generation progress updated", { jobId, progress, message });

    } catch (error) {
        logger.error("Error handling generation progress", error);
        throw error;
    }
}

/**
 * Calculate credit cost based on generation parameters
 */
function calculateCreditCost(requestData: any, results: any): number {
    let totalCost = 0;

    // Base cost for image generation
    const imageCount = results.generatedImages?.length || 0;
    totalCost += imageCount * 1.0; // 1 credit per image

    // Video generation cost
    if (requestData.generateVideo && results.generatedVideos?.length > 0) {
        totalCost += 2.0; // 2 credits for video
    }

    // Excel generation cost
    if (requestData.generateCsv && results.csv) {
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
    requestData: any
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

            // Log credit transaction
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
            });
        });

        logger.info("Credits deducted successfully", {
            userId,
            amount,
            jobId
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
            request_id: results.id || jobId,
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
            body: "Your product GenSpace has been generated successfully. Check your exports.",
            data: {
                jobId: jobId,
                imageCount: results.generatedImages?.length || 0,
                hasVideo: results.generatedVideos?.length > 0,
                hasExcel: !!results.csv,
            },
            read: false,
            createdAt: new Date(),
        });

        logger.info("Completion notification sent", { userId, jobId });

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
