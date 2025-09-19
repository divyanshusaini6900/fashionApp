# 🔧 Environment-Based Key Configuration

This guide shows how to configure Razorpay keys using environment variables for better security.

## 🚀 How to Use Environment Variables

### Method 1: Build-time Environment Variables (Recommended)

When building your app, pass the production key as a build argument:

```bash
# For release build with production key
flutter build apk --release --dart-define=RAZORPAY_LIVE_KEY_ID=rzp_live_nwXGjw3WE3n2jX

# For app bundle with production key
flutter build appbundle --release --dart-define=RAZORPAY_LIVE_KEY_ID=rzp_live_nwXGjw3WE3n2jX
```

### Method 2: IDE Configuration

#### VS Code:

Add to your `launch.json`:

```json
{
  "configurations": [
    {
      "name": "Flutter (Production)",
      "request": "launch",
      "type": "dart",
      "args": ["--dart-define=RAZORPAY_LIVE_KEY_ID=rzp_live_nwXGjw3WE3n2jX"]
    }
  ]
}
```

#### Android Studio:

1. Go to **Run** → **Edit Configurations**
2. Add to **Additional arguments**:
   ```
   --dart-define=RAZORPAY_LIVE_KEY_ID=rzp_live_nwXGjw3WE3n2jX
   ```

## 🔑 Production Key Configuration

✅ **Production key is already configured**: `rzp_live_nwXGjw3WE3n2jX`

The app will automatically use this key in production mode. You can still override it with environment variables if needed.

## 📱 Environment Behavior

### Debug Mode (`flutter run`):

- ✅ Uses test key: `rzp_test_RGKHJR9OqyYFUF`
- ✅ No environment variable needed
- ✅ Safe for development

### Release Mode (`flutter build apk --release`):

- ✅ Uses production key from environment variable
- ✅ Falls back to placeholder if not provided
- ✅ Validates key configuration on startup

## 🔍 Validation

The app validates configuration on startup:

```dart
// Automatic validation
if (RazorpayConfig.isProductionMode && !RazorpayConfig.isProductionKeyConfigured) {
  throw Exception('Production Razorpay key not configured');
}
```

## 📊 Debug Output

When running in debug mode, you'll see:

```
🏦 RazorPay Service initialized successfully
🔧 Environment: PRODUCTION
🔑 Key ID: rzp_live_...
📊 Config: {environment: PRODUCTION, keyId: rzp_live_..., ...}
```

## ⚠️ Security Notes

- **Never commit production keys to version control**
- **Use environment variables for production builds**
- **Test with small amounts first**
- **Keep your production keys secure**

## 🚀 Quick Commands

```bash
# Build with production key
flutter build apk --release --dart-define=RAZORPAY_LIVE_KEY_ID=rzp_live_nwXGjw3WE3n2jX

# Run with production key (for testing)
flutter run --dart-define=RAZORPAY_LIVE_KEY_ID=rzp_live_nwXGjw3WE3n2jX
```

---

**Your Razorpay keys are now securely managed through environment variables!** 🔐
