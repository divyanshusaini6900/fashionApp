// lib/features/upload/services/GenSpace_auth_service.dart
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/firebase_service.dart';
import '../models/user_model.dart';

class GenSpaceAuthService extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isInitialized = false;
  
  // Add a completer to track initialization
  Future<void>? _initializationFuture;

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _currentUser != null;
  bool get isInitialized => _isInitialized;

  // Ensure initialization
  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    
    // If already initializing, wait for it
    if (_initializationFuture != null) {
      await _initializationFuture;
      return;
    }
    
    // Start initialization
    _initializationFuture = _initialize();
    await _initializationFuture;
  }

  Future<void> _initialize() async {
    _setLoading(true);
    
    try {
      // Wait for Firebase Auth to be ready
      await FirebaseAuth.instance.authStateChanges().first;
      
      final firebaseUser = FirebaseService.currentUser;
      if (firebaseUser != null) {
        await _loadUserFromFirebase(firebaseUser);
      }
      
      _isInitialized = true;
    } catch (e) {
      _setError('Failed to initialize auth: ${e.toString()}');
      _isInitialized = false;
    } finally {
      _setLoading(false);
      _initializationFuture = null;
    }
  }

  // Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Set error message
  void _setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  // Load user from Firebase
  Future<void> _loadUserFromFirebase(User firebaseUser) async {
    try {
      // Get user data from Firestore
      final userData = await FirebaseService.getUserData();
      
      _currentUser = UserModel(
        id: firebaseUser.uid,
        username: userData?['displayName'] ?? 
                 firebaseUser.displayName ?? 
                 firebaseUser.email?.split('@').first ?? 
                 'User',
        email: firebaseUser.email,
        createdAt: userData?['createdAt']?.toDate() ?? DateTime.now(),
        companyName: userData?['companyName'],
      );
      
      notifyListeners();
    } catch (e) {
      print('Error loading user data: $e');
      // Create basic user model even if Firestore fails
      _currentUser = UserModel(
        id: firebaseUser.uid,
        username: firebaseUser.email?.split('@').first ?? 'User',
        email: firebaseUser.email,
        createdAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  // Initialize with Firebase User
  Future<void> initializeFromFirebase() async {
    await ensureInitialized();
  }

  // Listen to Firebase auth changes
  void listenToAuthChanges() {
    FirebaseService.authStateChanges.listen((firebaseUser) async {
      if (firebaseUser == null) {
        _currentUser = null;
        _isInitialized = false;
        notifyListeners();
      } else {
        // Load user data when auth state changes
        await _loadUserFromFirebase(firebaseUser);
        _isInitialized = true;
      }
    }, onError: (error) {
      print('Auth state error: $error');
      _setError('Auth state error: ${error.toString()}');
    });
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await FirebaseService.signOut();
      _currentUser = null;
      _isInitialized = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to sign out: ${e.toString()}');
    }
  }
  
  // Get current Firebase user directly (fallback)
  User? getFirebaseUser() {
    return FirebaseService.currentUser;
  }
}