import { onRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {
    // verifyWebhookSignature, // Temporarily disabled for testing
    sanitizeWebhookData,
    logSecurityEvent
} from "./webhook-security";

const db = getFirestore();

// Define secrets for webhook security
const webhookSecret = defineSecret("AI_GENERATION_WEBHOOK_SECRET");
const apiKey = defineSecret("FASHION_AI_API_KEY");
const baseUrl = defineSecret("FASHION_AI_BASE_URL");

/**
 * AI Generation Initiator Webhook
 * 
 * This webhook is called BEFORE making the API call to:
 * 1. Validate user has sufficient credits
 * 2. Deduct credits and mark as pending
 * 3. Initiate the AI generation API call
 * 4. Set up completion webhook
 * 
 * Flow:
 * 1. Receive generation request
 * 2. Check user credit balance
 * 3. Deduct credits and mark as pending
 * 4. Call AI generation API
 * 5. Set up completion webhook
 * 6. Return success/failure response
 */
export const aiGenerationInitiator = onRequest({
    secrets: [webhookSecret, apiKey, baseUrl],
    timeoutSeconds: 60,
    memory: "512MiB",
    cors: true
}, async (req, res) => {
    try {
        // Only accept POST requests
        if (req.method !== "POST") {
            logger.warn("Generation initiator called with non-POST method", { method: req.method });
            res.status(405).send("Method Not Allowed");
            return;
        }

        // TODO: Temporarily disable signature verification for testing
        // Verify webhook signature using security utilities
        // const signatureValidation = verifyWebhookSignature(
        //     { headers: req.headers, body: req.body },
        //     webhookSecret.value()
        // );

        // if (!signatureValidation.isValid) {
        //     logSecurityEvent("initiator_signature_verification_failed", {
        //         error: signatureValidation.error,
        //         details: signatureValidation.details
        //     }, "error");
        //     res.status(401).send(`Unauthorized - ${signatureValidation.error}`);
        //     return;
        // }

        // Validate webhook payload structure
        const payloadValidation = validateGenerationRequestPayload(req.body);
        if (!payloadValidation.isValid) {
            logSecurityEvent("generation_request_validation_failed", {
                error: payloadValidation.error,
                details: payloadValidation.details
            }, "warn");
            res.status(400).send(`Bad Request - ${payloadValidation.error}`);
            return;
        }

        // Sanitize webhook data
        const requestData = sanitizeWebhookData(req.body);
        logger.info("AI Generation initiator received", {
            jobId: requestData.jobId,
            userId: requestData.userId
        });

        // Process the generation request
        const result = await processGenerationRequest(requestData);

        res.status(200).json(result);
    } catch (error) {
        logger.error("Generation initiator error", error);
        res.status(500).json({
            success: false,
            error: "Internal Server Error",
            message: error instanceof Error ? error.message : String(error)
        });
    }
});

/**
 * Calculate credit cost based on rates from credits collection
 */
async function calculateCreditCostFromCollection(requestData: any): Promise<number> {
    try {
        // Fetch credit rates from the credits collection
        const creditsDoc = await db.collection("credits").doc("creditUsage").get();

        if (!creditsDoc.exists) {
            logger.warn("Credit rates document not found, using default rates");
            // Fallback to default rates if document doesn't exist
            return calculateCreditCostWithDefaultRates(requestData);
        }

        const creditRates = creditsDoc.data();
        logger.info("Fetched credit rates from collection", creditRates);

        let totalCredits = 0;

        // Images: credits per image
        const imageRate = creditRates?.image || 1;
        const imageCount = requestData.imagesToGenerate || 0;
        totalCredits += imageCount * imageRate;

        // Video: credits per video
        const videoRate = creditRates?.video || 1;
        if (requestData.generateVideo) {
            totalCredits += videoRate;
        }

        // Excel: credits per Excel file
        const excelRate = creditRates?.excel || 0.5;
        if (requestData.generateCsv) {
            totalCredits += excelRate;
        }

        logger.info("Credit calculation breakdown", {
            imageCount,
            imageRate,
            imageCost: imageCount * imageRate,
            hasVideo: requestData.generateVideo,
            videoRate,
            videoCost: requestData.generateVideo ? videoRate : 0,
            hasExcel: requestData.generateCsv,
            excelRate,
            excelCost: requestData.generateCsv ? excelRate : 0,
            totalCredits
        });

        return totalCredits;

    } catch (error) {
        logger.error("Error fetching credit rates from collection", error);
        // Fallback to default rates
        return calculateCreditCostWithDefaultRates(requestData);
    }
}

/**
 * Fallback credit calculation with default rates
 */
function calculateCreditCostWithDefaultRates(requestData: any): number {
    let totalCredits = 0;

    // Default rates (fallback)
    const defaultRates = {
        image: 1,
        video: 1,
        excel: 0.5
    };

    // Images
    const imageCount = requestData.imagesToGenerate || 0;
    totalCredits += imageCount * defaultRates.image;

    // Video
    if (requestData.generateVideo) {
        totalCredits += defaultRates.video;
    }

    // Excel
    if (requestData.generateCsv) {
        totalCredits += defaultRates.excel;
    }

    return totalCredits;
}

/**
 * Process generation request with proper credit flow
 */
async function processGenerationRequest(requestData: any) {
    try {
        const {
            jobId,
            userId,
            requestData: generationRequest,
            uploadedImageUrls,
            creditCost
        } = requestData;

        logger.info("Processing generation request", { jobId, userId, creditCost });

        // Calculate credit cost based on rates from credits collection
        const calculatedCreditCost = await calculateCreditCostFromCollection(generationRequest);
        logger.info("Credit cost calculation", {
            requested: creditCost,
            calculated: calculatedCreditCost,
            requestData: generationRequest
        });

        // 0. CREATE JOB DOCUMENT
        const jobRef = db.collection("GenSpace_jobs").doc(jobId);
        await jobRef.set({
            skuId: jobId,
            userId: userId,
            status: "processing",
            progress: 0.0,
            message: "Starting AI generation process...",
            createdAt: new Date(),
            requestData: generationRequest,
            uploadedImageUrls: uploadedImageUrls,
            creditCost: creditCost
        });

        // 1. CHECK USER CREDIT BALANCE
        const userRef = db.collection("users").doc(userId);
        const userDoc = await userRef.get();

        if (!userDoc.exists) {
            // For testing purposes, create a test user with credits
            if (userId.startsWith('test_user_')) {
                logger.info("Creating test user for testing purposes", { userId });
                await userRef.set({
                    creditBalance: 100, // Give test user 100 credits
                    email: `${userId}@test.com`,
                    createdAt: new Date(),
                    isTestUser: true
                });
                logger.info("Test user created successfully", { userId });
            } else {
                throw new Error("User document not found");
            }
        }

        const currentBalance = userDoc.data()?.creditBalance || 0;

        if (currentBalance < creditCost) {
            // Update job status to failed due to insufficient credits
            await db.collection("GenSpace_jobs").doc(jobId).update({
                status: "failed",
                message: `Insufficient credits. Required: ${creditCost}, Available: ${currentBalance}`,
                failedAt: new Date(),
                failureReason: "insufficient_credits",
                creditCheckFailed: true,
                requiredCredits: creditCost,
                availableCredits: currentBalance,
            });

            return {
                success: false,
                error: "insufficient_credits",
                message: `Insufficient credits. Required: ${creditCost}, Available: ${currentBalance}`,
                requiredCredits: creditCost,
                availableCredits: currentBalance
            };
        }

        // 2. DEDUCT CREDITS AND MARK AS PENDING
        const newBalance = await deductCreditsWithPendingStatus(
            userId,
            creditCost,
            jobId,
            generationRequest
        );

        // 3. UPDATE JOB STATUS TO PENDING
        await db.collection("GenSpace_jobs").doc(jobId).update({
            status: "pending",
            message: "Credits deducted. Initiating AI generation...",
            creditsDeducted: true,
            creditsDeductedAt: new Date(),
            creditsAmount: creditCost,
            creditBalanceAfter: newBalance,
            pendingAt: new Date(),
        });

        // 4. CALL AI GENERATION API
        const apiResult = await callAIGenerationAPI(
            generationRequest,
            uploadedImageUrls,
            jobId
        );

        if (!apiResult.success) {
            // API call failed - refund credits
            await refundCreditsForFailedJob(userId, creditCost, jobId, apiResult.error || "Unknown API error");

            return {
                success: false,
                error: "api_call_failed",
                message: apiResult.error,
                creditsRefunded: true
            };
        }

        // 5. UPDATE JOB WITH API RESPONSE
        await db.collection("GenSpace_jobs").doc(jobId).update({
            status: "processing",
            message: "AI generation in progress...",
            conversionId: apiResult.conversionId,
            apiCallSuccessful: true,
            processingStartedAt: new Date(),
        });

        logger.info("Generation request processed successfully", {
            jobId,
            userId,
            creditCost,
            conversionId: apiResult.conversionId
        });

        return {
            success: true,
            message: "Generation initiated successfully",
            conversionId: apiResult.conversionId,
            creditsDeducted: creditCost,
            newBalance: newBalance
        };

    } catch (error) {
        logger.error("Error processing generation request", error);
        throw error;
    }
}

/**
 * Deduct credits and mark transaction as pending
 */
async function deductCreditsWithPendingStatus(
    userId: string,
    amount: number,
    jobId: string,
    requestData: any
): Promise<number> {
    try {
        const userRef = db.collection("users").doc(userId);

        // Fetch credit rates outside transaction to avoid Firestore transaction rules
        const creditsDoc = await db.collection("credits").doc("creditUsage").get();
        let creditRates = creditsDoc.exists ? creditsDoc.data() : null;

        // Ensure creditRates is not undefined and has all required fields
        if (!creditRates || !creditRates.image || !creditRates.video || !creditRates.excel) {
            logger.warn("Credit rates document missing or incomplete, using default rates", { creditRates });
            // Use default rates
            creditRates = {
                image: 1,
                video: 1,
                excel: 0.5
            };
        }

        // TypeScript assertion - we know creditRates is not null at this point
        const rates = {
            image: creditRates.image,
            video: creditRates.video,
            excel: creditRates.excel
        };

        return await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
                // For testing purposes, create a test user with credits
                if (userId.startsWith('test_user_')) {
                    logger.info("Creating test user in transaction for testing purposes", { userId });
                    transaction.set(userRef, {
                        creditBalance: 100, // Give test user 100 credits
                        email: `${userId}@test.com`,
                        createdAt: new Date(),
                        isTestUser: true
                    });
                } else {
                    throw new Error("User document not found");
                }
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

            // Credit rates already fetched outside transaction

            // Log credit transaction as PENDING with detailed usage breakdown
            transaction.set(db.collection("creditTransactions").doc(), {
                userId: userId,
                type: "deduction",
                amount: amount,
                balanceBefore: currentBalance,
                balanceAfter: newBalance,
                timestamp: new Date(),
                reason: "AI_generation_initiated",
                operationType: "pending_deduction",
                jobId: jobId,
                status: "pending",
                requestData: {
                    generateVideo: requestData.generateVideo,
                    generateCsv: requestData.generateCsv,
                    imagesToGenerate: requestData.imagesToGenerate,
                },
                // Detailed credit usage breakdown with actual rates
                creditUsageBreakdown: {
                    image: {
                        requested: requestData.imagesToGenerate || 0,
                        creditsPerImage: rates.image,
                        totalCredits: (requestData.imagesToGenerate || 0) * rates.image,
                    },
                    video: {
                        requested: requestData.generateVideo ? 1 : 0,
                        creditsPerVideo: rates.video,
                        totalCredits: requestData.generateVideo ? rates.video : 0,
                    },
                    excel: {
                        requested: requestData.generateCsv ? 1 : 0,
                        creditsPerExcel: rates.excel,
                        totalCredits: requestData.generateCsv ? rates.excel : 0,
                    },
                    totalEstimatedCredits: amount,
                },
            });

            return newBalance;
        });

    } catch (error) {
        logger.error("Error deducting credits with pending status", error);
        throw error;
    }
}

/**
 * Call AI generation API
 */
async function callAIGenerationAPI(
    requestData: any,
    uploadedImageUrls: string[],
    jobId: string
): Promise<{ success: boolean; conversionId?: string; error?: string }> {
    try {
        // Build input images array
        const inputImages = uploadedImageUrls.map((url, index) => {
            let view = 'front';
            if (index === 0) view = 'front';
            else if (index === 1) view = 'back';
            else if (index === 2) view = 'side';
            else view = 'detail';

            return { url, view };
        });

        // Build completion webhook URL - use the correct webhook endpoint
        const completionWebhookUrl = `https://us-central1-techrelieve-90c12.cloudfunctions.net/aiGenerationWebhook?jobId=${jobId}`;

        // Prepare API request
        const apiRequest: any = {
            inputImages: inputImages,
            text: requestData.text || '',
            numberOfOutputs: requestData.imagesToGenerate || 1,
            isVideo: requestData.generateVideo || false,
            generateCsv: requestData.generateCsv || false,
            upscale: true,
            webhookUrl: completionWebhookUrl,
            webhookEvents: ['generation.completed', 'generation.failed'],
        };

        // Add optional fields conditionally
        if (requestData.productType) {
            apiRequest.productType = requestData.productType;
        }
        if (requestData.gender) {
            apiRequest.gender = requestData.gender === 'Male' ? 'man' : 'woman';
        }

        // Make API call
        const response = await fetch(`${baseUrl.value()}/ratnawnai/fashionai`, {
            method: 'POST',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'x-api-key': apiKey.value(),
            },
            body: JSON.stringify(apiRequest),
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`API call failed: ${response.status} - ${errorText}`);
        }

        const responseData = await response.json();
        const conversionId = responseData.id;

        if (!conversionId) {
            throw new Error('No conversion ID returned from API');
        }

        logger.info("AI generation API called successfully", {
            jobId,
            conversionId
        });

        return {
            success: true,
            conversionId: conversionId
        };

    } catch (error) {
        logger.error("Error calling AI generation API", error);
        return {
            success: false,
            error: error instanceof Error ? error.message : String(error)
        };
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
                // For testing purposes, create a test user with credits
                if (userId.startsWith('test_user_')) {
                    logger.info("Creating test user in refund transaction for testing purposes", { userId });
                    transaction.set(userRef, {
                        creditBalance: 100, // Give test user 100 credits
                        email: `${userId}@test.com`,
                        createdAt: new Date(),
                        isTestUser: true
                    });
                } else {
                    throw new Error("User document not found");
                }
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
        });

        // Update job status
        await db.collection("GenSpace_jobs").doc(jobId).update({
            status: "failed",
            message: `Generation failed: ${reason}. Credits refunded.`,
            failedAt: new Date(),
            failureReason: reason,
            creditsRefunded: true,
            creditsRefundedAt: new Date(),
            creditsRefundAmount: amount,
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
 * Validate generation request payload
 */
function validateGenerationRequestPayload(payload: any): { isValid: boolean; error?: string; details?: any } {
    try {
        if (!payload) {
            return { isValid: false, error: "Empty payload" };
        }

        // Required fields
        const requiredFields = ['jobId', 'userId', 'requestData', 'uploadedImageUrls', 'creditCost'];

        for (const field of requiredFields) {
            if (!payload[field]) {
                return {
                    isValid: false,
                    error: `Missing required field: ${field}`
                };
            }
        }

        // Validate credit cost
        if (typeof payload.creditCost !== 'number' || payload.creditCost <= 0) {
            return {
                isValid: false,
                error: "Invalid credit cost"
            };
        }

        // Validate request data
        const requestData = payload.requestData;
        if (!requestData.text) {
            return {
                isValid: false,
                error: "Missing text in request data"
            };
        }

        // Validate uploaded image URLs
        if (!Array.isArray(payload.uploadedImageUrls) || payload.uploadedImageUrls.length === 0) {
            return {
                isValid: false,
                error: "No uploaded image URLs provided"
            };
        }

        return { isValid: true };
    } catch (error) {
        return {
            isValid: false,
            error: "Payload validation failed",
            details: { error: error instanceof Error ? error.message : String(error) }
        };
    }
}