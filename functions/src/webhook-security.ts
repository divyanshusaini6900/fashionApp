import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";

/**
 * Webhook Security Utilities
 * 
 * This module provides security functions for webhook verification,
 * signature validation, and request authentication.
 */

export interface WebhookSecurityConfig {
    secret: string;
    allowedOrigins: string[];
    rateLimitWindow: number; // in milliseconds
    maxRequestsPerWindow: number;
}

export interface WebhookRequest {
    headers: { [key: string]: string | string[] | undefined };
    body: any;
    ip?: string;
    userAgent?: string;
}

export interface SecurityValidationResult {
    isValid: boolean;
    error?: string;
    details?: any;
}

/**
 * Verify webhook signature using HMAC-SHA256
 */
export function verifyWebhookSignature(
    request: WebhookRequest,
    secret: string,
    signatureHeader: string = "x-webhook-signature"
): SecurityValidationResult {
    try {
        const signature = request.headers[signatureHeader] as string;

        if (!signature) {
            return {
                isValid: false,
                error: "Missing webhook signature",
                details: { header: signatureHeader }
            };
        }

        const body = typeof request.body === "string"
            ? request.body
            : JSON.stringify(request.body);

        const expectedSignature = crypto
            .createHmac("sha256", secret)
            .update(body)
            .digest("hex");

        const isValid = crypto.timingSafeEqual(
            Buffer.from(signature, "hex"),
            Buffer.from(expectedSignature, "hex")
        );

        if (!isValid) {
            logger.warn("Invalid webhook signature", {
                received: signature,
                expected: expectedSignature,
                bodyLength: body.length
            });
        }

        return {
            isValid,
            error: isValid ? undefined : "Invalid webhook signature",
            details: {
                received: signature,
                expected: expectedSignature,
                bodyLength: body.length
            }
        };
    } catch (error) {
        logger.error("Error verifying webhook signature", error);
        return {
            isValid: false,
            error: "Signature verification failed",
            details: { error: error instanceof Error ? error.message : String(error) }
        };
    }
}

/**
 * Verify completion signature (for AI service completion calls)
 */
export function verifyCompletionSignature(
    request: WebhookRequest,
    secret: string,
    signatureHeader: string = "x-completion-signature"
): SecurityValidationResult {
    try {
        const signature = request.headers[signatureHeader] as string;

        if (!signature) {
            return {
                isValid: false,
                error: "Missing completion signature",
                details: { header: signatureHeader }
            };
        }

        const body = typeof request.body === "string"
            ? request.body
            : JSON.stringify(request.body);

        const expectedSignature = crypto
            .createHmac("sha256", secret)
            .update(body)
            .digest("hex");

        const isValid = crypto.timingSafeEqual(
            Buffer.from(signature, "hex"),
            Buffer.from(expectedSignature, "hex")
        );

        return {
            isValid,
            error: isValid ? undefined : "Invalid completion signature",
            details: {
                received: signature,
                expected: expectedSignature
            }
        };
    } catch (error) {
        logger.error("Error verifying completion signature", error);
        return {
            isValid: false,
            error: "Completion signature verification failed",
            details: { error: error instanceof Error ? error.message : String(error) }
        };
    }
}

/**
 * Validate request origin (if needed for additional security)
 */
export function validateRequestOrigin(
    request: WebhookRequest,
    allowedOrigins: string[]
): SecurityValidationResult {
    try {
        const origin = request.headers["origin"] as string;
        const referer = request.headers["referer"] as string;

        if (!origin && !referer) {
            // Some webhook services don't send origin/referer headers
            // This is acceptable for webhook endpoints
            return { isValid: true };
        }

        const requestOrigin = origin || referer;

        if (!requestOrigin) {
            return { isValid: true }; // No origin to validate
        }

        const isValid = allowedOrigins.some(allowedOrigin => {
            return requestOrigin.startsWith(allowedOrigin);
        });

        return {
            isValid,
            error: isValid ? undefined : "Request origin not allowed",
            details: {
                requestOrigin,
                allowedOrigins
            }
        };
    } catch (error) {
        logger.error("Error validating request origin", error);
        return {
            isValid: false,
            error: "Origin validation failed",
            details: { error: error instanceof Error ? error.message : String(error) }
        };
    }
}

/**
 * Validate request payload structure
 */
export function validateWebhookPayload(payload: any): SecurityValidationResult {
    try {
        // Check for required fields
        if (!payload) {
            return {
                isValid: false,
                error: "Empty payload"
            };
        }

        // Validate event type
        if (!payload.event) {
            return {
                isValid: false,
                error: "Missing event type"
            };
        }

        const validEvents = [
            "generation.completed",
            "generation.failed",
            "generation.progress"
        ];

        if (!validEvents.includes(payload.event)) {
            return {
                isValid: false,
                error: "Invalid event type",
                details: {
                    received: payload.event,
                    validEvents
                }
            };
        }

        // Validate job ID
        if (!payload.jobId) {
            return {
                isValid: false,
                error: "Missing job ID"
            };
        }

        // Validate completion data for completed events
        if (payload.event === "generation.completed") {
            if (!payload.results) {
                return {
                    isValid: false,
                    error: "Missing results for completion event"
                };
            }
        }

        // Validate failure data for failed events
        if (payload.event === "generation.failed") {
            if (!payload.reason) {
                return {
                    isValid: false,
                    error: "Missing failure reason"
                };
            }
        }

        return { isValid: true };
    } catch (error) {
        logger.error("Error validating webhook payload", error);
        return {
            isValid: false,
            error: "Payload validation failed",
            details: { error: error instanceof Error ? error.message : String(error) }
        };
    }
}

/**
 * Validate completion payload structure
 */
export function validateCompletionPayload(payload: any): SecurityValidationResult {
    try {
        // Check for required fields
        if (!payload) {
            return {
                isValid: false,
                error: "Empty completion payload"
            };
        }

        // Validate status
        if (!payload.status) {
            return {
                isValid: false,
                error: "Missing completion status"
            };
        }

        const validStatuses = ["completed", "failed"];
        if (!validStatuses.includes(payload.status)) {
            return {
                isValid: false,
                error: "Invalid completion status",
                details: {
                    received: payload.status,
                    validStatuses
                }
            };
        }

        // Validate job ID
        if (!payload.jobId) {
            return {
                isValid: false,
                error: "Missing job ID"
            };
        }

        // Validate conversion ID
        if (!payload.conversionId) {
            return {
                isValid: false,
                error: "Missing conversion ID"
            };
        }

        // Validate completion data for completed status
        if (payload.status === "completed") {
            if (!payload.results && !payload.generatedImages) {
                return {
                    isValid: false,
                    error: "Missing results for completion"
                };
            }
        }

        // Validate failure data for failed status
        if (payload.status === "failed") {
            if (!payload.reason) {
                return {
                    isValid: false,
                    error: "Missing failure reason"
                };
            }
        }

        return { isValid: true };
    } catch (error) {
        logger.error("Error validating completion payload", error);
        return {
            isValid: false,
            error: "Completion payload validation failed",
            details: { error: error instanceof Error ? error.message : String(error) }
        };
    }
}

/**
 * Sanitize webhook data to prevent injection attacks
 */
export function sanitizeWebhookData(data: any): any {
    try {
        if (typeof data === "string") {
            // Remove potentially dangerous characters
            return data
                .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, "")
                .replace(/javascript:/gi, "")
                .replace(/on\w+\s*=/gi, "")
                .trim();
        }

        if (Array.isArray(data)) {
            return data.map(item => sanitizeWebhookData(item));
        }

        if (data && typeof data === "object") {
            const sanitized: any = {};
            for (const [key, value] of Object.entries(data)) {
                // Sanitize key names
                const sanitizedKey = key.replace(/[^a-zA-Z0-9_]/g, "");
                sanitized[sanitizedKey] = sanitizeWebhookData(value);
            }
            return sanitized;
        }

        return data;
    } catch (error) {
        logger.error("Error sanitizing webhook data", error);
        return data; // Return original data if sanitization fails
    }
}

/**
 * Log security event for monitoring
 */
export function logSecurityEvent(
    event: string,
    details: any,
    severity: "info" | "warn" | "error" = "info"
) {
    const logData = {
        timestamp: new Date().toISOString(),
        event,
        severity,
        details
    };

    switch (severity) {
        case "error":
            logger.error("Security Event", logData);
            break;
        case "warn":
            logger.warn("Security Event", logData);
            break;
        default:
            logger.info("Security Event", logData);
    }
}

/**
 * Create webhook signature for outbound requests
 */
export function createWebhookSignature(
    payload: any,
    secret: string
): string {
    const body = typeof payload === "string"
        ? payload
        : JSON.stringify(payload);

    return crypto
        .createHmac("sha256", secret)
        .update(body)
        .digest("hex");
}

/**
 * Create completion signature for AI service calls
 */
export function createCompletionSignature(
    payload: any,
    secret: string
): string {
    const body = typeof payload === "string"
        ? payload
        : JSON.stringify(payload);

    return crypto
        .createHmac("sha256", secret)
        .update(body)
        .digest("hex");
}
