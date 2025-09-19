// lib/core/mixins/safe_state_mixin.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

mixin SafeStateMixin<T extends StatefulWidget> on State<T> {
  bool _mounted = true;

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }

  bool get isSafeMounted => _mounted && mounted;

  void safeSetState(VoidCallback fn) {
    if (isSafeMounted) {
      // Schedule setState for next frame if we're building
      if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (isSafeMounted) {
            setState(fn);
          }
        });
      } else {
        setState(fn);
      }
    }
  }

  void addBlocEvent<B extends Bloc>(B bloc, Object event) {
    if (isSafeMounted) {
      try {
        bloc.add(event);
      } catch (e) {
        debugPrint('Error adding bloc event: $e');
      }
    }
  }

  Future<void> safeAsync(Future<void> Function() callback) async {
    if (isSafeMounted) {
      try {
        await callback();
      } catch (e) {
        debugPrint('Error in safe async: $e');
      }
    }
  }
}