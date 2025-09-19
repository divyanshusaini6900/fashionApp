/**
 * Setup Test Data for Webhook Flow Testing
 * 
 * This script creates test data in Firestore for testing the webhook flow
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin with project ID
admin.initializeApp({
    projectId: 'techrelieve-90c12'
});

// Firebase Admin is already initialized above

const db = admin.firestore();

/**
 * Create test user with credits
 */
async function createTestUser() {
    const testUserId = 'test_user_123';

    try {
        await db.collection('users').doc(testUserId).set({
            uid: testUserId,
            email: 'test@example.com',
            creditBalance: 100, // Give user 100 credits for testing
            lastUpdated: new Date(),
            name: 'Test User',
            createdAt: new Date()
        });

        console.log('✅ Test user created with 100 credits');
        return testUserId;
    } catch (error) {
        console.error('❌ Error creating test user:', error);
        throw error;
    }
}

/**
 * Create test job document
 */
async function createTestJob(userId) {
    const jobId = 'test_job_' + Date.now();

    try {
        await db.collection('GenSpace_jobs').doc(jobId).set({
            id: jobId,
            userId: userId,
            status: 'pending',
            createdAt: new Date(),
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
            creditCost: 10 // 3 images (3) + 1 video (5) + 1 excel (2) = 10 credits
        });

        console.log('✅ Test job created:', jobId);
        return jobId;
    } catch (error) {
        console.error('❌ Error creating test job:', error);
        throw error;
    }
}

/**
 * Create legacy credit transaction (for backward compatibility testing)
 */
async function createLegacyTransaction(userId) {
    try {
        await db.collection('creditTransactions').add({
            userId: userId,
            type: 'deduction',
            amount: 1,
            balanceBefore: 101,
            balanceAfter: 100,
            timestamp: new Date(),
            reason: 'image_upload'
            // Note: Missing new fields (status, operationType, etc.)
        });

        console.log('✅ Legacy transaction created');
    } catch (error) {
        console.error('❌ Error creating legacy transaction:', error);
        throw error;
    }
}

/**
 * Create new format credit transaction
 */
async function createNewFormatTransaction(userId, jobId) {
    try {
        await db.collection('creditTransactions').add({
            userId: userId,
            type: 'deduction',
            amount: 10,
            balanceBefore: 100,
            balanceAfter: 90,
            timestamp: new Date(),
            status: 'completed',
            operationType: 'pending_deduction',
            jobId: jobId,
            reason: 'AI_generation_initiated',
            requestData: {
                generateVideo: true,
                generateCsv: true,
                imagesToGenerate: 3
            },
            creditUsageBreakdown: {
                images: {
                    requested: 3,
                    creditsPerImage: 1,
                    totalCredits: 3
                },
                video: {
                    requested: 1,
                    creditsPerVideo: 5,
                    totalCredits: 5
                },
                excel: {
                    requested: 1,
                    creditsPerExcel: 2,
                    totalCredits: 2
                },
                totalEstimatedCredits: 10
            },
            actualCreditUsage: {
                images: {
                    generated: 3,
                    creditsPerImage: 1,
                    totalCredits: 3
                },
                video: {
                    generated: 1,
                    creditsPerVideo: 5,
                    totalCredits: 5
                },
                excel: {
                    generated: 0, // Excel generation failed
                    creditsPerExcel: 2,
                    totalCredits: 0
                },
                totalActualCredits: 8
            },
            actualResults: {
                imageCount: 3,
                hasVideo: true,
                hasExcel: false
            },
            completedAt: new Date()
        });

        console.log('✅ New format transaction created');
    } catch (error) {
        console.error('❌ Error creating new format transaction:', error);
        throw error;
    }
}

/**
 * Setup all test data
 */
async function setupTestData() {
    console.log('🚀 Setting up test data...\n');

    try {
        // Create test user
        const userId = await createTestUser();

        // Create test job
        const jobId = await createTestJob(userId);

        // Create legacy transaction
        await createLegacyTransaction(userId);

        // Create new format transaction
        await createNewFormatTransaction(userId, jobId);

        console.log('\n🎉 Test data setup completed!');
        console.log('Test User ID:', userId);
        console.log('Test Job ID:', jobId);

    } catch (error) {
        console.error('💥 Test data setup failed:', error);
        process.exit(1);
    }
}

/**
 * Clean up test data
 */
async function cleanupTestData() {
    console.log('🧹 Cleaning up test data...');

    try {
        // Delete test user
        await db.collection('users').doc('test_user_123').delete();

        // Delete test jobs
        const jobs = await db.collection('GenSpace_jobs')
            .where('userId', '==', 'test_user_123')
            .get();

        const batch = db.batch();
        jobs.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();

        // Delete test transactions
        const transactions = await db.collection('creditTransactions')
            .where('userId', '==', 'test_user_123')
            .get();

        const transactionBatch = db.batch();
        transactions.docs.forEach(doc => transactionBatch.delete(doc.ref));
        await transactionBatch.commit();

        console.log('✅ Test data cleaned up');
    } catch (error) {
        console.error('❌ Error cleaning up test data:', error);
        throw error;
    }
}

// Run setup if called directly
if (require.main === module) {
    const command = process.argv[2];

    if (command === 'cleanup') {
        cleanupTestData();
    } else {
        setupTestData();
    }
}

module.exports = {
    createTestUser,
    createTestJob,
    createLegacyTransaction,
    createNewFormatTransaction,
    setupTestData,
    cleanupTestData
};
