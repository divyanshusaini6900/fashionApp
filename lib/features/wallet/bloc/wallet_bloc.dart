import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'dart:async';

import '../../../core/services/firebase_service.dart';
import '../models/subscription_model.dart';

// Events
abstract class WalletEvent extends Equatable {
  const WalletEvent();

  @override
  List<Object> get props => [];
}

class LoadWalletBalance extends WalletEvent {
  const LoadWalletBalance();
}

class LoadWalletData extends WalletEvent {
  const LoadWalletData();
}

class StartWalletStream extends WalletEvent {
  const StartWalletStream();
}

class StartWalletDataStream extends WalletEvent {
  const StartWalletDataStream();
}

class StopWalletStream extends WalletEvent {
  const StopWalletStream();
}

class StopWalletDataStream extends WalletEvent {
  const StopWalletDataStream();
}

class WalletBalanceUpdated extends WalletEvent {
  final double balance;

  const WalletBalanceUpdated({required this.balance});

  @override
  List<Object> get props => [balance];
}

class WalletDataUpdated extends WalletEvent {
  final Map<String, dynamic> walletData;

  const WalletDataUpdated({required this.walletData});

  @override
  List<Object> get props => [walletData];
}

// Manual deduction functionality removed
// Credits are only deducted automatically during GenSpace/video generation

class AddCredits extends WalletEvent {
  final double amount;

  const AddCredits({required this.amount});

  @override
  List<Object> get props => [amount];
}

class RefreshWallet extends WalletEvent {
  const RefreshWallet();
}

// States
abstract class WalletState extends Equatable {
  const WalletState();

  @override
  List<Object> get props => [];
}

class WalletInitial extends WalletState {
  const WalletInitial();
}

class WalletLoading extends WalletState {
  const WalletLoading();
}

class WalletLoaded extends WalletState {
  final double balance;

  const WalletLoaded({required this.balance});

  @override
  List<Object> get props => [balance];
}

class WalletDataLoaded extends WalletState {
  final WalletDataModel walletData;

  const WalletDataLoaded({required this.walletData});

  @override
  List<Object> get props => [walletData];
}

class WalletError extends WalletState {
  final String message;

  const WalletError({required this.message});

  @override
  List<Object> get props => [message];
}

// InsufficientFunds state removed
// Credit validation now handled at feature level (GenSpace/video generation)

// BLoC
class WalletBloc extends Bloc<WalletEvent, WalletState> {
  StreamSubscription<double>? _balanceSubscription;
  StreamSubscription<Map<String, dynamic>>? _walletDataSubscription;

  WalletBloc() : super(const WalletInitial()) {
    on<LoadWalletBalance>(_onLoadWalletBalance);
    on<LoadWalletData>(_onLoadWalletData);
    on<StartWalletStream>(_onStartWalletStream);
    on<StartWalletDataStream>(_onStartWalletDataStream);
    on<StopWalletStream>(_onStopWalletStream);
    on<StopWalletDataStream>(_onStopWalletDataStream);
    on<WalletBalanceUpdated>(_onWalletBalanceUpdated);
    on<WalletDataUpdated>(_onWalletDataUpdated);
    on<AddCredits>(_onAddCredits);
    on<RefreshWallet>(_onRefreshWallet);
  }

  @override
  Future<void> close() {
    _balanceSubscription?.cancel();
    _walletDataSubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadWalletBalance(
    LoadWalletBalance event,
    Emitter<WalletState> emit,
  ) async {
    try {
      emit(const WalletLoading());

      final balance = await FirebaseService.getUsercreditBalance();
      emit(WalletLoaded(balance: balance));
    } catch (e) {
      emit(WalletError(message: e.toString()));
    }
  }

  Future<void> _onLoadWalletData(
    LoadWalletData event,
    Emitter<WalletState> emit,
  ) async {
    try {
      emit(const WalletLoading());

      final walletDataMap = await FirebaseService.getWalletData();
      final walletData = WalletDataModel.fromFirestore(walletDataMap);
      emit(WalletDataLoaded(walletData: walletData));
    } catch (e) {
      emit(WalletError(message: e.toString()));
    }
  }

  Future<void> _onStartWalletStream(
    StartWalletStream event,
    Emitter<WalletState> emit,
  ) async {
    try {
      await _balanceSubscription?.cancel();

      _balanceSubscription = FirebaseService.getcreditBalanceStream().listen(
        (balance) {
          add(WalletBalanceUpdated(balance: balance));
        },
        onError: (error) {
          add(WalletBalanceUpdated(balance: 0)); // Fallback to 0 on error
        },
      );
    } catch (e) {
      emit(WalletError(message: e.toString()));
    }
  }

  Future<void> _onStartWalletDataStream(
    StartWalletDataStream event,
    Emitter<WalletState> emit,
  ) async {
    try {
      await _walletDataSubscription?.cancel();

      _walletDataSubscription = FirebaseService.getWalletDataStream().listen(
        (walletData) {
          add(WalletDataUpdated(walletData: walletData));
        },
        onError: (error) {
          // Fallback to default data on error
          add(WalletDataUpdated(walletData: {
            'creditBalance': 0.0,
            'subscription': null,
            'creditUsage': null,
            'rolloverData': null,
          }));
        },
      );
    } catch (e) {
      emit(WalletError(message: e.toString()));
    }
  }

  Future<void> _onStopWalletStream(
    StopWalletStream event,
    Emitter<WalletState> emit,
  ) async {
    await _balanceSubscription?.cancel();
    _balanceSubscription = null;
  }

  Future<void> _onStopWalletDataStream(
    StopWalletDataStream event,
    Emitter<WalletState> emit,
  ) async {
    await _walletDataSubscription?.cancel();
    _walletDataSubscription = null;
  }

  void _onWalletBalanceUpdated(
    WalletBalanceUpdated event,
    Emitter<WalletState> emit,
  ) {
    emit(WalletLoaded(balance: event.balance));
  }

  void _onWalletDataUpdated(
    WalletDataUpdated event,
    Emitter<WalletState> emit,
  ) {
    final walletData = WalletDataModel.fromFirestore(event.walletData);
    emit(WalletDataLoaded(walletData: walletData));
  }

  // Manual deduction method removed
  // Credits are only deducted automatically during GenSpace/video generation

  Future<void> _onAddCredits(
    AddCredits event,
    Emitter<WalletState> emit,
  ) async {
    try {
      emit(const WalletLoading());

      final newBalance = await FirebaseService.addCredits(event.amount);
      emit(WalletLoaded(balance: newBalance));
    } catch (e) {
      emit(WalletError(message: e.toString()));
    }
  }

  Future<void> _onRefreshWallet(
    RefreshWallet event,
    Emitter<WalletState> emit,
  ) async {
    try {
      final balance = await FirebaseService.getUsercreditBalance();
      emit(WalletLoaded(balance: balance));
    } catch (e) {
      emit(WalletError(message: e.toString()));
    }
  }
}
