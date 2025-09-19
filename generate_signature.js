const crypto = require('crypto');

// Your webhook secret
const webhookSecret = 'whsec_01985f455b23d98442a7a18c459f9e2e300923ea8a0e7f563945740650f09d73';

// Test webhook payload
const payload = {
    "event": "payment.captured",
    "account_id": "acc_test123",
    "contains": ["payment"],
    "payload": {
        "payment": {
            "entity": {
                "id": "pay_test123",
                "amount": 10000,
                "currency": "INR",
                "status": "captured",
                "order_id": "order_test123",
                "method": "card",
                "description": "Test payment",
                "notes": {
                    "user_id": "test_user_123",
                    "payment_type": "pay_as_you_go",
                    "credits": "10"
                }
            }
        }
    },
    "created_at": 1640995200
};

// Convert to JSON string (exactly as Razorpay sends it)
const payloadString = JSON.stringify(payload);

// Generate HMAC SHA256 signature
const signature = crypto
    .createHmac('sha256', webhookSecret)
    .update(payloadString)
    .digest('hex');

console.log('=== WEBHOOK TEST SIGNATURE ===');
console.log('X-Razorpay-Signature:', signature);
console.log('\n=== POSTMAN HEADERS ===');
console.log('Content-Type: application/json');
console.log('X-Razorpay-Signature:', signature);
console.log('\n=== POSTMAN URL ===');
console.log('POST https://razorpaywebhook-wmplavenaa-uc.a.run.app/');
console.log('\n=== POSTMAN BODY (Raw JSON) ===');
console.log(payloadString);




