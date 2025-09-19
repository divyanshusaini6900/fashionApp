import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../../features/wallet/models/subscription_model.dart';

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> initialize() async {
    // Initialize Firebase services if needed
    try {
      // Ensure Firebase Auth is ready
      await _auth.authStateChanges().first;
      if (kDebugMode) print('✅ Firebase Auth initialized');
      // Test Firestore connection
      await _firestore.collection('test').doc('test').set({
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (kDebugMode) print('✅ Firestore connection verified');
      await Future.delayed(ApiConfig.serviceInitDelay);
    } catch (e) {
      if (kDebugMode) print('⚠️ Firebase initialization warning: $e');
      // Continue anyway as Firebase might still work
    }
  }

  // Auth Methods with inline error handling
  static User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (e) {
      if (kDebugMode) print('Error getting current user: $e');
      return null;
    }
  }

  static Stream<User?> get authStateChanges {
    try {
      return _auth.authStateChanges().handleError((error) {
        if (kDebugMode) print('Auth state change error: $error');
        // Ignore PigeonUserDetails errors
        if (error.toString().contains('PigeonUserDetails')) {
          if (kDebugMode) print('Ignoring PigeonUserDetails type cast error');
          return null;
        }
        return null;
      });
    } catch (e) {
      if (kDebugMode) print('Error setting up auth state changes: $e');
      return Stream.value(null);
    }
  }

  static Future<UserCredential?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      // Trim email and password
      email = email.trim();
      password = password.trim();

      print('🔐 Attempting sign in for: $email');

      // Validate email format
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        throw 'Please enter a valid email address format.';
      }
      // Clear any existing auth state
      try {
        await _auth.signOut();
        await Future.delayed(ApiConfig.retryDelay);
      } catch (e) {
        print('Warning: Could not sign out existing user: $e');
      }
      UserCredential? credential;
      try {
        credential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (e) {
        // Handle PigeonUserDetails error specifically
        if (e.toString().contains('PigeonUserDetails')) {
          print('⚠️ Ignoring PigeonUserDetails error, retrying...');
          // Wait and retry
          await Future.delayed(ApiConfig.retryDelay);
          // Check if user is actually logged in despite the error
          final user = _auth.currentUser;
          if (user != null && user.email == email) {
            print('✅ User is logged in despite error');
            // Create a synthetic credential
            return null; // We'll handle this in the calling code
          }
        }
        throw e;
      }

      // Wait for auth state to stabilize
      await Future.delayed(ApiConfig.retryDelay);

      print('✅ Sign in successful');

      // Ensure user document exists
      if (credential.user != null) {
        await _ensureUserDocument(credential.user!);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Exception: ${e.code} - ${e.message}');

      // Provide specific error messages
      String errorMessage = _getAuthErrorMessage(e.code);

      // Special handling for invalid-credential
      if (e.code == 'invalid-credential' ||
          e.code == 'INVALID_LOGIN_CREDENTIALS') {
        errorMessage =
            'Invalid email or password. Please check your credentials and try again.';
      }

      throw errorMessage;
    } catch (e) {
      print('❌ Sign in error: $e');

      // Handle PigeonUserDetails error
      if (e.toString().contains('PigeonUserDetails')) {
        // Check if user is actually logged in
        await Future.delayed(ApiConfig.retryDelay);
        final user = _auth.currentUser;
        if (user != null) {
          print('✅ User logged in successfully despite error');
          await _ensureUserDocument(user);
          return null; // Success despite error
        }
      }

      // If it's our custom error message, throw it as is
      if (e is String) {
        throw e;
      }

      throw 'An unexpected error occurred. Please try again.';
    }
  }

  static Future<void> signOut() async {
    try {
      print('🚪 Signing out user...');
      await _auth.signOut();
      print('✅ User signed out successfully');
    } catch (e) {
      print('❌ Error signing out: $e');
      throw 'Failed to sign out: ${e.toString()}';
    }
  }

  static String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email address. Please check your email or sign up.';
      case 'wrong-password':
        return 'Incorrect password. Please check your password and try again.';
      case 'invalid-email':
        return 'The email address format is invalid. Please enter a valid email.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed login attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password login is not enabled. Please contact support.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection and try again.';
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Invalid email or password. Please check your credentials and try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'The password is too weak. Please use a stronger password.';
      default:
        return 'Login failed. Please check your email and password.';
    }
  }

  // Phone Authentication Methods
  static Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential) onVerificationCompleted,
    required void Function(FirebaseAuthException) onVerificationFailed,
    required void Function(String, int?) onCodeSent,
    required void Function(String) onCodeAutoRetrievalTimeout,
  }) async {
    try {
      print('📱 Starting phone verification for: $phoneNumber');

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: onVerificationCompleted,
        verificationFailed: onVerificationFailed,
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: onCodeAutoRetrievalTimeout,
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      print('❌ Phone verification error: $e');
      throw 'Phone verification failed: ${e.toString()}';
    }
  }

  // Public method to ensure user document exists
  static Future<void> ensureUserDocument(User user) async {
    await _ensureUserDocument(user);
  }

  // Update user profile with additional information (used after signup)
  static Future<void> updateUserProfileAfterSignup(
    User user, {
    required String name,
    required String email,
    required String phoneNumber,
  }) async {
    try {
      print('📝 Updating user profile for ${user.uid}');

      // Update Firebase Auth profile
      await user.updateDisplayName(name);

      // Update Firestore document with the provided Full Name
      final docRef = _firestore.collection('users').doc(user.uid);
      print('📝 Updating user profile with Full Name: "$name"');

      await docRef.set({
        'uid': user.uid,
        'email': email,
        'displayName': name.trim(), // Ensure we use the trimmed Full Name
        'fullName': name.trim(), // Ensure we use the trimmed Full Name
        'phoneNumber': phoneNumber,
        'photoURL': user.photoURL ?? '',
        'creditBalance': 0.0, // Use double for consistency
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(), // Add lastLogin field
        'isEmailVerified': user.emailVerified,
        'isPhoneVerified': phoneNumber.isNotEmpty,
      }, SetOptions(merge: true));

      print(
          '✅ User profile updated with displayName and fullName: "${name.trim()}"');

      print('✅ User profile updated successfully');
    } catch (e) {
      print('❌ Error updating user profile: $e');
      throw 'Failed to update user profile: ${e.toString()}';
    }
  }

  // Ensure user document exists in Firestore
  static Future<void> _ensureUserDocument(User user) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);

      final doc = await docRef.get().timeout(
            ApiConfig.firestoreTimeout,
            onTimeout: () => throw 'Timeout creating user document',
          );

      if (!doc.exists) {
        print('📝 Creating user document for ${user.uid}');

        // Create minimal user document - signup process should create complete document
        // Only create this if it's absolutely necessary (edge cases)
        final displayName =
            user.displayName ?? user.email?.split('@').first ?? 'User';
        await docRef.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': displayName,
          'fullName':
              displayName, // Use same value as displayName for consistency
          'phoneNumber': user.phoneNumber ?? '',
          'photoURL': user.photoURL ?? '',
          'creditBalance': 0.0, // Use double for consistency
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastLogin':
              FieldValue.serverTimestamp(), // Add lastLogin for new users
          'isEmailVerified': user.emailVerified,
          'isPhoneVerified':
              user.phoneNumber != null && user.phoneNumber!.isNotEmpty,
        });

        print('✅ User document created');
      } else {
        // Update last login with timeout
        await docRef.update({
          'lastLogin': FieldValue.serverTimestamp(),
        }).timeout(
          ApiConfig.authTimeout,
          onTimeout: () => print('Timeout updating last login'),
        );
      }
    } catch (e) {
      print('Error ensuring user document: $e');
      // Don't throw - this is not critical for auth
    }
  }

  // Storage Methods
  static Future<List<String>> uploadImages(List<XFile> images) async {
    print('🚀 Starting upload process for ${images.length} images');
    // Check if user is authenticated
    if (currentUser == null) {
      throw 'User not authenticated. Please login first.';
    }

    print('✅ User authenticated: ${currentUser!.email}');

    final List<String> exportUrls = [];

    for (int i = 0; i < images.length; i++) {
      final XFile image = images[i];
      final String fileName =
          'uploads/${currentUser!.uid}/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';

      print('📤 Uploading image ${i + 1}/${images.length}: $fileName');

      try {
        // Check file exists
        final File file = File(image.path);
        if (!await file.exists()) {
          throw 'Image file not found: ${image.path}';
        }

        print('✅ File exists, size: ${await file.length()} bytes');

        final Reference ref = _storage.ref().child(fileName);

        // Add metadata
        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploaded_by': currentUser!.email ?? 'unknown',
            'upload_time': DateTime.now().toIso8601String(),
          },
        );

        final UploadTask uploadTask = ref.putFile(file, metadata);

        // Monitor upload progress
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          double progress = snapshot.bytesTransferred / snapshot.totalBytes;
          print(
              '📊 Upload progress for image ${i + 1}: ${(progress * 100).toStringAsFixed(1)}%');
        });

        final TaskSnapshot snapshot = await uploadTask;
        print('✅ Upload complete for image ${i + 1}');

        final String exportUrl = await snapshot.ref.getDownloadURL();
        print('🔗 export URL obtained: ${exportUrl.substring(0, 50)}...');

        exportUrls.add(exportUrl);
      } catch (e) {
        print('❌ Error uploading image ${i + 1}: $e');
        throw 'Error uploading image ${i + 1}: ${e.toString()}';
      }
    }
    print('🎉 All uploads completed successfully!');
    return exportUrls;
  }

  // Get user uploads without compound index requirement
  static Future<List<Map<String, dynamic>>> getUserUploads() async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      print('📊 Fetching uploads for user: ${user.uid}');

      // Simple query without orderBy to avoid index requirement
      final QuerySnapshot snapshot = await _firestore
          .collection('uploads')
          .where('userId', isEqualTo: user.uid)
          .get();

      print('✅ Found ${snapshot.docs.length} upload records');

      final uploads = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID
        return data;
      }).toList();

      // Sort in memory by timestamp (newest first)
      uploads.sort((a, b) {
        final timestampA = a['timestamp'] as Timestamp?;
        final timestampB = b['timestamp'] as Timestamp?;
        if (timestampA == null || timestampB == null) return 0;
        return timestampB.compareTo(timestampA); // Descending order
      });

      return uploads;
    } catch (e) {
      print('❌ Error fetching user uploads: $e');
      throw 'Error fetching uploads: ${e.toString()}';
    }
  }

  // export Methods - Filter by current user
  static Future<List<exportableVideo>> getexportableVideos() async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      // Query videos only for the current user
      final QuerySnapshot snapshot = await _firestore
          .collection('exportable_videos')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return exportableVideo(
          id: doc.id,
          title: data['title'] ?? 'Untitled',
          videoUrl: data['videoUrl'] ?? '',
          thumbnailUrl: data['thumbnailUrl'] ?? '',
          timestamp: data['timestamp'] as Timestamp?,
        );
      }).toList();
    } catch (e) {
      print('❌ Error fetching exportable videos: $e');
      throw 'Error fetching exportable videos: ${e.toString()}';
    }
  }

  // Save video for export (associate with current user)
  static Future<void> saveVideoForexport({
    required String title,
    required String videoUrl,
    required String thumbnailUrl,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      await _firestore.collection('exportable_videos').add({
        'userId': user.uid,
        'userEmail': user.email,
        'title': title,
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ Video saved for export successfully');
    } catch (e) {
      print('❌ Error saving video for export: $e');
      throw 'Error saving video for export: ${e.toString()}';
    }
  }

  // User Methods
  static Future<Map<String, dynamic>?> getUserData() async {
    try {
      if (currentUser == null) return null;

      final doc =
          await _firestore.collection('users').doc(currentUser!.uid).get();

      if (doc.exists) {
        return doc.data();
      }

      // Create user document if it doesn't exist
      await _ensureUserDocument(currentUser!);

      // Fetch again
      final newDoc =
          await _firestore.collection('users').doc(currentUser!.uid).get();

      return newDoc.data();
    } catch (e) {
      print('Error fetching user data: $e');
      throw 'Error fetching user data: ${e.toString()}';
    }
  }

  static Future<void> updateUserData(Map<String, dynamic> data) async {
    try {
      if (currentUser == null) {
        throw 'User not authenticated';
      }
      await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      throw 'Error updating user data: ${e.toString()}';
    }
  }

  // Wallet Methods
  static Future<double> getUsercreditBalance() async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final dynamic balance = data['creditBalance'] ?? 0.0;
        return balance is int ? balance.toDouble() : (balance as double);
      } else {
        // Create comprehensive user document for new users
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName':
              user.displayName ?? user.email?.split('@').first ?? 'User',
          'fullName':
              user.displayName ?? user.email?.split('@').first ?? 'User',
          'phoneNumber': user.phoneNumber ?? '',
          'photoURL': user.photoURL ?? '',
          'creditBalance': 0.0, // Only new users get 0.0 Credits
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'isEmailVerified': user.emailVerified,
          'isPhoneVerified':
              user.phoneNumber != null && user.phoneNumber!.isNotEmpty,
        });
        return 0.0;
      }
    } catch (e) {
      print('❌ Error fetching credit balance: $e');
      throw 'Error fetching credit balance: ${e.toString()}';
    }
  }

  // Real-time credit balance stream
  static Stream<double> getcreditBalanceStream() {
    final user = currentUser;
    if (user == null) {
      return Stream.error('User not authenticated');
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .handleError((error) {
      print('credit balance stream error: $error');
      return 0.0;
    }).map((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final dynamic balance = data['creditBalance'] ?? 0.0;
        return balance is int ? balance.toDouble() : (balance as double);
      } else {
        // Create comprehensive user document if it doesn't exist (new user only)

        // NO fallbacks - only save displayName/fullName if user actually has displayName
        Map<String, dynamic> userData = {
          'uid': user.uid,
          'email': user.email ?? '',

          'phoneNumber': user.phoneNumber ?? '',
          'photoURL': user.photoURL ?? '',
          'creditBalance': 0.0, // Only new users get 0.0 Credits
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'isEmailVerified': user.emailVerified,
          'isPhoneVerified':
              user.phoneNumber != null && user.phoneNumber!.isNotEmpty,
        };

        // Only add displayName/fullName if actual displayName exists
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          userData['displayName'] = user.displayName!;
          userData['fullName'] = user.displayName!;
        }

        _firestore.collection('users').doc(user.uid).set(userData);

        return 0.0;
      }
    });
  }

  // Real-time user data stream
  static Stream<Map<String, dynamic>?> getUserDataStream() {
    final user = currentUser;
    if (user == null) {
      return Stream.error('User not authenticated');
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .handleError((error) {
      print('User data stream error: $error');
      if (error.toString().contains('PigeonUserDetails')) {
        print('Ignoring PigeonUserDetails error in stream');
      }
      return null;
    }).map((doc) {
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      } else {
        // Create comprehensive user document if it doesn't exist (new user only)

        // NO fallbacks - only save displayName/fullName if user actually has displayName
        final userData = <String, dynamic>{
          'uid': user.uid,
          'email': user.email ?? '',
          'phoneNumber': user.phoneNumber ?? '',
          'photoURL': user.photoURL ?? '',
          'creditBalance': 0.0, // Only new users get 0.0 Credits
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'isEmailVerified': user.emailVerified,
          'isPhoneVerified':
              user.phoneNumber != null && user.phoneNumber!.isNotEmpty,
        };

        // Only add displayName/fullName if actual displayName exists
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          userData['displayName'] = user.displayName!;
          userData['fullName'] = user.displayName!;
        }

        _firestore.collection('users').doc(user.uid).set(userData);
        return userData;
      }
    });
  }

  // Update user display name - FIXED VERSION
  static Future<void> updateUserDisplayName(String displayName) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      // First update Firestore (more reliable)
      await _firestore.collection('users').doc(user.uid).set({
        'displayName': displayName.trim(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Display name updated in Firestore');

      // Then try to update Firebase Auth profile
      // Wrap in try-catch to handle platform channel errors
      try {
        // Use updateProfile instead of updateDisplayName to avoid platform issues
        await user.updateProfile(displayName: displayName.trim());
        await user.reload();
        print('✅ Display name updated in Firebase Auth');
      } catch (authError) {
        // Log the error but don't throw - Firestore update was successful
        print('⚠️ Warning: Could not update Firebase Auth profile: $authError');
        print(
            'Display name is still updated in Firestore and will be used by the app');
      }
    } catch (e) {
      print('❌ Error updating display name: $e');
      throw 'Error updating display name: ${e.toString()}';
    }
  }

  // Upload profile image to Firebase Storage
  static Future<String> uploadProfileImage(File imageFile) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final fileName =
          'profile_${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('profile_images').child(fileName);

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final exportUrl = await snapshot.ref.getDownloadURL();

      print('✅ Profile image uploaded successfully');
      return exportUrl;
    } catch (e) {
      print('❌ Error uploading profile image: $e');
      throw 'Error uploading profile image: ${e.toString()}';
    }
  }

  // Update user photo URL in Firebase Auth
  static Future<void> updateUserPhotoURL(String photoURL) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      await user.updateProfile(photoURL: photoURL);
      await user.reload();
      print('✅ Profile photo URL updated in Firebase Auth');
    } catch (e) {
      print('⚠️ Warning: Could not update Firebase Auth photo URL: $e');
      // Don't throw - this is not critical
    }
  }

  // Update user profile in Firestore
  static Future<void> updateUserProfile(Map<String, dynamic> updates) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(updates, SetOptions(merge: true));
      print('✅ User profile updated in Firestore');
    } catch (e) {
      print('❌ Error updating user profile: $e');
      throw 'Error updating user profile: ${e.toString()}';
    }
  }

  static Future<double> deductCredits(double amount,
      {required String reason, String? operationType}) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final docRef = _firestore.collection('users').doc(user.uid);

      return await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          throw 'User document not found';
        }

        final dynamic currentBalanceRaw = doc.data()?['creditBalance'] ?? 0.0;
        final double currentBalance = currentBalanceRaw is int
            ? currentBalanceRaw.toDouble()
            : (currentBalanceRaw as double);

        if (currentBalance < amount) {
          throw 'Insufficient Credits. You have $currentBalance Credits but need $amount Credits.';
        }

        final double newBalance = currentBalance - amount;
        transaction.update(docRef, {
          'creditBalance': newBalance,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        // Log transaction
        transaction.set(_firestore.collection('creditTransactions').doc(), {
          'userId': user.uid,
          'type': 'deduction',
          'amount': amount,
          'balanceBefore': currentBalance,
          'balanceAfter': newBalance,
          'timestamp': FieldValue.serverTimestamp(),
          'reason': reason,
          'operationType':
              operationType, // Add operation type for better categorization
        });

        return newBalance;
      });
    } catch (e) {
      print('❌ Error deducting Credits: $e');
      throw e.toString();
    }
  }

  static Future<double> addCredits(double amount) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final docRef = _firestore.collection('users').doc(user.uid);

      return await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        final dynamic currentBalanceRaw =
            doc.exists ? (doc.data()?['creditBalance'] ?? 0.0) : 0.0;
        final double currentBalance = currentBalanceRaw is int
            ? currentBalanceRaw.toDouble()
            : (currentBalanceRaw as double);
        final double newBalance = currentBalance + amount;

        if (doc.exists) {
          transaction.update(docRef, {
            'creditBalance': newBalance,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.set(docRef, {
            'creditBalance': newBalance,
            'createdAt': FieldValue.serverTimestamp(),
            'email': user.email,
          });
        }

        // Log transaction
        transaction.set(_firestore.collection('creditTransactions').doc(), {
          'userId': user.uid,
          'type': 'addition',
          'amount': amount,
          'balanceBefore': currentBalance,
          'balanceAfter': newBalance,
          'timestamp': FieldValue.serverTimestamp(),
          'reason': 'credit_addition',
        });

        return newBalance;
      });
    } catch (e) {
      print('❌ Error adding Credits: $e');
      throw 'Error adding Credits: ${e.toString()}';
    }
  }

  static Future<bool> hasEnoughCredits(double requiredAmount) async {
    try {
      final balance = await getUsercreditBalance();
      return balance >= requiredAmount;
    } catch (e) {
      print('❌ Error checking credit balance: $e');
      return false;
    }
  }

  // Get dynamic credit usage data using Firebase Function
  static Future<Map<String, dynamic>> getDynamicCreditUsage() async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      // Call our new Firebase Function
      final response = await getUserCreditUsageAnalytics(user.uid);

      if (response['success'] == true) {
        final data = response['data'];
        final breakdown = data['breakdown'];

        return {
          'imagesUsed': breakdown['image']['totalGenerated'] ?? 0,
          'videosUsed': breakdown['video']['totalGenerated'] ?? 0,
          'excelUsed': breakdown['excel']['totalGenerated'] ?? 0,
          'totalCreditsUsed': data['summary']['totalCreditsUsed'] ?? 0.0,
          'imageRate': 1.0, // Fixed rate from our system
          'videoRate': 1.0, // Fixed rate from our system
          'excelRate': 0.5, // Fixed rate from our system
          'lastUpdated': DateTime.now().toIso8601String(),
        };
      } else {
        throw 'Failed to get credit usage analytics: ${response['error']}';
      }
    } catch (e) {
      print('❌ Error getting dynamic credit usage: $e');
      return {
        'imagesUsed': 0,
        'videosUsed': 0,
        'excelUsed': 0,
        'totalCreditsUsed': 0.0,
        'imageRate': 1.0,
        'videoRate': 1.0,
        'excelRate': 0.5,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }
  }

  // Get complete wallet data including subscription
  static Future<Map<String, dynamic>> getWalletData() async {
    try {
      final user = currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        // Get credit balance
        final dynamic balance = data['creditBalance'] ?? 0.0;
        final double creditBalance =
            balance is int ? balance.toDouble() : (balance as double);

        // Get subscription data
        final subscriptionData = data['subscription'] as Map<String, dynamic>?;

        // Get rollover data (if available)
        final rolloverData = data['rolloverData'] as Map<String, dynamic>?;

        // Get dynamic credit usage data from Firebase Function
        final creditUsageData = await getDynamicCreditUsage();

        // Create WalletDataModel with pricing data from Firestore
        final walletDataModel = await WalletDataModel.fromFirestoreWithPricing({
          'creditBalance': creditBalance,
          'subscription': subscriptionData,
          'creditUsage': creditUsageData,
          'rolloverData': rolloverData,
        });

        return {
          'creditBalance': walletDataModel.creditBalance,
          'subscription': walletDataModel.subscription?.toFirestore(),
          'creditUsage': walletDataModel.creditUsage.toFirestore(),
          'rolloverData': walletDataModel.rolloverData.toFirestore(),
        };
      } else {
        // Create comprehensive user document for new users
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName':
              user.displayName ?? user.email?.split('@').first ?? 'User',
          'fullName':
              user.displayName ?? user.email?.split('@').first ?? 'User',
          'phoneNumber': user.phoneNumber ?? '',
          'photoURL': user.photoURL ?? '',
          'creditBalance': 0.0,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'isEmailVerified': user.emailVerified,
          'isPhoneVerified':
              user.phoneNumber != null && user.phoneNumber!.isNotEmpty,
        });

        // Get dynamic credit usage data for new users (will return zeros)
        final creditUsageData = await getDynamicCreditUsage();

        return {
          'creditBalance': 0.0,
          'subscription': null,
          'creditUsage': creditUsageData,
          'rolloverData': null,
        };
      }
    } catch (e) {
      print('❌ Error fetching wallet data: $e');
      throw 'Error fetching wallet data: ${e.toString()}';
    }
  }

  // Real-time wallet data stream
  static Stream<Map<String, dynamic>> getWalletDataStream() {
    final user = currentUser;
    if (user == null) {
      return Stream.error('User not authenticated');
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .handleError((error) {
      print('Wallet data stream error: $error');
      return null;
    }).asyncMap((doc) async {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        // Get credit balance
        final dynamic balance = data['creditBalance'] ?? 0.0;
        final double creditBalance =
            balance is int ? balance.toDouble() : (balance as double);

        // Get subscription data
        final subscriptionData = data['subscription'] as Map<String, dynamic>?;

        // Get rollover data (if available)
        final rolloverData = data['rolloverData'] as Map<String, dynamic>?;

        // Get dynamic credit usage data from Firebase Function
        final creditUsageData = await getDynamicCreditUsage();

        // Create WalletDataModel with pricing data from Firestore
        final walletDataModel = await WalletDataModel.fromFirestoreWithPricing({
          'creditBalance': creditBalance,
          'subscription': subscriptionData,
          'creditUsage': creditUsageData,
          'rolloverData': rolloverData,
        });

        return {
          'creditBalance': walletDataModel.creditBalance,
          'subscription': walletDataModel.subscription?.toFirestore(),
          'creditUsage': walletDataModel.creditUsage.toFirestore(),
          'rolloverData': walletDataModel.rolloverData.toFirestore(),
        };
      } else {
        // Create comprehensive user document if it doesn't exist (new user only)
        final userData = {
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName':
              user.displayName ?? user.email?.split('@').first ?? 'User',
          'fullName':
              user.displayName ?? user.email?.split('@').first ?? 'User',
          'phoneNumber': user.phoneNumber ?? '',
          'photoURL': user.photoURL ?? '',
          'creditBalance': 0.0,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'isEmailVerified': user.emailVerified,
          'isPhoneVerified':
              user.phoneNumber != null && user.phoneNumber!.isNotEmpty,
        };
        _firestore.collection('users').doc(user.uid).set(userData);

        // Get dynamic credit usage data for new users (will return zeros)
        final creditUsageData = await getDynamicCreditUsage();

        return {
          'creditBalance': 0.0,
          'subscription': null,
          'creditUsage': creditUsageData,
          'rolloverData': null,
        };
      }
    });
  }

  // Reset Auth Instance (for troubleshooting)
  static Future<void> resetAuthInstance() async {
    try {
      // Sign out first
      await _auth.signOut();
      // Wait a bit
      await Future.delayed(ApiConfig.longRetryDelay);
      // Re-initialize
      await initialize();
    } catch (e) {
      print('Error resetting auth instance: $e');
    }
  }
}

class exportableVideo {
  final String id;
  final String title;
  final String videoUrl;
  final String thumbnailUrl;
  final Timestamp? timestamp;

  exportableVideo({
    required this.id,
    required this.title,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.timestamp,
  });

  DateTime? get createdAt => timestamp?.toDate();
}

// Helper function to call the Firebase Function
Future<Map<String, dynamic>> getUserCreditUsageAnalytics(String userId) async {
  try {
    final url =
        'https://us-central1-techrelieve-90c12.cloudfunctions.net/getUserCreditUsageAnalytics?userId=$userId';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw 'HTTP ${response.statusCode}: ${response.body}';
    }
  } catch (e) {
    print('❌ Error calling getUserCreditUsageAnalytics: $e');
    rethrow;
  }
}
