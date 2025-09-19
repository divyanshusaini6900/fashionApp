import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

class CleanPerformanceUtils {
  /// Optimize the app for better performance
  static void initialize() {
    // Basic performance optimizations
    _optimizeImageCache();
    _setupPeriodicCleanup();
    
    // Debug optimizations
    if (kDebugMode) {
      _optimizeDebugMode();
    }
  }

  /// Optimize image cache settings
  static void _optimizeImageCache() {
    PaintingBinding.instance.imageCache.maximumSize = 50;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 30 << 20; // 30 MB
  }

  /// Set up periodic cleanup
  static void _setupPeriodicCleanup() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (kDebugMode) {
        Future.delayed(const Duration(minutes: 5), () {
          clearImageCache();
        });
      }
    });
  }

  /// Optimize debug mode settings
  static void _optimizeDebugMode() {
    debugPaintSizeEnabled = false;
    debugRepaintRainbowEnabled = false;
    
    // Set normal animation speed
    timeDilation = 1.0;
  }

  /// Clear image cache to free memory
  static void clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
  }

  /// Clear live images from cache
  static void clearLiveImages() {
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  /// Enable performance overlay for debugging
  static void enablePerformanceOverlay() {
    if (kDebugMode) {
      WidgetsApp.showPerformanceOverlayOverride = true;
    }
  }

  /// Disable performance overlay
  static void disablePerformanceOverlay() {
    WidgetsApp.showPerformanceOverlayOverride = false;
  }
}

/// Simple wrapper widget for performance optimization
class OptimizedWidget extends StatelessWidget {
  final Widget child;

  const OptimizedWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: child);
  }
}

/// Optimized scroll view with better performance
class OptimizedScrollView extends StatelessWidget {
  final List<Widget> children;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;

  const OptimizedScrollView({
    super.key,
    required this.children,
    this.physics,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: physics ?? const BouncingScrollPhysics(),
      padding: padding,
      child: Column(
        children: children.map((child) => OptimizedWidget(child: child)).toList(),
      ),
    );
  }
}

/// Performance-optimized list builder
class OptimizedListBuilder extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final ScrollPhysics? physics;

  const OptimizedListBuilder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      physics: physics ?? const BouncingScrollPhysics(),
      cacheExtent: 200,
      itemBuilder: (context, index) {
        return OptimizedWidget(
          child: itemBuilder(context, index),
        );
      },
    );
  }
}