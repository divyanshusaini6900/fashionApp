import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'dart:async';

import '../../../core/services/firebase_service.dart';

// Events
abstract class UserEvent extends Equatable {
  const UserEvent();

  @override
  List<Object> get props => [];
}

class LoadUserData extends UserEvent {
  const LoadUserData();
}

class StartUserDataStream extends UserEvent {
  const StartUserDataStream();
}

class StopUserDataStream extends UserEvent {
  const StopUserDataStream();
}

class UserDataUpdated extends UserEvent {
  final Map<String, dynamic> userData;

  const UserDataUpdated({required this.userData});

  @override
  List<Object> get props => [userData];
}

class UpdateUserDisplayName extends UserEvent {
  final String displayName;

  const UpdateUserDisplayName({required this.displayName});

  @override
  List<Object> get props => [displayName];
}

class UpdateUserProfile extends UserEvent {
  final String displayName;
  final String? phoneNumber;
  final String? bio;
  final dynamic profileImage; // File object or null

  const UpdateUserProfile({
    required this.displayName,
    this.phoneNumber,
    this.bio,
    this.profileImage,
  });

  @override
  List<Object> get props => [displayName, phoneNumber ?? '', bio ?? '', profileImage ?? ''];
}

class RefreshUserData extends UserEvent {
  const RefreshUserData();
}

// States
abstract class UserState extends Equatable {
  const UserState();

  @override
  List<Object> get props => [];
}

class UserInitial extends UserState {
  const UserInitial();
}

class UserLoading extends UserState {
  const UserLoading();
}

class UserLoaded extends UserState {
  final Map<String, dynamic> userData;

  const UserLoaded({required this.userData});


  String get displayName => userData['displayName'] ?? userData['email']?.split('@').first ?? 'User';
  String get userFullName => userData['fullName']?? 'User';
  String get email => userData['email'] ?? '';
  String? get phoneNumber => userData['phoneNumber'];
  String? get bio => userData['bio'];
  String? get photoURL => userData['photoURL'];
  int get creditBalance => userData['creditBalance'] ?? 0;

  @override
  List<Object> get props => [userData];
}

class UserUpdateSuccess extends UserState {
  final String message;

  const UserUpdateSuccess({required this.message});

  @override
  List<Object> get props => [message];
}

class UserError extends UserState {
  final String message;

  const UserError({required this.message});

  @override
  List<Object> get props => [message];
}

// BLoC
class UserBloc extends Bloc<UserEvent, UserState> {
  StreamSubscription<Map<String, dynamic>?>? _userDataSubscription;
  Map<String, dynamic>? _lastUserData;

  UserBloc() : super(const UserInitial()) {
    on<LoadUserData>(_onLoadUserData);
    on<StartUserDataStream>(_onStartUserDataStream);
    on<StopUserDataStream>(_onStopUserDataStream);
    on<UserDataUpdated>(_onUserDataUpdated);
    on<UpdateUserDisplayName>(_onUpdateUserDisplayName);
    on<UpdateUserProfile>(_onUpdateUserProfile);
    on<RefreshUserData>(_onRefreshUserData);
  }

  @override
  Future<void> close() {
    _userDataSubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadUserData(
    LoadUserData event,
    Emitter<UserState> emit,
  ) async {
    try {
      emit(const UserLoading());
      
      final userData = await FirebaseService.getUserData();
      if (userData != null) {
        _lastUserData = userData;
        emit(UserLoaded(userData: userData));
      } else {
        emit(const UserError(message: 'User data not found'));
      }
    } catch (e) {
      emit(UserError(message: e.toString()));
    }
  }

  Future<void> _onStartUserDataStream(
    StartUserDataStream event,
    Emitter<UserState> emit,
  ) async {
    try {
      await _userDataSubscription?.cancel();
      
      _userDataSubscription = FirebaseService.getUserDataStream().listen(
        (userData) {
          if (userData != null) {
            _lastUserData = userData;
            add(UserDataUpdated(userData: userData));
          }
        },
        onError: (error) {
          print('Error in user data stream: $error');
          // Emit last known data if available
          if (_lastUserData != null) {
            add(UserDataUpdated(userData: _lastUserData!));
          }
        },
      );
    } catch (e) {
      emit(UserError(message: e.toString()));
    }
  }

  Future<void> _onStopUserDataStream(
    StopUserDataStream event,
    Emitter<UserState> emit,
  ) async {
    await _userDataSubscription?.cancel();
    _userDataSubscription = null;
  }

  void _onUserDataUpdated(
    UserDataUpdated event,
    Emitter<UserState> emit,
  ) {
    _lastUserData = event.userData;
    emit(UserLoaded(userData: event.userData));
  }

  Future<void> _onUpdateUserDisplayName(
    UpdateUserDisplayName event,
    Emitter<UserState> emit,
  ) async {
    try {
      // Don't emit loading state to prevent UI flicker
      // Just update the display name
      
      final trimmedName = event.displayName.trim();
      if (trimmedName.isEmpty) {
        emit(const UserError(message: 'Display name cannot be empty'));
        return;
      }
      
      await FirebaseService.updateUserDisplayName(trimmedName);
      
      // Update local cache immediately for better UX
      if (_lastUserData != null) {
        _lastUserData!['displayName'] = trimmedName;
        emit(UserLoaded(userData: _lastUserData!));
      }
      
      // The stream will automatically update with the new data
      emit(const UserUpdateSuccess(message: 'Display name updated successfully'));
      
      // After showing success, reload the user data
      await Future.delayed(const Duration(milliseconds: 500));
      if (_lastUserData != null) {
        emit(UserLoaded(userData: _lastUserData!));
      }
      
    } catch (e) {
      // Keep showing the current data even on error
      if (_lastUserData != null) {
        emit(UserLoaded(userData: _lastUserData!));
      }
      
      // Show error briefly then restore state
      emit(UserError(message: 'Failed to update display name. Please try again.'));
      await Future.delayed(const Duration(seconds: 2));
      
      if (_lastUserData != null) {
        emit(UserLoaded(userData: _lastUserData!));
      }
    }
  }

  Future<void> _onUpdateUserProfile(
    UpdateUserProfile event,
    Emitter<UserState> emit,
  ) async {
    try {
      // Show loading state briefly
      emit(const UserLoading());
      
      final trimmedName = event.displayName.trim();
      if (trimmedName.isEmpty) {
        emit(const UserError(message: 'Name cannot be empty'));
        return;
      }
      
      // Update Firebase Auth profile
      await FirebaseService.updateUserDisplayName(trimmedName);
      
      // Update additional profile data in Firestore
      final updates = <String, dynamic>{
        // 'displayName': trimmedName,
        'fullName': trimmedName,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      if (event.phoneNumber != null) {
        updates['phoneNumber'] = event.phoneNumber;
      }
      
      if (event.bio != null) {
        updates['bio'] = event.bio;
      }
      
      // Handle profile image upload if provided
      if (event.profileImage != null) {
        try {
          // Upload image to Firebase Storage and get URL
          final photoURL = await FirebaseService.uploadProfileImage(event.profileImage);
          updates['photoURL'] = photoURL;
          
          // Update Firebase Auth profile photo
          await FirebaseService.updateUserPhotoURL(photoURL);
        } catch (e) {
          print('Error uploading profile image: $e');
          // Continue with other updates even if image upload fails
        }
      }
      
      await FirebaseService.updateUserData(updates);
      
      // Update local cache immediately
      if (_lastUserData != null) {
        _lastUserData!.addAll(updates);
        emit(UserLoaded(userData: _lastUserData!));
      }
      
      emit(const UserUpdateSuccess(message: 'Profile updated successfully!'));
      
      // After showing success, reload the user data
      await Future.delayed(const Duration(milliseconds: 1000));
      if (_lastUserData != null) {
        emit(UserLoaded(userData: _lastUserData!));
      }
      
    } catch (e) {
      // Keep showing the current data even on error
      if (_lastUserData != null) {
        emit(UserLoaded(userData: _lastUserData!));
      }
      
      emit(UserError(message: 'Failed to update profile. Please try again.'));
      await Future.delayed(const Duration(seconds: 2));
      
      if (_lastUserData != null) {
        emit(UserLoaded(userData: _lastUserData!));
      }
    }
  }

  Future<void> _onRefreshUserData(
    RefreshUserData event,
    Emitter<UserState> emit,
  ) async {
    try {
      final userData = await FirebaseService.getUserData();
      if (userData != null) {
        _lastUserData = userData;
        emit(UserLoaded(userData: userData));
      }
    } catch (e) {
      // Keep showing last known data on refresh error
      if (_lastUserData != null) {
        emit(UserLoaded(userData: _lastUserData!));
      } else {
        emit(UserError(message: e.toString()));
      }
    }
  }
}