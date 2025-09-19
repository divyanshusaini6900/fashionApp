/**
 * Test Script for Webhook-Based Credit Flow
 * 
 * This script tests the complete webhook flow:
 * 1. ai-generation-initiator
 * 2. ai-completion-handler
 * 3. Credit usage analytics
 */

const axios = require('axios');
const crypto = require('crypto');

// Configuration
const BASE_URL = 'https://us-central1-techrelieve-90c12.cloudfunctions.net';
const TEST_USER_ID = 'test_user_123';
const TEST_JOB_ID = 'test_job_' + Date.now();

// Webhook secrets (same as set in Firebase)
const GENERATION_WEBHOOK_SECRET = 'ed1b8fa79c597a214b124e176df8df59fa377d3d1ca305aa399f619f35b4893d';
const COMPLETION_WEBHOOK_SECRET = 'b808bde109a135b15f552c427bdf395b451e5f2650d1c10e3bcb31ec67412801';

/**
 * Generate webhook signature for authentication
 */
function generateWebhookSignature(payload, secret) {
    const signature = crypto
        .createHmac('sha256', secret)
        .update(JSON.stringify(payload))
        .digest('hex');
    return signature; // Return just the hex string, not prefixed
}

// Test data
const testGenerationRequest = {
    jobId: TEST_JOB_ID,
    userId: TEST_USER_ID,
    requestData: {
        generateVideo: true,
        generateCsv: true,
        imagesToGenerate: 3,
        text: 'Test product description',
        productType: 'clothing',
        gender: 'Male'
    },
    uploadedImageUrls: [
        'https://example.com/test-image-1.jpg',
        'https://example.com/test-image-2.jpg'
    ],
    creditCost: 4.5 // 3 images (3×1) + 1 video (1×1) + 1 excel (1×0.5) = 4.5 credits
};

const testCompletionData = {
    jobId: TEST_JOB_ID,
    conversionId: 'test_conversion_' + Date.now(),
    status: 'completed',
    generatedImages: [
        { imageSrc: 'https://example.com/generated-1.jpg' },
        { imageSrc: 'https://example.com/generated-2.jpg' },
        { imageSrc: 'https://example.com/generated-3.jpg' }
    ],
    generatedVideos: [
        { videoUrl: 'https://example.com/generated-video.mp4' }
    ],
    csv: null, // Excel generation failed
    description: 'Generated test product description',
    keyFeatures: ['Feature 1', 'Feature 2'],
    searchKeywords: ['test', 'product']
};

/**
 * Test 1: AI Generation Initiator
 */
async function testGenerationInitiator() {
    console.log('🧪 Testing AI Generation Initiator...');

    try {
        const signature = generateWebhookSignature(testGenerationRequest, GENERATION_WEBHOOK_SECRET);
        
        const response = await axios.post(
            `${BASE_URL}/aiGenerationInitiator`,
            testGenerationRequest,
            {
                headers: {
                    'Content-Type': 'application/json',
                    'x-webhook-signature': signature
                }
            }
        );

        console.log('✅ Generation Initiator Response:', response.data);
        return response.data;
    } catch (error) {
        console.error('❌ Generation Initiator Error:', error.response?.data || error.message);
        throw error;
    }
}

/**
 * Test 2: AI Completion Handler
 */
async function testCompletionHandler() {
    console.log('🧪 Testing AI Completion Handler...');

    try {
        const signature = generateWebhookSignature(testCompletionData, COMPLETION_WEBHOOK_SECRET);
        
        const response = await axios.post(
            `${BASE_URL}/aiCompletionHandler`,
            testCompletionData,
            {
                headers: {
                    'Content-Type': 'application/json',
                    'x-webhook-signature': signature
                }
            }
        );

        console.log('✅ Completion Handler Response:', response.data);
        return response.data;
    } catch (error) {
        console.error('❌ Completion Handler Error:', error.response?.data || error.message);
        throw error;
    }
}

/**
 * Test 3: User Credit Usage Analytics
 */
async function testUserAnalytics() {
    console.log('🧪 Testing User Credit Usage Analytics...');

    try {
        const response = await axios.get(
            `${BASE_URL}/getUserCreditUsageAnalytics`,
            {
                params: {
                    userId: TEST_USER_ID,
                    startDate: '2024-01-01',
                    endDate: '2024-12-31',
                    groupBy: 'day'
                }
            }
        );

        console.log('✅ User Analytics Response:', response.data);
        return response.data;
    } catch (error) {
        console.error('❌ User Analytics Error:', error.response?.data || error.message);
        throw error;
    }
}

/**
 * Test 4: Admin Credit Usage Statistics
 */
async function testAdminStats() {
    console.log('🧪 Testing Admin Credit Usage Statistics...');

    try {
        const response = await axios.get(
            `${BASE_URL}/getAdminCreditUsageStats`,
            {
                params: {
                    startDate: '2024-01-01',
                    endDate: '2024-12-31',
                    groupBy: 'day'
                }
            }
        );

        console.log('✅ Admin Stats Response:', response.data);
        return response.data;
    } catch (error) {
        console.error('❌ Admin Stats Error:', error.response?.data || error.message);
        throw error;
    }
}

/**
 * Test 5: Test Failed Generation
 */
async function testFailedGeneration() {
    console.log('🧪 Testing Failed Generation...');

    const failedCompletionData = {
        ...testCompletionData,
        status: 'failed',
        error: 'AI service timeout',
        reason: 'Generation failed due to timeout'
    };

    try {
        const signature = generateWebhookSignature(failedCompletionData, COMPLETION_WEBHOOK_SECRET);
        
        const response = await axios.post(
            `${BASE_URL}/aiCompletionHandler`,
            failedCompletionData,
            {
                headers: {
                    'Content-Type': 'application/json',
                    'x-webhook-signature': signature
                }
            }
        );

        console.log('✅ Failed Generation Response:', response.data);
        return response.data;
    } catch (error) {
        console.error('❌ Failed Generation Error:', error.response?.data || error.message);
        throw error;
    }
}

/**
 * Run all tests
 */
async function runAllTests() {
    console.log('🚀 Starting Webhook Flow Tests...\n');

    try {
        // Test 1: Generation Initiator
        await testGenerationInitiator();
        console.log('');

        // Wait a bit for processing
        console.log('⏳ Waiting 2 seconds...');
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Test 2: Completion Handler
        await testCompletionHandler();
        console.log('');

        // Wait a bit for processing
        console.log('⏳ Waiting 2 seconds...');
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Test 3: User Analytics
        await testUserAnalytics();
        console.log('');

        // Test 4: Admin Stats
        await testAdminStats();
        console.log('');

        // Test 5: Failed Generation
        await testFailedGeneration();
        console.log('');

        console.log('🎉 All tests completed successfully!');

    } catch (error) {
        console.error('💥 Test suite failed:', error.message);
        process.exit(1);
    }
}

/**
 * Test individual components
 */
async function testIndividual() {
    const testType = process.argv[2];

    switch (testType) {
        case 'initiator':
            await testGenerationInitiator();
            break;
        case 'completion':
            await testCompletionHandler();
            break;
        case 'user-analytics':
            await testUserAnalytics();
            break;
        case 'admin-stats':
            await testAdminStats();
            break;
        case 'failed':
            await testFailedGeneration();
            break;
        default:
            console.log('Available tests: initiator, completion, user-analytics, admin-stats, failed');
            console.log('Usage: node test-webhook-flow.js [test-type]');
            console.log('Or run all tests: node test-webhook-flow.js');
    }
}

// Run tests
if (require.main === module) {
    if (process.argv.length > 2) {
        testIndividual();
    } else {
        runAllTests();
    }
}

module.exports = {
    testGenerationInitiator,
    testCompletionHandler,
    testUserAnalytics,
    testAdminStats,
    testFailedGeneration,
    runAllTests
};
