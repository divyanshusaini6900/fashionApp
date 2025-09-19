const axios = require('axios');

// Test completion data with the latest job ID
const testCompletionData = {
    status: 'completed',
    jobId: 'test_job_1757772222439', // Use the job ID from our last successful initiator test
    conversionId: 'fashionai_1757772229278_5oj59mqle',
    generatedImages: [
        {
            imageSrc: 'https://example.com/test-image-1.jpg',
            type: 'generated'
        },
        {
            imageSrc: 'https://example.com/test-image-2.jpg',
            type: 'generated'
        },
        {
            imageSrc: 'https://example.com/test-image-3.jpg',
            type: 'generated'
        }
    ],
    generatedVideos: [
        {
            videoUrl: 'https://example.com/test-video.mp4'
        }
    ],
    csv: 'https://example.com/test-data.csv',
    description: 'Test product description',
    keyFeatures: ['Feature 1', 'Feature 2', 'Feature 3'],
    searchKeywords: ['test', 'product', 'generated'],
    actualCreditUsage: {
        images: 3,
        video: 1,
        excel: 1,
        total: 4.5 // 3×1 + 1×1 + 1×0.5 = 4.5 credits
    }
};

async function testCompletionWithDebug() {
    console.log('🧪 Testing Completion Handler with Debug Logs...');
    console.log('📦 Completion Data:', JSON.stringify(testCompletionData, null, 2));

    try {
        const response = await axios.post(
            'https://us-central1-techrelieve-90c12.cloudfunctions.net/aiCompletionHandler',
            testCompletionData,
            {
                headers: {
                    'Content-Type': 'application/json'
                }
            }
        );

        console.log('✅ Completion Handler Response:', response.data);
        return response.data;
    } catch (error) {
        console.log('❌ Completion Handler Error:', error.response?.data || error.message);
        console.log('🔍 Check Firebase Functions logs for detailed error information');
        return null;
    }
}

async function main() {
    console.log('🚀 Starting Completion Handler Debug Test...\n');

    const result = await testCompletionWithDebug();

    if (result) {
        console.log('\n🎉 Completion Handler Test completed successfully!');
    } else {
        console.log('\n💥 Completion Handler Test failed - check logs above');
    }
}

main().catch(console.error);
