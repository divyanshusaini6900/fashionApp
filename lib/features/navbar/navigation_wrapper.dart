// lib/features/home/presentation/widgets/navigation_wrapper.dart
import 'package:flutter/material.dart';

class NavigationWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onActivate;
  final VoidCallback? onDeactivate;
  final bool maintainState;

  const NavigationWrapper({
    super.key,
    required this.child,
    this.onActivate,
    this.onDeactivate,
    this.maintainState = true,
  });

  @override
  State<NavigationWrapper> createState() => _NavigationWrapperState();
}

class _NavigationWrapperState extends State<NavigationWrapper> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => widget.maintainState;

  @override
  void initState() {
    super.initState();
    // Delay activation to avoid build conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onActivate?.call();
      }
    });
  }

  @override
  void deactivate() {
    widget.onDeactivate?.call();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return widget.child;
  }
}