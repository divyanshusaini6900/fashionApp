import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/logout_service.dart';

import '../../../core/services/free_credits_service.dart';

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

// Email/Password Login
class AuthEmailLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthEmailLoginRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object> get props => [email, password];
}

// Unified Signup with Password
class AuthSignUpRequested extends AuthEvent {
  final String name;
  final String email;
  final String password;
  final String phoneNumber;
  final String city;

  const AuthSignUpRequested({
    required this.name,
    required this.email,
    required this.password,
    required this.phoneNumber,
    required this.city,
  });

  @override
  List<Object> get props => [name, email, password, phoneNumber, city];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

class AuthStatusChanged extends AuthEvent {
  final User? user;

  const AuthStatusChanged({required this.user});

  @override
  List<Object> get props => [user ?? ''];
}

class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class AuthForgotPasswordRequested extends AuthEvent {
  final String email;

  const AuthForgotPasswordRequested({required this.email});

  @override
  List<Object> get props => [email];
}

// States
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final User user;

  const AuthAuthenticated({required this.user});

  @override
  List<Object> get props => [user];
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object> get props => [message];
}

class AuthSignUpSuccess extends AuthState {
  final String message;

  const AuthSignUpSuccess({required this.message});

  @override
  List<Object> get props => [message];
}

class AuthForgotPasswordSuccess extends AuthState {
  final String message;

  const AuthForgotPasswordSuccess({required this.message});

  @override
  List<Object> get props => [message];
}

// Enhanced Auth BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  StreamSubscription<User?>? _authStateSubscription;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AuthBloc() : super(const AuthInitial()) {
    on<AuthEmailLoginRequested>(_onEmailLoginRequested);
    on<AuthSignUpRequested>(_onSignUpRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthStatusChanged>(_onAuthStatusChanged);
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthForgotPasswordRequested>(_onForgotPasswordRequested);

    // Initialize auth state listener
    _initializeAuthListener();
  }

  void _initializeAuthListener() {
    _authStateSubscription?.cancel();

    _authStateSubscription = FirebaseService.authStateChanges.listen(
      (user) {
        Future.delayed(const Duration(milliseconds: 100), () {
          add(AuthStatusChanged(user: user));
        });
      },
      onError: (error) {
        print('Auth state error: $error');
        add(const AuthStatusChanged(user: null));
      },
    );
  }

  // Email/Password Login
  Future<void> _onEmailLoginRequested(
    AuthEmailLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      // Clean inputs
      final email = event.email.trim().toLowerCase();
      final password = event.password;

      // Validate email format
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        emit(const AuthError(message: 'Please enter a valid email address.'));
        return;
      }

      // Check if user exists
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        emit(const AuthError(
            message:
                'No account found with this email. Please sign up first.'));
        return;
      }

      // Try to sign in with email and password
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        await _ensureUserDocument(credential.user!);
        emit(AuthAuthenticated(user: credential.user!));
      } else {
        emit(const AuthError(message: 'Login failed. Please try again.'));
      }
    } on FirebaseAuthException catch (e) {
      emit(AuthError(message: _getAuthErrorMessage(e.code)));
    } catch (e) {
      print('Email login error: $e');
      emit(const AuthError(
          message: 'An unexpected error occurred. Please try again.'));
    }
  }

  // Unified Signup
  Future<void> _onSignUpRequested(
    AuthSignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final fullName = event.name.trim();
      final email = event.email.trim().toLowerCase();
      final phoneNumber = _formatPhoneNumber(event.phoneNumber);

      print('🚀 Starting signup process with Full Name: "$fullName"');

      // Check if email already exists
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (emailQuery.docs.isNotEmpty) {
        emit(const AuthError(
            message: 'An account already exists with this email.'));
        return;
      }

      // Check if phone already exists
      final phoneQuery = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (phoneQuery.docs.isNotEmpty) {
        emit(const AuthError(
            message: 'An account already exists with this phone number.'));
        return;
      }

      // Create account with email and password first
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: event.password,
      );

      if (userCredential.user != null) {
        // IMMEDIATELY sign out to prevent router redirect to home
        await _auth.signOut();
        print(
            '🔓 User signed out immediately after account creation to prevent auto-redirect');

        // Update display name in Firebase Auth to match the Full Name entered
        try {
          await userCredential.user!.updateDisplayName(fullName);
          // Reload user to ensure the displayName is updated
          await userCredential.user!.reload();
          // Verify the displayName was actually set
          final updatedUser = _auth.currentUser;
          if (updatedUser?.displayName == fullName) {
            print(
                '✅ Firebase Auth displayName successfully updated to: "$fullName"');
          } else {
            print(
                '⚠️ Firebase Auth displayName update verification failed. Expected: "$fullName", Got: "${updatedUser?.displayName}"');
          }
        } catch (e) {
          print('⚠️ Warning: Could not update Firebase Auth displayName: $e');
          // Continue anyway - we'll save the correct name in Firestore
        }

        // Save user data directly to Firestore with free credits
        // This ensures fullName and displayName are saved even if phone verification fails
        try {
          // First, fetch free credits amount from Firebase
          print('🎁 Fetching free credits for new user...');
          final freeCreditsAmount =
              await FreeCreditsService.getFreeCreditsAmount();

          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'uid': userCredential.user!.uid,
            'fullName': fullName,
            'displayName': fullName,
            'email': email,
            'phoneNumber': phoneNumber,
            'city': event.city,
            'photoURL': '',
            'creditBalance': freeCreditsAmount, // Set to free credits amount
            'freeCreditsApplied': true,
            'freeCreditsAmount': freeCreditsAmount,
            'freeCreditsAppliedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'isEmailVerified': true,
            'isPhoneVerified': true, // Phone number collected but not verified
          }, SetOptions(merge: true));

          print(
              '✅ User document saved with displayName: "$fullName" and free credits: $freeCreditsAmount');
        } catch (e) {
          print('⚠️ Error saving user document: $e');

          // Fallback: save with default credits
          try {
            await _firestore
                .collection('users')
                .doc(userCredential.user!.uid)
                .set({
              'uid': userCredential.user!.uid,
              'fullName': fullName,
              'displayName': fullName,
              'email': email,
              'phoneNumber': phoneNumber,
              'city': event.city,
              'photoURL': '',
              'creditBalance': 0.0, // Default fallback credits
              'freeCreditsApplied': true,
              'freeCreditsAmount': 0.0,
              'freeCreditsAppliedAt': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
              'lastUpdated': FieldValue.serverTimestamp(),
              'lastLogin': FieldValue.serverTimestamp(),
              'isEmailVerified': true,
              'isPhoneVerified':
                  true, // Phone number collected but not verified
            }, SetOptions(merge: true));

            print('🔄 Fallback: User document saved with default 0.0 credits');
          } catch (fallbackError) {
            print('❌ Fallback save also failed: $fallbackError');
          }
        }

        // Signup completed successfully without phone verification
        emit(const AuthSignUpSuccess(
            message:
                'Account created successfully! Please login to continue.'));
      }
    } on FirebaseAuthException catch (e) {
      emit(AuthError(message: _getAuthErrorMessage(e.code)));
    } catch (e) {
      print('Signup error: $e');
      emit(const AuthError(message: 'Signup failed. Please try again.'));
    }
  }

  // Helper methods
  String _formatPhoneNumber(String phoneNumber) {
    if (!phoneNumber.startsWith('+')) {
      if (phoneNumber.startsWith('0')) {
        return '+91${phoneNumber.substring(1)}';
      } else {
        return '+91$phoneNumber';
      }
    }
    return phoneNumber;
  }

  Future<void> _ensureUserDocument(User user) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        print('⚠️ User document does not exist for ${user.uid}');

        // Only create minimal document for login users
        // Signup users will have their document created after OTP verification
        // Check if this is a new signup by looking for phone number
        if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
          // This is a login user with phone, create document ONLY with actual displayName
          // NO fallbacks - only save displayName/fullName if user actually has displayName
          Map<String, dynamic> userData = {
            'uid': user.uid,
            'email': user.email ?? '',
            'phoneNumber': user.phoneNumber ?? '',
            'photoURL': user.photoURL ?? '',
            'creditBalance': 0,
            'isPhoneVerified': true,
            'createdAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
          };

          // Only add displayName/fullName if actual displayName exists from signup
          if (user.displayName != null && user.displayName!.isNotEmpty) {
            userData['displayName'] = user.displayName!;
            userData['fullName'] = user.displayName!;
            print(
                '✅ User document created with displayName: "${user.displayName!}"');
          } else {
            print(
                '✅ User document created without displayName (none available)');
          }

          await docRef.set(userData, SetOptions(merge: true));
        } else {
          // For email login or incomplete signup, create minimal document
          // This will be overwritten with complete data after OTP verification
          print('⏳ Skipping document creation - waiting for signup completion');
        }
      } else {
        final data = doc.data() as Map<String, dynamic>;

        if (data['fullName'] == null || data['phoneNumber'] == null) {
          print(
              '⚠️ User document exists but is incomplete - signup may not have completed');
        }

        await docRef.update({
          'lastLogin': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        print(
            '✅ User last login updated - preserved existing displayName/fullName');
      }
    } catch (e) {
      print('Error ensuring user document: $e');
      // Don't throw - this is not critical for auth
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(const AuthLoading());

      // Use enhanced logout service to clear all caches and sign out
      await LogoutService.performCompleteLogout();

      emit(const AuthUnauthenticated());
    } catch (e) {
      // If enhanced logout fails, try quick logout as fallback
      try {
        await LogoutService.performQuickLogout();
        emit(const AuthUnauthenticated());
      } catch (fallbackError) {
        emit(AuthError(message: 'Logout failed: ${e.toString()}'));
      }
    }
  }

  void _onAuthStatusChanged(
    AuthStatusChanged event,
    Emitter<AuthState> emit,
  ) {
    if (event.user != null) {
      emit(AuthAuthenticated(user: event.user!));
    } else {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        emit(AuthAuthenticated(user: user));
      } else {
        emit(const AuthUnauthenticated());
      }
    } catch (e) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onForgotPasswordRequested(
    AuthForgotPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final email = event.email.trim().toLowerCase();

      // Validate email format
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        emit(const AuthError(message: 'Please enter a valid email address.'));
        return;
      }

      // Check if user exists in Firestore
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        emit(const AuthError(
            message: 'No account found with this email address.'));
        return;
      }

      // Send password reset email
      await _auth.sendPasswordResetEmail(email: email);

      emit(const AuthForgotPasswordSuccess(
          message: 'Password reset email sent! Please check your inbox.'));
    } on FirebaseAuthException catch (e) {
      emit(AuthError(message: _getAuthErrorMessage(e.code)));
    } catch (e) {
      print('Forgot password error: $e');
      emit(const AuthError(
          message: 'Failed to send reset email. Please try again.'));
    }
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Invalid email format.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  @override
  Future<void> close() {
    _authStateSubscription?.cancel();
    return super.close();
  }
}
