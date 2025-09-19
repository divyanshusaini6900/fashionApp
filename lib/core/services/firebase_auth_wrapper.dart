// lib/core/services/firebase_auth_wrapper.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

/// Wrapper class to handle Firebase Auth operations safely
/// This prevents the PigeonUserDetails type cast error
class FirebaseAuthWrapper {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  /// Get current user with error handling
  static User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (e) {
      print('Error getting current user: $e');
      // Return null if there's any error
      return null;
    }
  }
  
  /// Safe auth state changes stream
  static Stream<User?> get authStateChanges {
    return _auth.authStateChanges().handleError((error) {
      print('Auth state change error: $error');
      return null;
    });
  }
  
  /// Safe user changes stream
  static Stream<User?> get userChanges {
    return _auth.userChanges().handleError((error) {
      print('User change error: $error');
      return null;
    });
  }
  
  /// Sign in with email and password
  static Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      // First, sign out any existing user to clear state
      await signOut();
      await Future.delayed(const Duration(milliseconds: 500));
      
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Wait for auth state to stabilize
      await Future.delayed(const Duration(milliseconds: 500));
      
      return credential;
    } on FirebaseAuthException catch (e) {
      throw e;
    } catch (e) {
      print('Sign in error: $e');
      throw 'An unexpected error occurred during sign in';
    }
  }
  
  /// Sign out
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
      // Wait for auth state to update
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      print('Sign out error: $e');
    }
  }
  
  /// Reload current user
  static Future<void> reloadCurrentUser() async {
    try {
      await _auth.currentUser?.reload();
    } catch (e) {
      print('Error reloading user: $e');
    }
  }
}